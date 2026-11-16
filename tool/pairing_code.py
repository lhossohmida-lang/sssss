#!/usr/bin/env python3
"""يولّد رمز ربط مدرسة (`SCH1.…`) ويفكّه.

الرمز يضمّ عنوان خادم المدرسة ومفتاحه العام واسمها، ويُلصق في تطبيقات المدرسة (الإدارة
والأستاذ والتلميذ) أو يُمسح بـQR عند أول تشغيل، فتكون النسخة واحدة لكل المدارس.

المفتاح العام (`sb_publishable_…`) مصمَّم ليُضمَّن في التطبيقات، لكن رمز مدرسة عميل لا يُنشر
علناً: شغّل هذا السكربت على حاسوبك لا في مسار GitHub عام (سجلاته علنية). وهو يرفض أي مفتاح
سرّي (`sb_secret_…` أو `service_role`) ولو مُرِّر بالخطأ.

صيغة الرمز مطابقة لما في `packages/core/lib/src/app/school_pairing.dart`، ويثبّتها متجه
اختبار مشترك في اختبار كل من الطرفين.

الاستعمال:
  python3 tool/pairing_code.py --ref <project-ref> --name "مدرسة النور"
      (المفتاح العام يُقرأ من Supabase؛ يلزم SUPABASE_ACCESS_TOKEN في البيئة)
  python3 tool/pairing_code.py --url https://xxxx.supabase.co --key sb_publishable_… --name "…"
  python3 tool/pairing_code.py --decode SCH1.…       # يعرض العنوان والاسم ويخفي المفتاح
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.parse
from typing import Any, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import supabase_bootstrap as sb  # noqa: E402

PREFIX = "SCH1."
VERSION = 1
MAX_NAME = 80


class PairingError(ValueError):
    """رمز أو مدخل مرفوض؛ الرسالة بالعربية وتُعرض كما هي."""


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _unb64(text: str) -> bytes:
    try:
        return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))
    except (ValueError, TypeError):
        raise PairingError("هذا ليس رمز ربط صحيحاً") from None


def normalize_url(raw: Any) -> str:
    """https فقط، بلا مسار ولا استعلام ولا بيانات دخول؛ أحرف صغيرة دون شرطة أخيرة."""
    if not isinstance(raw, str):
        raise PairingError("عنوان الخادم غير صالح")
    try:
        parsed = urllib.parse.urlsplit(raw.strip())
        port = parsed.port
    except ValueError:
        raise PairingError("عنوان الخادم غير صالح") from None
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
        or parsed.path not in ("", "/")
    ):
        raise PairingError("عنوان الخادم يجب أن يكون https دون مسار أو استعلام")
    suffix = f":{port}" if port not in (None, 443) else ""
    return f"https://{parsed.hostname.lower()}{suffix}"


def check_key(raw: Any) -> str:
    """مفتاح عام فقط: يُرفض السرّي (`sb_secret_…` أو JWT بدور غير anon) والناقص."""
    if not isinstance(raw, str):
        raise PairingError("مفتاح الاتصال غير صالح")
    key = raw.strip()
    if len(key) < 20 or len(key) > 600 or re.search(r"\s", key):
        raise PairingError("مفتاح الاتصال غير صالح")
    if key.startswith("sb_secret_"):
        raise PairingError("هذا مفتاح سرّي لا عام: لا يوضع في الرمز أبداً")
    parts = key.split(".")
    if len(parts) == 3:
        try:
            claims = json.loads(_unb64(parts[1]))
        except (PairingError, ValueError):
            raise PairingError("مفتاح الاتصال غير صالح") from None
        if isinstance(claims, dict) and claims.get("role") != "anon":
            raise PairingError("هذا مفتاح سرّي لا عام: لا يوضع في الرمز أبداً")
    return key


def encode(url: str, key: str, name: str = "") -> str:
    name = name.strip()
    if len(name) > MAX_NAME:
        raise PairingError(f"اسم المدرسة أطول من {MAX_NAME} حرفاً")
    payload: dict[str, Any] = {"v": VERSION, "u": normalize_url(url), "k": check_key(key)}
    if name:
        payload["n"] = name
    raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return PREFIX + _b64(raw)


def decode(code: str) -> dict[str, str]:
    cleaned = re.sub(r"\s+", "", code)
    if not cleaned:
        raise PairingError("لا رمز")
    if not cleaned.lower().startswith(PREFIX.lower()):
        raise PairingError("هذا ليس رمز ربط صحيحاً")
    try:
        payload = json.loads(_unb64(cleaned[len(PREFIX) :]))
    except (ValueError, UnicodeDecodeError):
        raise PairingError("هذا ليس رمز ربط صحيحاً") from None
    if not isinstance(payload, dict) or not isinstance(payload.get("v"), int):
        raise PairingError("هذا ليس رمز ربط صحيحاً")
    if payload["v"] != VERSION:
        raise PairingError("هذا الرمز من إصدار أحدث")
    name = payload.get("n")
    name = name.strip() if isinstance(name, str) else ""
    if len(name) > MAX_NAME:
        raise PairingError("هذا ليس رمز ربط صحيحاً")
    return {"url": normalize_url(payload.get("u")), "key": check_key(payload.get("k")), "name": name}


def project_public_key(ref: str, token: str, api_base: str = "https://api.supabase.com") -> str:
    """المفتاح العام للمشروع من Management API (الجديد `publishable` وإلا `anon` القديم)."""
    status, payload = sb.call(
        "GET", f"{api_base.rstrip('/')}/v1/projects/{ref}/api-keys", {"Authorization": f"Bearer {token}"}
    )
    if status in (401, 403):
        raise PairingError("رمز Supabase مرفوض أو لا يملك صلاحية قراءة مفاتيح المشروع")
    if status == 404:
        raise PairingError("المشروع غير موجود أو لا يصل إليه الرمز")
    if status != 200 or not isinstance(payload, list):
        raise PairingError(f"تعذّرت قراءة مفاتيح المشروع ({status})")
    keys = [k for k in payload if isinstance(k, dict) and isinstance(k.get("api_key"), str)]
    publishable = [k for k in keys if k.get("type") == "publishable"]
    legacy = [k for k in keys if k.get("name") == "anon"]
    chosen = (sorted(publishable, key=lambda k: k.get("name") != "default") or legacy or [None])[0]
    if chosen is None:
        raise PairingError("لا يوجد مفتاح عام (Publishable key) في المشروع")
    return chosen["api_key"]


def main(argv: list[str], environ: Optional[dict[str, str]] = None) -> int:
    environ = dict(os.environ) if environ is None else environ
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="رمز ربط مدرسة بتطبيقاتها")
    parser.add_argument("--ref", help="معرّف مشروع Supabase (يُقرأ المفتاح العام بـSUPABASE_ACCESS_TOKEN)")
    parser.add_argument("--url", help="عنوان الخادم https://…supabase.co")
    parser.add_argument("--key", help="المفتاح العام")
    parser.add_argument("--name", default="", help="اسم المدرسة للعرض")
    parser.add_argument("--decode", metavar="CODE", help="يفكّ رمزاً ويعرض عنوانه واسمه")
    args = parser.parse_args(argv[1:])
    try:
        if args.decode:
            info = decode(args.decode)
            print(f"url={info['url']}")
            print(f"name={info['name']}")
            kind = "publishable" if info["key"].startswith("sb_publishable_") else "legacy-anon"
            print(f"key={kind}")  # المفتاح نفسه لا يُعرض
            return 0
        if args.ref:
            token = environ.get("SUPABASE_ACCESS_TOKEN", "")
            if not token:
                raise PairingError("ضع رمز Supabase الشخصي في المتغير SUPABASE_ACCESS_TOKEN")
            if not re.fullmatch(r"[a-z0-9]{20}", args.ref):
                raise PairingError("معرّف المشروع عشرون حرفاً وأرقاماً صغيرة")
            api_base = environ.get("SUPABASE_API_BASE", "https://api.supabase.com")
            key = project_public_key(args.ref, token, api_base)
            url = args.url or f"https://{args.ref}.supabase.co"
        elif args.url and args.key:
            key, url = args.key, args.url
        else:
            raise PairingError("حدّد --ref أو (--url و--key) أو --decode")
        print(encode(url, key, args.name))
        return 0
    except (PairingError, sb.ApiError) as error:
        print(f"خطأ: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
