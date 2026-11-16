"""اختبارات مولّد ملف Firebase الاصطناعي: يطابق هيئة الملف الحقيقي ويقبله فاحص الأسرار."""

import json
import os
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fake_google_services as fake  # noqa: E402
import preflight  # noqa: E402

PACKAGES = ["dz.school.admin", "dz.school.teacher", "dz.school.student"]


class Build(unittest.TestCase):
    def test_has_one_client_per_package_in_the_real_files_shape(self):
        data = fake.build(PACKAGES)
        self.assertEqual(data["project_info"]["project_id"], fake.PROJECT_ID)
        self.assertEqual(data["configuration_version"], "1")
        found = [c["client_info"]["android_client_info"]["package_name"] for c in data["client"]]
        self.assertEqual(found, PACKAGES)
        for client in data["client"]:
            self.assertTrue(client["client_info"]["mobilesdk_app_id"].startswith("1:000000000000:android:"))
            self.assertTrue(client["api_key"][0]["current_key"])

    def test_app_ids_are_distinct_and_stable(self):
        first = [c["client_info"]["mobilesdk_app_id"] for c in fake.build(PACKAGES)["client"]]
        again = [c["client_info"]["mobilesdk_app_id"] for c in fake.build(PACKAGES)["client"]]
        self.assertEqual(first, again)
        self.assertEqual(len(set(first)), 3)

    def test_the_secrets_checker_accepts_it_as_a_shared_file(self):
        text = json.dumps(fake.build(PACKAGES))
        self.assertIsNone(preflight.google_services(*PACKAGES)(text, preflight.Values({}, {})))

    def test_nothing_looks_like_a_real_google_key(self):
        text = json.dumps(fake.build(PACKAGES))
        self.assertNotIn("AIza", text)


class Cli(unittest.TestCase):
    def test_writes_the_file_and_reports_the_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = pathlib.Path(tmp) / "nested" / "google-services.json"
            self.assertEqual(fake.main(["fake", str(target), *PACKAGES]), 0)
            data = json.loads(target.read_text(encoding="utf-8"))
            self.assertEqual(len(data["client"]), 3)

    def test_arguments_are_required(self):
        self.assertEqual(fake.main(["fake", "only-a-path.json"]), 2)


if __name__ == "__main__":
    unittest.main()
