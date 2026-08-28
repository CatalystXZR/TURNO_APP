// supabase/functions/fintoc-webhook/index.ts
//
// Receives Fintoc webhook events and credits the user's wallet.
// Handles: checkout_session.finished, checkout_session.expired,
//          payment_intent.succeeded, payment_intent.failed,
//          payment_intent.requires_action
//
// Fintoc event structure: data IS the resource object (flat, not nested).
// Signature: Fintoc-Signature header, format "t=<ts>,v1=<sig>"
//   (comma-separated). Message to verify: "<timestamp>.<raw_body>".
//
// Idempotency: credit_wallet_topup RPC no-ops for duplicated
// checkout_session_id with status 'approved'. Fintoc retries up to
// 17 times, so every path must return 2xx fast.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FINTOC_WEBHOOK_SECRET = Deno.env.get("FINTOC_WEBHOOK_SECRET") ?? "";

function logInfo(event: string, details: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ level: "info", event, ...details }));
}

function logWarn(event: string, details: Record<string, unknown> = {}) {
  console.warn(JSON.stringify({ level: "warn", event, ...details }));
}

function logError(event: string, details: Record<string, unknown> = {}) {
  console.error(JSON.stringify({ level: "error", event, ...details }));
}

function isValidUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

async function computeHmac(message: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

// Fintoc-Signature: "t=1620870928,v1=4df951e02db..." (comma-separated)
function parseSignatureHeader(header: string | null): { t?: string; v1?: string } {
  if (!header) return {};
  const parts: Record<string, string> = {};
  for (const pair of header.split(",")) {
    const idx = pair.indexOf("=");
    if (idx === -1) continue;
    parts[pair.slice(0, idx).trim()] = pair.slice(idx + 1).trim();
  }
  return { t: parts["t"], v1: parts["v1"] };
}

async function verifySignature(req: Request, rawBody: string): Promise<boolean> {
  if (!FINTOC_WEBHOOK_SECRET) {
    logError("fintoc_webhook_secret_missing_rejecting_all");
    return false;
  }

  const { t, v1 } = parseSignatureHeader(req.headers.get("Fintoc-Signature"));

  if (!t || !v1) {
    logError("fintoc_webhook_malformed_signature", {
      header: req.headers.get("Fintoc-Signature"),
    });
    return false;
  }

  const tsNum = Number(t);
  if (!Number.isFinite(tsNum) || Math.abs(Date.now() / 1000 - tsNum) > 300) {
    logError("fintoc_webhook_stale_timestamp", { t });
    return false;
  }

  const message = `${t}.${rawBody}`;
  const computedSig = await computeHmac(message, FINTOC_WEBHOOK_SECRET);

  if (!timingSafeEqual(computedSig, v1)) {
    logError("fintoc_webhook_signature_mismatch");
    return false;
  }

  return true;
}

function getServiceClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? (() => { throw new Error("SUPABASE_URL is required"); })();
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? (() => { throw new Error("SUPABASE_SERVICE_ROLE_KEY is required"); })();
  return createClient(supabaseUrl, serviceKey);
}

interface PendingPayment {
  checkout_session_id: string;
  user_id: string;
  amount_requested: number;
  fee_amount: number;
  amount_charged: number;
  status: string;
}

