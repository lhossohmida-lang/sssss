"""اختبارات pairing_code.py: الصيغة مطابقة للتطبيق، وترفض المفاتيح السرّية، وقراءة المفتاح من Supabase."""

import base64
import contextlib
import io
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pairing_code as pc  # noqa: E402
from supabase_bootstrap_test import ANON, REF, SECRET, SERVICE_ROLE_JWT, TOKEN, FakeServerCase  # noqa: E402

URL = "https://abcdefghijklmnopqrst.supabase.co"
KEY = "sb_publishable_abcdefghijklmnopqrstuvwxyz012345"
NAME = "مدرسة النور"
# متجها اختبار مشتركان مع packages/core/test/app/school_pairing_test.dart: أي تغيير في الصيغة
# يكسر الاختبارين معاً فلا ينحرف المولِّد عن التطبيق.
CODE_WITH_NAME = (
    "SCH1.eyJ2IjoxLCJ1IjoiaHR0cHM6Ly9hYmNkZWZnaGlqa2xtbm9wcXJzdC5zdXBhYmFzZS5jbyIsImsiOiJzYl9w"
    "dWJsaXNoYWJsZV9hYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ejAxMjM0NSIsIm4iOiLZhdiv2LHYs9ipINin2YTZhtmI"
    "2LEifQ"
)
CODE_NO_NAME = (
    "SCH1.eyJ2IjoxLCJ1IjoiaHR0cHM6Ly9hYmNkZWZnaGlqa2xtbm9wcXJzdC5zdXBhYmFzZS5jbyIsImsiOiJzYl9w"
    "dWJsaXNoYWJsZV9hYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ejAxMjM0NSJ9"
)


def b64(value) -> str:
    raw = json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def jwt(role: str) -> str:
    return f"eyJhbGciOiJIUzI1NiJ9.{b64({'role': role})}.c2ln"


def run(argv, environ=None):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        status = pc.main(["pairing_code.py", *argv], environ or {})
    return status, out.getvalue().strip(), err.getvalue().strip()


class Format(unittest.TestCase):
    def test_matches_the_vector_the_app_checks(self):
        self.assertEqual(pc.encode(URL, KEY, NAME), CODE_WITH_NAME)
        self.assertEqual(pc.encode(URL, KEY), CODE_NO_NAME)

    def test_roundtrip_and_tolerance(self):
        info = pc.decode(CODE_WITH_NAME)
        self.assertEqual(info, {"url": URL, "key": KEY, "name": NAME})
        broken = "  " + CODE_WITH_NAME[:30] + "\n" + CODE_WITH_NAME[30:60] + "\r\n" + CODE_WITH_NAME[60:] + " "
        self.assertEqual(pc.decode(broken)["url"], URL)
        self.assertEqual(pc.decode(CODE_NO_NAME.replace("SCH1.", "sch1."))["name"], "")

    def test_url_normalisation(self):
        self.assertEqual(pc.normalize_url("https://ABCDefghijklmnopqrst.Supabase.co/"), URL)
        self.assertEqual(pc.normalize_url("https://x.example.com:443"), "https://x.example.com")
        self.assertEqual(pc.normalize_url("https://x.example.com:8443"), "https://x.example.com:8443")

    def test_bad_urls_are_refused(self):
        for url in [
            "http://abcdefghijklmnopqrst.supabase.co",
            "https://abcdefghijklmnopqrst.supabase.co/rest/v1",
            "https://u:p@abcdefghijklmnopqrst.supabase.co",
            "https://abcdefghijklmnopqrst.supabase.co?x=1",
            "abcdefghijklmnopqrst.supabase.co",
            "",
            None,
        ]:
            with self.assertRaises(pc.PairingError, msg=str(url)):
                pc.normalize_url(url)

    def test_secret_keys_never_get_into_a_code(self):
        for key in ["sb_secret_abcdefghijklmnopqrstuv", SERVICE_ROLE_JWT, jwt("service_role")]:
            with self.assertRaises(pc.PairingError, msg=key):
                pc.encode(URL, key)
        self.assertEqual(pc.encode(URL, jwt("anon")), pc.encode(URL, jwt("anon")))
        self.assertEqual(pc.decode(pc.encode(URL, jwt("anon")))["key"], jwt("anon"))

    def test_incomplete_keys_and_long_names_are_refused(self):
        for key in ["", "short", "has space inside the key value 1234"]:
            with self.assertRaises(pc.PairingError, msg=key):
                pc.encode(URL, key)
        with self.assertRaises(pc.PairingError):
            pc.encode(URL, KEY, "ب" * 81)

    def test_malformed_and_future_codes_are_refused(self):
        for code in ["", "   ", "https://x.supabase.co", "SCH1.!!!", "SCH1." + b64([1, 2])]:
            with self.assertRaises(pc.PairingError, msg=code):
                pc.decode(code)
        with self.assertRaisesRegex(pc.PairingError, "أحدث"):
            pc.decode("SCH1." + b64({"v": 2, "u": URL, "k": KEY}))
        # رمز قديم بمفتاح سرّي مدسوس يُرفض عند الفك أيضاً.
        with self.assertRaises(pc.PairingError):
            pc.decode("SCH1." + b64({"v": 1, "u": URL, "k": "sb_secret_abcdefghijklmnopqrstuv"}))


