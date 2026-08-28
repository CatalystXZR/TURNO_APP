/**
 *
 * Project: Turno
 *
 * Original Concept: Agustin Puelma, Cristobal Cordova, Carlos Ibarra
 *
 * Software Architecture & Code: Matias Toledo (catalystxzr)
 *
 * Description: Production-grade implementation for UDD carpooling system.
 *
 * Copyright (c) 2026. All rights reserved.
 *
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
    const token = extractBearerToken(req.headers.get("Authorization"));
    if (!token) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? (() => { throw new Error("SUPABASE_URL is required"); })();
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? (() => { throw new Error("SUPABASE_SERVICE_ROLE_KEY is required"); })();
    const supabaseAdmin = createClient(supabaseUrl, serviceKey);

    const { data: { user }, error: authErr } = await supabaseAdmin.auth.getUser(token);
    if (authErr || !user) {
      return jsonResponse({ error: "invalid_token" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const reason = typeof body?.reason === "string" ? body.reason.trim() : null;

    logInfo("account_delete_requested", {
      user_id: user.id,
      reason,
    });

    // Call the delete_user_account RPC with the user's UUID explicitly.
    // Uses the service_role client (supabaseAdmin) to bypass RLS. The RPC
    // runs as SECURITY DEFINER and handles the full cleanup of associated data.
    const { error: rpcErr } = await supabaseAdmin.rpc("delete_user_account", {
      p_user_id: user.id,
      p_reason: reason || null,
    });

    if (rpcErr) {
      logError("delete_user_account_rpc_failed", {
        user_id: user.id,
        error: rpcErr.message,
      });

      // Fallback: attempt direct auth deletion (may still fail on FK constraints
      // if the RPC didn't clean up child tables first).
      const { error: deleteErr } = await supabaseAdmin.auth.admin.deleteUser(user.id, true);
      if (deleteErr) {
        logError("account_delete_failed", {
          user_id: user.id,
          error: deleteErr.message,
        });
        return jsonResponse({ error: "delete_failed" }, 500);
      }
    }

    logInfo("account_deleted", { user_id: user.id });
    return jsonResponse({ success: true });
  } catch (err) {
    logError("account_delete_unhandled", {
      message: err instanceof Error ? err.message : String(err),
    });
    return jsonResponse({ error: "internal_server_error" }, 500);
  }
});
