#!/usr/bin/env python3
"""فحص عقد الخادم الحقيقي لمدرسة بعد النشر: RLS وكتابة المزامنة والدوال والملفات.

يعمل بحساب المالك ثم بحساب أستاذ مؤقت ينشئه بدالة provision-account، ويحذف كل ما أنشأه
في النهاية. لا يُطبع أي سرّ؛ النتائج في تعليقات `server-check` العامة.

الاستعمال: python3 tool/server_check.py
المدخلات: نفس متغيرات supabase_bootstrap.py (SUPABASE_ACCESS_TOKEN وPROJECT_REF وURL
وANON_KEY وOWNER_PHONE وOWNER_INITIAL_PASSWORD). إن غُيّرت كلمة سر المالك بعد
الإنشاء يُتخطّى الفحص بلا خطأ.
"""

from __future__ import annotations

import os
import secrets as randomness
import sys
import time
import urllib.error
import urllib.request
import uuid
from typing import Any, Callable, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import supabase_bootstrap as sb  # noqa: E402


def raw(method: str, url: str, headers: dict[str, str], data: Optional[bytes] = None) -> tuple[int, bytes]:
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except (urllib.error.URLError, TimeoutError, OSError):
        raise sb.ApiError("تعذّر الاتصال بالخادم") from None


class Skip(Exception):
    """فحص لا ينطبق الآن (لا مفتاح نموذج، أو المزوّد مشغول): ليس نجاحاً ولا فشلاً."""


