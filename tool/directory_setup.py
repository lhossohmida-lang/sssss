#!/usr/bin/env python3
"""ينشئ دليل المدارس ويهيّئه آلياً برمز Supabase الشخصي، ويحلّ عنوانه ومفتاحه العام للبناء.

الاستعمال:
  python3 tool/directory_setup.py setup    # (مسار directory-deploy) ينشئ مشروع `directory` إن لم يوجد، ويطبّق
                                           # ترحيلاته، ويفحصه بمفتاحه العام، ويطبع العنوان والمفتاح (عامّان)
  python3 tool/directory_setup.py public   # (مسار build) يصدّر DIRECTORY_URL وDIRECTORY_KEY إلى GITHUB_ENV

setup يعمل داخل Environment مدرسة فيه SUPABASE_ACCESS_TOKEN (رمز المطوّر الشخصي، يصل إلى كل مشاريع حسابه) وSUPABASE_PROJECT_REF
(مشروع تلك المدرسة، ومنه تُؤخذ المنظمة والمنطقة ليكون الدليل في المنظمة نفسها وبجوارها). لا يلزم حفظ أي قيمة جديدة في GitHub:
كلمة سر قاعدة الدليل تُولَّد عشوائياً ولا تُخزَّن (الترحيلات تمرّ بـManagement API لا بالقاعدة مباشرة)، ومفتاحاه يُجلبان بالرمز
متى لزما. بعد نجاحه يضع المطوّر الناتج العام (`directory-public`) في `directory/public.json`، فيضمّنه `build` في التطبيقات العامة
(بلا رمز ربط)، وتسجّل مسارات supabase-deploy كل مدرسة فيه.

لا يُطبع أي سرّ؛ الرسائل فيها الأسباب والقيم العامة فقط.
"""

from __future__ import annotations

import json
import os
import re
import secrets as randomness
import sys
import time
from typing import Any, Callable, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import directory_register as dr  # noqa: E402
import supabase_bootstrap as sb  # noqa: E402

NAME = "directory"
TITLE = "directory-setup"
MIGRATIONS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "directory", "supabase", "migrations")

# مناطق Supabase المحددة المقبولة عند الإنشاء (الباقي يُختار له التجميع الأوروبي).
REGIONS = {
    "us-east-1", "us-east-2", "us-west-1", "us-west-2", "ap-east-1", "ap-southeast-1", "ap-northeast-1",
    "ap-northeast-2", "ap-southeast-2", "eu-west-1", "eu-west-2", "eu-west-3", "eu-north-1", "eu-central-1",
    "eu-central-2", "ca-central-1", "ap-south-1", "sa-east-1",
}

FAILED = {"INIT_FAILED", "REMOVED", "RESTORE_FAILED", "PAUSE_FAILED", "GOING_DOWN"}
PUBLIC_PREFIX = "directory-public: "


def project_url(ref: str) -> str:
    return f"https://{ref}.supabase.co"


