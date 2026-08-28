/**
 *
 * Project: Turno
 *
 * Description: Edge Function that sends APNs push notifications
 *              to iOS devices via Apple's HTTP/2 API.
 *
 * Called from DB trigger via pg_net when booking dispatch_status changes.
 *
 * Required secrets (set in Supabase Dashboard > Edge Functions):
 *   APNS_KEY_ID        = Apple Key ID (10-char alphanumeric)
 *   APNS_TEAM_ID       = Apple Team ID
 *   APNS_BUNDLE_ID      = App bundle identifier (e.g., com.turnoapp.app)
 *   APNS_KEY_BASE64    = Base64-encoded contents of the .p8 APNs key
 *   INTERNAL_PUSH_SECRET = Shared secret to validate incoming calls from DB trigger
 *
 * Environment:
 *   SUPABASE_URL        = set automatically by Supabase
 *   SUPABASE_SERVICE_ROLE_KEY = set automatically by Supabase
 *
 * Copyright (c) 2026. All rights reserved.
 *
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function base64url(buf: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function createES256Jwt(
  header: { alg: string; kid: string },
  payload: Record<string, unknown>,
  privateKey: CryptoKey,
): Promise<string> {
  const enc = new TextEncoder();
  const headerB64 = base64url(enc.encode(JSON.stringify(header)));
  const payloadB64 = base64url(enc.encode(JSON.stringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    enc.encode(signingInput),
  );
  const sigB64 = base64url(sig);
  return `${signingInput}.${sigB64}`;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? (() => { throw new Error("SUPABASE_URL is required"); })();
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? (() => { throw new Error("SUPABASE_SERVICE_ROLE_KEY is required"); })();

const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "com.turnoapp.app";
const APNS_KEY_BASE64 = Deno.env.get("APNS_KEY_BASE64") ?? "";

const INTERNAL_SECRET = Deno.env.get("INTERNAL_PUSH_SECRET") ?? "";

const APNS_BASE_URL = "https://api.push.apple.com";
const APNS_ENDPOINT = (token: string) => `/3/device/${token}`;

let apnsJwtCache: { token: string; expiresAt: number } | null = null;

const ALLOWED_ORIGINS = [
  "https://turnoapp.cl",
  "https://www.turnoapp.cl",
];

function corsHeadersFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin");
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    return {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-internal-secret",
      "Vary": "Origin",
    };
  }
  return {};
}

function logInfo(event: string, details: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ level: "info", event, ...details }));
}

function logError(event: string, details: Record<string, unknown> = {}) {
  console.error(JSON.stringify({ level: "error", event, ...details }));
}

async function getApnsJwt(): Promise<string> {
  if (apnsJwtCache && apnsJwtCache.expiresAt > Date.now() + 30_000) {
    return apnsJwtCache.token;
  }

  if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_KEY_BASE64) {
    throw new Error("apns_config_missing");
  }

  const keyBase64 = APNS_KEY_BASE64.replace(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(keyBase64), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);
  const jwt = await createES256Jwt(
    { alg: "ES256", kid: APNS_KEY_ID },
    {
      iss: APNS_TEAM_ID,
      iat: now,
    },
    cryptoKey,
  );

  apnsJwtCache = {
    token: jwt,
    expiresAt: Date.now() + 50 * 60 * 1000,
  };

  return jwt;
}

async function sendApnsNotification(
  token: string,
  title: string,
  body: string,
  customPayload: Record<string, unknown>,
): Promise<{ success: boolean; error?: string }> {
  if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_KEY_BASE64) {
    return { success: false, error: "apns_not_configured" };
  }

  try {
    const jwt = await getApnsJwt();

    const apnsPayload = {
      aps: {
        alert: {
          title,
          body,
        },
        sound: "default",
        badge: 1,
      },
      ...customPayload,
    };

    const url = `${APNS_BASE_URL}${APNS_ENDPOINT(token)}`;
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "authorization": `bearer ${jwt}`,
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify(apnsPayload),
    });

    if (response.status === 410) {
      return { success: false, error: "token_expired" };
    }
    if (!response.ok) {
      const body = await response.text();
      return { success: false, error: `apns_error_${response.status}: ${body}` };
    }

    return { success: true };
  } catch (err) {
    return {
      success: false,
      error: err instanceof Error ? err.message : "unknown_error",
    };
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
    if (!INTERNAL_SECRET) {
      logError("push_notification_secret_not_configured");
      return jsonResponse({ error: "service_not_configured" }, 503);
    }

    const internalSecret = req.headers.get("X-Internal-Secret");
    if (internalSecret !== INTERNAL_SECRET) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const payload = await req.json() as {
      user_id?: string;
      title?: string;
      body?: string;
      booking_id?: string;
      ride_id?: string;
    };

    const { user_id, title, body, booking_id, ride_id } = payload;

    if (!user_id || !title || !body) {
      return jsonResponse({ error: "missing_required_fields" }, 400);
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: tokens, error: dbError } = await supabase
      .from("device_tokens")
      .select("token, platform")
      .eq("user_id", user_id);

    if (dbError) {
      logError("db_query_failed", { user_id, error: dbError.message });
      return jsonResponse({ error: "db_error" }, 500);
    }

    if (!tokens || tokens.length === 0) {
      logInfo("no_device_tokens", { user_id });
      return jsonResponse({ sent: false, reason: "no_device_tokens" }, 200);
    }

    const customPayload: Record<string, unknown> = {};
    if (booking_id) customPayload.booking_id = booking_id;
    if (ride_id) customPayload.ride_id = ride_id;

    let succeeded = 0;
    let expired = 0;
    let failed = 0;

    for (const device of tokens) {
      const result = await sendApnsNotification(
        device.token,
        title,
        body,
        customPayload,
      );

      if (result.success) {
        succeeded++;
      } else if (result.error === "token_expired") {
        expired++;
        await supabase
          .from("device_tokens")
          .delete()
          .eq("token", device.token)
          .eq("user_id", user_id)
          .then(
            () => {},
            () => {}
          );
      } else {
        failed++;
        logError("apns_send_failed", {
          user_id,
          platform: device.platform,
          error: result.error,
        });
      }
    }

    logInfo("push_sent", { user_id, succeeded, expired, failed });

    return jsonResponse({
      sent: succeeded > 0,
      details: { succeeded, expired, failed },
    });
  } catch (err) {
    logError("unhandled_error", {
      message: err instanceof Error ? err.message : String(err),
    });
    return jsonResponse({ error: "internal_server_error" }, 500);
  }
});
