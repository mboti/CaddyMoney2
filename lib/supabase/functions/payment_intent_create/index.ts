// Supabase Edge Function: payment_intent_create
//
// IMPORTANT:
// - This function is deployed with verify_jwt = false (gateway), because some
//   projects encounter gateway-side “Invalid JWT” while the same token is valid
//   against /auth/v1/user.
// - We still enforce authentication securely INSIDE the function by validating
//   the bearer token via supabase.auth.getUser().
//
// Creates a payment intent (payment request) for a merchant.
// SECURITY PRINCIPLES:
// - Never trust the Flutter client for validation.
// - QR must encode ONLY an opaque identifier/token (not amount as proof).
// - The merchant app never finalizes the payment.
//
// Expected request body (JSON):
// {
//   "amount": 12.34,
//   "currency_code": "EUR"
// }
//
// Response (JSON):
// {
//   "success": true,
//   "payment_intent": {
//     "id": "...",
//     "token": "...",
//     "amount_cents": 1234,
//     "currency_code": "EUR",
//     "status": "pending",
//     "created_at": "...",
//     "updated_at": "...",
//     "expires_at": "..."
//   }
// }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Json = Record<string, unknown>;

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

function randomToken(bytes = 16): string {
  // URL-safe base64 token.
  const arr = crypto.getRandomValues(new Uint8Array(bytes));
  let b64 = btoa(String.fromCharCode(...arr));
  b64 = b64.replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
  return b64;
}

function randomTypingCode(length = 8): string {
  // Human-friendly, uppercase, no ambiguous chars (no I/O/1/0).
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const arr = crypto.getRandomValues(new Uint8Array(length));
  let out = "";
  for (let i = 0; i < length; i++) out += alphabet[arr[i] % alphabet.length];
  return out;
}

function parseAmountCents(input: unknown): number | null {
  // Accepts number or string. Enforces 2 decimal places max.
  if (input === null || input === undefined) return null;
  const n = typeof input === "number" ? input : Number(String(input).replace(",", "."));
  if (!Number.isFinite(n)) return null;
  if (n <= 0) return null;
  const cents = Math.round(n * 100);
  const back = cents / 100;
  if (Math.abs(back - n) > 0.00001) return null;
  return cents;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse(405, { error: "Method not allowed" });

  try {
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");

    const authHeader = req.headers.get("authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return jsonResponse(401, { error: "Missing Authorization header" });
    }

    // Validate the JWT by calling GoTrue, rather than trusting the client.
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !userData?.user) {
      return jsonResponse(401, { error: "Unauthorized" });
    }

    const profileId = userData.user.id;

    const body = (await req.json()) as Json;
    const amountCents = parseAmountCents(body.amount);
    const currencyCode = String(body.currency_code ?? "EUR").toUpperCase().trim();

    // Server-side validation (do not trust client):
    if (amountCents === null) return jsonResponse(400, { error: "Invalid amount" });
    if (!currencyCode || currencyCode.length !== 3) return jsonResponse(400, { error: "Invalid currency" });

    // Example bounds. Adjust to your business constraints.
    if (amountCents < 50) return jsonResponse(400, { error: "Minimum amount is 0.50" });
    if (amountCents > 2_000_000) return jsonResponse(400, { error: "Maximum amount exceeded" });

    const admin = createClient(supabaseUrl, serviceRoleKey);

    // Resolve merchant for this profile and ensure they are allowed to request payment.
    const { data: merchant, error: merchantErr } = await admin
      .from("merchants")
      .select("id,status")
      .eq("profile_id", profileId)
      .maybeSingle();

    if (merchantErr) return jsonResponse(500, { error: "Failed to resolve merchant" });
    if (!merchant?.id) return jsonResponse(403, { error: "Not a merchant" });

    const status = String(merchant.status ?? "").toLowerCase();
    if (status !== "approved") return jsonResponse(403, { error: "Merchant is not approved" });

    const now = new Date();
    const expiresAt = new Date(now.getTime() + 10 * 60 * 1000);

    const baseRow = {
      id: crypto.randomUUID(),
      merchant_id: merchant.id,
      merchant_profile_id: profileId,
      amount_cents: amountCents,
      currency_code: currencyCode,
      status: "pending",
      expires_at: expiresAt.toISOString(),
    };

    // Token is for QR (opaque). short_code is for manual typing.
    // We retry a few times in case either hits a uniqueness constraint.
    for (let attempt = 0; attempt < 4; attempt++) {
      const row = {
        ...baseRow,
        token: randomToken(18),
        short_code: randomTypingCode(8),
      };

      const { data: inserted, error: insertErr } = await admin
        .from("payment_intents")
        .insert(row)
        .select("*")
        .single();

      if (!insertErr && inserted) {
        return jsonResponse(200, { success: true, payment_intent: inserted });
      }

      const msg = String((insertErr as any)?.message ?? "").toLowerCase();
      const isUnique = msg.includes("duplicate") || msg.includes("unique") || msg.includes("already exists");
      if (!isUnique) {
        return jsonResponse(500, { error: "Failed to create payment intent" });
      }
    }

    return jsonResponse(500, { error: "Failed to create payment intent" });
  } catch (e) {
    return jsonResponse(500, { error: (e as Error)?.message ?? "Internal error" });
  }
});
