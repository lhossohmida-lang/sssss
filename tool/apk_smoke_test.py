import contextlib
import hashlib
import io
import json
import struct
import tempfile
import unittest
from pathlib import Path

import apk_smoke as smoke

CRASH = (
    "11-16 12:00:01.100  1234  1234 E AndroidRuntime: FATAL EXCEPTION: main\n"
    "11-16 12:00:01.100  1234  1234 E AndroidRuntime: Process: dz.school.admin, PID: 1234\n"
    "11-16 12:00:01.100  1234  1234 E AndroidRuntime: java.lang.IllegalStateException: Default FirebaseApp is not initialized\n"
    "11-16 12:00:01.100  1234  1234 E AndroidRuntime: \tat com.example.Foo.bar(Foo.java:1)\n"
)
DUMPSYS = (
    "ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)\n"
    "  topResumedActivity=ActivityRecord{12f3d71 u0 dz.school.admin/.MainActivity t12}\n"
    "  ResumedActivity: ActivityRecord{12f3d71 u0 dz.school.admin/.MainActivity t12}\n"
)
XML = (
    "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>"
    '<hierarchy rotation="0">'
    '<node text="" content-desc="ربط التطبيق بمدرستك" class="android.view.View"/>'
    '<node text="الصق الرمز" content-desc="" class="android.widget.EditText"/>'
    '<node text="الصق الرمز" content-desc="" class="android.widget.EditText"/>'
    "</hierarchy>UI hierchary dumped to: /sdcard/smoke_ui.xml"
)


def raw_screen(colors: int, width: int = 40, height: int = 30) -> bytes:
    """لقطة خام: رأس من 4 أعداد صحيحة (واجهة Android 12+) ثم بكسلات تتناوب بين [colors] لوناً."""
    header = struct.pack("<IIII", width, height, 1, 0)
    palette = [bytes([i * 10 % 256, i * 20 % 256, i * 30 % 256, 255]) for i in range(max(colors, 1))]
    return header + b"".join(palette[i % len(palette)] for i in range(width * height))


class FakeAdb:
    def __init__(
        self,
        install="Performing Streamed Install\nSuccess\n",
        launch="Events injected: 1\n",
        pid="4242\n",
        logcat="",
        dumpsys=DUMPSYS,
        raw=None,
        xml=XML,
    ):
        self.install_output = install
        self.launch = launch
        self.pid = pid
        self.logcat = logcat
        self.dumpsys = dumpsys
        self.raw = raw if raw is not None else raw_screen(8)
        self.xml = xml
        self.calls = []

    def uninstall(self, package):
        self.calls.append(("uninstall", package))

    def install(self, apk):
        self.calls.append(("install", apk))
        return self.install_output

    def logcat_clear(self):
        self.calls.append(("logcat_clear",))

    def logcat_dump(self):
        return self.logcat

    def shell(self, *args, timeout=60):
        self.calls.append(("shell",) + args)
        head = args[0]
        if head == "monkey":
            return self.launch
        if head == "pidof":
            return self.pid
        if head == "dumpsys":
            return self.dumpsys
        if head == "cat":
            return self.xml
        return ""

    def screencap_raw(self):
        return self.raw

    def screencap_png(self):
        return b"\x89PNG-fake"


