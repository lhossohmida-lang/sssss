#!/usr/bin/env python3
"""فحص ما قبل النشر: أسماء الأسرار والمتغيرات وصيغها، دون طباعة أي قيمة.

الاستعمال:
  python3 tool/preflight.py school   (داخل Environment المدرسة)
  python3 tool/preflight.py repo     (دون Environment: مستوى المستودع فقط)

المدخلات من البيئة: لكل اسم N المتغير N (من secrets.N) والمتغير VAR_N (من vars.N)،
وSCHOOL لاسم المدرسة (للعرض). تُسمّى الأسماء صراحةً في المسار ولا يُستعمل
toJSON(secrets) (يعدّه GitHub نمطاً مشبوهاً ويوقف التشغيل لموافقة يدوية). لا
تُطبع قيمة سرّية أبداً: الرسائل فيها الأسماء والأسباب فقط.
"""

from __future__ import annotations

import base64
import binascii
import json
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Callable, Optional

# نتيجة فحص الصيغة: None سليم، أو (مستوى، رسالة) ومستواه error أو warn.
Problem = Optional[tuple[str, str]]


class Values:
    """القيم المتاحة للمهمة. المتغيرات غير سرّية؛ والأسرار تُقرأ ولا تُعرض."""

    def __init__(self, secrets: dict[str, str], variables: dict[str, str]):
        self.secrets = {k.upper(): v for k, v in secrets.items()}
        self.variables = {k.upper(): v for k, v in variables.items()}

    def get(self, name: str, secret_only: bool = False) -> str:
        value = self.secrets.get(name)
        if not value and not secret_only:
            value = self.variables.get(name)
        return value or ""


Check = Callable[[str, Values], Problem]


@dataclass(frozen=True)
class Item:
    name: str
    required: bool  # مطلوب في مدرسة الآن؟
    secret_only: bool  # يجب أن يكون في Secrets لا Variables
    check: Optional[Check] = None
    # قيمة افتراضية للمطوّر يجوز أن تكون على مستوى المستودع (تحذير لا خطأ): يسقط عليها مسار مدرسة
    # لا تضع قيمتها في Environment، وضررها حساب فوترة لا قاعدة بيانات مدرسة أخرى.
    repo_default_ok: bool = False


def jwt_payload(token: str) -> Optional[dict]:
    parts = token.split(".")
    if len(parts) != 3:
        return None
    try:
        padded = parts[1] + "=" * (-len(parts[1]) % 4)
        data = json.loads(base64.urlsafe_b64decode(padded))
    except (ValueError, binascii.Error):
        return None
    return data if isinstance(data, dict) else None


def check_url(value: str, ctx: Values) -> Problem:
    match = re.fullmatch(r"https://([a-z0-9]{20})\.supabase\.co", value)
    if not match:
        return ("error", "الصيغة المتوقعة https://<20 حرفاً>.supabase.co دون شرطة أخيرة")
    ref = ctx.get("SUPABASE_PROJECT_REF")
    if ref and ref != match.group(1):
        return ("error", "معرّف المشروع في الرابط يخالف SUPABASE_PROJECT_REF")
    return None


def check_ref(value: str, ctx: Values) -> Problem:
    if not re.fullmatch(r"[a-z0-9]{20}", value):
        return ("error", "المعرّف 20 حرفاً صغيراً وأرقاماً")
    return None


def check_anon(value: str, ctx: Values) -> Problem:
    if value.startswith("sb_secret_"):
        return ("error", "هذا مفتاح سرّي (sb_secret_) لا المفتاح العام، ويجب ألا يُضمَّن في أي تطبيق")
    if value.startswith("sb_publishable_"):
        return None
    payload = jwt_payload(value)
    if payload is None:
        return ("error", "ليس مفتاحاً عاماً معروفاً (sb_publishable_… أو anon JWT)")
    role = payload.get("role")
    if role == "service_role":
        return ("error", "هذا مفتاح service_role السرّي لا المفتاح العام")
    if role != "anon":
        return ("warn", "دور مفتاح JWT ليس anon")
    return None


