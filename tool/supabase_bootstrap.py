#!/usr/bin/env python3
"""تهيئة مشروع Supabase لمدرسة بعد تطبيق الترحيلات.

الاستعمال:
  python3 tool/supabase_bootstrap.py verify      # وصول الرمز إلى المشروع وصلاحياته
  python3 tool/supabase_bootstrap.py bootstrap   # إعدادات الدخول + حساب المالك + دخول تجريبي
  python3 tool/supabase_bootstrap.py push-config # عنوان دالة الدفع وسرّها في قاعدة المدرسة (PUSH_SECRET)
  python3 tool/supabase_bootstrap.py reset-owner-password  # يعيد كلمة سر المالك إلى OWNER_INITIAL_PASSWORD (عند الطلب)

المدخلات من البيئة: SUPABASE_ACCESS_TOKEN وSUPABASE_PROJECT_REF (verify)، ويضاف لها
في bootstrap: SUPABASE_URL وSUPABASE_ANON_KEY وOWNER_PHONE وOWNER_INITIAL_PASSWORD.
العملية متكررة الأمان: لا تُنشئ حساباً ثانياً، ولا تُعيد كلمة سر مالك موجود، ولا
تُعيد فرض تغييرها. وحدها `reset-owner-password` (تُشغَّل عند الطلب) تعيد كلمة سر المالك الموجود إلى
OWNER_INITIAL_PASSWORD وتلزمه بتغييرها عند أول دخول. لا تُطبع أي قيمة سرّية؛ الرسائل فيها الأسباب فقط.
"""

from __future__ import annotations

import json
import os
import re
import secrets as randomness
import sys
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from typing import Any, Optional

EMAIL_DOMAIN = "school.local"
OWNER_DISPLAY_NAME = "صاحب المدرسة"
# حسابات مالك مؤقتة للفحوص الآلية: لا تمسّ مالك المدرسة الحقيقي ولا كلمة سره (التي
# يغيّرها عند أول دخول فتفشل فحوص تعتمد عليها).
TEMP_OWNER_PREFIX = "ci-owner-"
# أقل طول لكلمة السر المبدئية عند إعادتها (يطابق حد كلمة السر في التطبيق).
MIN_OWNER_PASSWORD = 8


class ApiError(Exception):
    def __init__(self, message: str, status: int = 0):
        super().__init__(message)
        self.status = status


def jwt_like(value: str) -> bool:
    return value.startswith("eyJ") and value.count(".") == 2


def reason(payload: Any) -> str:
    """سبب الرفض من رد الخادم (قصير، ولا يحوي أسراراً عادةً)."""
    if isinstance(payload, dict):
        for key in ("message", "msg", "error_description", "error", "hint"):
            value = payload.get(key)
            if isinstance(value, str) and value:
                return value[:200]
    if isinstance(payload, str):
        return payload[:200]
    return ""


def token_hint(token: str) -> str:
    """يصف شكل رمز الوصول المحفوظ دون ذكر قيمته، ويُلحق برسالة رفضه ليتضح عيب اللصق (سجلات المستودع علنية)."""
    if not token:
        return ": السرّ SUPABASE_ACCESS_TOKEN فارغ"
    if "*" in token:
        return (
            "؛ القيمة المحفوظة فيها نجوم (*)، أي أنها الرمز المقنَّع الظاهر في قائمة الرموز لا الرمز الكامل. "
            "انسخ الرمز بزر Copy فور إنشائه (يظهر كاملاً مرة واحدة) والصقه وحده"
        )
    if not token.startswith("sbp_"):
        return "؛ القيمة المحفوظة لا تبدأ بـ sbp_ فليست رمز وصول شخصياً من Supabase"
    if any(ch.isspace() for ch in token):
        return "؛ في القيمة المحفوظة فراغ أو سطر جديد وسط الرمز: الصق الرمز وحده"
    return (
        "؛ شكل القيمة المحفوظة سليم (تبدأ بـ sbp_) لكن Supabase لا يعرفها: حُذف الرمز أو انتهى أو لُصق ناقصاً، "
        "فأنشئ رمزاً جديداً وأعد لصقه"
    )