class Suite:
    def __init__(self, config: sb.Config, secret_key: str):
        self.cfg = config
        self.secret = secret_key
        self.results: list[tuple[str, str, str]] = []  # (اسم، ok|fail، تفصيل)
        self.cleanups: list[Callable[[], None]] = []
        self.owner = ""
        self.teacher_id = ""
        self.teacher_email = ""
        self.teacher_token = ""

    # ---- رؤوس وطلبات

    def anon(self) -> dict[str, str]:
        return {"apikey": self.cfg.anon_key}

    def user(self, token: str) -> dict[str, str]:
        return {"apikey": self.cfg.anon_key, "Authorization": f"Bearer {token}"}

    def admin(self) -> dict[str, str]:
        return sb.Bootstrap._admin(self.secret)

    def call(
        self, method: str, path: str, headers: dict[str, str], body: Any = None, timeout: float = 30
    ) -> tuple[int, Any]:
        return sb.call(method, f"{self.cfg.url}{path}", headers, body, timeout=timeout)

    def sign_in(self, email: str, password: str) -> Optional[str]:
        status, payload = self.call(
            "POST",
            "/auth/v1/token?grant_type=password",
            self.anon(),
            {"email": email, "password": password},
        )
        token = payload.get("access_token") if isinstance(payload, dict) else None
        return token if status == 200 and isinstance(token, str) else None

    def upsert(self, table: str, headers: dict[str, str], row: dict[str, Any]) -> tuple[int, Any]:
        return self.call(
            "POST",
            f"/rest/v1/{table}?on_conflict=id",
            {**headers, "Prefer": "resolution=merge-duplicates,return=representation"},
            row,
        )

    # ---- المشغّل

    def check(self, name: str, fn: Callable[[], Optional[str]]) -> None:
        try:
            detail = fn()
        except Skip as error:
            self.results.append((name, "skip", str(error)))
        except AssertionError as error:
            self.results.append((name, "fail", str(error)))
        except sb.ApiError as error:
            self.results.append((name, "fail", str(error)))
        except Exception as error:  # noqa: BLE001  (خطأ برمجي في الفحص نفسه)
            self.results.append((name, "fail", f"{type(error).__name__}: {error}"[:200]))
        else:
            self.results.append((name, "ok", detail or ""))

    def cleanup(self) -> None:
        for step in reversed(self.cleanups):
            try:
                step()
            except Exception:  # noqa: BLE001  (التنظيف لا يُسقط التقرير)
                pass

    # ---- الفحوص

    def anon_sees_nothing(self) -> None:
        status, rows = self.call("GET", "/rest/v1/user_accounts?select=id", self.anon())
        assert status in (200, 401, 403), f"قراءة مجهولة أعادت {status}"
        assert status != 200 or rows == [], "المستخدم المجهول رأى حسابات"

    def owner_reads_own_account(self) -> None:
        status, rows = self.call("GET", "/rest/v1/user_accounts?select=id,role", self.user(self.owner))
        assert status == 200 and isinstance(rows, list), f"قراءة المالك أعادت {status}"
        assert any(r.get("role") == "owner" for r in rows), "حساب المالك غير ظاهر له"

    def sync_write_and_last_write_wins(self) -> None:
        row_id = f"server-check-{uuid.uuid4()}"
        now = int(time.time() * 1000)
        owner = self.user(self.owner)
        self.cleanups.append(
            lambda: self.call("DELETE", f"/rest/v1/rooms?id=eq.{row_id}", self.admin())
        )
        base = {"id": row_id, "created_at": now, "updated_at": now, "name": "فحص الخادم", "capacity": 1}

        status, rows = self.upsert("rooms", owner, base)
        assert status in (200, 201) and rows, f"كتابة المالك أعادت {status}"
        first = rows[0]["synced_at"]
        assert isinstance(first, int) and first > 0, "synced_at لم يُختم"

        # «آخر تعديل يفوز»: تحديث أقدم يُتجاهل.
        status, _ = self.upsert("rooms", owner, {**base, "updated_at": now - 1000, "name": "قديم"})
        assert status in (200, 201, 204), f"التحديث القديم أعاد {status}"
        status, rows = self.call("GET", f"/rest/v1/rooms?id=eq.{row_id}&select=name", owner)
        assert rows and rows[0]["name"] == "فحص الخادم", "التحديث الأقدم غيّر الصف"

        status, rows = self.upsert("rooms", owner, {**base, "updated_at": now + 1000, "name": "جديد"})
        assert status in (200, 201) and rows and rows[0]["name"] == "جديد", "التحديث الأحدث لم يُطبَّق"
        assert rows[0]["synced_at"] > first, "synced_at لم يتقدم"

        status, rows = self.upsert(
            "rooms", owner, {**base, "updated_at": now + 2000, "deleted_at": now + 2000, "name": "جديد"}
        )
        assert status in (200, 201) and rows and rows[0]["deleted_at"], "الحذف الناعم لم يُحفظ"

    def provisioning_and_roles(self) -> None:
        owner = self.user(self.owner)
        body = lambda email, password, role: {"email": email, "password": password, "role": role}
        suffix = uuid.uuid4().hex[:12]
        email = f"server-check-{suffix}@school.local"
        password = randomness.token_urlsafe(18)
        changed = randomness.token_urlsafe(18)

        status, _ = self.call("POST", "/functions/v1/provision-account", self.anon(), body(email, password, "teacher"))
        assert status == 401, f"إنشاء حساب دون جلسة أعاد {status}"

        status, payload = self.call("POST", "/functions/v1/provision-account", owner, body(email, password, "teacher"))
        assert status == 200 and isinstance(payload, dict) and isinstance(payload.get("id"), str), (
            f"إنشاء حساب بالمالك أعاد {status} {sb.reason(payload)}"
        )
        self.teacher_id, self.teacher_email = payload["id"], email
        uid = self.teacher_id
        self.cleanups.append(lambda: self.call("DELETE", f"/rest/v1/user_accounts?id=eq.{uid}", self.admin()))
        self.cleanups.append(lambda: self.call("DELETE", f"/auth/v1/admin/users/{uid}", self.admin()))

        status, _ = self.call("POST", "/functions/v1/provision-account", owner, body(email, password, "teacher"))
        assert status == 409, f"بريد مكرر أعاد {status}"

        now = int(time.time() * 1000)
        status, _ = self.call(
            "POST",
            "/rest/v1/user_accounts",
            {**owner, "Prefer": "return=minimal"},
            {
                "id": uid, "created_at": now, "updated_at": now, "email": email, "role": "teacher",
                "entity_id": None, "display_name": "فحص الخادم", "must_change_password": False,
            },
        )
        assert status in (200, 201, 204), f"إضافة صف حساب الأستاذ أعادت {status}"

        token = self.sign_in(email, password)
        assert token, "دخول الأستاذ الجديد فشل"
        self.teacher_token = token
        teacher = self.user(token)

        status, _ = self.call("POST", "/functions/v1/provision-account", teacher, body("x" + email, password, "parent"))
        assert status == 403, f"الأستاذ أنشأ حساباً (الحالة {status})"
        status, _ = self.call("POST", "/functions/v1/reset-account-password", teacher, {"id": uid, "password": changed})
        assert status == 403, f"الأستاذ غيّر كلمة سر (الحالة {status})"

        status, payload = self.call("POST", "/functions/v1/reset-account-password", owner, {"id": uid, "password": changed})
        assert status == 200, f"إعادة كلمة السر بالمالك أعادت {status} {sb.reason(payload)}"
        assert self.sign_in(email, password) is None, "كلمة السر القديمة ما زالت تعمل"
        assert self.sign_in(email, changed), "كلمة السر الجديدة لا تعمل"

    def teacher_is_limited_by_rls(self) -> None:
        assert self.teacher_token, "لا جلسة أستاذ (فشل فحص الحسابات قبله)"
        teacher = self.user(self.teacher_token)
        status, rows = self.call("GET", "/rest/v1/payments?select=id", teacher)
        assert status in (401, 403) or (status == 200 and rows == []), f"الأستاذ قرأ المدفوعات ({status})"
        status, _ = self.upsert(
            "rooms", teacher,
            {"id": f"server-check-{uuid.uuid4()}", "created_at": 1, "updated_at": 1, "name": "ممنوع", "capacity": 1},
        )
        assert status in (401, 403), f"الأستاذ كتب في القاعات ({status})"

    def storage_policies(self) -> None:
        assert self.teacher_token, "لا جلسة أستاذ (فشل فحص الحسابات قبله)"
        owner, teacher = self.user(self.owner), self.user(self.teacher_token)
        name = f"server-check/{uuid.uuid4()}.txt"
        content = f"فحص الخادم {uuid.uuid4()}".encode()
        self.cleanups.append(
            lambda: raw("DELETE", f"{self.cfg.url}/storage/v1/object/files/{name}", self.admin())
        )

        status, body = raw(
            "POST", f"{self.cfg.url}/storage/v1/object/files/{name}",
            {**owner, "Content-Type": "text/plain"}, content,
        )
        assert status == 200, f"رفع المالك أعاد {status}"
        url = f"{self.cfg.url}/storage/v1/object/authenticated/files/{name}"
        status, body = raw("GET", url, owner)
        assert status == 200 and body == content, f"تنزيل المالك أعاد {status}"
        status, body = raw("GET", url, teacher)
        assert status == 200 and body == content, f"تنزيل الأستاذ أعاد {status}"
        status, body = raw("GET", url, self.anon())
        assert status in (400, 401, 403, 404) and body != content, f"التنزيل دون جلسة أعاد {status}"

        photo = f"{self.cfg.url}/storage/v1/object/photos/server-check/{uuid.uuid4()}.bin"
        self.cleanups.append(lambda: raw("DELETE", photo, self.admin()))
        status, _ = raw("POST", photo, {**teacher, "Content-Type": "application/octet-stream"}, b"x")
        assert status in (400, 401, 403), f"الأستاذ رفع صورة ({status})"
        # حدّ مخزن الصور 10 MiB (الترحيل 0006: صور الفواتير تحتاج دقة أعلى من الوجوه).
        status, _ = raw(
            "POST", photo, {**owner, "Content-Type": "application/octet-stream"}, b"\0" * (10 * 1024 * 1024 + 4096)
        )
        assert status in (400, 413), f"حدّ حجم الصور لم يُطبَّق ({status})"

    def assistant_live(self) -> Optional[str]:
        """طلب حقيقي إلى دالة المساعد بنموذج المدرسة (بلا بيانات تلاميذ، وطلب واحد لكل نشر)."""
        body = {
            "role": "owner",
            "messages": [{"role": "user", "content": "اكتب كلمة واحدة فقط: جاهز"}],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "my_children",
                        "description": "أبناء الحساب",
                        "parameters": {"type": "object", "properties": {}, "additionalProperties": False},
                    },
                }
            ],
        }
        for attempt in range(2):
            status, payload = self.call(
                "POST", "/functions/v1/assistant", self.user(self.owner), body, timeout=90
            )
            code = payload.get("error") if isinstance(payload, dict) else None
            if status == 503 and code == "assistant_not_configured" and attempt == 0:
                time.sleep(15)  # أسرار الدالة الجديدة تصل إلى العمليات بعد لحظات من ضبطها
                continue
            break
        if status == 503 and code == "assistant_not_configured":
            raise Skip("لا مفتاح نموذج في هذه المدرسة بعد (أو لم تصل الأسرار إلى الدالة)")
        if status in (429, 504):
            raise Skip(f"النموذج مشغول أو بطيء الآن ({status} {code})")
        assert status == 200 and isinstance(payload, dict), f"الدالة أعادت {status} {code or sb.reason(payload)}"
        assert payload.get("content") or payload.get("toolCalls"), "رد النموذج فارغ"
        model = payload.get("model")
        return model if isinstance(model, str) and model else None  # النموذج الذي أجاب فعلاً

    def housekeeping(self) -> None:
        """يزيل ما خلّفته اختبارات Dart السابقة (لا يملك المالك حذف الملفات)."""
        self.call("DELETE", "/rest/v1/rooms?id=like.srv-*", self.admin())
        for bucket in ("files", "photos"):
            status, listing = self.call(
                "POST", f"/storage/v1/object/list/{bucket}", self.admin(), {"prefix": "integration", "limit": 1000}
            )
            if status == 200 and isinstance(listing, list):
                for entry in listing:
                    name = entry.get("name") if isinstance(entry, dict) else None
                    if isinstance(name, str):
                        raw("DELETE", f"{self.cfg.url}/storage/v1/object/{bucket}/integration/{name}", self.admin())

    def run_all(self) -> None:
        self.housekeeping()
        self.check("anon-sees-nothing", self.anon_sees_nothing)
        self.check("owner-reads-own-account", self.owner_reads_own_account)
        self.check("sync-write-last-write-wins", self.sync_write_and_last_write_wins)
        self.check("provisioning-and-roles", self.provisioning_and_roles)
        self.check("teacher-limited-by-rls", self.teacher_is_limited_by_rls)
        self.check("storage-policies", self.storage_policies)
        self.check("assistant-live", self.assistant_live)