def check_pat(value: str, ctx: Values) -> Problem:
    if not re.fullmatch(r"sbp_[A-Za-z0-9_]{20,}", value):
        return ("error", "الصيغة المتوقعة sbp_… (رمز وصول شخصي من Supabase)")
    return None


def check_db_password(value: str, ctx: Values) -> Problem:
    if value != value.strip() or re.search(r"\s", value):
        return ("error", "فيها مسافة أو سطر فارغ (تحقق من اللصق)")
    if len(value) < 12:
        return ("error", "أقصر من 12 خانة")
    if re.search(r"[@:/?#%&]", value):
        return ("warn", "فيها رموز قد تكسر رابط الاتصال (@ : / ? # % &)")
    return None


def check_owner_password(value: str, ctx: Values) -> Problem:
    if value != value.strip():
        return ("error", "تبدأ أو تنتهي بمسافة أو سطر فارغ (تحقق من اللصق)")
    if len(value) < 8:
        return ("error", "أقصر من 8 خانات")
    return None


def check_phone(value: str, ctx: Values) -> Problem:
    if not re.fullmatch(r"0[567][0-9]{8}", value):
        return ("error", "الصيغة 05/06/07 ثم 8 أرقام (10 أرقام لاتينية)")
    return None


def check_email(value: str, ctx: Values) -> Problem:
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
        return ("error", "بريد غير صالح")
    return None


def check_https_url(value: str, ctx: Values) -> Problem:
    if not re.fullmatch(r"https://[^\s/]+(/\S*)?", value) or value.endswith("/"):
        return ("error", "رابط https دون شرطة أخيرة")
    return None


def check_llm_key(value: str, ctx: Values) -> Problem:
    if not value.startswith("sk-or-"):
        return ("warn", "ليس بصيغة مفتاح OpenRouter (sk-or-…)")
    return None


def check_nonempty(value: str, ctx: Values) -> Problem:
    if value != value.strip():
        return ("error", "تبدأ أو تنتهي بمسافة أو سطر فارغ (تحقق من اللصق)")
    return None


def check_key_password(value: str, ctx: Values) -> Problem:
    problem = check_nonempty(value, ctx)
    if problem:
        return problem
    store = ctx.get("SCHOOL_KEYSTORE_PASSWORD", secret_only=True)
    if store and store != value:
        return ("warn", "تخالف SCHOOL_KEYSTORE_PASSWORD (ملف PKCS12 يتطلب تطابقهما)")
    return None


def check_keystore(value: str, ctx: Values) -> Problem:
    compact = re.sub(r"\s+", "", value)
    try:
        raw = base64.b64decode(compact, validate=True)
    except (binascii.Error, ValueError):
        return ("error", "ليست base64 صالحة")
    if len(raw) < 500:
        return ("error", "أصغر من أن تكون ملف مفاتيح")
    if raw[:2] != b"\x30\x82" and raw[:4] != b"\xfe\xed\xfe\xed":
        return ("error", "لا يبدو ملف مفاتيح (PKCS12 أو JKS)")
    return None


def check_google_client_id(value: str, ctx: Values) -> Problem:
    if not re.fullmatch(r"[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com", value):
        return ("error", "الصيغة المتوقعة <أرقام>-<نص>.apps.googleusercontent.com")
    return None


def check_desktop_secret(value: str, ctx: Values) -> Problem:
    if not value.startswith("GOCSPX-"):
        return ("error", "الصيغة المتوقعة GOCSPX-…")
    return None


def google_services(package: str) -> Check:
    def check(value: str, ctx: Values) -> Problem:
        try:
            data = json.loads(value)
        except ValueError:
            return ("error", "ليس JSON صالحاً")
        clients = data.get("client") if isinstance(data, dict) else None
        packages = {
            ((c.get("client_info") or {}).get("android_client_info") or {}).get("package_name")
            for c in (clients or [])
            if isinstance(c, dict)
        }
        if package not in packages:
            return ("error", f"اسم الحزمة داخل الملف لا يطابق {package}")
        return None

    return check


