#!/usr/bin/env python3
"""يفحص أن تطبيق Windows لا يحتاج DLL غير موجودة على جهاز نظيف (لا Visual Studio ولا Visual C++ Redistributable).

يقرأ جدول الاستيراد (import وdelay-import) في كل `.exe` و`.dll` داخل مجلد التطبيق، ويصنّف كل DLL مطلوبة:
  * مجمَّعة: موجودة في المجلد نفسه (يبحث Windows فيه أولاً).
  * نظامية: من واجهات API sets (`api-ms-win-*`) أو مما يأتي مع Windows 10 نفسه (قائمة مدمجة، ويمكن ضمّ
    قائمة أخرى بالخيار --os-list؛ يولّدها المسار من System32 بحسب اسم المنتج «Operating System»).
وما عدا ذلك خطأ. أشهر الأمثلة `vcruntime140.dll` و`msvcp140.dll` و`vcruntime140_1.dll`: توجد على جهاز المطوّر
لأن Visual Studio يثبّتها، ولا تأتي مع Windows، فيظهر على جهاز نظيف «The code execution cannot proceed because
VCRUNTIME140.dll was not found». علاجها نسخها بجانب admin.exe (نشر محلي للتطبيق مسموح بشروط Microsoft).

الاستعمال:
  python3 tool/windows_dll_check.py <مجلد التطبيق> [--os-list ملف.txt] [--tolerate المستورِد:المطلوبة ...]

الخروج 0 إن سلم، و1 إن نقصت DLL أو اختلفت المعمارية. DLL مؤجَّلة التحميل (delay-load) تعطي تحذيراً فقط.
--tolerate يسمح بنقص معروف وغير ضار (مثل `dartjni.dll:jvm.dll`: جسر JNI من مكتبة Android يُبنى مع
التطبيق ولا يُحمَّل أبداً على Windows) ويُذكر في التقرير تحذيراً.
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
from dataclasses import dataclass, field
from typing import Optional

MACHINE_X64 = 0x8664
MAGIC_PE32 = 0x10B
MAGIC_PE32_PLUS = 0x20B
DIR_IMPORT = 1
DIR_DELAY_IMPORT = 13

API_SET_PREFIXES = ("api-ms-win-", "ext-ms-win-", "api-ms-onecore-")

# مكتبات تأتي مع Windows 10 وما بعده (أسماء صغيرة). يكمّلها خيار --os-list في المسار.
BUILTIN_OS = frozenset(
    """
    kernel32.dll kernelbase.dll ntdll.dll user32.dll gdi32.dll gdi32full.dll win32u.dll advapi32.dll sechost.dll
    rpcrt4.dll shell32.dll shlwapi.dll shcore.dll ole32.dll oleaut32.dll combase.dll comdlg32.dll comctl32.dll
    imm32.dll msvcrt.dll ucrtbase.dll ws2_32.dll wsock32.dll winmm.dll version.dll dwmapi.dll uxtheme.dll dxgi.dll
    d3d9.dll d3d11.dll d3d12.dll d3dcompiler_47.dll dwrite.dll d2d1.dll opengl32.dll setupapi.dll cfgmgr32.dll bcrypt.dll
    crypt32.dll ncrypt.dll secur32.dll sspicli.dll wintrust.dll userenv.dll wtsapi32.dll powrprof.dll winhttp.dll
    wininet.dll iphlpapi.dll netapi32.dll dnsapi.dll mswsock.dll psapi.dll dbghelp.dll imagehlp.dll normaliz.dll
    msctf.dll usp10.dll propsys.dll windowscodecs.dll mfplat.dll mf.dll mfreadwrite.dll avrt.dll hid.dll
    oleacc.dll uiautomationcore.dll wldap32.dll mpr.dll authz.dll cabinet.dll urlmon.dll msimg32.dll winspool.drv
    credui.dll rstrtmgr.dll shfolder.dll winusb.dll dnsapi.dll ncrypt.dll bcryptprimitives.dll cryptsp.dll
    rpcrt4.dll profapi.dll gdiplus.dll msi.dll cryptbase.dll dhcpcsvc.dll nsi.dll wevtapi.dll comsvcs.dll
    """.split()
)


class PeError(Exception):
    pass


@dataclass
class PeInfo:
    machine: int
    imports: list[str] = field(default_factory=list)
    delay_imports: list[str] = field(default_factory=list)


def _cstring(data: bytes, offset: int) -> str:
    end = data.find(b"\0", offset)
    if end == -1:
        raise PeError("اسم DLL غير منتهٍ")
    return data[offset:end].decode("ascii", "replace")


def parse_pe(data: bytes) -> PeInfo:
    """يقرأ نوع المعمارية وأسماء الـDLL المستوردة (والمؤجَّلة) من ملف PE."""
    try:
        if data[:2] != b"MZ":
            raise PeError("ليس ملف PE")
        e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
        if data[e_lfanew : e_lfanew + 4] != b"PE\0\0":
            raise PeError("توقيع PE مفقود")
        machine, sections_count, _, _, _, optional_size, _ = struct.unpack_from("<HHIIIHH", data, e_lfanew + 4)
        optional = e_lfanew + 24
        magic = struct.unpack_from("<H", data, optional)[0]
        if magic == MAGIC_PE32_PLUS:
            directories = optional + 112
        elif magic == MAGIC_PE32:
            directories = optional + 96
        else:
            raise PeError("رأس اختياري غير معروف")
        directory_count = struct.unpack_from("<I", data, directories - 4)[0]
        table = optional + optional_size
        sections = []
        for i in range(sections_count):
            _, virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from("<8sIIII", data, table + 40 * i)
            sections.append((virtual_address, max(virtual_size, raw_size), raw_pointer))

        def offset_of(rva: int) -> int:
            for address, size, pointer in sections:
                if address <= rva < address + size:
                    return rva - address + pointer
            raise PeError("عنوان خارج الأقسام")

        def directory(index: int) -> int:
            if index >= directory_count:
                return 0
            return struct.unpack_from("<II", data, directories + 8 * index)[0]

        info = PeInfo(machine=machine)
        rva = directory(DIR_IMPORT)
        if rva:
            at = offset_of(rva)
            while True:
                fields = struct.unpack_from("<IIIII", data, at)
                if not any(fields):
                    break
                info.imports.append(_cstring(data, offset_of(fields[3])))
                at += 20
        rva = directory(DIR_DELAY_IMPORT)
        if rva:
            at = offset_of(rva)
            while True:
                fields = struct.unpack_from("<IIIIIIII", data, at)
                if not any(fields):
                    break
                info.delay_imports.append(_cstring(data, offset_of(fields[1])))
                at += 32
        return info
    except struct.error as error:
        raise PeError(f"ملف PE مقطوع: {error}") from None


@dataclass
class Report:
    files: list[str] = field(default_factory=list)
    bundled_runtime: list[str] = field(default_factory=list)
    missing: dict[str, list[str]] = field(default_factory=dict)  # DLL ← الملفات التي تستوردها
    delay_missing: dict[str, list[str]] = field(default_factory=dict)
    tolerated: list[str] = field(default_factory=list)  # «المستورِد ← المطلوبة» المسموح بنقصها
    wrong_machine: list[str] = field(default_factory=list)
    unreadable: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not (self.missing or self.wrong_machine or self.unreadable)


def load_os_names(path: Optional[str]) -> frozenset[str]:
    names = set(BUILTIN_OS)
    if path:
        with open(path, encoding="utf-8", errors="replace") as f:
            names.update(line.strip().lower() for line in f if line.strip())
    return frozenset(names)


def is_system(name: str, os_names: frozenset[str]) -> bool:
    return name.startswith(API_SET_PREFIXES) or name in os_names


def parse_tolerated(items: list[str]) -> frozenset[tuple[str, str]]:
    pairs = set()
    for item in items:
        importer, separator, dependency = item.lower().partition(":")
        if not separator or not importer or not dependency:
            raise ValueError(f"صيغة --tolerate المستورِد:المطلوبة، لا «{item}»")
        pairs.add((importer, dependency))
    return frozenset(pairs)


def check(
    app_dir: str, os_names: frozenset[str], tolerated: frozenset[tuple[str, str]] = frozenset()
) -> Report:
    report = Report()
    present = {n.lower(): n for n in os.listdir(app_dir) if n.lower().endswith((".dll", ".exe"))}
    report.files = sorted(present.values(), key=str.lower)
    for lower, original in sorted(present.items()):
        try:
            with open(os.path.join(app_dir, original), "rb") as f:
                info = parse_pe(f.read())
        except (PeError, OSError):
            report.unreadable.append(original)
            continue
        if info.machine != MACHINE_X64:
            report.wrong_machine.append(f"{original} (0x{info.machine:04x})")
        for target, bucket in ((info.imports, report.missing), (info.delay_imports, report.delay_missing)):
            for dependency in {d.lower() for d in target}:
                if dependency in present or is_system(dependency, os_names):
                    continue
                if (lower, dependency) in tolerated:
                    report.tolerated.append(f"{original} ← {dependency}")
                    continue
                bucket.setdefault(dependency, []).append(original)
    runtime = [n for n in report.files if n.lower().startswith(("vcruntime", "msvcp", "concrt", "vcomp"))]
    report.bundled_runtime = runtime
    for dependency in list(report.delay_missing):
        if dependency in report.missing:
            del report.delay_missing[dependency]
    return report


def describe(report: Report) -> list[str]:
    lines = [f"ملفات PE في المجلد: {len(report.files)}"]
    lines.append("مكتبات Visual C++ المجمَّعة: " + (", ".join(report.bundled_runtime) or "لا شيء"))
    for dependency, importers in sorted(report.missing.items()):
        lines.append(f"✗ ناقصة: {dependency} (يطلبها: {', '.join(sorted(set(importers)))})")
    for dependency, importers in sorted(report.delay_missing.items()):
        lines.append(f"⚠ مؤجَّلة ناقصة: {dependency} (يطلبها: {', '.join(sorted(set(importers)))})")
    for item in report.tolerated:
        lines.append(f"⚠ نقص مسموح به: {item}")
    for item in report.wrong_machine:
        lines.append(f"✗ معمارية غير x64: {item}")
    for item in report.unreadable:
        lines.append(f"✗ تعذّرت قراءته كملف PE: {item}")
    if report.ok:
        lines.append("✓ كل المكتبات المطلوبة مجمَّعة أو من Windows نفسه")
    return lines


def main(argv: list[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="فحص اكتمال مكتبات تطبيق Windows")
    parser.add_argument("app_dir")
    parser.add_argument("--os-list", help="ملف بأسماء مكتبات Windows (سطر لكل اسم)")
    parser.add_argument("--tolerate", action="append", default=[], metavar="المستورِد:المطلوبة")
    args = parser.parse_args(argv[1:])
    try:
        tolerated = parse_tolerated(args.tolerate)
    except ValueError as error:
        print(f"::error title=windows-dll-check::{error}")
        return 2
    if not os.path.isdir(args.app_dir):
        print(f"::error title=windows-dll-check::المجلد غير موجود: {args.app_dir}")
        return 2
    report = check(args.app_dir, load_os_names(args.os_list), tolerated)
    lines = describe(report)
    for line in lines:
        print(line)
    if not report.ok:
        message = " | ".join(lines).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::error title=windows-dll-check::{message}")
        return 1
    if report.delay_missing:
        print("::warning title=windows-dll-check::" + ", ".join(sorted(report.delay_missing)))
    print(f"::notice title=windows-dll-check::ok files={len(report.files)} runtime={len(report.bundled_runtime)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
