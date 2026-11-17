// يغيّر رقم دخول المستخدم الحالي (بريد الدخول المولَّد من هاتفه) بعد التحقق من كلمة سره الحالية.
// للمالك والعامل وحدهما (من يدخل من تطبيق الإدارة)؛ أرقام الأساتذة والأولياء تديرها الإدارة. تحتاج
// المفتاح السرّي لتعديل مستخدم Supabase Auth فتعمل على الخادم، وتحدّث دليل المدارس إن وُجد دليل:
// يُسجَّل الرقم الجديد ويُزال القديم، فيعرف تطبيق الإدارة المدرسة من الرقم الجديد.
// صف `user_accounts` يكتبه التطبيق بعدها عبر المزامنة العادية.
import {
  adminHeaders,
  corsHeaders,
  getCaller,
  isRecord,
  json,
  publishableKey,
  rejection,
  secretKey,
} from "../_shared/accounts.ts";
import {
  directoryConfig,
  needsDirectoryEntry,
  phoneOfLoginEmail,
  registerStaffPhone,
  unregisterStaffPhone,
} from "../_shared/directory.ts";

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
    if (
      !isRecord(body) || typeof body.new_email !== "string" ||
      typeof body.current_password !== "string" || body.current_password.length === 0
    ) {
      return json(400, { error: "invalid_request" });
    }
    const newEmail = body.new_email.trim().toLowerCase();
    const newPhone = phoneOfLoginEmail(newEmail);
    if (newPhone === null) return json(400, { error: "invalid_request" });

    const caller = await getCaller(authorization, supabaseUrl, publishable);
    if (!needsDirectoryEntry(caller.role)) return json(403, { error: "forbidden" });
    if (caller.email === "") return json(502, { error: "auth_unavailable" });
    if (caller.email === newEmail) return json(400, { error: "same_email" });

    // كلمة السر الحالية: يمنع من يمسك جلسة مفتوحة من الاستيلاء على الحساب برقم جديد.
    const check = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: publishable, "Content-Type": "application/json" },
      body: JSON.stringify({ email: caller.email, password: body.current_password }),
    });
    if (check.status === 400 || check.status === 401) return json(403, { error: "wrong_password" });
    if (!check.ok) return json(502, { error: "auth_unavailable" });

    const change = (email: string) =>
      fetch(`${supabaseUrl}/auth/v1/admin/users/${caller.id}`, {
        method: "PUT",
        headers: { ...adminHeaders(secret), "Content-Type": "application/json" },
        body: JSON.stringify({ email, email_confirm: true }),
      });

    const updated = await change(newEmail);
    if (updated.status === 409 || updated.status === 422) return json(409, { error: "email_exists" });
    if (!updated.ok) {
      console.error("change-login: auth rejected the request", updated.status);
      return json(502, { error: "auth_unavailable" });
    }

    // الدليل بعد نجاح التغيير: فإن رفض الرقم الجديد يُعاد البريد القديم فلا يضيع الدخول.
    const directory = directoryConfig();
    if (directory !== null) {
      if (!(await registerStaffPhone(directory, newPhone))) {
        await change(caller.email).catch(() => undefined);
        return json(502, { error: "directory_unavailable" });
      }
      const oldPhone = phoneOfLoginEmail(caller.email);
      if (oldPhone !== null && oldPhone !== newPhone) {
        await unregisterStaffPhone(directory, oldPhone);
      }
    }
    return json(200, { ok: true });
  } catch (error) {
    if (error instanceof Response) return rejection(error);
    // لا تُسجَّل كلمات السر ولا الرموز ولا ردود الخادم.
    console.error("change-login failed");
    return json(502, { error: "unavailable" });
  }
}

if (import.meta.main) Deno.serve(handle);