def check_service_account(value: str, ctx: Values) -> Problem:
    try:
        data = json.loads(value)
    except ValueError:
        return ("error", "ليس JSON صالحاً")
    if not isinstance(data, dict) or data.get("type") != "service_account":
        return ("error", "ليس ملف حساب خدمة (type ≠ service_account)")
    if not str(data.get("private_key", "")).startswith("-----BEGIN PRIVATE KEY-----"):
        return ("error", "لا يحوي مفتاحاً خاصاً")
    if not str(data.get("client_email", "")).endswith(".iam.gserviceaccount.com"):
        return ("error", "بريد حساب الخدمة غير معتاد")
    return None


# قيم كل مدرسة (تُحفظ داخل Environment باسمها فقط).
SCHOOL_ITEMS: list[Item] = [
    Item("SUPABASE_URL", True, False, check_url),
    Item("SUPABASE_PROJECT_REF", True, False, check_ref),
    Item("SUPABASE_ANON_KEY", True, False, check_anon),
    Item("SUPABASE_ACCESS_TOKEN", True, True, check_pat),
    Item("SUPABASE_DB_PASSWORD", True, True, check_db_password),
    Item("OWNER_PHONE", True, False, check_phone),
    Item("OWNER_INITIAL_PASSWORD", True, True, check_owner_password),
    Item("LLM_API_KEY", False, True, check_llm_key, repo_default_ok=True),
    Item("LLM_MODEL", False, False, None, repo_default_ok=True),
    Item("LLM_BASE_URL", False, False, check_https_url, repo_default_ok=True),
    Item("GOOGLE_DRIVE_OWNER_EMAIL", False, False, check_email),
]

# أسرار المطوّر المشتركة بين المدارس (على مستوى المستودع).
DEVELOPER_ITEMS: list[Item] = [
    Item("SCHOOL_KEYSTORE_BASE64", False, True, check_keystore),
    Item("SCHOOL_KEYSTORE_PASSWORD", False, True, check_nonempty),
    Item("SCHOOL_KEY_ALIAS", False, True, check_nonempty),
    Item("SCHOOL_KEY_PASSWORD", False, True, check_key_password),
    Item("GOOGLE_DESKTOP_CLIENT_SECRET", False, True, check_desktop_secret),
    Item("GOOGLE_DRIVE_WINDOWS_CLIENT_ID", False, False, check_google_client_id),
    Item("GOOGLE_SERVER_CLIENT_ID", False, False, check_google_client_id),
    Item("GOOGLE_SERVICES_ADMIN", False, True, google_services("dz.school.admin")),
    Item("GOOGLE_SERVICES_TEACHER", False, True, google_services("dz.school.teacher")),
    Item("GOOGLE_SERVICES_STUDENT", False, True, google_services("dz.school.student")),
    Item("FIREBASE_SERVICE_ACCOUNT", False, True, check_service_account),
]

FIREBASE_PROJECT_SOURCES = (
    "GOOGLE_SERVICES_ADMIN",
    "GOOGLE_SERVICES_TEACHER",
    "GOOGLE_SERVICES_STUDENT",
    "FIREBASE_SERVICE_ACCOUNT",
)


@dataclass
class Report:
    rows: list[tuple[str, str]] = field(default_factory=list)  # (اسم، حالة)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def firebase_project_id(name: str, raw: str) -> Optional[str]:
    try:
        data = json.loads(raw)
    except ValueError:
        return None
    if not isinstance(data, dict):
        return None
    if name == "FIREBASE_SERVICE_ACCOUNT":
        project = data.get("project_id")
    else:
        project = (data.get("project_info") or {}).get("project_id")
    return project if isinstance(project, str) else None


