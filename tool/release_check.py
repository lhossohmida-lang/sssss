#!/usr/bin/env python3
"""يتحقق أن إصداراً منشوراً صالح لتحديث التطبيقات تلقائياً.

التطبيقات تقرأ ملفاتها من واجهة GitHub (`/releases`) وتتحقق من بصمة SHA-256 التي يعلنها GitHub لكل ملف
(`digest`)، ولا تقبل رابطاً خارج `https://github.com/<المستودع>/releases/download/`. فيفحص هذا السكربت بعد النشر أن
كل ملف متوقع موجود مرفوع وحجمه موجب وبصمته سليمة ورابطه من مستودعنا، وإلا فشل المسار فلا يصل أجهزةً إصدار لا يستطيع
تحديث نفسه (والبصمة قد تتأخر ثوانيَ بعد الرفع فتُعاد المحاولة).

الاستعمال: python3 tool/release_check.py <وسم الإصدار>
المدخلات من البيئة: GITHUB_REPOSITORY (المالك/المستودع)، وGITHUB_TOKEN (اختياري)، وGITHUB_API_URL (الافتراضي
https://api.github.com)، وRELEASE_CHECK_ATTEMPTS (الافتراضي 6) وRELEASE_CHECK_DELAY بالثواني (الافتراضي 10).
لا يُطبع الرمز أبداً.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from typing import Any, Callable, Optional

EXPECTED = (
    "school-admin.apk",
    "school-teacher.apk",
    "school-student.apk",
    "school-admin-setup.exe",
    "school-admin-windows.zip",
)
DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")


def fetch(url: str, token: str = "") -> tuple[int, Any]:
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "release-check"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, None
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        return 0, None


def problems(release: Any, repo: str, tag: str) -> list[str]:
    """أسباب عدم صلاحية الإصدار للتحديث التلقائي (فارغة إن سلم)."""
    if not isinstance(release, dict):
        return ["الإصدار غير موجود أو تعذّرت قراءته"]
    found: list[str] = []
    if release.get("draft"):
        found.append("الإصدار مسوّدة")
    assets = {a.get("name"): a for a in release.get("assets", []) if isinstance(a, dict)}
    prefix = f"https://github.com/{repo}/releases/download/{tag}/"
    for name in EXPECTED:
        asset = assets.get(name)
        if asset is None:
            found.append(f"{name}: غير موجود")
            continue
        if asset.get("state") != "uploaded":
            found.append(f"{name}: لم يكتمل رفعه")
        size = asset.get("size")
        if not isinstance(size, int) or size <= 0:
            found.append(f"{name}: حجمه غير صالح")
        if not DIGEST.match(str(asset.get("digest", ""))):
            found.append(f"{name}: بلا بصمة SHA-256 معلنة")
        if asset.get("browser_download_url") != prefix + name:
            found.append(f"{name}: رابط التنزيل ليس من {prefix}")
    return found


def main(
    argv: list[str],
    environ: Optional[dict[str, str]] = None,
    sleep: Callable[[float], None] = time.sleep,
) -> int:
    environ = dict(os.environ) if environ is None else environ
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) != 2 or not argv[1].strip():
        print("الاستعمال: release_check.py <وسم الإصدار>", file=sys.stderr)
        return 2
    tag = argv[1].strip()
    repo = environ.get("GITHUB_REPOSITORY", "")
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
        print("::error title=release-check::GITHUB_REPOSITORY غير مضبوط")
        return 2
    api = environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
    token = environ.get("GITHUB_TOKEN", "")
    attempts = max(1, int(environ.get("RELEASE_CHECK_ATTEMPTS", "6")))
    delay = float(environ.get("RELEASE_CHECK_DELAY", "10"))
    found: list[str] = []
    release: Any = None
    for attempt in range(1, attempts + 1):
        status, release = fetch(f"{api}/repos/{repo}/releases/tags/{tag}", token)
        found = [f"الواجهة ردّت {status}"] if status != 200 else problems(release, repo, tag)
        if not found:
            break
        if attempt < attempts:
            sleep(delay)
    if found:
        message = " | ".join(found).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::error title=release-check::{message}")
        return 1
    for asset in release["assets"]:
        if asset["name"] in EXPECTED:
            print(f"{asset['name']} {asset['size']} bytes {asset['digest'][:19]}…")
    print(f"::notice title=release-check::ok tag={tag} assets={len(EXPECTED)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
