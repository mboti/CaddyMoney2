// supabase/functions/admin_create_admin/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

type CreateAdminRequest = {
  email: string;
  password: string;
  full_name: string;
  bootstrap_token?: string;
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json; charset=utf-8" },
  });
}

function cleanEmail(input: string) {
  return input.trim().toLowerCase().replace(/\s+/g, "");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return json(405, { success: false, error: "Method not allowed" });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SERVICE_ROLE_KEY) {
      return json(500, { success: false, error: "Missing Supabase environment" });
    }

    const adminBootstrapToken = Deno.env.get("ADMIN_BOOTSTRAP_TOKEN") ?? "";
    const authHeader = req.headers.get("authorization") ?? "";

    const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    const body = (await req.json()) as Partial<CreateAdminRequest>;
    const email = typeof body.email === "string" ? cleanEmail(body.email) : "";
    const password = typeof body.password === "string" ? body.password.trim() : "";
    const fullName = typeof body.full_name === "string" ? body.full_name.trim() : "";
    const bootstrapToken = typeof body.bootstrap_token === "string" ? body.bootstrap_token.trim() : "";

    if (!email || !email.includes("@")) return json(400, { success: false, error: "Invalid email" });
    if (password.length < 8) return json(400, { success: false, error: "Password must be at least 8 characters" });
    if (!fullName) return json(400, { success: false, error: "Full name is required" });

    // Authorization:
    // - Preferred: existing admin JWT can call this function.
    // - Bootstrap: only when there are no admins yet, and bootstrap token matches.
    let authorized = false;
    let authorizedBy = "";

    if (authHeader.toLowerCase().startsWith("bearer ")) {
      const requester = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { authorization: authHeader } },
        auth: { persistSession: false },
      });

      const userRes = await requester.auth.getUser();
      const requesterId = userRes.data.user?.id;
      if (requesterId) {
        const roleRes = await service
          .from("profiles")
          .select("role")
          .eq("id", requesterId)
          .maybeSingle();

        if (roleRes.data?.role === "admin") {
          authorized = true;
          authorizedBy = "jwt_admin";
        }
      }
    }

    if (!authorized) {
      const { count, error } = await service
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .eq("role", "admin");

      if (error) return json(500, { success: false, error: "Failed to check admin bootstrap" });

      const adminCount = count ?? 0;
      if (adminCount === 0 && adminBootstrapToken && bootstrapToken && bootstrapToken === adminBootstrapToken) {
        authorized = true;
        authorizedBy = "bootstrap_token";
      }
    }

    if (!authorized) return json(403, { success: false, error: "Not authorized" });

    // Create Auth user
    const createRes = await service.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName, role: "admin" },
    });

  // If the user already exists (e.g., created manually in Supabase Auth), we can still
  // "repair" access by upserting their profile role to admin.
  if (createRes.error) {
    const msg = (createRes.error.message ?? "").toLowerCase();
    const looksLikeDuplicate = msg.includes("already") || msg.includes("registered") || msg.includes("exists");
    if (!looksLikeDuplicate) return json(400, { success: false, error: createRes.error.message });

    const existingProfileRes = await service
      .from("profiles")
      .select("id")
      .eq("email", email)
      .maybeSingle();

    if (existingProfileRes.error) {
      return json(500, { success: false, error: "User exists, but failed to read profile" });
    }
    if (!existingProfileRes.data?.id) {
      return json(409, {
        success: false,
        error:
          "User already exists in Auth, but no profile row was found. Create a profile row for this user, then re-run bootstrap.",
      });
    }

    const now = new Date().toISOString();
    const repairRes = await service.from("profiles").upsert({
      id: existingProfileRes.data.id,
      email,
      full_name: fullName,
      role: "admin",
      status: "active",
      updated_at: now,
    });

    if (repairRes.error) {
      return json(500, { success: false, error: `Failed to repair profile role: ${repairRes.error.message}` });
    }

    return json(200, { success: true, user_id: existingProfileRes.data.id, repaired: true, authorized_by: authorizedBy });
  }

  const newUser = createRes.data.user;
  if (!newUser) return json(500, { success: false, error: "User creation failed" });

    // Ensure profile exists / is correct.
    // (If you already have an auth trigger creating profiles, this upsert will be idempotent.)
    const now = new Date().toISOString();
    const upsertRes = await service.from("profiles").upsert({
      id: newUser.id,
      email,
      full_name: fullName,
      role: "admin",
      status: "active",
      created_at: now,
      updated_at: now,
    });

    if (upsertRes.error) {
      // Don't fail the whole request; the user exists in Auth.
      return json(201, {
        success: true,
        user_id: newUser.id,
        warning: "Admin created, but profile upsert failed",
        details: upsertRes.error.message,
        authorized_by: authorizedBy,
      });
    }

    return json(201, { success: true, user_id: newUser.id, authorized_by: authorizedBy });
  } catch (e) {
    return json(500, { success: false, error: `Unexpected error: ${String(e)}` });
  }
});