def evaluate(mode: str, secrets: dict[str, str], variables: dict[str, str]) -> Report:
    values = Values(secrets, variables)
    report = Report()
    items = SCHOOL_ITEMS if mode == "school" else DEVELOPER_ITEMS
    for item in items:
        if item.secret_only and values.variables.get(item.name):
            report.rows.append((item.name, "bad"))
            report.errors.append(
                f"{item.name}: حُفظ في Variables فيظهر علناً؛ احذفه وأضفه في Secrets"
            )
            continue
        value = values.get(item.name, item.secret_only)
        if not value:
            required = item.required and mode == "school"
            report.rows.append((item.name, "missing" if required else "not-set"))
            if required:
                report.errors.append(f"{item.name}: غير موجود")
            continue
        problem = item.check(value, values) if item.check else None
        if problem is not None and problem[0] == "error":
            report.rows.append((item.name, "bad"))
            report.errors.append(f"{item.name}: {problem[1]}")
            continue
        report.rows.append((item.name, "ok"))
        if problem is not None:
            report.warnings.append(f"{item.name}: {problem[1]}")

    if mode == "repo":
        for item in SCHOOL_ITEMS:
            if not values.get(item.name):
                continue
            if item.repo_default_ok:
                report.warnings.append(
                    f"{item.name}: على مستوى المستودع فتستعمله كل مدرسة لا تضع قيمتها في "
                    "Environment؛ ضع قيمة كل مدرسة في Environment عند إضافة مدرسة ثانية"
                )
            else:
                report.errors.append(
                    f"{item.name}: قيمة خاصة بمدرسة على مستوى المستودع؛ "
                    "انقلها إلى Environment المدرسة"
                )
        projects = {
            project
            for name in FIREBASE_PROJECT_SOURCES
            if (raw := values.get(name, secret_only=True))
            and (project := firebase_project_id(name, raw))
        }
        if len(projects) > 1:
            report.errors.append("ملفات Firebase وحساب الخدمة من مشاريع مختلفة")

    return report


STATE_LABEL = {
    "ok": "✅ موجود وصيغته سليمة",
    "bad": "❌ صيغته أو مكانه خاطئ",
    "missing": "❌ مطلوب وغير موجود",
    "not-set": "➖ غير مضبوط (ليس مطلوباً الآن)",
}


def render(report: Report, mode: str, school: str) -> str:
    title = f"مدرسة `{school}`" if mode == "school" else "مستوى المستودع (أسرار المطوّر المشتركة)"
    lines = [f"### فحص ما قبل النشر: {title}", "", "| الاسم | الحالة |", "| --- | --- |"]
    lines += [f"| `{name}` | {STATE_LABEL[state]} |" for name, state in report.rows]
    if report.errors:
        lines += ["", "**أخطاء:**"] + [f"- {e}" for e in report.errors]
    if report.warnings:
        lines += ["", "**تحذيرات:**"] + [f"- {w}" for w in report.warnings]
    return "\n".join(lines)


def escape(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def annotations(report: Report, mode: str) -> list[str]:
    states = " ".join(f"{name}={state}" for name, state in report.rows)
    out = [f"::notice title=preflight-{mode}::{escape(states)}"]
    if report.errors:
        out.append(f"::error title=preflight-{mode}::{escape('; '.join(report.errors))}")
    if report.warnings:
        out.append(f"::warning title=preflight-{mode}::{escape('; '.join(report.warnings))}")
    return out


def names_for(mode: str) -> list[str]:
    """الأسماء التي يفحصها المسار في [mode]، وكلها تُمرَّر صراحةً من ملف المسار."""
    school = [item.name for item in SCHOOL_ITEMS]
    developer = [item.name for item in DEVELOPER_ITEMS]
    return school if mode == "school" else developer + school


def collect(names: list[str], environ: dict[str, str]) -> tuple[dict[str, str], dict[str, str]]:
    secrets = {name: environ.get(name, "") for name in names}
    variables = {name: environ.get("VAR_" + name, "") for name in names}
    return secrets, variables


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in ("school", "repo"):
        print("الاستعمال: preflight.py school|repo", file=sys.stderr)
        return 2
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    mode = argv[1]
    secrets, variables = collect(names_for(mode), dict(os.environ))
    school = re.sub(r"[^A-Za-z0-9_-]", "", os.environ.get("SCHOOL", ""))[:40]
    report = evaluate(mode, secrets, variables)
    text = render(report, mode, school)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text + "\n")
    for line in annotations(report, mode):
        print(line)
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