def main(argv: list[str], environ: Optional[dict[str, str]] = None) -> int:
    environ = dict(os.environ) if environ is None else environ
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    # مالك مؤقت أنشأته الخطوة السابقة في المسار (الأفضل: لا يتأثر بتغيير كلمة سر المالك
    # الحقيقي)، وإلا يُستعمل مالك المدرسة بهاتفه وكلمة سره الأولى.
    ci_email, ci_password = environ.get("CI_OWNER_EMAIL", ""), environ.get("CI_OWNER_PASSWORD", "")
    needed = ["SUPABASE_ACCESS_TOKEN", "SUPABASE_PROJECT_REF", "SUPABASE_URL", "SUPABASE_ANON_KEY"]
    if not (ci_email and ci_password):
        needed += ["OWNER_PHONE", "OWNER_INITIAL_PASSWORD"]
    missing = [n for n in needed if not environ.get(n)]
    if missing:
        print(f"::error title=server-check::{sb.escape('متغيرات ناقصة: ' + ', '.join(missing))}")
        return 1
    config = sb.Config.from_env(environ)
    try:
        secret = sb.Bootstrap(config).secret_key()
        probe = Suite(config, secret)
        token = probe.sign_in(ci_email or probe_email(config), ci_password or config.password)
        if token is None:
            if ci_email:
                print("::error title=server-check::فشل دخول مالك الفحوص المؤقت")
                return 1
            print("::notice title=server-check::تُخطّى الفحص: كلمة سر المالك غُيّرت منذ الإنشاء")
            return 0
        probe.owner = token
        try:
            probe.run_all()
        finally:
            probe.cleanup()
    except sb.ApiError as error:
        print(f"::error title=server-check::{sb.escape(str(error))}")
        return 1
    failed = [(n, d) for n, s, d in probe.results if s == "fail"]
    states = " ".join(f"{n}={s}" + (f"({d})" if s == "ok" and d else "") for n, s, d in probe.results)
    print(f"::notice title=server-check::{sb.escape(states)}")
    skipped = [(n, d) for n, s, d in probe.results if s == "skip"]
    if skipped:
        print(f"::notice title=server-check::{sb.escape('تخطّي: ' + '; '.join(f'{n}: {d}' for n, d in skipped))}")
    if failed:
        print(f"::error title=server-check::{sb.escape('; '.join(f'{n}: {d}' for n, d in failed))}")
        return 1
    return 0


def probe_email(config: sb.Config) -> str:
    return f"{config.phone}@{sb.EMAIL_DOMAIN}"


if __name__ == "__main__":
    sys.exit(main(sys.argv))
