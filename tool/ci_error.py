#!/usr/bin/env python3
"""يحوّل ذيل سجل فاشل إلى تعليق `::error` عام بعد إخفاء قيم الأسرار.

الاستعمال:
  MASK_ENV=NAME1,NAME2 python3 tool/ci_error.py <عنوان> <ملف السجل> [عدد الأسطر=30]

MASK_ENV أسماء متغيرات بيئة تُستبدل قيمها بـ*** من النص قبل نشره (المستودع عام
وتعليقات المسار تُقرأ علناً).
"""

from __future__ import annotations

import os
import sys


def sanitize(text: str, secrets: list[str]) -> str:
    # الأطول أولاً حتى لا يبقى جزء من سرّ يحوي سرّاً أقصر منه.
    for secret in sorted({s for s in secrets if len(s) >= 4}, key=len, reverse=True):
        text = text.replace(secret, "***")
    return text


def annotation(title: str, text: str, secrets: list[str], tail: int = 30, width: int = 300) -> str:
    lines = sanitize(text, secrets).splitlines()[-tail:]
    message = "\n".join(line[:width] for line in lines)
    message = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return f"::error title={title}::{message}"


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        print("الاستعمال: ci_error.py <عنوان> <ملف السجل> [عدد الأسطر]", file=sys.stderr)
        return 2
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    names = [n.strip() for n in os.environ.get("MASK_ENV", "").split(",") if n.strip()]
    secrets = [os.environ.get(n, "") for n in names]
    with open(argv[2], encoding="utf-8", errors="replace") as f:
        text = f.read()
    print(annotation(argv[1], text, secrets, int(argv[3]) if len(argv) == 4 else 30))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
