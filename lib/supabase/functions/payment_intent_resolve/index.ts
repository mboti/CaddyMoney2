// Supabase Edge Function: payment_intent_resolve
//
// Resolves a QR-scanned token (or payment intent UUID) to server-authoritative details.
//
// IMPORTANT: Your *remote* DB schema uses `amount_cents` (int) not `amount`.
// The Flutter client already supports both, but this function must query the real column.
//
// Request (POST JSON):
//   { "token_or_id": "<opaque token or uuid>" }
//
// Response (200 JSON):
//   {
//     "success": true,
//     "payment_intent": {
//       "id": "...",
//       "token": "...",
//       "amount_cents": 1234,
//       "currency_code": "EUR",
//       "status": "pending|completed|expired|cancelled",
//       "expires_at": "...",
//       "created_at": "...",
//       "updated_at": "...",
//       "merchant": { "id": "...", "business_name": "..." }
//     }
//   }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Json = Record<string, unknown>;

type SupabaseErrorLike = {
  message?: string;
  details?: string;
  hint?: string;
  code?: string;
};

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

function jsonResponse(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
}

function requiredEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing environment variable: ${name}`);
  return v;
}

function looksLikeUuid(v: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v);
}

function normalizeTypingCode(v: string): string {
  // Allow user-entered formats like "abcd-efgh", "ABCD EFGH", etc.
  return v.replace(/[^a-z0-9]/gi, "").toUpperCase();
}

function looksLikeTypingCode(v: string): boolean {
  // Current design: 8 chars, uppercase, no confusing characters.
  // We'll accept any alnum and normalize before matching.
  return /^[a-z0-9]{8}$/i.test(v);
}

function formatSupabaseError(err: unknown): Json | null {
  if (!err || typeof err !== "object") return null;
  const e = err as SupabaseErrorLike;
  const out: Json = {};
  if (typeof e.code === "string" && e.code) out.code = e.code;
  if (typeof e.message === "string" && e.message) out.message = e.message;
  if (typeof e.details === "string" && e.details) out.details = e.details;
  if (typeof e.hint === "string" && e.hint) out.hint = e.hint;
  return Object.keys(out).length ? out : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse(405, { error: "Method not allowed" });

  try {
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");

    // verify_jwt is disabled for easier web usage, but we still validate the caller.
    const authHeader = req.headers.get("authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return jsonResponse(401, { error: "Missing Authorization header" });
    }

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !userData?.user) {
      return jsonResponse(401, { error: "Unauthorized", supabase: formatSupabaseError(userErr) ?? undefined });
    }

    const body = (await req.json()) as Json;
    const raw = String(body.token_or_id ?? "").trim();
    if (!raw) return jsonResponse(400, { error: "Missing token_or_id" });

    const normalized = normalizeTypingCode(raw);
    const rawLooksLikeCode = looksLikeTypingCode(normalized);

    // Use service role for resolving by token (token is not tied to auth.uid()).
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const byId = looksLikeUuid(raw);

    const baseQuery = admin
      .from("payment_intents")
      .select(
        // NOTE: Some deployments encode the QR as `short_code`, others reuse `transaction_reference`.
        // We include both so the client can always resolve an 8-char QR.
        "id,token,short_code,transaction_reference,merchant_id,amount_cents,currency_code,status,expires_at,created_at,updated_at",
      );

    let intent: any = null;
    let intentErr: any = null;
    if (byId) {
      const res = await baseQuery.eq("id", raw).maybeSingle();
      intent = res.data;
      intentErr = res.error;
    } else {
      // Prefer resolving by short_code / transaction_reference when it looks like a typing code.
      // This avoids potential filter parsing edge cases when `raw` is a long token.
      if (rawLooksLikeCode) {
        const res = await baseQuery
          .or(`short_code.eq.${normalized},transaction_reference.eq.${normalized},transaction_reference.eq.${raw}`)
          .maybeSingle();
        intent = res.data;
        intentErr = res.error;
      } else {
        // Resolve by token first, then fall back to short_code / transaction_reference.
        const res = await baseQuery
          .or(
            `token.eq.${raw},short_code.eq.${normalized},short_code.eq.${raw},transaction_reference.eq.${normalized},transaction_reference.eq.${raw}`,
          )
          .maybeSingle();
        intent = res.data;
        intentErr = res.error;
      }

      // Backward compatibility: if the DB doesn't have `short_code` yet, fallback to token-only.
      const msg = String((intentErr as any)?.message ?? "").toLowerCase();
      if (intentErr && msg.includes("short_code") && msg.includes("does not exist")) {
        const fallback = await admin
          .from("payment_intents")
          .select("id,token,transaction_reference,merchant_id,amount_cents,currency_code,status,expires_at,created_at,updated_at")
          .or(`token.eq.${raw},transaction_reference.eq.${normalized},transaction_reference.eq.${raw}`)
          .maybeSingle();
        intent = fallback.data;
        intentErr = fallback.error;
      }
    }

    if (intentErr) {
      console.error("payment_intent_resolve: intent query failed", intentErr);
      return jsonResponse(500, {
        error: "Failed to fetch payment intent",
        supabase: formatSupabaseError(intentErr) ?? undefined,
      });
    }

    if (!intent?.id) return jsonResponse(404, { error: "Payment intent not found" });

    let merchantName: string | null = null;
    let merchantCategories: string[] = [];
    if (intent.merchant_id) {
      const { data: merchant, error: merchantErr } = await admin
        .from("merchants")
        // Include categories so the user confirmation UI can display them.
        // Expected column type: text[] (or json/array-like).
        .select("id,business_name,categories")
        .eq("id", intent.merchant_id)
        .maybeSingle();

      if (merchantErr) {
        console.error("payment_intent_resolve: merchant query failed", merchantErr);
        return jsonResponse(500, {
          error: "Failed to fetch merchant",
          supabase: formatSupabaseError(merchantErr) ?? undefined,
        });
      }

      merchantName = (merchant as any)?.business_name ?? null;
      const rawCategories = (merchant as any)?.categories;
      if (Array.isArray(rawCategories)) {
        merchantCategories = rawCategories.map((c) => String(c)).map((c) => c.trim()).filter((c) => c.length > 0);
      } else {
        merchantCategories = [];
      }
    }

    // Derive status based on expiry time (server-authoritative).
    const now = new Date();
    const expiresAt = intent.expires_at ? new Date(String(intent.expires_at)) : null;
    const rawStatus = String(intent.status ?? "pending").toLowerCase();

    let derivedStatus = rawStatus;
    if (rawStatus === "pending" && expiresAt && now.getTime() > expiresAt.getTime()) {
      derivedStatus = "expired";
    }

    return jsonResponse(200, {
      success: true,
      payment_intent: {
        ...intent,
        status: derivedStatus,
        merchant: {
          id: intent.merchant_id ?? null,
          business_name: merchantName,
          categories: merchantCategories,
        },
      },
    });
  } catch (e) {
    console.error("payment_intent_resolve: unhandled", e);
    return jsonResponse(500, { error: (e as Error)?.message ?? "Internal error" });
  }
});
