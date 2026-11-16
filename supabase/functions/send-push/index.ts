// دالة إرسال إشعارات الدفع. يستدعيها مشغِّل قاعدة البيانات (pg_net) بعد إدراج إشعار أو رسالة
// محادثة، بسرّ مشترك في الترويسة x-push-secret (لا جلسة مستخدم، فلا JWT: انظر config.toml).
// تقرأ الصف بمفتاح الخادم السرّي، وتحدد المستلمين، وترسل إلى معرّفات تثبيت Firebase المسجّلة لهم.
// لا يُسجَّل هنا نص إشعار ولا رسالة ولا رمز ولا مفتاح.
import { adminHeaders, isRecord, json, secretKey } from "../_shared/accounts.ts";
import {
  accessToken,
  type PushMessage,
  parseServiceAccount,
  type ServiceAccount,
  sendToInstallation,
} from "../_shared/fcm.ts";

const MAX_INSTALLATIONS = 200;
const BATCH = 10;

/** مقارنة سرّين دون كشف طول المطابقة بزمن المقارنة. */
export function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

type Job = { recipients: string[]; message: PushMessage };

async function rows(
  supabaseUrl: string,
  key: string,
  path: string,
): Promise<Record<string, unknown>[]> {
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    headers: adminHeaders(key),
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error("read_failed");
  }
  const payload: unknown = await response.json();
  return Array.isArray(payload) ? payload.filter(isRecord) : [];
}

const clip = (value: unknown, max: number): string =>
  typeof value === "string" ? value.trim().slice(0, max) : "";

/** ما يُرسَل ولمن، من صف الإشعار أو الرسالة. `null` = لا شيء يُرسَل (محذوف أو بلا مستلمين). */
export async function buildJob(
  supabaseUrl: string,
  key: string,
  table: string,
  id: string,
): Promise<Job | null> {
  const q = encodeURIComponent(id);
  if (table === "notifications") {
    const [row] = await rows(
      supabaseUrl,
      key,
      `notifications?id=eq.${q}&select=user_id,title,body,deleted_at&limit=1`,
    );
    if (!row || row.deleted_at != null || typeof row.user_id !== "string") return null;
    const userId: string = row.user_id;
    return {
      recipients: [userId],
      message: {
        title: clip(row.title, 100) || "إشعار جديد",
        body: clip(row.body, 200),
        data: { type: "notification", notification_id: id },
      },
    };
  }
  const [message] = await rows(
    supabaseUrl,
    key,
    `chat_messages?id=eq.${q}&select=room_id,sender_id,content,attachment_name,deleted_at&limit=1`,
  );
  if (
    !message || message.deleted_at != null || typeof message.room_id !== "string" ||
    typeof message.sender_id !== "string"
  ) {
    return null;
  }
  const roomId: string = message.room_id;
  const senderId: string = message.sender_id;
  const room = encodeURIComponent(roomId);
  const [members, rooms] = await Promise.all([
    rows(supabaseUrl, key, `chat_members?room_id=eq.${room}&deleted_at=is.null&select=user_id`),
    rows(supabaseUrl, key, `chat_rooms?id=eq.${room}&select=title,deleted_at&limit=1`),
  ]);
  if (rooms[0]?.deleted_at != null) return null;
  const recipients = [
    ...new Set(
      members.map((m) => m.user_id).filter((u): u is string => typeof u === "string" && u !== senderId),
    ),
  ];
  if (recipients.length === 0) return null;
  const text = clip(message.content, 120);
  return {
    recipients,
    message: {
      title: clip(rooms[0]?.title, 100) || "رسالة جديدة",
      body: text || (message.attachment_name ? "مرفق جديد" : "رسالة جديدة"),
      data: { type: "chat", room_id: roomId },
    },
  };
}

export async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const expected = Deno.env.get("PUSH_SECRET") ?? "";
  if (expected.length < 32 || !sameSecret(req.headers.get("x-push-secret") ?? "", expected)) {
    return json(401, { error: "unauthorized" });
  }
  const account: ServiceAccount | null = parseServiceAccount(
    Deno.env.get("FIREBASE_SERVICE_ACCOUNT"),
  );
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.replace(/\/$/, "");
  const key = secretKey();
  if (!account || !supabaseUrl || !key) return json(503, { error: "push_not_configured" });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }
  if (
    !isRecord(body) || typeof body.id !== "string" || body.id.length === 0 ||
    body.id.length > 100 || (body.table !== "notifications" && body.table !== "chat_messages")
  ) {
    return json(400, { error: "invalid_request" });
  }

  try {
    const job = await buildJob(supabaseUrl, key, body.table, body.id);
    if (!job) return json(200, { sent: 0, removed: 0 });
    const users = job.recipients.map((u) => `"${u.replaceAll('"', "")}"`).join(",");
    const installs = (await rows(
      supabaseUrl,
      key,
      `push_installations?user_id=in.(${encodeURIComponent(users)})&select=installation_id&limit=${MAX_INSTALLATIONS}`,
    )).map((r) => r.installation_id).filter((v): v is string => typeof v === "string");
    if (installs.length === 0) return json(200, { sent: 0, removed: 0 });

    const token = await accessToken(account);
    let sent = 0;
    const gone: string[] = [];
    for (let i = 0; i < installs.length; i += BATCH) {
      const outcomes = await Promise.all(
        installs.slice(i, i + BATCH).map((fid) => sendToInstallation(account, token, fid, job.message)),
      );
      outcomes.forEach((outcome, index) => {
        if (outcome === "sent") sent++;
        else if (outcome === "gone") gone.push(installs[i + index]);
      });
    }
    for (const fid of gone) {
      await fetch(
        `${supabaseUrl}/rest/v1/push_installations?installation_id=eq.${encodeURIComponent(fid)}`,
        { method: "DELETE", headers: adminHeaders(key), signal: AbortSignal.timeout(10_000) },
      ).then((r) => r.body?.cancel()).catch(() => {});
    }
    return json(200, { sent, removed: gone.length });
  } catch {
    // لا تفاصيل في السجل: قد تحوي نصاً من محادثة.
    console.error("Push send failed");
    return json(502, { error: "push_failed" });
  }
}

if (import.meta.main) Deno.serve(handle);
