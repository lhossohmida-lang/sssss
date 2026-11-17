// يسجّل أرقام طاقم المدرسة (المالك والعمال) في دليل المدارس ليعرف تطبيق الإدارة مدرسة كل منهم من
// هاتفه فلا يلصق أحد رمز ربط. يعمل إن ضُبطت أسرار الدليل في دوال المدرسة (DIRECTORY_URL وDIRECTORY_ANON_KEY
// وDIRECTORY_SLUG وDIRECTORY_REGISTER_KEY، يضبطها مسار supabase-deploy)؛ دونها يُتجاوز بلا خطأ (مدرسة بلا دليل).
// مفتاح التسجيل خاص بهذه المدرسة: لا يسجّل به غيرها ولا يقرأ منه شيء. لا تُسجَّل هنا أرقام ولا مفاتيح.
import { adminHeaders } from "./accounts.ts";

export type DirectoryConfig = {
  url: string;
  anonKey: string;
  slug: string;
  registerKey: string;
};

export function directoryConfig(): DirectoryConfig | null {
  const url = Deno.env.get("DIRECTORY_URL")?.trim().replace(/\/$/, "");
  const anonKey = Deno.env.get("DIRECTORY_ANON_KEY")?.trim();
  const slug = Deno.env.get("DIRECTORY_SLUG")?.trim();
  const registerKey = Deno.env.get("DIRECTORY_REGISTER_KEY")?.trim();
  if (!url || !anonKey || !slug || !registerKey) return null;
  return { url, anonKey, slug, registerKey };
}

/** رقم الهاتف المحلي من بريد الدخول المولَّد `0550123456@school.local`، وإلا null. */
export function phoneOfLoginEmail(email: string): string | null {
  const match = /^(0[567][0-9]{8})@school\.local$/i.exec(email.trim());
  return match === null ? null : match[1];
}

/** الأدوار التي يدخل أصحابها من تطبيق الإدارة، فيلزم أن يُعرفوا من هاتفهم. */
export function needsDirectoryEntry(role: string): boolean {
  return role === "owner" || role === "worker";
}

async function call(config: DirectoryConfig, name: string, phone: string): Promise<boolean> {
  try {
    const response = await fetch(`${config.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: { ...adminHeaders(config.anonKey), "Content-Type": "application/json" },
      body: JSON.stringify({
        p_slug: config.slug,
        p_register_key: config.registerKey,
        p_phone: phone,
      }),
    });
    if (!response.ok) return false;
    const result: unknown = await response.json();
    return result === true;
  } catch {
    return false;
  }
}

/** يسجّل [phone] لهذه المدرسة؛ `true` إن قبله الدليل. */
export function registerStaffPhone(config: DirectoryConfig, phone: string): Promise<boolean> {
  return call(config, "school_register_phone", phone);
}

/** يزيل [phone] من هذه المدرسة (عند حذف حساب أو تغيير رقم)؛ `true` إن قبله الدليل. */
export function unregisterStaffPhone(config: DirectoryConfig, phone: string): Promise<boolean> {
  return call(config, "school_unregister_phone", phone);
}
