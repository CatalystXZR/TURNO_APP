// supabase/functions/create-topup-intent/index.ts
//
// Creates a Fintoc Checkout Session for wallet top-up.
// Returns redirect_url so the user can pay on Fintoc's hosted page.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const APP_BASE_URL = Deno.env.get("APP_BASE_URL") ?? "https://turnoapp.cl";

const FINTOC_SECRET_KEY = Deno.env.get("FINTOC_SECRET_KEY") ?? "";
const FINTOC_API_BASE = "https://api.fintoc.com/v2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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

async function getAuthedUser(authHeader: string | null) {
  const token = extractBearerToken(authHeader);
  if (!token) return null;

  const supabase = createClient(
    SUPABASE_URL,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) return null;
  return user;
}

async function createFintocCheckout(params: {
  amountRequested: number;
  amountCharged: number;
  userId: string;
  userEmail?: string;
}): Promise<{ checkout_session_id: string; redirect_url: string }> {
  const { amountRequested, amountCharged, userId, userEmail } = params;

  if (!FINTOC_SECRET_KEY) {
    throw new Error("fintoc_secret_key_missing");
  }

  const body: Record<string, unknown> = {
    amount: amountCharged,
    currency: "CLP",
    success_url: `${APP_BASE_URL}/wallet?topup=success`,
    cancel_url: `${APP_BASE_URL}/wallet?topup=failure`,
    metadata: {
      user_id: userId,
      amount_requested: amountRequested,
    },
  };

  if (userEmail?.trim()) {
    body.customer_email = userEmail.trim();
  }

  const res = await fetch(`${FINTOC_API_BASE}/checkout_sessions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  try {
    const user = await getAuthedUser(req.headers.get("Authorization"));
    if (!user) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const body = await req.json() as { amount?: unknown };
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
    logError("create_topup_intent_unhandled", {
      message: err instanceof Error ? err.message : String(err),
    });
    if (err instanceof Error && err.message === "payment_provider_error") {
      return jsonResponse({ error: "payment_provider_error" }, 502);
    }
    return jsonResponse({ error: "internal_server_error" }, 500);
  }
});
