#!/usr/bin/env python3
"""يولّد ملف google-services.json اصطناعياً (قيم وهمية لا سرّية) لفحص بناء أندرويد في CI.

الغرض: التأكد أن إضافة Gradle الخاصة بـ Google تتوافق مع إصدارَي Android Gradle Plugin وFlutter
المستعملَين، دون انتظار أول بناء إصدار حقيقي بعد لصق الملف الحقيقي في الأسرار. الملف الناتج
لا يصلح للاتصال بأي مشروع Firebase، ولا يُحفظ في المستودع (.gitignore يحجبه).

الاستعمال:
  python3 tool/fake_google_services.py <ملف الإخراج> <اسم حزمة> [<اسم حزمة> ...]
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import sys

PROJECT_ID = "synthetic-ci-project"
PROJECT_NUMBER = "000000000000"


def build(packages: list[str]) -> dict:
    """هيئة الملف الحقيقي نفسها: مشروع واحد وعميل لكل تطبيق أندرويد."""
    clients = []
    for package in packages:
        # معرّف التطبيق الاصطناعي مشتق من اسم الحزمة، ومفتاح الواجهة نص ظاهر الزيف (لا يشبه
        # صيغة مفاتيح Google فلا ينبّه فاحصات الأسرار).
        digest = hashlib.sha1(package.encode()).hexdigest()[:20]
        clients.append(
            {
                "client_info": {
                    "mobilesdk_app_id": f"1:{PROJECT_NUMBER}:android:{digest}",
                    "android_client_info": {"package_name": package},
                },
                "oauth_client": [],
                "api_key": [{"current_key": "synthetic-ci-key-not-a-secret"}],
                "services": {"appinvite_service": {"other_platform_oauth_client": []}},
            }
        )
    return {
        "project_info": {
            "project_number": PROJECT_NUMBER,
            "project_id": PROJECT_ID,
            "storage_bucket": f"{PROJECT_ID}.appspot.com",
        },
        "client": clients,
        "configuration_version": "1",
    }


def main(argv: list[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8")
    if len(argv) < 3:
        print("الاستعمال: fake_google_services.py <ملف الإخراج> <اسم حزمة> [...]", file=sys.stderr)
        return 2
    out = pathlib.Path(argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(build(argv[2:]), indent=2) + "\n", encoding="utf-8")
    print(f"كُتب ملف Firebase اصطناعي لـ {len(argv) - 2} تطبيقاً في {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
