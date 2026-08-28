// supabase/functions/create-topup-intent/index.ts
//
// Creates a Fintoc Checkout Session for wallet top-up (sandbox/test mode).
// 1. Authenticates the user via JWT.
// 2. Validates amount and computes the 1% fee.
// 3. POSTs to https://api.fintoc.com/v2/checkout_sessions.
// 4. Stores a 'pending' row in fintoc_payments for lifecycle tracking.
// 5. Returns the redirect_url so the user pays on Fintoc's hosted page.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? (() => { throw new Error("SUPABASE_URL is required"); })();
const APP_BASE_URL = (Deno.env.get("APP_BASE_URL") ?? "https://turnoapp.cl").replace(/\/+$/, "");

const FINTOC_SECRET_KEY = Deno.env.get("FINTOC_SECRET_KEY") ?? "";
const FINTOC_API_BASE = "https://api.fintoc.com/v2";

const ALLOWED_ORIGINS = [
  "https://turnoapp.cl",
  "https://www.turnoapp.cl",
];

function corsHeadersFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin");
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    return {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      "Vary": "Origin",
    };
  }
  return {};
}

function sanitizeAmount(rawAmount: unknown): number | null {
  if (typeof rawAmount === "number") {
    if (!Number.isFinite(rawAmount)) return null;
    return Math.round(rawAmount);
  }
  if (typeof rawAmount === "string") {
    const parsed = Number(rawAmount.trim());
    if (!Number.isFinite(parsed)) return null;
    return Math.round(parsed);
  }
  return null;
}

function topupFee(amount: number): number {
  return Math.round(amount * 0.01);
}

function topupChargedAmount(amount: number): number {
  return amount + topupFee(amount);
}

// Fintoc requires HTTPS success/cancel URLs (rejects custom schemes).
// Allow only URLs on the APP_BASE_URL origin to prevent open redirects.
function sanitizeRedirectUrl(raw: unknown, fallback: string): string {
  if (typeof raw !== "string" || raw.trim() === "") return fallback;
  const candidate = raw.trim();

  try {
    const url = new URL(candidate);
    if (url.protocol !== "https:") return fallback;
    const base = new URL(APP_BASE_URL);
    if (url.origin === base.origin) return candidate;
  } catch {
    // invalid URL -> fall through to fallback
  }

  return fallback;
}

function logInfo(event: string, details: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ level: "info", event, ...details }));
}

function logError(event: string, details: Record<string, unknown> = {}) {
  console.error(JSON.stringify({ level: "error", event, ...details }));
}

function extractBearerToken(authHeader: string | null): string | null {
  if (!authHeader) return null;
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() ?? null;
}

function getServiceClient() {
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? (() => { throw new Error("SUPABASE_SERVICE_ROLE_KEY is required"); })();
  return createClient(SUPABASE_URL, serviceKey);
}

async function getAuthedUser(authHeader: string | null) {
  const token = extractBearerToken(authHeader);
  if (!token) return null;

  const supabase = getServiceClient();
  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) return null;
  return user;
}