def call(
    method: str,
    url: str,
    headers: Optional[dict[str, str]] = None,
    body: Any = None,
    timeout: float = 30,
) -> tuple[int, Any]:
    data = None
    merged = {"Accept": "application/json", "User-Agent": "school-bootstrap"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        merged["Content-Type"] = "application/json"
    merged.update(headers or {})
    request = urllib.request.Request(url, data=data, method=method, headers=merged)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw, status = response.read(), response.status
    except urllib.error.HTTPError as error:
        raw, status = error.read(), error.code
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ApiError("تعذّر الاتصال بالخادم") from None
    try:
        payload = json.loads(raw) if raw else None
    except ValueError:
        payload = raw.decode("utf-8", "replace")[:200]
    return status, payload


@dataclass(frozen=True)
class Config:
    token: str = ""
    ref: str = ""
    url: str = ""
    anon_key: str = ""
    phone: str = ""
    password: str = ""
    push_secret: str = ""
    api_base: str = "https://api.supabase.com"

    @staticmethod
    def from_env(environ: dict[str, str]) -> "Config":
        return Config(
            # يُقصّ ما يتركه اللصق من فراغ أو سطر جديد حول الرمز.
            token=environ.get("SUPABASE_ACCESS_TOKEN", "").strip(),
            ref=environ.get("SUPABASE_PROJECT_REF", ""),
            url=environ.get("SUPABASE_URL", "").rstrip("/"),
            anon_key=environ.get("SUPABASE_ANON_KEY", ""),
            phone=environ.get("OWNER_PHONE", "").strip(),
            # يُقصّ ما يتركه اللصق من فراغ أو سطر جديد في آخر القيمة: لا يستطيع المالك كتابته.
            password=environ.get("OWNER_INITIAL_PASSWORD", "").strip(),
            push_secret=environ.get("PUSH_SECRET", ""),
            api_base=environ.get("SUPABASE_API_BASE", "https://api.supabase.com").rstrip("/"),
        )


class Bootstrap:
    def __init__(self, config: Config):
        self.cfg = config
        # متغيرات تُصدَّر للخطوات التالية في GitHub Actions (انظر main).
        self.exports: dict[str, str] = {}

    # ---- Management API (برمز الوصول الشخصي)

    @property
    def _management(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.cfg.token}"}

    def project_status(self) -> str:
        status, payload = call(
            "GET", f"{self.cfg.api_base}/v1/projects/{self.cfg.ref}", self._management
        )
        if status == 401:
            raise ApiError("رمز Supabase مرفوض (خاطئ أو منتهٍ)" + token_hint(self.cfg.token), status)
        if status == 403:
            raise ApiError("رمز Supabase لا يملك صلاحية قراءة المشروع (Project Settings)", status)
        if status == 404:
            raise ApiError(
                "المشروع غير موجود أو لا يصل إليه الرمز: تحقق من SUPABASE_PROJECT_REF ونطاق الرمز",
                status,
            )
        if status != 200 or not isinstance(payload, dict):
            raise ApiError(f"تعذّرت قراءة المشروع ({status}) {reason(payload)}", status)
        return str(payload.get("status", ""))

    def secret_key(self) -> str:
        status, payload = call(
            "GET",
            f"{self.cfg.api_base}/v1/projects/{self.cfg.ref}/api-keys?reveal=true",
            self._management,
        )
        if status in (401, 403):
            raise ApiError(
                "رمز Supabase لا يملك صلاحية قراءة أسرار المفاتيح (API Key Secrets: Read)", status
            )
        if status != 200 or not isinstance(payload, list):
            raise ApiError(f"تعذّرت قراءة مفاتيح المشروع ({status}) {reason(payload)}", status)
        keys = [k for k in payload if isinstance(k, dict) and isinstance(k.get("api_key"), str)]
        secrets = sorted(
            (k for k in keys if k.get("type") == "secret"), key=lambda k: k.get("name") != "default"
        )
        legacy = [k for k in keys if k.get("name") == "service_role"]
        chosen = (secrets or legacy or [None])[0]
        if chosen is None:
            raise ApiError("لا يوجد مفتاح سرّي في المشروع (أنشئ Secret key من إعدادات API Keys)")
        key = chosen["api_key"]
        if not re.fullmatch(r"[A-Za-z0-9_.\-]+", key):
            raise ApiError("المفتاح السرّي مخفي: امنح الرمز صلاحية API Key Secrets (قراءة)")
        return key

    def push_config(self) -> list[str]:
        """يضبط عنوان دالة الدفع وسرّها المشترك في قاعدة المدرسة (rpc لا يصله غير المفتاح السرّي)."""
        key = self.secret_key()
        status, payload = call(
            "POST",
            f"{self.cfg.url}/rest/v1/rpc/set_push_config",
            self._admin(key),
            {"p_url": f"{self.cfg.url}/functions/v1/send-push", "p_secret": self.cfg.push_secret},
        )
        if status in (200, 204):
            return ["push-config=ok"]
        raise ApiError(f"تعذّر ضبط إعداد الدفع ({status}) {reason(payload)}", status)

    def disable_signup(self) -> None:
        status, payload = call(
            "PATCH",
            f"{self.cfg.api_base}/v1/projects/{self.cfg.ref}/config/auth",
            self._management,
            {"disable_signup": True},
        )
        if status in (401, 403):
            raise ApiError("رمز Supabase لا يملك صلاحية تعديل إعدادات الدخول (Auth Config)", status)
        if status not in (200, 201):
            raise ApiError(f"تعذّر تعطيل التسجيل العام ({status}) {reason(payload)}", status)

    # ---- المشروع نفسه (بالمفتاح السرّي)

    @property
    def email(self) -> str:
        return f"{self.cfg.phone}@{EMAIL_DOMAIN}"

    @staticmethod
    def _admin(key: str) -> dict[str, str]:
        headers = {"apikey": key}
        if jwt_like(key):
            headers["Authorization"] = f"Bearer {key}"
        return headers

    def _find_user(self, key: str) -> Optional[str]:
        for page in range(1, 51):
            status, payload = call(
                "GET",
                f"{self.cfg.url}/auth/v1/admin/users?page={page}&per_page=200",
                self._admin(key),
            )
            if status != 200 or not isinstance(payload, dict):
                raise ApiError(f"تعذّرت قراءة المستخدمين ({status}) {reason(payload)}", status)
            users = payload.get("users") or []
            for user in users:
                if isinstance(user, dict) and str(user.get("email", "")).lower() == self.email:
                    return str(user.get("id"))
            if len(users) < 200:
                return None
        return None

    def ensure_auth_user(self, key: str) -> tuple[str, bool]:
        """يعيد (معرّف المستخدم، هل أُنشئ الآن)."""
        status, payload = call(
            "POST",
            f"{self.cfg.url}/auth/v1/admin/users",
            self._admin(key),
            {"email": self.email, "password": self.cfg.password, "email_confirm": True},
        )
        if status in (200, 201) and isinstance(payload, dict) and isinstance(payload.get("id"), str):
            return payload["id"], True
        code = payload.get("error_code") if isinstance(payload, dict) else None
        if status in (409, 422) and code in (None, "email_exists", "user_already_exists"):
            found = self._find_user(key)
            if found:
                return found, False
            raise ApiError("حساب المالك موجود لكن تعذّر العثور على معرّفه")
        if status in (401, 403):
            raise ApiError("المفتاح السرّي مرفوض في Auth: تحقق من نوع المفتاح وصلاحياته", status)
        raise ApiError(f"تعذّر إنشاء مستخدم المالك ({status}) {reason(payload)}", status)

    def ensure_account_row(self, key: str, uid: str) -> bool:
        """يضيف صف `user_accounts` للمالك إن لم يوجد؛ يعيد هل أُضيف الآن."""
        headers = self._admin(key)
        status, rows = call(
            "GET", f"{self.cfg.url}/rest/v1/user_accounts?id=eq.{uid}&select=id", headers
        )
        if status != 200 or not isinstance(rows, list):
            raise ApiError(
                f"تعذّرت قراءة user_accounts ({status}) {reason(rows)}: هل طُبّقت الترحيلات؟", status
            )
        if rows:
            return False
        now = int(time.time() * 1000)
        status, payload = call(
            "POST",
            f"{self.cfg.url}/rest/v1/user_accounts",
            {**headers, "Prefer": "return=minimal"},
            {
                "id": uid,
                "created_at": now,
                "updated_at": now,
                "email": self.email,
                "role": "owner",
                "entity_id": None,
                "display_name": OWNER_DISPLAY_NAME,
                "must_change_password": True,
            },
        )
        if status not in (200, 201, 204):
            raise ApiError(f"تعذّر إضافة حساب المالك ({status}) {reason(payload)}", status)
        return True

    def smoke(self) -> str:
        """دخول المالك بالمفتاح العام وقراءته حسابه عبر RLS: ok أو skipped."""
        status, payload = call(
            "POST",
            f"{self.cfg.url}/auth/v1/token?grant_type=password",
            {"apikey": self.cfg.anon_key},
            {"email": self.email, "password": self.cfg.password},
        )
        code = payload.get("error_code") if isinstance(payload, dict) else None
        if status in (400, 401) and code == "invalid_credentials":
            return "skipped"  # غُيّرت كلمة السر منذ الإنشاء: لا خطأ
        token = payload.get("access_token") if isinstance(payload, dict) else None
        if status != 200 or not isinstance(token, str):
            raise ApiError(f"فشل الدخول التجريبي ({status}) {reason(payload)}", status)
        status, rows = call(
            "GET",
            f"{self.cfg.url}/rest/v1/user_accounts?select=id,role",
            {"apikey": self.cfg.anon_key, "Authorization": f"Bearer {token}"},
        )
        if status != 200 or not isinstance(rows, list) or not any(
            isinstance(r, dict) and r.get("role") == "owner" for r in rows
        ):
            raise ApiError(
                f"قراءة حساب المالك بعد الدخول فشلت ({status}): تحقق من المخطط وسياسات RLS", status
            )
        return "ok"

    # ---- مالك مؤقت للفحوص

    def _delete_user(self, key: str, uid: str) -> None:
        call("DELETE", f"{self.cfg.url}/rest/v1/user_accounts?id=eq.{uid}", self._admin(key))
        call("DELETE", f"{self.cfg.url}/auth/v1/admin/users/{uid}", self._admin(key))

    def temp_owner_create(self) -> list[str]:
        """ينشئ مالكاً مؤقتاً (مستخدم Auth وصف user_accounts) ويصدّر بياناته للخطوات التالية."""
        key = self.secret_key()
        email = f"{TEMP_OWNER_PREFIX}{uuid.uuid4().hex[:12]}@{EMAIL_DOMAIN}"
        password = randomness.token_urlsafe(24)
        status, payload = call(
            "POST",
            f"{self.cfg.url}/auth/v1/admin/users",
            self._admin(key),
            {"email": email, "password": password, "email_confirm": True},
        )
        if status not in (200, 201) or not isinstance(payload, dict) or not isinstance(payload.get("id"), str):
            raise ApiError(f"تعذّر إنشاء مالك الفحوص ({status}) {reason(payload)}", status)
        uid = payload["id"]
        now = int(time.time() * 1000)
        status, payload = call(
            "POST",
            f"{self.cfg.url}/rest/v1/user_accounts",
            {**self._admin(key), "Prefer": "return=minimal"},
            {
                "id": uid, "created_at": now, "updated_at": now, "email": email, "role": "owner",
                "entity_id": None, "display_name": "فحص آلي", "must_change_password": False,
            },
        )
        if status not in (200, 201, 204):
            self._delete_user(key, uid)  # لا يُترك مستخدم بلا صف
            raise ApiError(f"تعذّر إضافة صف مالك الفحوص ({status}) {reason(payload)}", status)
        self.exports = {"CI_OWNER_EMAIL": email, "CI_OWNER_PASSWORD": password, "CI_OWNER_ID": uid}
        return ["temp-owner=created"]

    def temp_owner_delete(self) -> list[str]:
        """يحذف كل المالكين المؤقتين (ومنهم ما خلّفه تشغيل أُلغي قبل تنظيفه)."""
        key = self.secret_key()
        removed = 0
        for page in range(1, 51):
            status, payload = call(
                "GET",
                f"{self.cfg.url}/auth/v1/admin/users?page={page}&per_page=200",
                self._admin(key),
            )
            if status != 200 or not isinstance(payload, dict):
                raise ApiError(f"تعذّرت قراءة المستخدمين ({status}) {reason(payload)}", status)
            users = payload.get("users") or []
            for user in users:
                email = str(user.get("email", "")) if isinstance(user, dict) else ""
                if email.startswith(TEMP_OWNER_PREFIX) and email.endswith(f"@{EMAIL_DOMAIN}"):
                    self._delete_user(key, str(user.get("id")))
                    removed += 1
            if len(users) < 200:
                break
        return [f"temp-owners-removed={removed}"]

    # ---- الأوامر

    def verify(self) -> list[str]:
        status = self.project_status()
        if not status.startswith("ACTIVE"):
            raise ApiError(f"المشروع ليس نشطاً (الحالة {status}): استعده من لوحة Supabase")
        self.secret_key()
        return [f"project={status} token=ok secret-key=readable"]

    def bootstrap(self) -> list[str]:
        out = self.verify()
        key = self.secret_key()
        self.disable_signup()
        uid, created = self.ensure_auth_user(key)
        row = self.ensure_account_row(key, uid)
        smoke = self.smoke()
        out.append(
            f"signup=disabled owner={'created' if created else 'existed'} "
            f"account-row={'created' if row else 'existed'} smoke={smoke}"
        )
        return out

    def reset_owner_password(self) -> list[str]:
        """يعيد كلمة سر المالك الموجود إلى OWNER_INITIAL_PASSWORD ويُلزمه بتغييرها، ثم يجرّب الدخول بها.

        لمالك نسي كلمة سره أو لم تعد تطابق ما في السرّ (غُيّر السرّ بعد إنشاء الحساب، أو لُصق بسطر زائد).
        لا يُنشئ حساباً: يفشل إن لم يوجد المالك، فالإنشاء للنشر العادي.
        """
        if len(self.cfg.password) < MIN_OWNER_PASSWORD:
            raise ApiError(
                f"كلمة السر المبدئية أقل من {MIN_OWNER_PASSWORD} رموز: اكتب في السرّ OWNER_INITIAL_PASSWORD "
                "كلمة أطول (يغيّرها المالك عند أول دخول)"
            )
        out = self.verify()
        key = self.secret_key()
        uid = self._find_user(key)
        if uid is None:
            raise ApiError("حساب المالك غير موجود: شغّل النشر العادي أولاً ليُنشئه")
        status, payload = call(
            "PUT",
            f"{self.cfg.url}/auth/v1/admin/users/{uid}",
            self._admin(key),
            {"password": self.cfg.password},
        )
        if status not in (200, 201):
            code = payload.get("error_code") if isinstance(payload, dict) else None
            if code == "weak_password":
                raise ApiError("كلمة السر مرفوضة من Supabase (ضعيفة): اختر كلمة أطول وأقوى", status)
            if status in (401, 403):
                raise ApiError("المفتاح السرّي مرفوض في Auth: تحقق من نوع المفتاح وصلاحياته", status)
            raise ApiError(f"تعذّر تغيير كلمة سر المالك ({status}) {reason(payload)}", status)
        self.ensure_account_row(key, uid)
        status, payload = call(
            "PATCH",
            f"{self.cfg.url}/rest/v1/user_accounts?id=eq.{uid}",
            {**self._admin(key), "Prefer": "return=minimal"},
            {"must_change_password": True, "updated_at": int(time.time() * 1000)},
        )
        if status not in (200, 204):
            raise ApiError(f"أُعيدت كلمة السر لكن تعذّر إلزام المالك بتغييرها ({status}) {reason(payload)}", status)
        smoke = self.smoke()
        if smoke != "ok":
            raise ApiError(f"أُعيدت كلمة السر لكن الدخول التجريبي بها لم ينجح ({smoke})")
        out.append("owner-password=reset must-change=true smoke=ok")
        return out


def escape(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


REQUIRED = {
    "verify": ("SUPABASE_ACCESS_TOKEN", "SUPABASE_PROJECT_REF"),
    "bootstrap": (
        "SUPABASE_ACCESS_TOKEN",
        "SUPABASE_PROJECT_REF",
        "SUPABASE_URL",
        "SUPABASE_ANON_KEY",
        "OWNER_PHONE",
        "OWNER_INITIAL_PASSWORD",
    ),
    "reset-owner-password": (
        "SUPABASE_ACCESS_TOKEN",
        "SUPABASE_PROJECT_REF",
        "SUPABASE_URL",
        "SUPABASE_ANON_KEY",
        "OWNER_PHONE",
        "OWNER_INITIAL_PASSWORD",
    ),
    "push-config": ("SUPABASE_ACCESS_TOKEN", "SUPABASE_PROJECT_REF", "SUPABASE_URL", "PUSH_SECRET"),
    "temp-owner-create": ("SUPABASE_ACCESS_TOKEN", "SUPABASE_PROJECT_REF", "SUPABASE_URL"),
    "temp-owner-delete": ("SUPABASE_ACCESS_TOKEN", "SUPABASE_PROJECT_REF", "SUPABASE_URL"),
}


def export_to_github_env(exports: dict[str, str], environ: dict[str, str]) -> None:
    """يصدّر المتغيرات للخطوات التالية؛ كلمة السر تُخفى من السجل قبل كتابتها."""
    for name, value in exports.items():
        if name.endswith("PASSWORD"):
            print(f"::add-mask::{value}")
    path = environ.get("GITHUB_ENV")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            for name, value in exports.items():
                f.write(f"{name}={value}\n")


def main(argv: list[str], environ: Optional[dict[str, str]] = None) -> int:
    environ = dict(os.environ) if environ is None else environ
    if len(argv) != 2 or argv[1] not in REQUIRED:
        print("الاستعمال: supabase_bootstrap.py verify|bootstrap|reset-owner-password|push-config|temp-owner-create|temp-owner-delete", file=sys.stderr)
        return 2
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    command = argv[1]
    title = f"supabase-{command}"
    missing = [name for name in REQUIRED[command] if not environ.get(name)]
    if missing:
        print(f"::error title={title}::{escape('متغيرات ناقصة: ' + ', '.join(missing))}")
        return 1
    bootstrap = Bootstrap(Config.from_env(environ))
    try:
        lines = getattr(bootstrap, command.replace("-", "_"))()
    except ApiError as error:
        print(f"::error title={title}::{escape(str(error))}")
        return 1
    export_to_github_env(bootstrap.exports, environ)
    for line in lines:
        print(f"::notice title={title}::{escape(line)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
