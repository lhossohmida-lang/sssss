#!/usr/bin/env python3
"""يسجّل مدرسة في دليل المدارس ويصدّر مفتاح تسجيلها لخطوات مسار النشر التالية.

الاستعمال:
  python3 tool/directory_register.py register   # يسجّل مدرسة (مسار supabase-deploy)
  python3 tool/directory_register.py verify     # يفحص الدليل بمفتاحه العام (مسار directory-deploy)

المدخلات من البيئة:
  DIRECTORY_URL (متغيّر عام) وDIRECTORY_SERVICE_KEY (سرّ المطوّر: مفتاح الدليل السرّي). دون
  DIRECTORY_URL لا يحدث شيء (مدرسة بلا دليل).
  SCHOOL_SLUG (اسم Environment المدرسة) وSCHOOL_NAME (اسمها الظاهر، وإلا الاسم المختصر) وSCHOOL_LISTED
  (true|false، الافتراضي true)، وSUPABASE_URL وSUPABASE_ANON_KEY (خادم المدرسة ومفتاحه العام)
  وOWNER_PHONE (رقم المالك ليعرف تطبيق الإدارة مدرسته منه).

يولّد مفتاح تسجيل عشوائياً لهذه المدرسة: يحفظ الدليل بصمته، ويُصدَّر المفتاح نفسه إلى GITHUB_ENV باسم
DIRECTORY_REGISTER_KEY (بعد إخفائه من السجل) ليضعه المسار في أسرار دوال المدرسة؛ بذلك تسجّل دالة
إنشاء الحسابات أرقام العمال الجدد في الدليل. لا يُطبع أي سرّ؛ الرسائل فيها الأسباب فقط.
"""

from __future__ import annotations

import os
import re
import secrets as randomness
import sys
from typing import Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import supabase_bootstrap as sb  # noqa: E402

SLUG = re.compile(r"^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$")
TITLE = "directory-register"


def admin_headers(key: str) -> dict[str, str]:
    """المفتاح الجديد ليس JWT فيُرسل في apikey وحده؛ والقديم JWT يُرسل في الرأسين."""
    headers = {"apikey": key}
    if sb.jwt_like(key):
        headers["Authorization"] = f"Bearer {key}"
    return headers


def register(environ: dict[str, str]) -> tuple[Optional[str], list[tuple[str, str]]]:
    """يسجّل المدرسة. يعيد (مفتاح التسجيل أو None، رسائل (مستوى، نص)) ويرمي ApiError."""
    directory_url = environ.get("DIRECTORY_URL", "").strip().rstrip("/")
    if not directory_url:
        return None, [("notice", "لا دليل مدارس مضبوط (DIRECTORY_URL): لم تُسجَّل المدرسة")]

    service_key = environ.get("DIRECTORY_SERVICE_KEY", "")
    if not service_key:
        raise sb.ApiError("DIRECTORY_URL مضبوط لكن DIRECTORY_SERVICE_KEY غير موجود في أسرار المستودع")
    if service_key.startswith("sb_publishable_"):
        raise sb.ApiError("DIRECTORY_SERVICE_KEY مفتاح عام؛ المطلوب المفتاح السرّي (sb_secret_…) للدليل")

    slug = environ.get("SCHOOL_SLUG", "")
    if not SLUG.fullmatch(slug):
        raise sb.ApiError(
            "اسم Environment المدرسة يجب أن يكون أحرفاً لاتينية صغيرة وأرقاماً وشرطة (حتى 40 حرفاً) "
            "ليُسجَّل في الدليل"
        )
    school_url = environ.get("SUPABASE_URL", "").strip().rstrip("/")
    school_key = environ.get("SUPABASE_ANON_KEY", "")
    if not school_url or not school_key:
        raise sb.ApiError("SUPABASE_URL وSUPABASE_ANON_KEY مطلوبان لتسجيل المدرسة في الدليل")

    notes: list[tuple[str, str]] = []
    name = environ.get("SCHOOL_NAME", "").strip()
    if not name:
        name = slug
        notes.append(
            (
                "warning",
                "SCHOOL_NAME غير مضبوط في Environment المدرسة: ظهرت باسمها المختصر في قائمة المدارس",
            )
        )
    listed = environ.get("SCHOOL_LISTED", "true").strip().lower() != "false"
    owner_phone = environ.get("OWNER_PHONE", "").strip() or None

    register_key = randomness.token_hex(32)
    status, payload = sb.call(
        "POST",
        f"{directory_url}/rest/v1/rpc/register_school",
        admin_headers(service_key),
        {
            "p_slug": slug,
            "p_name": name,
            "p_url": school_url,
            "p_key": school_key,
            "p_listed": listed,
            "p_register_key": register_key,
            "p_owner_phone": owner_phone,
        },
    )
    if status in (401, 403):
        raise sb.ApiError(f"الدليل رفض المفتاح السرّي ({status}): تحقق من DIRECTORY_SERVICE_KEY", status)
    if status == 404:
        raise sb.ApiError("دالة register_school غير موجودة في الدليل: شغّل مسار directory-deploy أولاً", status)
    if status not in (200, 201):
        raise sb.ApiError(f"تعذّر تسجيل المدرسة في الدليل ({status}) {sb.reason(payload)}", status)

    visibility = "معلنة" if listed else "غير معلنة"
    notes.append(("notice", f"سُجّلت المدرسة {slug} في الدليل ({visibility}) وأُصدر مفتاح تسجيل جديد لها"))
    return register_key, notes