async function createFintocCheckout(params: {
  amountRequested: number;
  amountCharged: number;
  userId: string;
  userEmail?: string;
  successUrl: string;
  cancelUrl: string;
}): Promise<{ checkout_session_id: string; redirect_url: string }> {
  const { amountRequested, amountCharged, userId, userEmail, successUrl, cancelUrl } = params;

  if (!FINTOC_SECRET_KEY) {
    throw new Error("fintoc_secret_key_missing");
  }

  const body: Record<string, unknown> = {
    currency: "CLP",
    success_url: successUrl,
    cancel_url: cancelUrl,
    metadata: {
      user_id: userId,
      amount_requested: amountRequested,
    },
    // Fintoc: line_items and amount are mutually exclusive — we use line_items
    // so the checkout page shows the item description.
    line_items: [
      {
        quantity: 1,
        price_data: {
          currency: "CLP",
          unit_amount: amountCharged,
          product_data: {
            name: "Recarga billetera Turno",
          },
        },
      },
    ],
  };

  if (userEmail?.trim()) {
    body.customer_email = userEmail.trim();
  }

  const res = await fetch(`${FINTOC_API_BASE}/checkout_sessions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      // Fintoc expects the raw secret key, no Bearer prefix
      "Authorization": FINTOC_SECRET_KEY,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const responseText = await res.text();
    logError("fintoc_checkout_create_failed", {
      status: res.status,
      response: responseText,
      amount_requested: amountRequested,
      amount_charged: amountCharged,
    });
    throw new Error("payment_provider_error");
  }

  const data = await res.json();
  return {
    checkout_session_id: data.id as string,
    redirect_url: data.redirect_url as string,
  };
}

async function recordPendingPayment(params: {
  checkoutSessionId: string;
  userId: string;
  amountRequested: number;
  feeAmount: number;
  amountCharged: number;
}): Promise<void> {
  const supabase = getServiceClient();
  const { error } = await supabase.from("fintoc_payments").upsert({
    checkout_session_id: params.checkoutSessionId,
    user_id: params.userId,
    amount: params.amountRequested,
    amount_requested: params.amountRequested,
    fee_amount: params.feeAmount,
    amount_charged: params.amountCharged,
    status: "pending",
    currency: "CLP",
  }, { onConflict: "checkout_session_id" });

  if (error) {
    // Non-fatal: the webhook can still credit via session metadata.
    logError("fintoc_pending_record_failed", {
      checkout_session_id: params.checkoutSessionId,
      error,
    });
  }
}

serve(async (req) => {
  const cors = corsHeadersFor(req);
  const jsonResponse = (payload: unknown, status = 200): Response =>
    new Response(JSON.stringify(payload), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  try {
    const user = await getAuthedUser(req.headers.get("Authorization"));
    if (!user) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const body = await req.json() as {
      amount?: unknown;
      success_url?: unknown;
      cancel_url?: unknown;
    };
    const amountRequested = sanitizeAmount(body.amount);

    if (amountRequested == null) {
      return jsonResponse({ error: "invalid_amount" }, 400);
    }

    if (amountRequested < 2000) {
      return jsonResponse({ error: "minimum amount is 2000 CLP" }, 400);
    }

    if (amountRequested > 200000) {
      return jsonResponse({ error: "maximum amount is 200000 CLP" }, 400);
    }

    const feeAmount = topupFee(amountRequested);
    const amountCharged = topupChargedAmount(amountRequested);

    const successUrl = sanitizeRedirectUrl(
      body.success_url,
      `${APP_BASE_URL}/wallet?topup=success`,
    );
    const cancelUrl = sanitizeRedirectUrl(
      body.cancel_url,
      `${APP_BASE_URL}/wallet?topup=failure`,
    );

    const provider = (Deno.env.get("PAYMENT_PROVIDER") ?? "fintoc").toLowerCase();
    if (provider === "disabled") {
      return jsonResponse({
        provider: "disabled",
        status: "disabled",
        message: "Recargas temporalmente deshabilitadas.",
        amount_requested: amountRequested,
        fee_amount: feeAmount,
        amount_charged: amountCharged,
      });
    }

    logInfo("topup_intent_requested", {
      user_id: user.id,
      provider: "fintoc",
      amount_requested: amountRequested,
      fee_amount: feeAmount,
      amount_charged: amountCharged,
    });

    const fintocResult = await createFintocCheckout({
      amountRequested,
      amountCharged,
      userId: user.id,
      userEmail: user.email,
      successUrl,
      cancelUrl,
    });

    await recordPendingPayment({
      checkoutSessionId: fintocResult.checkout_session_id,
      userId: user.id,
      amountRequested,
      feeAmount,
      amountCharged,
    });

    return jsonResponse({
      provider: "fintoc",
      checkout_session_id: fintocResult.checkout_session_id,
      redirect_url: fintocResult.redirect_url,
      amount_requested: amountRequested,
      fee_amount: feeAmount,
      amount_charged: amountCharged,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logError("create_topup_intent_unhandled", { message });
    if (message === "fintoc_secret_key_missing") {
      return jsonResponse({ error: "fintoc_secret_key_missing" }, 503);
    }
    if (message === "payment_provider_error") {
      return jsonResponse({ error: "payment_provider_error" }, 502);
    }
    return jsonResponse({ error: "internal_server_error" }, 500);
  }
});