class PureFunctionsTest(unittest.TestCase):
    def test_parse_pid(self):
        self.assertEqual(smoke.parse_pid("1234\n"), 1234)
        self.assertEqual(smoke.parse_pid("1234 5678\n"), 1234)
        self.assertIsNone(smoke.parse_pid(""))
        self.assertIsNone(smoke.parse_pid("pidof: not found"))

    def test_resumed_package(self):
        self.assertEqual(smoke.resumed_package(DUMPSYS), "dz.school.admin")
        self.assertIsNone(smoke.resumed_package("nothing here"))
        launcher = "  topResumedActivity=ActivityRecord{ab12 u0 com.google.android.apps.nexuslauncher/.NexusLauncherActivity t1}\n"
        self.assertEqual(smoke.resumed_package(launcher), "com.google.android.apps.nexuslauncher")

    def test_crash_reasons_finds_the_exception_of_our_package(self):
        reasons = smoke.crash_reasons(CRASH, "dz.school.admin")
        self.assertEqual(len(reasons), 1)
        self.assertIn("FirebaseApp", reasons[0])

    def test_crash_reasons_ignores_other_packages_and_quiet_logs(self):
        self.assertEqual(smoke.crash_reasons(CRASH, "dz.school.teacher"), [])
        self.assertEqual(smoke.crash_reasons("I ActivityManager: Start proc dz.school.admin\n", "dz.school.admin"), [])

    def test_crash_reasons_anr_and_native_signal(self):
        anr = "11-16 12:00:01.100  500  600 E ActivityManager: ANR in dz.school.student (dz.school.student/.MainActivity)\n"
        self.assertEqual(len(smoke.crash_reasons(anr, "dz.school.student")), 1)
        native = "11-16 12:00:01.100  900  900 F libc: Fatal signal 11 (SIGSEGV), code 1 in tid 900 (1.ui), pid 900 (dz.school.teacher)\n"
        self.assertEqual(len(smoke.crash_reasons(native, "dz.school.teacher")), 1)
        self.assertEqual(smoke.crash_reasons(native, "dz.school.admin"), [])

    def test_hierarchy_and_texts(self):
        xml = smoke.extract_hierarchy(XML)
        self.assertTrue(xml.startswith("<?xml"))
        self.assertTrue(xml.endswith("</hierarchy>"))
        self.assertEqual(smoke.ui_texts(xml), ["ربط التطبيق بمدرستك", "الصق الرمز"])
        self.assertEqual(smoke.extract_hierarchy("no xml"), "")
        self.assertEqual(smoke.ui_texts(""), [])
        self.assertEqual(smoke.ui_texts("<hierarchy><node"), [])

    def test_distinct_colors(self):
        self.assertEqual(smoke.distinct_colors(raw_screen(1)), 1)
        self.assertGreaterEqual(smoke.distinct_colors(raw_screen(8)), 8)
        self.assertEqual(smoke.distinct_colors(b""), 0)
        self.assertEqual(smoke.distinct_colors(raw_screen(8)[:-100]), 0)
        # رأس من 3 أعداد (قبل Android 12)
        short = struct.pack("<III", 4, 4, 1) + bytes(range(64))
        self.assertGreater(smoke.distinct_colors(short), 1)

    def test_escape(self):
        self.assertEqual(smoke.escape("a%b\nc\r"), "a%25b%0Ac%0D")


class SmokeAppTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.out = Path(self.tmp.name) / "out"
        self.sleeps = []

    def smoke(self, adb, settle=10):
        return smoke.smoke_app(
            adb, "admin", "dz.school.admin", Path("school-admin.apk"), self.out, sleep=self.sleeps.append, settle=settle, poll=5
        )

    def test_a_healthy_app_passes_and_leaves_a_screenshot(self):
        adb = FakeAdb()
        outcome = self.smoke(adb)
        self.assertTrue(outcome.ok, outcome.problems)
        self.assertEqual(outcome.pid, 4242)
        self.assertEqual(outcome.resumed, "dz.school.admin")
        self.assertGreaterEqual(outcome.colors, 5)
        self.assertEqual(outcome.texts, ["ربط التطبيق بمدرستك", "الصق الرمز"])
        self.assertEqual((self.out / "admin.png").read_bytes(), b"\x89PNG-fake")
        self.assertEqual(self.sleeps, [5, 5])
        self.assertIn(("shell", "am", "force-stop", "dz.school.admin"), adb.calls)
        # يُمسح التثبيت السابق أولاً وتُمنح الصلاحيات عند التثبيت
        self.assertEqual(adb.calls[0], ("uninstall", "dz.school.admin"))

    def test_install_failure_stops_before_launching(self):
        adb = FakeAdb(install="Failure [INSTALL_FAILED_NO_MATCHING_ABIS]\n")
        outcome = self.smoke(adb)
        self.assertFalse(outcome.installed)
        self.assertIn("INSTALL_FAILED_NO_MATCHING_ABIS", outcome.problems[0])
        self.assertFalse(any(call[:2] == ("shell", "monkey") for call in adb.calls))

    def test_launch_failure(self):
        outcome = self.smoke(FakeAdb(launch="** No activities found to run, monkey aborted.\n"))
        self.assertTrue(outcome.installed)
        self.assertIn("تعذّر تشغيل التطبيق", outcome.problems[0])

    def test_a_crash_is_reported_and_stops_waiting(self):
        outcome = self.smoke(FakeAdb(logcat=CRASH, pid=""), settle=30)
        self.assertFalse(outcome.ok)
        self.assertTrue(any("FirebaseApp" in p for p in outcome.problems))
        self.assertEqual(self.sleeps, [5])  # لم ينتظر بقية المهلة
        self.assertTrue(any("العملية انتهت" in p for p in outcome.problems))

    def test_a_process_that_dies_silently(self):
        outcome = self.smoke(FakeAdb(pid=""))
        self.assertTrue(any("العملية انتهت" in p for p in outcome.problems))

    def test_wrong_foreground_app(self):
        launcher = "  topResumedActivity=ActivityRecord{ab12 u0 com.android.launcher3/.Launcher t1}\n"
        outcome = self.smoke(FakeAdb(dumpsys=launcher))
        self.assertTrue(any("ليست التطبيق" in p and "launcher3" in p for p in outcome.problems))

    def test_blank_screen(self):
        outcome = self.smoke(FakeAdb(raw=raw_screen(1)))
        self.assertTrue(any("فارغة" in p for p in outcome.problems))

    def test_an_unexpected_first_screen_fails(self):
        error_screen = (
            "<?xml version='1.0' ?><hierarchy>"
            '<node text="تعذّر التحميل" content-desc="" class="android.view.View"/>'
            '<node text="إعادة المحاولة" content-desc="" class="android.view.View"/>'
            "</hierarchy>"
        )
        outcome = self.smoke(FakeAdb(xml=error_screen))
        self.assertTrue(any("الشاشة الأولى" in p and "تعذّر التحميل" in p for p in outcome.problems), outcome.problems)

    def test_a_missing_ui_tree_is_not_a_failure(self):
        outcome = self.smoke(FakeAdb(xml="ERROR: null root node returned by UiTestAutomationBridge."))
        self.assertTrue(outcome.ok, outcome.problems)
        self.assertEqual(outcome.texts, [])


class RunAndReportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.apks = self.root / "apks"
        self.apks.mkdir()

    def test_run_reports_missing_files_and_writes_the_summary(self):
        (self.apks / "school-admin.apk").write_bytes(b"apk")
        out = self.root / "out"
        with contextlib.redirect_stdout(io.StringIO()):
            code = smoke.run(self.apks, out, adb=FakeAdb(), sleep=lambda _s: None, settle=5)
        self.assertEqual(code, 1)
        data = json.loads((out / "summary.json").read_text(encoding="utf-8"))
        self.assertEqual([item["app"] for item in data], ["admin", "teacher", "student"])
        self.assertEqual(data[0]["problems"], [])
        self.assertIn("school-teacher.apk", data[1]["problems"][0])

    def test_run_succeeds_when_every_app_is_healthy(self):
        for name in ("school-admin.apk", "school-teacher.apk", "school-student.apk"):
            (self.apks / name).write_bytes(b"apk")
        out = self.root / "out"

        class PerAppAdb(FakeAdb):
            """كل تطبيق يظهر في المقدمة بعد تثبيته."""

            current = ""

            def install(self, apk):
                self.current = {
                    "school-admin.apk": "dz.school.admin",
                    "school-teacher.apk": "dz.school.teacher",
                    "school-student.apk": "dz.school.student",
                }[Path(apk).name]
                return super().install(apk)

            def shell(self, *args, timeout=60):
                if args[0] == "dumpsys":
                    return "  topResumedActivity=ActivityRecord{1 u0 %s/.MainActivity t1}\n" % self.current
                return super().shell(*args, timeout=timeout)

        with contextlib.redirect_stdout(io.StringIO()):
            code = smoke.run(self.apks, out, adb=PerAppAdb(), sleep=lambda _s: None, settle=5)
        self.assertEqual(code, 0)

    def test_an_exception_in_one_app_does_not_stop_the_others(self):
        for name in ("school-admin.apk", "school-teacher.apk", "school-student.apk"):
            (self.apks / name).write_bytes(b"apk")

        class Broken(FakeAdb):
            def install(self, apk):
                if apk.endswith("school-teacher.apk"):
                    raise TimeoutError("adb hung")
                return super().install(apk)

        with contextlib.redirect_stdout(io.StringIO()):
            code = smoke.run(self.apks, self.root / "out", adb=Broken(), sleep=lambda _s: None, settle=5)
        data = json.loads((self.root / "out" / "summary.json").read_text(encoding="utf-8"))
        self.assertEqual(code, 1)
        self.assertIn("خطأ أثناء الفحص", data[1]["problems"][0])
        self.assertEqual(len(data), 3)

    def test_report_prints_notices_and_errors(self):
        summary = self.root / "summary.json"
        smoke.write_summary(
            summary,
            [
                smoke.Outcome("admin", "dz.school.admin", True, 7, "dz.school.admin", 9, ["ربط التطبيق بمدرستك"]),
                smoke.Outcome("teacher", "dz.school.teacher", True, None, None, 1, [], ["انهيار\nسطر ثانٍ"]),
            ],
        )
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = smoke.report(summary)
        out = buffer.getvalue()
        self.assertEqual(code, 1)
        self.assertIn("::notice title=apk-smoke-admin::ok pid=7", out)
        self.assertIn("ربط التطبيق بمدرستك", out)
        self.assertIn("::error title=apk-smoke-teacher::انهيار%0Aسطر ثانٍ", out)

    def test_report_without_a_summary_fails(self):
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = smoke.report(self.root / "missing.json")
        self.assertEqual(code, 1)
        self.assertIn("::error title=apk-smoke::", buffer.getvalue())


class DigestTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.release = {"assets": []}
        for _app, _package, name in smoke.APPS:
            data = name.encode()
            (self.dir / name).write_bytes(data)
            self.release["assets"].append(
                {"name": name, "size": len(data), "digest": "sha256:" + hashlib.sha256(data).hexdigest()}
            )

    def test_matching_files_have_no_problems(self):
        self.assertEqual(smoke.digest_problems(self.dir, self.release), [])

    def test_a_changed_file_is_caught(self):
        (self.dir / "school-student.apk").write_bytes(b"tampered")
        found = smoke.digest_problems(self.dir, self.release)
        self.assertTrue(any("school-student.apk" in p and "البصمة" in p for p in found))

    def test_missing_asset_and_missing_file(self):
        self.release["assets"].pop()
        (self.dir / "school-admin.apk").unlink()
        found = smoke.digest_problems(self.dir, self.release)
        self.assertTrue(any("school-student.apk: ليس في الإصدار" in p for p in found))
        self.assertTrue(any("school-admin.apk: لم يُنزَّل" in p for p in found))

    def test_unreadable_release(self):
        self.assertEqual(smoke.digest_problems(self.dir, None), ["الإصدار غير موجود أو تعذّرت قراءته"])


if __name__ == "__main__":
    unittest.main()