class Cli(FakeServerCase):
    def test_url_and_key_print_the_code_only(self):
        status, out, err = run(["--url", URL, "--key", KEY, "--name", NAME])
        self.assertEqual((status, out, err), (0, CODE_WITH_NAME, ""))

    def test_decode_hides_the_key(self):
        status, out, _ = run(["--decode", CODE_WITH_NAME])
        self.assertEqual(status, 0)
        self.assertIn(f"url={URL}", out)
        self.assertIn(f"name={NAME}", out)
        self.assertIn("key=publishable", out)
        self.assertNotIn(KEY, out)

    def test_secret_key_is_refused_without_echoing_it(self):
        secret = "sb_secret_abcdefghijklmnopqrstuv"
        status, out, err = run(["--url", URL, "--key", secret])
        self.assertEqual(status, 1)
        self.assertEqual(out, "")
        self.assertNotIn(secret, out + err)

    def test_ref_reads_the_public_key_from_supabase(self):
        env = {"SUPABASE_ACCESS_TOKEN": TOKEN, "SUPABASE_API_BASE": self.base}
        status, out, err = run(["--ref", REF, "--name", NAME], env)
        self.assertEqual((status, err), (0, ""), err)
        info = pc.decode(out)
        self.assertEqual(info["key"], ANON)
        self.assertEqual(info["url"], f"https://{REF}.supabase.co")
        self.assertNotIn(SECRET, out, "المفتاح السرّي لا يظهر في المخرجات أبداً")

    def test_ref_falls_back_to_the_legacy_anon_key(self):
        legacy = jwt("anon")
        self.state.keys = [
            {"type": "legacy", "name": "service_role", "api_key": SERVICE_ROLE_JWT},
            {"type": "legacy", "name": "anon", "api_key": legacy},
        ]
        env = {"SUPABASE_ACCESS_TOKEN": TOKEN, "SUPABASE_API_BASE": self.base}
        status, out, err = run(["--ref", REF], env)
        self.assertEqual(status, 0, err)
        self.assertEqual(pc.decode(out)["key"], legacy)

    def test_ref_without_any_public_key_is_an_error(self):
        self.state.keys = [{"type": "secret", "name": "default", "api_key": SECRET}]
        env = {"SUPABASE_ACCESS_TOKEN": TOKEN, "SUPABASE_API_BASE": self.base}
        status, out, err = run(["--ref", REF], env)
        self.assertEqual(status, 1)
        self.assertEqual(out, "")
        self.assertIn("Publishable", err)
        self.assertNotIn(SECRET, err)

    def test_ref_needs_a_token_a_valid_ref_and_access(self):
        env = {"SUPABASE_API_BASE": self.base}
        status, _, err = run(["--ref", REF], env)
        self.assertEqual(status, 1)
        self.assertIn("SUPABASE_ACCESS_TOKEN", err)
        status, _, err = run(["--ref", "bad"], {**env, "SUPABASE_ACCESS_TOKEN": TOKEN})
        self.assertEqual(status, 1)
        self.assertIn("معرّف المشروع", err)
        self.state.keys_status = 403
        status, _, err = run(["--ref", REF], {**env, "SUPABASE_ACCESS_TOKEN": TOKEN})
        self.assertEqual(status, 1)
        self.assertIn("صلاحية", err)
        status, _, err = run(["--ref", REF], {**env, "SUPABASE_ACCESS_TOKEN": "sbp_wrong"})
        self.assertEqual(status, 1)

    def test_no_arguments_explains_the_usage(self):
        status, _, err = run([])
        self.assertEqual(status, 1)
        self.assertIn("--ref", err)


if __name__ == "__main__":
    unittest.main()
