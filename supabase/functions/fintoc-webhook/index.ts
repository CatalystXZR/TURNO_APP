// supabase/functions/fintoc-webhook/index.ts
//
// Receives Fintoc webhook events and credits the user's wallet.
// Events handled: checkout_session.finished, payment_intent.succeeded
//
// Fintoc event structure: data IS the checkout session (flat, not nested)
// Signature: Fintoc-Signature header with format "t=<ts>,v1=<sig>"
// Message to verify: "<timestamp>.<raw_body>"
//
// Idempotent: credit_wallet_topup RPC skips duplicate checkout_session_id.

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

async function verifySignature(req: Request, rawBody: string): Promise<boolean> {
  if (!FINTOC_WEBHOOK_SECRET) {
    logError("fintoc_webhook_secret_missing_rejecting_all");
    return false;
  }

  const header = req.headers.get("Fintoc-Signature");
  if (!header) {
    logError("fintoc_webhook_missing_signature_header");
    return false;
  }

  const parts = Object.fromEntries(
    header.split(";").map((part) => {
      const [k, v] = part.split("=");
      return [k.trim(), v?.trim() ?? ""];
    }),
  );

  const ts = parts["t"];
  const receivedSig = parts["v1"];

  if (!ts || !receivedSig) {
    logError("fintoc_webhook_malformed_signature", { header });
    return false;
  }

  const tsNum = Number(ts);
  if (!Number.isFinite(tsNum) || Math.abs(Date.now() / 1000 - tsNum) > 300) {
    logError("fintoc_webhook_stale_timestamp", { ts });
    return false;
  }

  const message = `${ts}.${rawBody}`;
  const computedSig = await computeHmac(message, FINTOC_WEBHOOK_SECRET);

  if (!timingSafeEqual(computedSig, receivedSig)) {
    logError("fintoc_webhook_signature_mismatch");
    return false;
  }

  return true;
}

function extractUserAndAmount(session: Record<string, unknown>): {
  userId: string;
  amountRequested: number;
} | null {
  // Metadata from our own create-topup-intent
  const metadata = (session.metadata as Record<string, unknown>) ?? {};
  const userId = metadata.user_id as string | undefined;
  const amountMeta = metadata.amount_requested;

  // Fallback: try to get amount from the session directly
  const sessionAmount = typeof session.amount === "number" ? session.amount : 0;

  if (!userId || !isValidUuid(userId)) {
    logError("fintoc_webhook_missing_user_id", {
      session_id: session.id,
      metadata,
    });
    return null;
  }

  const amountRequested = typeof amountMeta === "number" && amountMeta > 0
    ? amountMeta
    : sessionAmount > 0
    ? sessionAmount
    : 0;

  if (amountRequested <= 0) {
    logError("fintoc_webhook_invalid_amount", {
      session_id: session.id,
      amount_meta: amountMeta,
      session_amount: sessionAmount,
    });
    return null;
  }

  return { userId, amountRequested: Math.round(amountRequested) };
}

async function handleEvent(
  event: Record<string, unknown>,
): Promise<Response> {
  const eventType = event.type as string | undefined;
  // Fintoc event structure: data IS the checkout session (flat)
  const session = event.data as Record<string, unknown> | undefined;

  if (!session || !session.id) {
    logError("fintoc_webhook_missing_session", { event_type: eventType });
    return new Response("missing session data", { status: 400 });
  }

  const checkoutSessionId = session.id as string;
  const sessionStatus = (session.status as string) ?? "";

  // Only process terminal states
  const finalStates = ["succeeded", "finished"];
  if (!finalStates.includes(sessionStatus) &&
      eventType !== "checkout_session.finished" &&
      eventType !== "payment_intent.succeeded") {
    logInfo("fintoc_webhook_skipped_status", {
      checkout_session_id: checkoutSessionId,
      status: sessionStatus,
      event_type: eventType,
    });
    return new Response("status not final", { status: 200 });
  }

  const extracted = extractUserAndAmount(session);
  if (!extracted) {
    return new Response("invalid session data", { status: 400 });
  }

  const { userId, amountRequested } = extracted;
  const feeAmount = Math.round(amountRequested * 0.01);
  const amountCharged = amountRequested + feeAmount;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { error: creditErr } = await supabase.rpc("credit_wallet_topup", {
    p_user_id: userId,
    p_amount: amountRequested,
    p_external_payment_id: checkoutSessionId,
    p_amount_charged: amountCharged,
    p_fee_amount: feeAmount,
    p_provider: "fintoc",
  });

  if (creditErr) {
    logError("fintoc_credit_wallet_topup_failed", {
      checkout_session_id: checkoutSessionId,
      error: creditErr,
    });
    return new Response("db credit failed", { status: 500 });
  }

  logInfo("fintoc_wallet_topped_up", {
    checkout_session_id: checkoutSessionId,
    user_id: userId,
    amount: amountRequested,
  });

  return new Response(
    JSON.stringify({ status: "success", checkout_session_id: checkoutSessionId }),
    {
      headers: { "Content-Type": "application/json" },
      status: 200,
    },
  );
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
