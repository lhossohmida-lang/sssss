// يغيّر كلمة سر حساب موجود (إعادة توليد بيانات الدخول). مثل provision-account: تحتاج
// المفتاح السرّي فتعمل على الخادم، وتتحقق من جلسة المستدعي وصلاحيته على دور الحساب
// المستهدف مطابقاً لسياسات RLS قبل أي تغيير.
import {
  adminHeaders,
  canManage,
  corsHeaders,
  getCaller,
  isRecord,
  json,
  publishableKey,
  rejection,
  secretKey,
  validPassword,
  validUuid,
} from "../_shared/accounts.ts";

export async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const authorization = req.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/i.test(authorization)) return json(401, { error: "unauthorized" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.replace(/\/$/, "");
  const publishable = publishableKey();
  const secret = secretKey();
  if (!supabaseUrl || !publishable || !secret) return json(503, { error: "not_configured" });

  try {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return json(400, { error: "invalid_json" });
    }
    if (!isRecord(body) || !validUuid(body.id) || !validPassword(body.password)) {
      return json(400, { error: "invalid_request" });
    }

    const caller = await getCaller(authorization, supabaseUrl, publishable);

    // دور الحساب المستهدف يُقرأ بجلسة المستدعي (RLS تُظهر حسابات الإدارة وحدها للموظفين).
    const targetUrl = new URL(`${supabaseUrl}/rest/v1/user_accounts`);
    targetUrl.search = new URLSearchParams({
      select: "role",
      id: `eq.${body.id}`,
      deleted_at: "is.null",
    }).toString();
    const targetResponse = await fetch(targetUrl, {
      headers: { apikey: publishable, Authorization: authorization },
    });
    if (!targetResponse.ok) return json(403, { error: "forbidden" });
    const targets: unknown = await targetResponse.json();
    const target = Array.isArray(targets) && targets.length === 1 ? targets[0] : null;
    if (!isRecord(target) || typeof target.role !== "string") {
      return json(404, { error: "not_found" });
    }
    if (!canManage(caller, target.role, "edit")) return json(403, { error: "forbidden" });

    const updated = await fetch(`${supabaseUrl}/auth/v1/admin/users/${body.id}`, {
      method: "PUT",
      headers: { ...adminHeaders(secret), "Content-Type": "application/json" },
      body: JSON.stringify({ password: body.password }),
    });
    if (!updated.ok) {
      console.error("reset-account-password: auth rejected the request", updated.status);
      return json(502, { error: "auth_unavailable" });
    }
    return json(200, { ok: true });
  } catch (error) {
    if (error instanceof Response) return rejection(error);
    // لا تُسجَّل كلمات السر ولا الرموز ولا ردود الخادم.
    console.error("reset-account-password failed");
    return json(502, { error: "unavailable" });
  }
}

if (import.meta.main) Deno.serve(handle);
