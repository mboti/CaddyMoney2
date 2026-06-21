// supabase/functions/coupons_list/index.ts

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Json = Record<string, unknown>;

type CouponRow = {
  id: string;
  profile_id: string;
  title: string | null;
  category: string | null;
  currency_code: string | null;
  balance: number | null;
  status: string | null;
  created_at: string | null;
  updated_at: string | null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const body = (await req.json().catch(() => ({}))) as Json;
    const currencyCode = String(body["currency_code"] ?? "EUR").trim().toUpperCase();

    // IMPORTANT: Use the user's JWT to identify them.
    // We use the Service Role key for the DB query so we can safely read coupons
    // even if client-side SELECT is restricted by RLS.
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authHeader = req.headers.get("authorization") ?? "";

    // Client with anon key for auth.getUser() (verifies JWT and returns user id)
    const supabaseAuth = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await supabaseAuth.auth.getUser();
    if (userErr || !userData.user) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthorized. Please sign in again." }),
        { status: 401, headers: { ...CORS_HEADERS, "content-type": "application/json" } },
      );
    }

    const userId = userData.user.id;

    // Service role client for DB reads.
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data, error } = await supabaseAdmin
      .from("coupons")
      .select("id,profile_id,title,category,currency_code,balance,status,created_at,updated_at")
      .eq("profile_id", userId)
      .eq("status", "active")
      .eq("currency_code", currencyCode)
      .gt("balance", 0)
      .order("updated_at", { ascending: false });

    if (error) {
      return new Response(
        JSON.stringify({ success: false, error: "Failed to load coupons.", supabase: error }),
        { status: 400, headers: { ...CORS_HEADERS, "content-type": "application/json" } },
      );
    }

    const coupons = (data ?? []) as CouponRow[];

    return new Response(
      JSON.stringify({ success: true, coupons }),
      { status: 200, headers: { ...CORS_HEADERS, "content-type": "application/json" } },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return new Response(
      JSON.stringify({ success: false, error: "Unexpected server error.", details: msg }),
      { status: 500, headers: { ...CORS_HEADERS, "content-type": "application/json" } },
    );
  }
});
