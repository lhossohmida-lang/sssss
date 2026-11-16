// إرسال إشعارات Firebase Cloud Messaging (HTTP v1) بحساب خدمة. التطبيقات تسجّل «معرّف تثبيت
// Firebase» (FID) لا رمز التسجيل، فيُرسَل إلى الحقل `fid` (وثائق FCM تعدّه الأسلوب الموصى به).
// لا يُسجَّل هنا أي رمز وصول ولا مفتاح خاص ولا نص إشعار.

export type ServiceAccount = { client_email: string; private_key: string; project_id: string };

export type PushMessage = { title: string; body: string; data: Record<string, string> };

export type SendOutcome = "sent" | "gone" | "failed";

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

/** يقرأ JSON حساب الخدمة من البيئة؛ `null` إن غاب أو كان ناقصاً. */
export function parseServiceAccount(raw: string | undefined): ServiceAccount | null {
  if (!raw) return null;
  try {
    const value: unknown = JSON.parse(raw);
    if (typeof value !== "object" || value === null) return null;
    const { client_email, private_key, project_id } = value as Record<string, unknown>;
    if (
      typeof client_email !== "string" || typeof private_key !== "string" ||
      typeof project_id !== "string" || !private_key.includes("BEGIN PRIVATE KEY") ||
      !/^[a-z][a-z0-9-]{4,60}$/.test(project_id)
    ) {
      return null;
    }
    return { client_email, private_key, project_id };
  } catch {
    return null;
  }
}

function base64url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

let cached: { token: string; expiresAt: number } | undefined;

/** يفرّغ ذاكرة رمز الوصول (للاختبارات). */
export function resetTokenCache(): void {
  cached = undefined;
}

/** رمز وصول OAuth لحساب الخدمة (JWT موقَّع بـ RS256 يُبدَّل بالرمز)، مخزَّن حتى قبيل انتهائه. */
export async function accessToken(
  account: ServiceAccount,
  fetchFn: typeof fetch = fetch,
  now: number = Date.now(),
): Promise<string> {
  if (cached && cached.expiresAt - 60_000 > now) return cached.token;
  const issued = Math.floor(now / 1000);
  const signingInput = `${base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${
    base64url(JSON.stringify({
      iss: account.client_email,
      scope: SCOPE,
      aud: TOKEN_URL,
      iat: issued,
      exp: issued + 3600,
    }))
  }`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput)),
  );
  const response = await fetchFn(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${signingInput}.${base64url(signature)}`,
    }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error("token_rejected");
  }
  const payload: unknown = await response.json();
  const token = typeof payload === "object" && payload !== null
    ? (payload as Record<string, unknown>).access_token
    : undefined;
  const lifetime = typeof payload === "object" && payload !== null
    ? Number((payload as Record<string, unknown>).expires_in)
    : NaN;
  if (typeof token !== "string" || token.length === 0) throw new Error("token_missing");
  cached = { token, expiresAt: now + (Number.isFinite(lifetime) ? lifetime : 3000) * 1000 };
  return token;
}

/** يرسل إشعاراً إلى تثبيت واحد. `gone` = التثبيت لم يعد موجوداً فيُحذف من القاعدة. */
export async function sendToInstallation(
  account: ServiceAccount,
  token: string,
  fid: string,
  message: PushMessage,
  fetchFn: typeof fetch = fetch,
): Promise<SendOutcome> {
  let response: Response;
  try {
    response = await fetchFn(
      `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            fid,
            notification: { title: message.title, body: message.body },
            data: message.data,
            android: { priority: "HIGH" },
          },
        }),
        signal: AbortSignal.timeout(15_000),
      },
    );
  } catch {
    return "failed";
  }
  await response.body?.cancel();
  if (response.ok) return "sent";
  // 404: التثبيت غير مسجَّل لدى FCM (حُذف التطبيق أو أُلغي التسجيل).
  return response.status === 404 ? "gone" : "failed";
}