class Management:
    """Management API برمز الشخصي: قراءة المشاريع وإنشاؤها وتشغيل SQL وجلب المفاتيح."""

    def __init__(self, config: "sb.Config"):
        self.base = config.api_base
        self.headers = {"Authorization": f"Bearer {config.token}"}

    def request(self, method: str, path: str, body: Any = None, timeout: float = 60) -> tuple[int, Any]:
        status, payload = sb.call(method, f"{self.base}{path}", self.headers, body, timeout=timeout)
        if status == 401:
            raise sb.ApiError("رمز Supabase مرفوض (خاطئ أو منتهٍ)", status)
        return status, payload

    def project(self, ref: str) -> dict[str, Any]:
        status, payload = self.request("GET", f"/v1/projects/{ref}")
        if status == 403:
            raise sb.ApiError("رمز Supabase لا يملك صلاحية قراءة المشروع", status)
        if status == 404:
            raise sb.ApiError("المشروع غير موجود أو لا يصل إليه الرمز: تحقق من SUPABASE_PROJECT_REF", status)
        if status != 200 or not isinstance(payload, dict):
            raise sb.ApiError(f"تعذّرت قراءة المشروع ({status}) {sb.reason(payload)}", status)
        return payload

    def find(self, name: str) -> Optional[dict[str, Any]]:
        status, payload = self.request("GET", "/v1/projects")
        if status != 200 or not isinstance(payload, list):
            raise sb.ApiError(f"تعذّرت قراءة قائمة المشاريع ({status}) {sb.reason(payload)}", status)
        found = [p for p in payload if isinstance(p, dict) and p.get("name") == name]
        return found[0] if found else None

    def create(self, name: str, organization: str, region: str) -> dict[str, Any]:
        selection = (
            {"type": "specific", "code": region} if region in REGIONS else {"type": "smartGroup", "code": "emea"}
        )
        status, payload = self.request(
            "POST",
            "/v1/projects",
            {
                "name": name,
                "organization_slug": organization,
                # كلمة سر قاعدة عشوائية لا تُخزَّن ولا تُطبع؛ الترحيلات تمرّ بـManagement API فلا حاجة إليها.
                "db_pass": randomness.token_urlsafe(24),
                "region_selection": selection,
            },
            timeout=120,
        )
        if status not in (200, 201) or not isinstance(payload, dict) or not payload.get("ref"):
            raise sb.ApiError(
                f"تعذّر إنشاء مشروع الدليل ({status}) {sb.reason(payload)}. الخطة المجانية تسمح بمشروعين "
                "نشطين فقط: أنشئ مشروعاً باسم directory من لوحة Supabase يدوياً أو أوقف مشروعاً غير مستعمل",
                status,
            )
        return payload

    def restore(self, ref: str) -> None:
        status, payload = self.request("POST", f"/v1/projects/{ref}/restore", {})
        if status not in (200, 201, 202):
            raise sb.ApiError(
                f"مشروع الدليل متوقف ({status}) {sb.reason(payload)}: استأنفه من لوحة Supabase (Restore project)",
                status,
            )

    def wait_ready(
        self, ref: str, sleep: Callable[[float], None], poll: float, timeout: float
    ) -> list[tuple[str, str]]:
        notes: list[tuple[str, str]] = []
        restored = False
        waited = 0.0
        while True:
            state = str(self.project(ref).get("status", ""))
            if state == "ACTIVE_HEALTHY":
                return notes
            if state in FAILED:
                raise sb.ApiError(f"تعذّر تجهيز مشروع الدليل (الحالة {state}): راجعه في لوحة Supabase")
            if state == "INACTIVE" and not restored:
                self.restore(ref)
                restored = True
                notes.append(("notice", "كان مشروع الدليل متوقفاً (Paused) فطُلب استئنافه"))
            if waited >= timeout:
                raise sb.ApiError(f"انتهت مهلة تجهيز مشروع الدليل (الحالة {state}): أعد تشغيل المسار بعد دقائق")
            sleep(poll)
            waited += poll

    def run_sql(self, ref: str, sql: str, sleep: Callable[[float], None], poll: float, attempts: int = 12) -> None:
        """ينفّذ SQL؛ المشروع الجديد قد يرفض أول استعلام لحظات بعد اكتمال تجهيزه فتُعاد المحاولة."""
        last = ""
        for _ in range(attempts):
            try:
                status, payload = self.request("POST", f"/v1/projects/{ref}/database/query", {"query": sql}, timeout=120)
            except sb.ApiError as error:
                if error.status == 401:
                    raise
                status, payload = 0, str(error)
            if status in (200, 201):
                return
            last = f"({status}) {sb.reason(payload)}"
            if 400 <= status < 500 and status not in (408, 409, 425, 429):
                raise sb.ApiError(f"رفض Supabase ترحيل الدليل {last}", status)
            sleep(poll)
        raise sb.ApiError(f"تعذّر تطبيق ترحيل الدليل بعد {attempts} محاولة {last}")

    def publishable_key(self, ref: str) -> str:
        status, payload = self.request("GET", f"/v1/projects/{ref}/api-keys")
        if status == 403:
            raise sb.ApiError("رمز Supabase لا يملك صلاحية قراءة مفاتيح المشروع", status)
        if status != 200 or not isinstance(payload, list):
            raise sb.ApiError(f"تعذّرت قراءة مفاتيح الدليل ({status}) {sb.reason(payload)}", status)
        keys = [
            k
            for k in payload
            if isinstance(k, dict)
            and k.get("type") == "publishable"
            and isinstance(k.get("api_key"), str)
            and k["api_key"].startswith("sb_publishable_")
        ]
        keys.sort(key=lambda k: k.get("name") != "default")
        if not keys:
            raise sb.ApiError("لا مفتاح عام (Publishable key) في مشروع الدليل: أنشئه من Project Settings ← API Keys")
        return keys[0]["api_key"]


def migration_files(path: str = MIGRATIONS) -> list[tuple[str, str]]:
    names = sorted(n for n in os.listdir(path) if n.endswith(".sql"))
    if not names:
        raise sb.ApiError("لا ترحيلات للدليل في directory/supabase/migrations")
    out = []
    for name in names:
        with open(os.path.join(path, name), encoding="utf-8") as f:
            out.append((name, f.read()))
    return out


