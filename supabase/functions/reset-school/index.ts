// إعادة تعيين المدرسة بالكامل: يحذف كل بياناتها (التلاميذ والأفواج والحضور والمدفوعات والإعدادات والرسائل
// والصور والملفات...) وحسابات كل من عدا صاحب المدرسة، ويبقى صاحبها بحسابه، وكأنها مدرسة جديدة. لصاحب
// المدرسة وحده بعد كلمة سرّه وعبارة تأكيد صريحة، ولا رجعة فيه.
//
// تعمل بالمفتاح السرّي على الخادم: دالة SQL (reset_school_data) تمسح الجداول وتبدّل «دورة» المدرسة في
// معاملة واحدة، ثم تُحذف حسابات الدخول (Auth) ويُزال طاقم المدرسة من دليل المدارس وتُحذف ملفات التخزين.
// ما بعد المعاملة لا يتراجع إن تعذّر بعضه: يعود الرد بعدد ما تعذّر ويكفي إعادة التشغيل لإكماله (الدالة
// آمنة عند التكرار). لا تُسجَّل هنا كلمات سر ولا رموز ولا أرقام.
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
  unregisterStaffPhone,
} from "../_shared/directory.ts";

/** العبارة التي يرسلها التطبيق بعد أن يكتبها المالك: لا إعادة تعيين بطلب ناقص. */
export const CONFIRMATION = "RESET-SCHOOL";

/** أقصى صفحات حسابات الدخول التي تُمسح بحثاً عن حسابات يتيمة (200 حساب في الصفحة). */
const MAX_AUTH_PAGES = 100;
const AUTH_PAGE_SIZE = 200;
const STORAGE_CHUNK = 200;
const CONCURRENCY = 10;

type Removed = { id: string; email: string; role: string };
type StoredObject = { bucket: string; name: string };

/** ينفّذ [task] لكل عنصر، [limit] في آن واحد، ويعيد عدد من فشل. */
async function forEachLimited<T>(
  items: T[],
  limit: number,
  task: (item: T) => Promise<boolean>,
): Promise<number> {
  let failed = 0;
  for (let start = 0; start < items.length; start += limit) {
    const batch = items.slice(start, start + limit);
    const results = await Promise.all(batch.map((item) => task(item).catch(() => false)));
    failed += results.filter((ok) => !ok).length;
  }
  return failed;
}

function parseRemoved(value: unknown): Removed[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    if (
      isRecord(entry) && typeof entry.id === "string" && typeof entry.email === "string" &&
      typeof entry.role === "string"
    ) {
      return [{ id: entry.id, email: entry.email, role: entry.role }];
    }
    return [];
  });
}

