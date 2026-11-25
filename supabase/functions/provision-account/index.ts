// ينشئ مستخدم دخول (بريد وكلمة سر مؤكَّد البريد) ويعيد معرّفه. تحتاج إنشاء مستخدمين في
// Supabase Auth إلى المفتاح السرّي الذي لا يخرج من الخادم، فيستدعيها تطبيق الإدارة بجلسة
// المستخدم. الصلاحية على الأدوار مطابقة لسياسات RLS (انظر canManage). صفّ
// `user_accounts` يكتبه التطبيق بعدها عبر المزامنة العادية بالمعرّف المُعاد.
import {
  adminHeaders,
  canManage,
  corsHeaders,
  getCaller,
  isRecord,
  json,
  publishableKey,
  rejection,
  roles,
  secretKey,
  validEmail,
  validPassword,
} from "../_shared/accounts.ts";
import {
  directoryConfig,
  needsDirectoryEntry,
  phoneOfLoginEmail,
  registerStaffPhone,
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
      !isRecord(body) || !validEmail(body.email) || !validPassword(body.password) ||
      typeof body.role !== "string" || !roles.has(body.role)
    ) {
      return json(400, { error: "invalid_request" });
    }
    // Optional client-chosen id: an account created offline already uses it on the device.
    const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (body.id !== undefined && (typeof body.id !== "string" || !UUID.test(body.id))) {
      return json(400, { error: "invalid_request" });
    }
    const requestedId = typeof body.id === "string" ? body.id : undefined;

    const caller = await getCaller(authorization, supabaseUrl, publishable);
    if (!canManage(caller, body.role, "add")) return json(403, { error: "forbidden" });

    const created = await fetch(`${supabaseUrl}/auth/v1/admin/users`, {
      method: "POST",
      headers: { ...adminHeaders(secret), "Content-Type": "application/json" },
      body: JSON.stringify({
        ...(requestedId ? { id: requestedId } : {}),
        email: body.email,
        password: body.password,
        email_confirm: true,
      }),
    });
    if (created.status === 409 || created.status === 422) {
      // A retry of the same offline request (the first reply was lost): the user already exists.
      if (requestedId) {
        const same = await fetch(`${supabaseUrl}/auth/v1/admin/users/${requestedId}`, {
          headers: adminHeaders(secret),
        });
        if (same.ok) {
          const existing: unknown = await same.json();
          if (isRecord(existing) && existing.email === body.email) {
            return json(200, { id: requestedId });
          }
        }
      }
      return json(409, { error: "email_exists" });
    }
    if (!created.ok) {
      console.error("provision-account: auth rejected the request", created.status);
      return json(502, { error: "auth_unavailable" });
    }
    const user: unknown = await created.json();
    if (!isRecord(user) || typeof user.id !== "string") {
      return json(502, { error: "auth_unavailable" });
    }

    // مالك أو عامل يدخل من تطبيق الإدارة: يُسجَّل هاتفه في دليل المدارس (إن وُجد دليل) ليعرف التطبيق
    // مدرسته من رقمه. فإن تعذّر التسجيل يُحذف المستخدم الذي أُنشئ للتو ليُعاد إنشاؤه كاملاً.
    const directory = directoryConfig();
    const phone = phoneOfLoginEmail(body.email);
    if (directory !== null && phone !== null && needsDirectoryEntry(body.role)) {
      if (!(await registerStaffPhone(directory, phone))) {
        await fetch(`${supabaseUrl}/auth/v1/admin/users/${user.id}`, {
          method: "DELETE",
          headers: adminHeaders(secret),
        }).catch(() => undefined);
        return json(502, { error: "directory_unavailable" });
      }
    }
    return json(200, { id: user.id });
  } catch (error) {
    if (error instanceof Response) return rejection(error);
    // لا تُسجَّل كلمات السر ولا الرموز ولا ردود الخادم.
    console.error("provision-account failed");
    return json(502, { error: "unavailable" });
  }
}

if (import.meta.main) Deno.serve(handle);