def verify(environ: dict[str, str]) -> list[str]:
    """يفحص الدليل بمفتاحه العام كما تراه التطبيقات: القراءة تعمل، والتسجيل والجداول مغلقة."""
    url = environ.get("DIRECTORY_URL", "").strip().rstrip("/")
    anon = environ.get("DIRECTORY_ANON_KEY", "")
    if not url or not anon:
        raise sb.ApiError("DIRECTORY_URL وDIRECTORY_ANON_KEY مطلوبان لفحص الدليل")
    if anon.startswith("sb_secret_"):
        raise sb.ApiError("DIRECTORY_ANON_KEY مفتاح سرّي؛ المطلوب المفتاح العام (sb_publishable_…)")
    headers = admin_headers(anon)

    def rpc(name: str, body: dict) -> tuple[int, object]:
        return sb.call("POST", f"{url}/rest/v1/rpc/{name}", headers, body)

    status, payload = rpc("list_schools", {})
    if status != 200 or not isinstance(payload, list):
        raise sb.ApiError(
            f"دالة list_schools لا تعمل ({status}) {sb.reason(payload)}: شغّل directory-deploy", status
        )
    schools = len(payload)
    status, payload = rpc("resolve_school", {"p_phone": "0000000000"})
    if status != 200 or payload != []:
        raise sb.ApiError(f"دالة resolve_school لا تعمل كما يجب ({status}) {sb.reason(payload)}", status)
    status, _ = rpc(
        "register_school",
        {
            "p_slug": "verify-probe",
            "p_name": "فحص",
            "p_url": "https://aaaaaaaaaaaaaaaaaaaa.supabase.co",
            "p_key": "sb_publishable_verify-probe-key",
            "p_listed": False,
            "p_register_key": "x" * 40,
            "p_owner_phone": None,
        },
    )
    if status not in (401, 403, 404):
        raise sb.ApiError(f"تسجيل المدارس مفتوح بالمفتاح العام ({status})! راجع صلاحيات register_school", status)
    status, _ = sb.call("GET", f"{url}/rest/v1/schools?select=id&limit=1", headers)
    if status == 200:
        raise sb.ApiError("جدول schools مقروء بالمفتاح العام! يجب أن تبقى الجداول مغلقة", status)
    return [f"الدليل سليم: القائمة تعمل ({schools} مدرسة معلنة) والبحث يعمل والتسجيل والجداول مغلقة"]


def main(argv: list[str], environ: Optional[dict[str, str]] = None) -> int:
    environ = dict(os.environ) if environ is None else environ
    if len(argv) != 2 or argv[1] not in ("register", "verify"):
        print("الاستعمال: directory_register.py register|verify", file=sys.stderr)
        return 2
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if argv[1] == "verify":
        try:
            lines = verify(environ)
        except sb.ApiError as error:
            print(f"::error title=directory-verify::{sb.escape(str(error))}")
            return 1
        for line in lines:
            print(f"::notice title=directory-verify::{sb.escape(line)}")
        return 0
    try:
        key, notes = register(environ)
    except sb.ApiError as error:
        print(f"::error title={TITLE}::{sb.escape(str(error))}")
        return 1
    if key:
        print(f"::add-mask::{key}")
        path = environ.get("GITHUB_ENV")
        if path:
            with open(path, "a", encoding="utf-8") as f:
                f.write(f"DIRECTORY_REGISTER_KEY={key}\n")
    for level, text in notes:
        print(f"::{level} title={TITLE}::{sb.escape(text)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