// Authoritative amounts come from the row our own edge function created.
// Falls back to session metadata for sessions created before migration 33.
async function resolvePayment(
  supabase: ReturnType<typeof getServiceClient>,
  checkoutSessionId: string,
  session: Record<string, unknown>,
): Promise<PendingPayment | null> {
  const { data: row, error } = await supabase
    .from("fintoc_payments")
    .select("checkout_session_id, user_id, amount_requested, fee_amount, amount_charged, status")
    .eq("checkout_session_id", checkoutSessionId)
    .maybeSingle();

  if (!error && row) {
    return {
      checkout_session_id: row.checkout_session_id,
      user_id: row.user_id,
      amount_requested: row.amount_requested,
      fee_amount: row.fee_amount,
      amount_charged: row.amount_charged,
      status: row.status,
    };
  }

  // Fallback: metadata from our own create-topup-intent
  const metadata = (session.metadata as Record<string, unknown>) ?? {};
  const userId = metadata.user_id as string | undefined;
  const amountMeta = metadata.amount_requested;
  const sessionAmount = typeof session.amount === "number" ? session.amount : 0;

  if (!userId || !isValidUuid(userId)) {
    logError("fintoc_webhook_missing_user_id", { checkout_session_id: checkoutSessionId });
    return null;
  }

  const amountRequested = typeof amountMeta === "number" && amountMeta > 0
    ? Math.round(amountMeta)
    : sessionAmount > 0
    ? sessionAmount
    : 0;

  if (amountRequested <= 0) {
    logError("fintoc_webhook_invalid_amount", {
      checkout_session_id: checkoutSessionId,
      amount_meta: amountMeta,
      session_amount: sessionAmount,
    });
    return null;
  }

  const feeAmount = Math.round(amountRequested * 0.01);
  const amountCharged = amountRequested + feeAmount;

  return {
    checkout_session_id: checkoutSessionId,
    user_id: userId,
    amount_requested: amountRequested,
    fee_amount: feeAmount,
    amount_charged: amountCharged,
    status: "pending",
  };
}

async function creditWallet(supabase: ReturnType<typeof getServiceClient>, payment: PendingPayment): Promise<boolean> {
  const { error: creditErr } = await supabase.rpc("credit_wallet_topup", {
    p_user_id: payment.user_id,
    p_amount: payment.amount_requested,
    p_external_payment_id: payment.checkout_session_id,
    p_amount_charged: payment.amount_charged,
    p_fee_amount: payment.fee_amount,
    p_provider: "fintoc",
  });

  if (creditErr) {
    logError("fintoc_credit_wallet_topup_failed", {
      checkout_session_id: payment.checkout_session_id,
      error: creditErr,
    });
    return false;
  }

  logInfo("fintoc_wallet_topped_up", {
    checkout_session_id: payment.checkout_session_id,
    user_id: payment.user_id,
    amount: payment.amount_requested,
  });
  return true;
}

async function setStatus(
  supabase: ReturnType<typeof getServiceClient>,
  checkoutSessionId: string,
  status: "failed" | "expired" | "requires_action" | "pending",
): Promise<void> {
  const { error } = await supabase.rpc("update_fintoc_payment_status", {
    p_checkout_session_id: checkoutSessionId,
    p_status: status,
  });
  if (error) {
    logWarn("fintoc_status_update_failed", { checkout_session_id: checkoutSessionId, status, error });
  }
}

async function linkPaymentIntent(
  supabase: ReturnType<typeof getServiceClient>,
  checkoutSessionId: string,
  paymentIntentId: string,
): Promise<void> {
  const { error } = await supabase
    .from("fintoc_payments")
    .update({ payment_intent_id: paymentIntentId })
    .eq("checkout_session_id", checkoutSessionId);
  if (error) {
    logWarn("fintoc_link_payment_intent_failed", { checkoutSessionId, paymentIntentId, error });
  }
}

async function findByPaymentIntent(
  supabase: ReturnType<typeof getServiceClient>,
  paymentIntentId: string,
): Promise<PendingPayment | null> {
  const { data: row, error } = await supabase
    .from("fintoc_payments")
    .select("checkout_session_id, user_id, amount_requested, fee_amount, amount_charged, status")
    .eq("payment_intent_id", paymentIntentId)
    .maybeSingle();

  if (error || !row) return null;

  return {
    checkout_session_id: row.checkout_session_id,
    user_id: row.user_id,
    amount_requested: row.amount_requested,
    fee_amount: row.fee_amount,
    amount_charged: row.amount_charged,
    status: row.status,
  };
}

