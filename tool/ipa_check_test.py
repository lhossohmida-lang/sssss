import contextlib
import io
import os
import plistlib
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ipa_check as ic  # noqa: E402

MACHO = b"\xcf\xfa\xed\xfe" + b"\x00" * 60
INFO = {
    "CFBundleIdentifier": "dz.school.student",
    "CFBundleDisplayName": "وليّ التلميذ",
    "CFBundleExecutable": "Runner",
    "CFBundleShortVersionString": "0.1.0",
    "CFBundleVersion": "1",
    "MinimumOSVersion": "15.0",
    "NSCameraUsageDescription": "camera",
    "NSPhotoLibraryUsageDescription": "photos",
}


def make_ipa(directory, info=None, files=None, root="Payload/Runner.app/"):
    path = os.path.join(directory, "school-student.ipa")
    members = {
        root + "Info.plist": plistlib.dumps(INFO if info is None else info, fmt=plistlib.FMT_BINARY),
        root + "Runner": MACHO,
        root + "Frameworks/Flutter.framework/Flutter": MACHO,
        root + "Frameworks/App.framework/App": MACHO,
    }
    members.update(files or {})
    with zipfile.ZipFile(path, "w") as archive:
        for name, data in members.items():
            if data is not None:
                archive.writestr(name, data)
    return path


class IpaCheckTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def run_main(self, path, bundle="dz.school.student"):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = ic.main(["ipa_check.py", path, bundle])
        return code, out.getvalue()

    def test_a_complete_unsigned_ipa_passes_with_its_details(self):
        code, out = self.run_main(make_ipa(self.tmp.name))
        self.assertEqual(code, 0)
        self.assertIn("::notice title=ipa-school-student::bundle=dz.school.student", out)
        self.assertIn("min_ios=15.0", out)
        self.assertIn("version=0.1.0 (1)", out)

    def test_a_wrong_bundle_id_fails(self):
        code, out = self.run_main(make_ipa(self.tmp.name), bundle="dz.school.admin")
        self.assertEqual(code, 1)
        self.assertIn("::error title=ipa-check::", out)
        self.assertIn("'dz.school.admin'", out)

    def test_missing_flutter_code_fails(self):
        path = make_ipa(self.tmp.name, files={"Payload/Runner.app/Frameworks/App.framework/App": None})
        problems, _ = ic.inspect(path, "dz.school.student")
        self.assertEqual(len(problems), 1)
        self.assertIn("App.framework/App", problems[0])

    def test_a_non_macho_binary_fails(self):
        path = make_ipa(self.tmp.name, files={"Payload/Runner.app/Runner": b"#!/bin/sh\n"})
        problems, _ = ic.inspect(path, "dz.school.student")
        self.assertTrue(any("Mach-O" in p for p in problems))

    def test_missing_permission_texts_fail(self):
        info = dict(INFO)
        del info["NSCameraUsageDescription"]
        problems, _ = ic.inspect(make_ipa(self.tmp.name, info=info), "dz.school.student")
        self.assertTrue(any("NSCameraUsageDescription" in p for p in problems))

    def test_missing_payload_or_bad_zip_fails(self):
        problems, _ = ic.inspect(make_ipa(self.tmp.name, root="Runner.app/"), "dz.school.student")
        self.assertIn("Payload", problems[0])
        bad = os.path.join(self.tmp.name, "bad.ipa")
        with open(bad, "wb") as f:
            f.write(b"not a zip")
        problems, _ = ic.inspect(bad, "dz.school.student")
        self.assertIn("zip", problems[0])
        problems, _ = ic.inspect(os.path.join(self.tmp.name, "none.ipa"), "dz.school.student")
        self.assertIn("غير موجود", problems[0])

    def test_usage(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(ic.main(["ipa_check.py"]), 2)


if __name__ == "__main__":
    unittest.main()