def setup(
    environ: dict[str, str],
    *,
    sleep: Callable[[float], None] = time.sleep,
    poll: float = 10.0,
    timeout: float = 900.0,
    migrations: Optional[list[tuple[str, str]]] = None,
    url_for: Optional[Callable[[str], str]] = None,
) -> tuple[list[tuple[str, str]], dict[str, str]]:
    """ينشئ الدليل إن لم يوجد، ويهيّئه، ويفحصه. يعيد (رسائل، الناتج العام {url, anon_key})."""
    config = sb.Config.from_env(environ)
    missing = [n for n, v in (("SUPABASE_ACCESS_TOKEN", config.token), ("SUPABASE_PROJECT_REF", config.ref)) if not v]
    if missing:
        raise sb.ApiError("متغيرات ناقصة في Environment المدرسة: " + ", ".join(missing))
    api = Management(config)
    notes: list[tuple[str, str]] = []

    existing = api.find(NAME)
    if existing is not None:
        ref = str(existing.get("ref", ""))
        notes.append(("notice", f"مشروع الدليل موجود ({ref}): يُهيَّأ من جديد بأمان"))
    else:
        school = api.project(config.ref)
        organization = str(school.get("organization_slug") or school.get("organization_id") or "")
        if not organization:
            raise sb.ApiError("تعذّر معرفة منظمة مشروع المدرسة لإنشاء الدليل فيها")
        created = api.create(NAME, organization, str(school.get("region", "")))
        ref = str(created["ref"])
        notes.append(("notice", f"أُنشئ مشروع الدليل ({ref}) في منظمة المدرسة نفسها"))
    if not re.fullmatch(r"[a-z]{20}", ref):
        raise sb.ApiError("معرّف مشروع الدليل غير صالح")

    notes += api.wait_ready(ref, sleep, poll, timeout)

    files = migrations if migrations is not None else migration_files()
    for name, sql in files:
        api.run_sql(ref, sql, sleep, poll)
        notes.append(("notice", f"طُبّق ترحيل الدليل {name}"))

    url = (url_for or project_url)(ref)
    key = api.publishable_key(ref)
    # فحص الدليل كما تراه التطبيقات (بمفتاحه العام): القراءة تعمل والتسجيل والجداول مغلقة.
    # قد يتأخر وصول الواجهة بعد الإنشاء لحظات، فتُعاد المحاولة.
    last: Optional[sb.ApiError] = None
    for _ in range(12):
        try:
            for line in dr.verify({"DIRECTORY_URL": url, "DIRECTORY_ANON_KEY": key}):
                notes.append(("notice", line))
            last = None
            break
        except sb.ApiError as error:
            last = error
            sleep(poll)
    if last is not None:
        raise last
    public = {"url": url, "anon_key": key}
    notes.append(("notice", PUBLIC_PREFIX + json.dumps(public, ensure_ascii=False)))
    return notes, public


def export_public(environ: dict[str, str]) -> list[str]:
    """يصدّر DIRECTORY_URL وDIRECTORY_KEY للخطوات التالية (متغيرات المستودع أولاً ثم الملف)."""
    url, key = dr.public_config(environ)
    path = environ.get("GITHUB_ENV")
    if url and key:
        if path:
            with open(path, "a", encoding="utf-8") as f:
                f.write(f"DIRECTORY_URL={url}\nDIRECTORY_KEY={key}\n")
        return [f"دليل المدارس: {url}"]
    return ["لا دليل مدارس مضبوط: يبقى التطبيق على رمز الربط"]


def main(argv: list[str], environ: Optional[dict[str, str]] = None) -> int:
    environ = dict(os.environ) if environ is None else environ
    if len(argv) != 2 or argv[1] not in ("setup", "public"):
        print("الاستعمال: directory_setup.py setup|public", file=sys.stderr)
        return 2
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if argv[1] == "public":
        for line in export_public(environ):
            print(f"::notice title=directory-public::{sb.escape(line)}")
        return 0
    # مفتاحان للاختبارات (يبقى الافتراضي في الإنتاج): فاصل الانتظار بين قراءتين، وقالب عنوان المشروع.
    poll = float(environ.get("DIRECTORY_SETUP_POLL", "10"))
    template = environ.get("DIRECTORY_PROJECT_URL_TEMPLATE", "https://{ref}.supabase.co")
    try:
        notes, _ = setup(environ, poll=poll, url_for=lambda ref: template.format(ref=ref))
    except sb.ApiError as error:
        print(f"::error title={TITLE}::{sb.escape(str(error))}")
        return 1
    for level, text in notes:
        # الناتج العام (عنوان الدليل ومفتاحه العام) بعنوانه المستقل ليسهل نسخه إلى directory/public.json.
        if text.startswith(PUBLIC_PREFIX):
            print(f"::notice title=directory-public::{sb.escape(text[len(PUBLIC_PREFIX):])}")
        else:
            print(f"::{level} title={TITLE}::{sb.escape(text)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
