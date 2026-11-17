// أدوات مشتركة بين دالتَي إنشاء الحسابات (provision-account) وإعادة كلمة السر
// (reset-account-password). بلا اعتماديات خارجية. لا تُسجَّل هنا كلمات سر ولا رموز.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};

export const roles = new Set<string>(["owner", "worker", "teacher", "parent"]);

export type Caller = {
  id: string;
  /** بريد الدخول الحالي بأحرف صغيرة (فارغ إن لم يُعد الخادم بريداً). */
  email: string;
  role: string;
  entityId: string | null;
  permissions: Record<string, unknown>;
};

export function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function envObject(name: string): Record<string, unknown> | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed: unknown = JSON.parse(raw);
    return isRecord(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function pickKey(keys: Record<string, unknown> | null): string | undefined {
  if (keys === null) return undefined;
  if (typeof keys.default === "string" && keys.default.length > 0) return keys.default;
  for (const value of Object.values(keys)) {
    if (typeof value === "string" && value.length > 0) return value;
  }
  return undefined;
}

/** المفتاح العام: الجديد (`SUPABASE_PUBLISHABLE_KEYS`) ثم anon القديم. */
export function publishableKey(): string | undefined {
  return pickKey(envObject("SUPABASE_PUBLISHABLE_KEYS")) ??
    Deno.env.get("SUPABASE_ANON_KEY") ?? undefined;
}

/** المفتاح السرّي: الجديد (`SUPABASE_SECRET_KEYS`) ثم service_role القديم. */
export function secretKey(): string | undefined {
  return pickKey(envObject("SUPABASE_SECRET_KEYS")) ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? undefined;
}

/** المفاتيح الجديدة ليست JWT فتُرسل في apikey وحده؛ والقديم JWT يُرسل في الرأسين. */
export function adminHeaders(key: string): Record<string, string> {
  return key.startsWith("eyJ")
    ? { apikey: key, Authorization: `Bearer ${key}` }
    : { apikey: key };
}

export function validEmail(value: unknown): value is string {
  return typeof value === "string" && value.length <= 254 &&
    /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value);
}

export function validPassword(value: unknown): value is string {
  return typeof value === "string" && value.length >= 8 &&
    new TextEncoder().encode(value).length <= 72;
}

export function validUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

function can(permissions: Record<string, unknown>, module: string, action: string): boolean {
  const actions = permissions[module];
  return Array.isArray(actions) && actions.includes(action);
}

/**
 * من يجوز له إنشاء حساب أو تعديله، مطابقاً لسياسات RLS على `user_accounts`:
 * صاحب المدرسة يدير كل الأدوار؛ والعامل حسابات الأساتذة بصلاحية `teachers`
 * وحسابات الأولياء بصلاحية `students`؛ ولا أحد غيرهما.
 */
export function canManage(
  caller: Pick<Caller, "role" | "permissions">,
  target: string,
  action: "add" | "edit",
): boolean {
  if (!roles.has(target)) return false;
  if (caller.role === "owner") return true;
  if (caller.role !== "worker") return false;
  if (target === "teacher") return can(caller.permissions, "teachers", action);
  if (target === "parent") return can(caller.permissions, "students", action);
  return false;
}

/** يتحقق من المستخدم من جلسته ويقرأ دوره وصلاحياته؛ يرمي Response عند الرفض. */
export async function getCaller(
  authorization: string,
  supabaseUrl: string,
  apiKey: string,
): Promise<Caller> {
  const headers = { apikey: apiKey, Authorization: authorization };
  const auth = await fetch(`${supabaseUrl}/auth/v1/user`, { headers });
  if (!auth.ok) throw new Response("Unauthorized", { status: 401 });
  const user: unknown = await auth.json();
  if (!isRecord(user) || typeof user.id !== "string") {
    throw new Response("Unauthorized", { status: 401 });
  }

  const accountUrl = new URL(`${supabaseUrl}/rest/v1/user_accounts`);
  accountUrl.search = new URLSearchParams({
    select: "id,role,entity_id",
    id: `eq.${user.id}`,
    deleted_at: "is.null",
  }).toString();
  const accountResponse = await fetch(accountUrl, { headers });
  if (!accountResponse.ok) throw new Response("Account unavailable", { status: 403 });
  const accounts: unknown = await accountResponse.json();
  const account = Array.isArray(accounts) && accounts.length === 1 ? accounts[0] : null;
  if (!isRecord(account) || account.id !== user.id || !roles.has(String(account.role))) {
    throw new Response("Account unavailable", { status: 403 });
  }

  const role = String(account.role);
  const entityId = typeof account.entity_id === "string" ? account.entity_id : null;
  let permissions: Record<string, unknown> = {};
  if (role === "worker" && entityId !== null) {
    const workerUrl = new URL(`${supabaseUrl}/rest/v1/workers`);
    workerUrl.search = new URLSearchParams({
      select: "permissions",
      id: `eq.${entityId}`,
      deleted_at: "is.null",
    }).toString();
    const workerResponse = await fetch(workerUrl, { headers });
    if (!workerResponse.ok) throw new Response("Permissions unavailable", { status: 403 });
    const workers: unknown = await workerResponse.json();
    if (Array.isArray(workers) && workers.length === 1 && isRecord(workers[0])) {
      const raw = workers[0].permissions;
      if (typeof raw === "string") {
        try {
          const parsed: unknown = JSON.parse(raw);
          if (isRecord(parsed)) permissions = parsed;
        } catch {
          permissions = {};
        }
      } else if (isRecord(raw)) {
        permissions = raw;
      }
    }
  }
  const email = typeof user.email === "string" ? user.email.trim().toLowerCase() : "";
  return { id: user.id, email, role, entityId, permissions };
}

/** يحوّل Response مرمياً من getCaller إلى رد نظيف (دون تفاصيل). */
export function rejection(error: Response): Response {
  return json(error.status === 401 ? 401 : 403, {
    error: error.status === 401 ? "unauthorized" : "forbidden",
  });
}