function parseObjects(value: unknown): StoredObject[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    if (isRecord(entry) && typeof entry.bucket === "string" && typeof entry.name === "string") {
      return [{ bucket: entry.bucket, name: entry.name }];
    }
    return [];
  });
}

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
      !isRecord(body) || typeof body.current_password !== "string" ||
      body.current_password.length === 0 || body.confirm !== CONFIRMATION
    ) {
      return json(400, { error: "invalid_request" });
    }

    const caller = await getCaller(authorization, supabaseUrl, publishable);
    if (caller.role !== "owner") return json(403, { error: "forbidden" });
    if (caller.email === "") return json(502, { error: "auth_unavailable" });

    // كلمة السر الحالية: من يمسك جلسة مفتوحة لا يمسح مدرسة بلا كلمة صاحبها.
    const check = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: publishable, "Content-Type": "application/json" },
      body: JSON.stringify({ email: caller.email, password: body.current_password }),
    });
    if (check.status === 400 || check.status === 401) return json(403, { error: "wrong_password" });
    if (!check.ok) return json(502, { error: "auth_unavailable" });

    const headers = { ...adminHeaders(secret), "Content-Type": "application/json" };

    // اسم المنفّذ لسجل العمليات (من حسابه لا من الطلب).
    let actorName = "";
    const named = await fetch(
      `${supabaseUrl}/rest/v1/user_accounts?select=display_name&id=eq.${encodeURIComponent(caller.id)}`,
      { headers: adminHeaders(secret) },
    ).catch(() => null);
    if (named?.ok) {
      const rows: unknown = await named.json().catch(() => null);
      if (Array.isArray(rows) && isRecord(rows[0]) && typeof rows[0].display_name === "string") {
        actorName = rows[0].display_name.slice(0, 100);
      }
    }

    // البيانات: معاملة واحدة تمسح كل شيء وتبدّل الدورة.
    const reset = await fetch(`${supabaseUrl}/rest/v1/rpc/reset_school_data`, {
      method: "POST",
      headers,
      body: JSON.stringify({ p_actor_id: caller.id, p_actor_name: actorName }),
    });
    if (!reset.ok) {
      console.error("reset-school: the data reset was rejected", reset.status);
      return json(502, { error: "reset_failed" });
    }
    const result: unknown = await reset.json().catch(() => null);
    if (!isRecord(result) || typeof result.epoch !== "string" || result.epoch === "") {
      console.error("reset-school: unexpected reset reply");
      return json(502, { error: "reset_failed" });
    }
    const removed = parseRemoved(result.removed);
    const objects = parseObjects(result.objects);

    // بعد نجاح المسح لا يُرجَع فشلٌ مهما حدث: ما تعذّر يُعدّ ويكفي إعادة التشغيل لإكماله.
    let authFailed = 0;
    let directoryFailed = 0;
    let storageFailed = 0;
    try {
      // أصحاب المدرسة المتبقون: لا يُحذف لهم حساب دخول.
      const owners = new Set<string>([caller.id]);
      const ownerRows = await fetch(
        `${supabaseUrl}/rest/v1/user_accounts?select=id&role=eq.owner`,
        { headers: adminHeaders(secret) },
      ).catch(() => null);
      if (ownerRows?.ok) {
        const rows: unknown = await ownerRows.json().catch(() => null);
        if (Array.isArray(rows)) {
          for (const row of rows) if (isRecord(row) && typeof row.id === "string") owners.add(row.id);
        }
      }

      // حسابات الدخول: من حُذفت صفوفهم، وكل حساب يتيم بريده بريد هاتف (حسابات لم تُكتب صفوفها بعد).
      const doomed = new Set<string>(removed.map((account) => account.id));
      for (let page = 1; page <= MAX_AUTH_PAGES; page++) {
        const listed = await fetch(
          `${supabaseUrl}/auth/v1/admin/users?page=${page}&per_page=${AUTH_PAGE_SIZE}`,
          { headers: adminHeaders(secret) },
        ).catch(() => null);
        if (!listed?.ok) break;
        const payload: unknown = await listed.json().catch(() => null);
        const users = isRecord(payload) && Array.isArray(payload.users) ? payload.users : [];
        for (const user of users) {
          if (
            isRecord(user) && typeof user.id === "string" && typeof user.email === "string" &&
            !owners.has(user.id) && phoneOfLoginEmail(user.email) !== null
          ) {
            doomed.add(user.id);
          }
        }
        if (users.length < AUTH_PAGE_SIZE) break;
      }
      for (const id of owners) doomed.delete(id);
      authFailed = await forEachLimited([...doomed], CONCURRENCY, async (id) => {
        const response = await fetch(`${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(id)}`, {
          method: "DELETE",
          headers: adminHeaders(secret),
        });
        return response.ok || response.status === 404;
      });

      // دليل المدارس: يُزال هاتف كل عامل حُذف.
      const directory = directoryConfig();
      if (directory !== null) {
        const phones = removed
          .filter((account) => needsDirectoryEntry(account.role))
          .map((account) => phoneOfLoginEmail(account.email))
          .filter((phone): phone is string => phone !== null);
        directoryFailed = await forEachLimited(phones, CONCURRENCY, (phone) => unregisterStaffPhone(directory, phone));
      }

      // الملفات: بواجهة التخزين فتُحذف الكتل معها.
      const byBucket = new Map<string, string[]>();
      for (const object of objects) {
        byBucket.set(object.bucket, [...(byBucket.get(object.bucket) ?? []), object.name]);
      }
      for (const [bucket, names] of byBucket) {
        for (let start = 0; start < names.length; start += STORAGE_CHUNK) {
          const chunk = names.slice(start, start + STORAGE_CHUNK);
          const response = await fetch(`${supabaseUrl}/storage/v1/object/${encodeURIComponent(bucket)}`, {
            method: "DELETE",
            headers,
            body: JSON.stringify({ prefixes: chunk }),
          }).catch(() => null);
          if (response === null || !response.ok) storageFailed += chunk.length;
        }
      }
    } catch {
      console.error("reset-school: the cleanup after the data reset was interrupted");
      authFailed = Math.max(authFailed, 1);
    }

    return json(200, {
      ok: true,
      epoch: result.epoch,
      removed_accounts: removed.length,
      failures: { auth: authFailed, directory: directoryFailed, storage: storageFailed },
    });
  } catch (error) {
    if (error instanceof Response) return rejection(error);
    // لا تُسجَّل كلمات السر ولا الرموز ولا ردود الخادم.
    console.error("reset-school failed");
    return json(502, { error: "unavailable" });
  }
}

if (import.meta.main) Deno.serve(handle);
