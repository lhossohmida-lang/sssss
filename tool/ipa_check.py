#!/usr/bin/env python3
"""يفحص ملف .ipa غير موقَّع بُني في مسار ios قبل رفعه، فلا يُنشر ملف ناقص لا يُثبَّت على iPhone.

الملف حزمة zip فيها `Payload/Runner.app`؛ يُتحقق أن معرّف الحزمة هو المتوقع، وأن البرنامج ومكتبتي Flutter
(المحرك وكود التطبيق المترجم AOT) موجودة وثنائيات Mach-O لـarm64، وأن أقل إصدار iOS معلن، وأن نصوص أذونات
الكاميرا والصور موجودة (يرفض iOS طلب الإذن دونها فينهار التطبيق).

الاستعمال: python3 tool/ipa_check.py <ملف ipa> <معرّف الحزمة المتوقع>
يطبع `::notice title=ipa-<الاسم>::…` عند السلامة، و`::error title=ipa-check::…` بالأسباب عند الفشل.
"""

from __future__ import annotations

import os
import plistlib
import sys
import zipfile
from typing import Any

# رأس Mach-O 64 بت (arm64) بترتيب البايتات الصغير، ورأس الثنائي الشامل (fat) إن جُمعت معماريات.
MACHO_MAGICS = (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")
REQUIRED_USAGE = ("NSCameraUsageDescription", "NSPhotoLibraryUsageDescription")


def app_root(names: list[str]) -> str:
    """مسار `Payload/<الاسم>.app/` الوحيد في الحزمة، أو فارغ إن لم يوجد أو تعدّد."""
    roots = {
        "/".join(name.split("/")[:2]) + "/"
        for name in names
        if name.startswith("Payload/") and name.split("/")[1].endswith(".app")
    }
    return roots.pop() if len(roots) == 1 else ""


def is_macho(data: bytes) -> bool:
    return data[:4] in MACHO_MAGICS


def inspect(path: str, bundle_id: str) -> tuple[list[str], dict[str, Any]]:
    """(أسباب الفشل، معلومات للعرض). الأسباب فارغة إن سلم الملف."""
    if not os.path.isfile(path):
        return [f"{path}: غير موجود"], {}
    try:
        archive = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        return [f"{path}: ليس حزمة zip صالحة"], {}
    with archive:
        names = archive.namelist()
        root = app_root(names)
        if not root:
            return ["لا يوجد مجلد Payload/<اسم>.app واحد في الحزمة"], {}
        try:
            info = plistlib.loads(archive.read(root + "Info.plist"))
        except KeyError:
            return [f"{root}Info.plist غير موجود"], {}
        except (plistlib.InvalidFileException, ValueError):
            return [f"{root}Info.plist تالف"], {}

        problems: list[str] = []
        found = info.get("CFBundleIdentifier")
        if found != bundle_id:
            problems.append(f"معرّف الحزمة {found!r} وليس {bundle_id!r}")
        if not str(info.get("MinimumOSVersion", "")).strip():
            problems.append("MinimumOSVersion غير معلن")
        for key in REQUIRED_USAGE:
            if not str(info.get(key, "")).strip():
                problems.append(f"{key} غير موجود (ينهار التطبيق عند طلب الإذن)")

        binaries = {
            "البرنامج": root + str(info.get("CFBundleExecutable", "")),
            "محرك Flutter": root + "Frameworks/Flutter.framework/Flutter",
            "كود التطبيق (AOT)": root + "Frameworks/App.framework/App",
        }
        for label, member in binaries.items():
            try:
                with archive.open(member) as f:
                    head = f.read(4)
            except KeyError:
                problems.append(f"{label}: {member} غير موجود")
                continue
            if not is_macho(head):
                problems.append(f"{label}: {member} ليس ثنائي Mach-O")

    details = {
        "bundle": found,
        "name": info.get("CFBundleDisplayName") or info.get("CFBundleName"),
        "version": f"{info.get('CFBundleShortVersionString', '?')} ({info.get('CFBundleVersion', '?')})",
        "min_ios": info.get("MinimumOSVersion"),
        "size_mb": round(os.path.getsize(path) / (1024 * 1024), 1),
    }
    return problems, details


def escape(message: str) -> str:
    return message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main(argv: list[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) != 3:
        print("الاستعمال: ipa_check.py <ملف ipa> <معرّف الحزمة المتوقع>", file=sys.stderr)
        return 2
    path, bundle_id = argv[1], argv[2]
    problems, details = inspect(path, bundle_id)
    name = os.path.basename(path)
    if problems:
        print(f"::error title=ipa-check::{escape(name + ': ' + '؛ '.join(problems))}")
        return 1
    summary = " ".join(f"{key}={value}" for key, value in details.items())
    print(f"::notice title=ipa-{os.path.splitext(name)[0]}::{escape(summary)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
