// supabase edge function: merchant_logo_signed_url
// Generates a signed URL for merchant logos stored in a private bucket.
// Security:
// - Requires a valid authenticated user (JWT)
// - Only allows paths under merchant/<uuid>/logo/
// - Only allows merchants with status = 'approved'

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function jsonResponse(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json; charset=utf-8" },
  });
}

function isUuid(v: string) {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(v);
}

function validateLogoPath(objectPath: string) {
  const p = objectPath.trim().replace(/^\/+/, "");
  const parts = p.split("/").filter(Boolean);
  // Expect: merchant/<merchantId>/logo/<filename...>
  if (parts.length < 4) return null;
  if (parts[0] !== "merchant") return null;
  const merchantId = parts[1];
  if (!isUuid(merchantId)) return null;
  if (parts[2] !== "logo") return null;
  return { merchantId, normalized: parts.join("/") };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse(405, { error: "Method not allowed" });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7) : "";
    if (!jwt) return jsonResponse(401, { error: "Missing Authorization bearer token" });

    const payload = await req.json();
    const bucketName = (payload?.bucket ?? "").toString().trim();
    const objectPath = (payload?.object_path ?? "").toString().trim();
    const expiresIn = Number(payload?.expires_in ?? 900);

    if (!bucketName) return jsonResponse(400, { error: "Missing bucket" });
    if (!objectPath) return jsonResponse(400, { error: "Missing object_path" });
    if (!Number.isFinite(expiresIn) || expiresIn <= 0 || expiresIn > 3600) {
      return jsonResponse(400, { error: "expires_in must be 1..3600 seconds" });
    }

    const validated = validateLogoPath(objectPath);
    if (!validated) {
      return jsonResponse(403, { error: "object_path is not an allowed merchant logo path" });
    }

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Service role client (used for privileged DB+Storage access)
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    // Verify the JWT is valid (prevents unauthenticated scraping of signed URLs).
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData?.user) return jsonResponse(401, { error: "Invalid token" });

    // Only allow approved merchants.
    // IMPORTANT: our storage paths are written as `merchant/<auth_uid>/...`
    // (see Flutter upload code). In DB, that value is stored in `profile_id`,
    // while `id` is the merchant record id.
    //
    // To be resilient across older data, we accept either match.
    let merchant: { id: string; status: string } | null = null;
    let merchantErr: { message: string } | null = null;

    const byProfile = await admin
      .from("merchants")
      .select("id,status")
      .eq("profile_id", validated.merchantId)
      .maybeSingle();
    merchant = (byProfile.data as any) ?? null;
    merchantErr = (byProfile.error as any) ?? null;

    if (!merchant && !merchantErr) {
      const byId = await admin
        .from("merchants")
        .select("id,status")
        .eq("id", validated.merchantId)
        .maybeSingle();
      merchant = (byId.data as any) ?? null;
      merchantErr = (byId.error as any) ?? null;
    }

    if (merchantErr) return jsonResponse(500, { error: "Failed to validate merchant", details: merchantErr.message });
    if (!merchant) return jsonResponse(404, { error: "Merchant not found" });

    const status = (merchant.status ?? "").toString().toLowerCase();
    if (status !== "approved") return jsonResponse(403, { error: "Merchant is not approved" });

    const { data, error } = await admin.storage.from(bucketName).createSignedUrl(validated.normalized, expiresIn);
    if (error) return jsonResponse(500, { error: "Failed to create signed url", details: error.message });

    return jsonResponse(200, { url: data?.signedUrl ?? null });
  } catch (e) {
    return jsonResponse(500, { error: "Unexpected error", details: String(e) });
  }
});
