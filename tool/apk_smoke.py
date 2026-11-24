#!/usr/bin/env python3
"""اختبار دخان لملفات APK على محاكي Android: يثبّت كل تطبيق ويشغّله ويتحقق أنه يبقى حياً ويرسم واجهته بلا انهيار.

يعوّض غياب جهاز حقيقي في أمر واحد: أن الملفات المنشورة (موقَّعة، بإعدادات Firebase وGoogle الحقيقية، بوضع release) تُثبَّت
وتبدأ ولا تنهار ولا تعرض شاشة فارغة. لا يختبر الكاميرا ولا الرسائل القصيرة ولا وصول الإشعارات ولا تسجيل الدخول إلى Google؛
هذه في قائمة القبول عند الزبون (OPERATIONS.md القسم 10).

الاستعمال:
  python3 tool/apk_smoke.py verify <مجلد APK> <وسم الإصدار>
      يقارن بصمة SHA-256 وحجم كل ملف منزَّل بما يعلنه GitHub (GITHUB_REPOSITORY وGITHUB_TOKEN من البيئة).
  python3 tool/apk_smoke.py run <مجلد APK> <مجلد المخرجات>
      يُشغَّل والمحاكي يعمل (adb في المسار): يكتب <المخرجات>/summary.json ولقطة شاشة لكل تطبيق، ويخرج بـ1 إن فشل أي تطبيق.
      الشاشة الأولى المقبولة تتبع SMOKE_DIRECTORY: 1 = البناء يضمّن دليل المدارس (تسجيل الدخول بالهاتف لدى الإدارة، واختيار
      المدرسة لدى الأستاذ والتلميذ)، 0 = بلا دليل («ربط التطبيق بمدرستك»)، وغير ذلك يقبل الاثنين.
  python3 tool/apk_smoke.py report <ملخص summary.json>
      يطبع النتيجة تعليقات GitHub (notice/error) يقرأها من لا يملك سجلات المسار، ويخرج بـ1 إن فشل أي تطبيق.
مجلد APK فيه school-admin.apk وschool-teacher.apk وschool-student.apk.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable, Optional
from xml.etree import ElementTree

from release_check import fetch

APPS = (
    ("admin", "dz.school.admin", "school-admin.apk"),
    ("teacher", "dz.school.teacher", "school-teacher.apk"),
    ("student", "dz.school.student", "school-student.apk"),
)
SETTLE_SECONDS = 45  # يشمل الفحص الأول للمحدِّث (بعد 20 ثانية) وتهيئة Firebase
POLL_SECONDS = 5
MIN_COLORS = 5  # شاشة سوداء أو بيضاء فارغة لها لون واحد؛ واجهة حقيقية لها أكثر بكثير
# الشاشة الأولى للبناء العام. بلا دليل مدارس مضمَّن: «ربط التطبيق بمدرستك» (ظهر نصها فعلاً في فحص preview-7). ومع الدليل
# المضمَّن (ظهرت على محاكي في بناء preview-10): الإدارة على تسجيل الدخول بالهاتف، والأستاذ والتلميذ على اختيار المدرسة.
# إن كشفت واجهة الأندرويد نصوصاً ولم تكن بينها الشاشة المقبولة فالتطبيق على شاشة أخرى (خطأ تحميل مثلاً) فيفشل الفحص؛
# ولا نصوص مكشوفة = لا حكم.
FIRST_SCREEN = "ربط التطبيق بمدرستك"
DIRECTORY_FIRST_SCREENS = {
    "admin": "أدخل رقم هاتفك وكلمة السر",
    "teacher": "اختر مدرستك",
    "student": "اختر مدرستك",
}

_LOG_PREFIX = re.compile(r"^\d\d-\d\d\s+[\d:.]+\s+\d+\s+\d+\s+[A-Z]\s+[^:]*:\s*")
_RESUMED = re.compile(r"(?:topResumedActivity|ResumedActivity)[=:]\s*ActivityRecord\{[0-9a-f]+ u\d+ ([\w.]+)/")


def one_line(text: str, limit: int = 220) -> str:
    collapsed = " ".join(str(text).split())
    return collapsed if len(collapsed) <= limit else collapsed[: limit - 1] + "…"


def escape(message: str) -> str:
    """ترميز رسالة تعليق GitHub (سطر واحد)."""
    return message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def first_screens(app: str, directory: Optional[bool] = None) -> list[str]:
    """الشاشات الأولى المقبولة لتطبيق: مع دليل مضمَّن (True) شاشة الدليل، وبلا دليل (False) رمز الربط، ودون علم (None) كلتاهما."""
    with_directory = DIRECTORY_FIRST_SCREENS[app]
    if directory is True:
        return [with_directory]
    if directory is False:
        return [FIRST_SCREEN]
    return [FIRST_SCREEN, with_directory]


def directory_expectation(environ: dict[str, str]) -> Optional[bool]:
    """SMOKE_DIRECTORY=1: البناء يضمّن دليل المدارس، =0: بلا دليل، وغير ذلك: يُقبل الاثنان (إصدار منشور سابق مثلاً)."""
    return {"1": True, "0": False}.get(environ.get("SMOKE_DIRECTORY", "").strip())


def parse_pid(output: str) -> Optional[int]:
    """ناتج `pidof` (قد يحوي أكثر من رقم): أول رقم، أو None إن لم تكن العملية حية."""
    for token in output.split():
        if token.isdigit():
            return int(token)
    return None


def resumed_package(dumpsys: str) -> Optional[str]:
    """حزمة النشاط الظاهر الآن من `dumpsys activity activities`."""
    match = _RESUMED.search(dumpsys)
    return match.group(1) if match else None


def crash_reasons(logcat: str, package: str) -> list[str]:
    """أسباب انهيار تطبيق [package] من سجل النظام (فارغة إن لم ينهَر)."""
    reasons: list[str] = []
    lines = logcat.splitlines()
    pkg = re.escape(package)
    for index, line in enumerate(lines):
        if "FATAL EXCEPTION" in line:
            following = lines[index + 1 : index + 6]
            if any(re.search(rf"Process: {pkg}\b", item) for item in following):
                detail = next(
                    (_LOG_PREFIX.sub("", item).strip() for item in following if re.search(r"(Exception|Error)\b", item)),
                    "",
                )
                reasons.append(one_line(f"انهيار (FATAL EXCEPTION): {detail}"))
        elif re.search(rf"\bANR in {pkg}\b", line):
            reasons.append(one_line(f"التطبيق لا يستجيب: {_LOG_PREFIX.sub('', line).strip()}"))
        elif "Fatal signal" in line and re.search(rf"\b{pkg}\b", line):
            reasons.append(one_line(f"انهيار أصلي: {_LOG_PREFIX.sub('', line).strip()}"))
    return reasons


# نافذة نظام تغطي التطبيق في المحاكي (تطبيق آخر لا يستجيب، مثل الواجهة الرئيسية للمحاكي البطيء): ليست من تطبيقنا.
_SYSTEM_DIALOG = re.compile(r"isn't responding|is not responding|keeps stopping|لا يستجيب|يتوقف باستمرار")
_WAIT_LABELS = ("Wait", "انتظار")
_BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def system_dialog(texts: list[str]) -> bool:
    """هل تغطي الشاشةَ نافذةُ نظام «… لا يستجيب»؟"""
    return any(_SYSTEM_DIALOG.search(text) for text in texts)


def wait_button_center(xml: str) -> Optional[tuple[int, int]]:
    """وسط زر «Wait» في نافذة النظام من ناتج `uiautomator dump`، أو None."""
    if not xml.strip():
        return None
    try:
        root = ElementTree.fromstring(xml)
    except ElementTree.ParseError:
        return None
    for node in root.iter("node"):
        if node.get("text", "").strip() in _WAIT_LABELS:
            match = _BOUNDS.fullmatch(node.get("bounds", ""))
            if match:
                x1, y1, x2, y2 = (int(v) for v in match.groups())
                return ((x1 + x2) // 2, (y1 + y2) // 2)
    return None


def extract_hierarchy(output: str) -> str:
    """مقطع XML من ناتج `uiautomator dump` (يسبقه ويليه نص آخر أحياناً)."""
    start = output.find("<?xml")
    if start < 0:
        start = output.find("<hierarchy")
    end = output.rfind("</hierarchy>")
    if start < 0 or end < 0:
        return ""
    return output[start : end + len("</hierarchy>")]


def ui_texts(xml: str) -> list[str]:
    """النصوص الظاهرة (text وcontent-desc) بترتيب ظهورها دون تكرار."""
    if not xml.strip():
        return []
    try:
        root = ElementTree.fromstring(xml)
    except ElementTree.ParseError:
        return []
    found: list[str] = []
    for node in root.iter():
        for attribute in ("text", "content-desc"):
            value = (node.attrib.get(attribute) or "").strip()
            if value and value not in found:
                found.append(value)
    return found


def distinct_colors(raw: bytes, sample: int = 20000) -> int:
    """عدد الألوان المختلفة في لقطة خام RGBA من `screencap` (يسبقها رأس من 3 أو 4 أعداد صحيحة)."""
    if len(raw) < 16:
        return 0
    width, height = struct.unpack_from("<II", raw, 0)
    pixels = width * height
    if width <= 0 or height <= 0 or len(raw) < pixels * 4:
        return 0
    body = raw[len(raw) - pixels * 4 :]
    step = max(1, pixels // sample)
    return len({body[i * 4 : i * 4 + 4] for i in range(0, pixels, step)})


@dataclass
class Outcome:
    app: str
    package: str
    installed: bool = False
    pid: Optional[int] = None
    resumed: Optional[str] = None
    colors: int = 0
    texts: list[str] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    # ما عولج في المحاكي دون أن يكون عيباً في التطبيق (نافذة نظام أُغلقت).
    notes: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.problems


def find_adb() -> str:
    found = shutil.which("adb")
    if found:
        return found
    for variable in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        root = os.environ.get(variable)
        if root:
            candidate = Path(root) / "platform-tools" / ("adb.exe" if os.name == "nt" else "adb")
            if candidate.is_file():
                return str(candidate)
    raise FileNotFoundError("لم أجد adb: ضعه في PATH أو اضبط ANDROID_HOME")


class Adb:
    """غلاف رفيع على adb (يُستبدل في الاختبارات)."""

    def __init__(self, executable: Optional[str] = None) -> None:
        self.executable = executable or find_adb()

    def _run(self, args: list[str], timeout: int) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run([self.executable, *args], capture_output=True, timeout=timeout)

    def text(self, *args: str, timeout: int = 120) -> str:
        done = self._run(list(args), timeout)
        return (done.stdout + done.stderr).decode("utf-8", "replace")

    def shell(self, *args: str, timeout: int = 60) -> str:
        return self.text("shell", *args, timeout=timeout)

    def install(self, apk: str) -> str:
        return self.text("install", "-r", "-g", apk, timeout=300)

    def uninstall(self, package: str) -> None:
        self.text("uninstall", package)

    def logcat_clear(self) -> None:
        self.text("logcat", "-c")

    def logcat_dump(self) -> str:
        return self.text("logcat", "-d", "-b", "main,system,crash", timeout=120)

    def screencap_raw(self) -> bytes:
        return self._run(["exec-out", "screencap"], 60).stdout

    def screencap_png(self) -> bytes:
        return self._run(["exec-out", "screencap", "-p"], 60).stdout


def smoke_app(
    adb: Any,
    app: str,
    package: str,
    apk: Path,
    out_dir: Path,
    sleep: Callable[[float], None] = time.sleep,
    settle: int = SETTLE_SECONDS,
    poll: int = POLL_SECONDS,
    directory: Optional[bool] = None,
) -> Outcome:
    """يثبّت [apk] ويشغّله ويراقبه [settle] ثانية، ويجمع أي مشكلة في [Outcome.problems]."""
    outcome = Outcome(app, package)
    adb.uninstall(package)
    installed = adb.install(str(apk))
    if "Success" not in installed:
        outcome.problems.append("التثبيت فشل: " + one_line(installed))
        return outcome
    outcome.installed = True
    adb.logcat_clear()
    launched = adb.shell("monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1")
    if "Events injected: 1" not in launched:
        outcome.problems.append("تعذّر تشغيل التطبيق: " + one_line(launched))
        return outcome

    crashes: list[str] = []
    waited = 0
    while waited < settle:
        sleep(poll)
        waited += poll
        crashes = crash_reasons(adb.logcat_dump(), package)
        if crashes or parse_pid(adb.shell("pidof", package)) is None:
            break
    outcome.problems.extend(crashes)

    def screen_xml() -> str:
        adb.shell("uiautomator", "dump", "/sdcard/smoke_ui.xml", timeout=60)
        return extract_hierarchy(adb.shell("cat", "/sdcard/smoke_ui.xml"))

    # نافذة «… لا يستجيب» لتطبيق آخر في المحاكي تغطي التطبيق: تُغلق («Wait») ويُعاد النظر، حتى 3 مرات.
    xml = screen_xml()
    for _ in range(3):
        if not system_dialog(ui_texts(xml)):
            break
        outcome.notes.append("أُغلقت نافذة نظام: " + one_line(" | ".join(ui_texts(xml)[:3])))
        center = wait_button_center(xml)
        if center:
            adb.shell("input", "tap", str(center[0]), str(center[1]))
        else:
            adb.shell("am", "broadcast", "-a", "android.intent.action.CLOSE_SYSTEM_DIALOGS")
        sleep(poll)
        xml = screen_xml()

    outcome.pid = parse_pid(adb.shell("pidof", package))
    if outcome.pid is None:
        outcome.problems.append("العملية انتهت بعد التشغيل (انهيار أو إغلاق)")

    outcome.resumed = resumed_package(adb.shell("dumpsys", "activity", "activities", timeout=60))
    if outcome.resumed != package:
        outcome.problems.append(f"الواجهة الظاهرة ليست التطبيق ({outcome.resumed or 'لا شيء'})")

    outcome.colors = distinct_colors(adb.screencap_raw())
    if outcome.colors < MIN_COLORS:
        outcome.problems.append(f"الشاشة تبدو فارغة ({outcome.colors} لون)")
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{app}.png").write_bytes(adb.screencap_png())

    texts = ui_texts(xml)
    outcome.texts = texts[:12]
    expected = first_screens(app, directory)
    if texts and not any(screen in text for text in texts for screen in expected):
        names = " أو ".join(f"«{screen}»" for screen in expected)
        outcome.problems.append(f"الشاشة الأولى ليست {names}: {one_line(' | '.join(texts[:6]))}")
    adb.shell("am", "force-stop", package)
    return outcome


def write_summary(path: Path, outcomes: list[Outcome]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps([asdict(o) for o in outcomes], ensure_ascii=False, indent=2), encoding="utf-8")


def run(
    apk_dir: Path,
    out_dir: Path,
    adb: Any = None,
    sleep: Callable[[float], None] = time.sleep,
    settle: int = SETTLE_SECONDS,
    directory: Optional[bool] = None,
) -> int:
    adb = adb or Adb()
    outcomes: list[Outcome] = []
    for app, package, name in APPS:
        apk = apk_dir / name
        if not apk.is_file():
            outcomes.append(Outcome(app, package, problems=[f"الملف غير موجود: {name}"]))
        else:
            try:
                outcomes.append(
                    smoke_app(adb, app, package, apk, out_dir, sleep=sleep, settle=settle, directory=directory)
                )
            except Exception as error:  # noqa: BLE001 — تعطّل تطبيق لا يوقف فحص البقية
                outcomes.append(Outcome(app, package, problems=[f"خطأ أثناء الفحص: {one_line(repr(error))}"]))
        last = outcomes[-1]
        print(f"{app}: {'ok' if last.ok else 'FAILED'} pid={last.pid} activity={last.resumed} colors={last.colors}")
        for problem in last.problems:
            print(f"  - {problem}")
        write_summary(out_dir / "summary.json", outcomes)
    return 0 if all(o.ok for o in outcomes) else 1


def report(summary: Path) -> int:
    try:
        data = json.loads(summary.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        print("::error title=apk-smoke::لا ملخص للنتيجة (هل فشل المحاكي قبل بدء الاختبار؟)")
        return 1
    failed = False
    for item in data:
        title = f"apk-smoke-{item['app']}"
        if item["problems"]:
            failed = True
            print(f"::error title={title}::{escape(' | '.join(item['problems']))}")
        else:
            texts = " | ".join(item["texts"][:8]) or "(بلا نصوص مكشوفة)"
            message = f"ok pid={item['pid']} activity={item['resumed']} colors={item['colors']} texts={texts}"
            print(f"::notice title={title}::{escape(message)}")
    return 1 if failed else 0


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def digest_problems(apk_dir: Path, release: Any) -> list[str]:
    """فروق بين الملفات المنزَّلة وما يعلنه GitHub لإصدار منشور (فارغة إن تطابقت)."""
    if not isinstance(release, dict):
        return ["الإصدار غير موجود أو تعذّرت قراءته"]
    assets = {a.get("name"): a for a in release.get("assets", []) if isinstance(a, dict)}
    found: list[str] = []
    for _app, _package, name in APPS:
        asset = assets.get(name)
        path = apk_dir / name
        if asset is None:
            found.append(f"{name}: ليس في الإصدار")
        elif not path.is_file():
            found.append(f"{name}: لم يُنزَّل")
        else:
            actual = "sha256:" + sha256_file(path)
            if actual != str(asset.get("digest", "")):
                found.append(f"{name}: البصمة المنزَّلة {actual[:19]}… لا تطابق المعلنة")
            if asset.get("size") != path.stat().st_size:
                found.append(f"{name}: الحجم المنزَّل {path.stat().st_size} لا يطابق المعلن {asset.get('size')}")
    return found


def verify(apk_dir: Path, tag: str, environ: Optional[dict[str, str]] = None) -> int:
    environ = dict(os.environ) if environ is None else environ
    repo = environ.get("GITHUB_REPOSITORY", "")
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
        print("::error title=apk-verify::GITHUB_REPOSITORY غير مضبوط")
        return 2
    status, release = fetch(f"https://api.github.com/repos/{repo}/releases/tags/{tag}", environ.get("GITHUB_TOKEN", ""))
    found = [f"الواجهة ردّت {status}"] if status != 200 else digest_problems(apk_dir, release)
    if found:
        print(f"::error title=apk-verify::{escape(' | '.join(found))}")
        return 1
    print(f"::notice title=apk-verify::ok tag={tag} الملفات الثلاثة مطابقة لبصمات GitHub")
    return 0


def main(argv: list[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = argv[1:]
    if len(args) == 3 and args[0] == "run":
        return run(Path(args[1]), Path(args[2]), directory=directory_expectation(dict(os.environ)))
    if len(args) == 2 and args[0] == "report":
        return report(Path(args[1]))
    if len(args) == 3 and args[0] == "verify":
        return verify(Path(args[1]), args[2])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
