// Supabase Edge Function: merchant_review_decide
// Approve/reject a submitted merchant application (KYC) and notify the merchant by email.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Decision = "approve" | "reject";

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "content-type": "application/json; charset=utf-8" } });
}

function requiredEnv(name: string): string | null {
  const v = Deno.env.get(name);
  if (!v || v.trim().length === 0) return null;
  return v.trim();
}

function validateMerchantRow(row: Record<string, unknown>): string[] {
  const missing: string[] = [];

  const requiredStrings = [
    "business_name",
    "business_email",
    "owner_first_name",
    "owner_last_name",
    "business_type",
    "nationality",
    "iban",
    "account_holder_name",
  ];

  for (const k of requiredStrings) {
    const v = row[k];
    if (typeof v !== "string" || v.trim().length === 0) missing.push(k);
  }

  const requiredDocs = ["id_document_path", "business_registration_doc_path"];
  for (const k of requiredDocs) {
    const v = row[k];
    if (typeof v !== "string" || v.trim().length === 0) missing.push(k);
  }

  if (row["date_of_birth"] == null) missing.push("date_of_birth");

  const categories = row["categories"];
  if (!Array.isArray(categories) || categories.length === 0) missing.push("categories");

  const profileCompleted = row["profile_completed"];
  if (profileCompleted !== true) missing.push("profile_completed");

  return missing;
}

async function sendEmail({ to, subject, html }: { to: string; subject: string; html: string }): Promise<{ ok: boolean; skipped: boolean; error?: string }> {
  const apiKey = requiredEnv("RESEND_API_KEY");
  const fromEmail = requiredEnv("RESEND_FROM_EMAIL");

  if (!apiKey || !fromEmail) {
    console.log("Email skipped: RESEND_API_KEY/RESEND_FROM_EMAIL not set");
    return { ok: true, skipped: true };
  }

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ from: fromEmail, to: [to], subject, html }),
    });

    if (!res.ok) {
      const text = await res.text();
      return { ok: false, skipped: false, error: `Resend failed: ${res.status} ${text}` };
    }

    return { ok: true, skipped: false };
  } catch (e) {
    return { ok: false, skipped: false, error: `Resend error: ${String(e)}` };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse(405, { error: "Method not allowed" });

  const supabaseUrl = requiredEnv("SUPABASE_URL");
  const supabaseAnonKey = requiredEnv("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) return jsonResponse(500, { error: "Supabase env not configured" });

  const authorization = req.headers.get("Authorization") ?? "";
  const client = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authorization } } });

  const {
    data: { user },
    error: userErr,
  } = await client.auth.getUser();

  if (userErr || !user) return jsonResponse(401, { error: "Unauthorized" });

  // Admin check
  const { data: adminProfile, error: adminErr } = await client.from("profiles").select("id, role").eq("id", user.id).maybeSingle();
  if (adminErr) return jsonResponse(500, { error: `Failed to read admin profile: ${adminErr.message}` });
  if (!adminProfile || adminProfile.role !== "admin") return jsonResponse(403, { error: "Forbidden" });

  let body: any;
  try {
    body = await req.json();
  } catch (_) {
    return jsonResponse(400, { error: "Invalid JSON body" });
  }

  const merchantId = typeof body?.merchant_id === "string" ? body.merchant_id.trim() : "";
  const decision = (body?.decision as Decision) ?? null;
  const rejectReason = typeof body?.reason === "string" ? body.reason.trim() : "";

  if (!merchantId) return jsonResponse(400, { error: "merchant_id is required" });
  if (decision !== "approve" && decision !== "reject") return jsonResponse(400, { error: "decision must be 'approve' or 'reject'" });
  if (decision === "reject" && rejectReason.length < 3) return jsonResponse(400, { error: "reason is required for rejection" });

  const { data: merchantRow, error: merchantErr } = await client.from("merchants").select("*").eq("id", merchantId).maybeSingle();
  if (merchantErr) return jsonResponse(500, { error: `Failed to read merchant: ${merchantErr.message}` });
  if (!merchantRow) return jsonResponse(404, { error: "Merchant not found" });

  if (decision === "approve") {
    const missing = validateMerchantRow(merchantRow as Record<string, unknown>);
    if (missing.length > 0) {
      return jsonResponse(400, {
        error: "Merchant submission is incomplete",
        missing_fields: missing,
      });
    }
  }

  const oldStatus = (merchantRow as any).status;
  const nowIso = new Date().toISOString();

  const updatePayload: Record<string, unknown> =
    decision === "approve"
      ? {
          status: "approved",
          approved_by: user.id,
          approved_at: nowIso,
          rejected_reason: null,
          suspended_reason: null,
        }
      : {
          status: "rejected",
          approved_by: null,
          approved_at: null,
          rejected_reason: rejectReason,
        };

  const { error: updateErr } = await client.from("merchants").update(updatePayload).eq("id", merchantId);
  if (updateErr) return jsonResponse(500, { error: `Failed to update merchant: ${updateErr.message}` });

  // Status history is best-effort (some schemas may not have the table)
  try {
    await client.from("merchant_status_history").insert({
      merchant_id: merchantId,
      old_status: oldStatus,
      new_status: decision === "approve" ? "approved" : "rejected",
      changed_by: user.id,
      reason: decision === "approve" ? (body?.reason ?? null) : rejectReason,
      created_at: nowIso,
    });
  } catch (e) {
    console.log(`merchant_status_history insert skipped/failed: ${String(e)}`);
  }

  const merchantEmail = (merchantRow as any).business_email as string | null;
  const businessName = ((merchantRow as any).business_name as string | null) ?? "";

  let emailResult: { ok: boolean; skipped: boolean; error?: string } = { ok: true, skipped: true };
  if (merchantEmail && merchantEmail.includes("@")) {
    if (decision === "approve") {
      emailResult = await sendEmail({
        to: merchantEmail,
        subject: "Votre compte marchand a été approuvé",
        html: `<div style="font-family: ui-sans-serif, system-ui; line-height:1.5;">
          <h2>Demande approuvée</h2>
          <p>Bonjour,</p>
          <p>Votre demande marchand <b>${businessName}</b> a été validée. Vous pouvez maintenant vous connecter et accéder à votre tableau de bord.</p>
          <p>Merci.</p>
        </div>`,
      });
    } else {
      emailResult = await sendEmail({
        to: merchantEmail,
        subject: "Votre demande marchand a été rejetée",
        html: `<div style="font-family: ui-sans-serif, system-ui; line-height:1.5;">
          <h2>Demande rejetée</h2>
          <p>Bonjour,</p>
          <p>Votre demande marchand <b>${businessName}</b> a été rejetée.</p>
          <p><b>Motif :</b> ${rejectReason}</p>
          <p>Vous ne pouvez pas encore accéder au tableau de bord marchand.</p>
        </div>`,
      });
    }
  }

  if (!emailResult.ok) {
    // The business action succeeded; email is secondary. Return 200 with a warning.
    return jsonResponse(200, {
      success: true,
      decision,
      email_sent: false,
      email_skipped: false,
      email_error: emailResult.error,
    });
  }

  return jsonResponse(200, {
    success: true,
    decision,
    email_sent: !emailResult.skipped,
    email_skipped: emailResult.skipped,
  });
});