async function handleEvent(event: Record<string, unknown>): Promise<Response> {
  const eventType = event.type as string | undefined;
  const data = event.data as Record<string, unknown> | undefined;

  if (!data || typeof data !== "object") {
    logWarn("fintoc_webhook_missing_data", { event_type: eventType });
    return new Response("missing data", { status: 200 });
  }

  const supabase = getServiceClient();
  const resourceType = data.object as string | undefined;

  // ---- checkout_session events: data IS the checkout session ----
  if (resourceType === "checkout_session") {
    const session = data;
    const checkoutSessionId = session.id as string;
    const paymentResource = session.payment_resource as Record<string, unknown> | undefined;
    const paymentIntent = paymentResource?.payment_intent as Record<string, unknown> | undefined;
    const paymentIntentId = paymentIntent?.id as string | undefined;
    const piStatus = paymentIntent?.status as string | undefined;

    if (!checkoutSessionId) {
      return new Response("missing session id", { status: 200 });
    }

    if (paymentIntentId) {
      await linkPaymentIntent(supabase, checkoutSessionId, paymentIntentId);
    }

    if (eventType === "checkout_session.expired") {
      logInfo("fintoc_session_expired", { checkout_session_id: checkoutSessionId });
      await setStatus(supabase, checkoutSessionId, "expired");
      return new Response("expired recorded", { status: 200 });
    }

    if (eventType !== "checkout_session.finished") {
      logInfo("fintoc_session_event_skipped", { checkout_session_id: checkoutSessionId, event_type: eventType });
      return new Response("skipped", { status: 200 });
    }

    if (piStatus !== "succeeded") {
      // Session reached a final state without a successful payment.
      if (piStatus === "failed") {
        await setStatus(supabase, checkoutSessionId, "failed");
      } else if (piStatus === "requires_action") {
        await setStatus(supabase, checkoutSessionId, "requires_action");
      }
      logInfo("fintoc_session_finished_not_succeeded", {
        checkout_session_id: checkoutSessionId,
        payment_intent_status: piStatus ?? "missing",
      });
      return new Response("not succeeded", { status: 200 });
    }

    const payment = await resolvePayment(supabase, checkoutSessionId, session);
    if (!payment) {
      return new Response("unresolvable payment", { status: 200 });
    }

    const credited = await creditWallet(supabase, payment);
    return credited
      ? new Response(JSON.stringify({ status: "credited" }), { headers: { "Content-Type": "application/json" }, status: 200 })
      : new Response("credit failed", { status: 500 });
  }

  // ---- payment_intent events: data IS the payment intent ----
  if (resourceType === "payment_intent") {
    const paymentIntentId = data.id as string;
    if (!paymentIntentId) {
      return new Response("missing payment intent id", { status: 200 });
    }

    const payment = await findByPaymentIntent(supabase, paymentIntentId);
    if (!payment) {
      // checkout_session.finished (which fires first) is the authoritative
      // crediting path; without a linked row there is nothing to do here.
      logInfo("fintoc_payment_intent_unlinked", { payment_intent_id: paymentIntentId, event_type: eventType });
      return new Response("unlinked", { status: 200 });
    }

    if (eventType === "payment_intent.succeeded") {
      const credited = await creditWallet(supabase, payment);
      return credited
        ? new Response(JSON.stringify({ status: "credited" }), { headers: { "Content-Type": "application/json" }, status: 200 })
        : new Response("credit failed", { status: 500 });
    }

    if (eventType === "payment_intent.failed" || eventType === "payment_intent.rejected") {
      await setStatus(supabase, payment.checkout_session_id, "failed");
      return new Response("failed recorded", { status: 200 });
    }

    if (eventType === "payment_intent.requires_action") {
      await setStatus(supabase, payment.checkout_session_id, "requires_action");
      return new Response("requires action recorded", { status: 200 });
    }

    logInfo("fintoc_payment_intent_event_skipped", { payment_intent_id: paymentIntentId, event_type: eventType });
    return new Response("skipped", { status: 200 });
  }

  logInfo("fintoc_unknown_resource_type", { event_type: eventType, resource_type: resourceType });
  return new Response("unhandled resource type", { status: 200 });
}

Deno.serve(async (req) => {
  if (req.method === "GET") return new Response("ok", { status: 200 });

  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  try {
    const rawBody = await req.text();

    const signatureValid = await verifySignature(req, rawBody);
    if (!signatureValid) {
      return new Response("invalid signature", { status: 401 });
    }

    const body = JSON.parse(rawBody) as Record<string, unknown>;
    logInfo("fintoc_webhook_received", {
      event_type: body.type as string,
      event_id: body.id as string,
    });

    return await handleEvent(body);
  } catch (err) {
    logError("fintoc_webhook_unhandled", {
      message: err instanceof Error ? err.message : String(err),
    });
    return new Response("internal error", { status: 500 });
  }
});
