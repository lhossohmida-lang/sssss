"""اختبارات directory_register.py على دليل وهمي محلي."""

import contextlib
import io
import json
import os
import re
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import directory_register as dr  # noqa: E402

SERVICE_KEY = "sb_secret_SENTINEL-DIRECTORY-KEY"
SCHOOL_KEY = "sb_publishable_school-public-key"
SERVICE_ROLE_JWT = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature"
NO_PUBLIC_FILE = os.path.join(tempfile.gettempdir(), "no-such-directory-public.json")
DIRECTORY_REF = "directorydirectorydi"


class State:
    def __init__(self):
        self.status = 200
        self.requests = []
        # فحص الدليل: ما تعيده الدوال والجداول بالمفتاح العام.
        self.list = [{"id": "1", "name": "مدرسة النور"}]
        self.resolve = (200, [])
        self.register_as_anon = 403
        self.table_as_anon = 401


def make_handler(state):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, status, payload):
            raw = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            state.requests.append((self.path, {}, None))
            self.reply(state.table_as_anon, {"message": "permission denied"})

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(length)) if length else None
            state.requests.append(
                (self.path, {k.lower(): v for k, v in self.headers.items()}, body)
            )
            anon = self.headers.get("apikey", "").startswith("sb_publishable_")
            if self.path.endswith("/list_schools"):
                self.reply(200, state.list)
            elif self.path.endswith("/resolve_school"):
                self.reply(*state.resolve)
            elif self.path.endswith("/register_school") and anon:
                self.reply(state.register_as_anon, {"message": "permission denied"})
            elif state.status == 200:
                self.reply(200, "6b1d1c2e-0000-4000-8000-000000000001")
            else:
                self.reply(state.status, {"message": "denied"})

    return Handler


class DirectoryRegisterTest(unittest.TestCase):
    def setUp(self):
        self.state = State()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.state))
        threading.Thread(
            target=self.server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True
        ).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.env_file = tempfile.NamedTemporaryFile("w+", delete=False, suffix=".env")
        self.env_file.close()
        self.addCleanup(os.unlink, self.env_file.name)

    def environ(self, **overrides):
        values = {
            "DIRECTORY_URL": f"http://127.0.0.1:{self.server.server_address[1]}",
            "DIRECTORY_SERVICE_KEY": SERVICE_KEY,
            "SCHOOL_SLUG": "alnour",
            "SCHOOL_NAME": "مدرسة النور",
            "SUPABASE_URL": "https://abcdefghijklmnopqrst.supabase.co",
            "SUPABASE_ANON_KEY": SCHOOL_KEY,
            "OWNER_PHONE": "0550123456",
            "GITHUB_ENV": self.env_file.name,
            "DIRECTORY_PUBLIC_FILE": NO_PUBLIC_FILE,
        }
        values.update(overrides)
        return values

    def run_main(self, environ):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = dr.main(["directory_register.py", "register"], environ)
        return code, out.getvalue()

    def exported_key(self):
        with open(self.env_file.name, encoding="utf-8") as f:
            match = re.search(r"^DIRECTORY_REGISTER_KEY=([0-9a-f]{64})$", f.read(), re.M)
        return match.group(1) if match else None

    def test_registers_the_school_and_exports_a_fresh_key(self):
        code, output = self.run_main(self.environ())
        self.assertEqual(code, 0, output)
        path, headers, body = self.state.requests[0]
        self.assertEqual(path, "/rest/v1/rpc/register_school")
        self.assertEqual(headers["apikey"], SERVICE_KEY)
        self.assertNotIn("authorization", headers, "المفتاح الجديد ليس JWT")
        self.assertEqual(
            {k: v for k, v in body.items() if k != "p_register_key"},
            {
                "p_slug": "alnour",
                "p_name": "مدرسة النور",
                "p_url": "https://abcdefghijklmnopqrst.supabase.co",
                "p_key": SCHOOL_KEY,
                "p_listed": True,
                "p_owner_phone": "0550123456",
            },
        )
        key = self.exported_key()
        self.assertIsNotNone(key)
        self.assertEqual(body["p_register_key"], key)
        self.assertIn(f"::add-mask::{key}", output)

    def test_every_run_issues_a_different_key(self):
        self.run_main(self.environ())
        first = self.state.requests[0][2]["p_register_key"]
        self.run_main(self.environ())
        self.assertNotEqual(self.state.requests[1][2]["p_register_key"], first)

    def test_legacy_service_role_jwt_goes_in_both_headers(self):
        code, _ = self.run_main(self.environ(DIRECTORY_SERVICE_KEY=SERVICE_ROLE_JWT))
        self.assertEqual(code, 0)
        headers = self.state.requests[0][1]
        self.assertEqual(headers["apikey"], SERVICE_ROLE_JWT)
        self.assertEqual(headers["authorization"], f"Bearer {SERVICE_ROLE_JWT}")

    def test_unlisted_school_and_missing_phone(self):
        code, _ = self.run_main(self.environ(SCHOOL_LISTED="false", OWNER_PHONE=""))
        self.assertEqual(code, 0)
        body = self.state.requests[0][2]
        self.assertIs(body["p_listed"], False)
        self.assertIsNone(body["p_owner_phone"])

    def test_missing_name_falls_back_to_the_slug_with_a_warning(self):
        code, output = self.run_main(self.environ(SCHOOL_NAME=""))
        self.assertEqual(code, 0)
        self.assertEqual(self.state.requests[0][2]["p_name"], "alnour")
        self.assertIn("::warning title=directory-register::", output)

    def test_without_a_directory_nothing_happens(self):
        code, output = self.run_main(self.environ(DIRECTORY_URL=""))
        self.assertEqual(code, 0)
        self.assertEqual(self.state.requests, [])
        self.assertIsNone(self.exported_key())
        self.assertIn("لم تُسجَّل المدرسة", output)

    def test_misconfiguration_is_an_error_before_any_request(self):
        cases = {
            "missing service key": {"DIRECTORY_SERVICE_KEY": ""},
            "publishable key": {"DIRECTORY_SERVICE_KEY": "sb_publishable_oops"},
            "uppercase slug": {"SCHOOL_SLUG": "AlNour"},
            "underscore slug": {"SCHOOL_SLUG": "al_nour"},
            "missing school url": {"SUPABASE_URL": ""},
            "missing school key": {"SUPABASE_ANON_KEY": ""},
        }
        for label, overrides in cases.items():
            with self.subTest(label):
                code, output = self.run_main(self.environ(**overrides))
                self.assertEqual(code, 1, output)
                self.assertIn("::error title=directory-register::", output)
        self.assertEqual(self.state.requests, [])
        self.assertIsNone(self.exported_key())

    def test_rejected_key_and_missing_function_have_clear_messages(self):
        self.state.status = 401
        code, output = self.run_main(self.environ())
        self.assertEqual(code, 1)
        self.assertIn("DIRECTORY_SERVICE_KEY", output)
        self.state.status = 404
        code, output = self.run_main(self.environ())
        self.assertEqual(code, 1)
        self.assertIn("directory-deploy", output)
        self.state.status = 500
        code, output = self.run_main(self.environ())
        self.assertEqual(code, 1)
        self.assertIsNone(self.exported_key(), "لا يُصدَّر مفتاح لتسجيل فاشل")

    def test_no_secret_is_printed(self):
        _, output = self.run_main(self.environ())
        key = self.exported_key()
        printed = output.replace(f"::add-mask::{key}", "")
        self.assertNotIn(SERVICE_KEY, output)
        self.assertNotIn(key, printed)

    def test_the_demo_school_gets_its_default_name_without_a_warning(self):
        code, output = self.run_main(self.environ(SCHOOL_SLUG="demo", SCHOOL_NAME=""))
        self.assertEqual(code, 0, output)
        self.assertEqual(self.state.requests[0][2]["p_name"], "مدرسة العرض التجريبية")
        self.assertNotIn("::warning", output)

    def test_an_explicit_school_name_wins_over_the_default(self):
        self.run_main(self.environ(SCHOOL_SLUG="demo", SCHOOL_NAME="مدرستي"))
        self.assertEqual(self.state.requests[0][2]["p_name"], "مدرستي")

    def test_public_values_are_exported_for_the_next_steps_when_known(self):
        self.run_main(self.environ(DIRECTORY_ANON_KEY="sb_publishable_directory-public"))
        with open(self.env_file.name, encoding="utf-8") as f:
            content = f.read()
        self.assertIn(f"DIRECTORY_URL=http://127.0.0.1:{self.server.server_address[1]}", content)
        self.assertIn("DIRECTORY_ANON_KEY=sb_publishable_directory-public", content)

    def test_public_values_are_not_exported_when_the_key_is_unknown(self):
        self.run_main(self.environ())
        with open(self.env_file.name, encoding="utf-8") as f:
            self.assertNotIn("DIRECTORY_URL=", f.read())

    def test_usage(self):
        out = io.StringIO()
        with contextlib.redirect_stderr(out):
            self.assertEqual(dr.main(["directory_register.py"], {}), 2)
            self.assertEqual(dr.main(["directory_register.py", "other"], {}), 2)

    def verify_environ(self, **overrides):
        values = {
            "DIRECTORY_URL": f"http://127.0.0.1:{self.server.server_address[1]}",
            "DIRECTORY_ANON_KEY": "sb_publishable_directory-public",
        }
        values.update(overrides)
        return values

    def run_verify(self, environ):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = dr.main(["directory_register.py", "verify"], environ)
        return code, out.getvalue()

    def test_verify_passes_on_a_correctly_closed_directory(self):
        code, output = self.run_verify(self.verify_environ())
        self.assertEqual(code, 0, output)
        self.assertIn("::notice title=directory-verify::", output)
        self.assertIn("1 مدرسة معلنة", output)

    def test_verify_fails_when_registration_is_open_to_the_public_key(self):
        self.state.register_as_anon = 200
        code, output = self.run_verify(self.verify_environ())
        self.assertEqual(code, 1)
        self.assertIn("تسجيل المدارس مفتوح", output)

    def test_verify_fails_when_a_table_is_readable(self):
        self.state.table_as_anon = 200
        code, output = self.run_verify(self.verify_environ())
        self.assertEqual(code, 1)
        self.assertIn("schools", output)

    def test_verify_fails_when_the_functions_are_missing_or_wrong(self):
        self.state.list = {"message": "not found"}
        code, output = self.run_verify(self.verify_environ())
        self.assertEqual(code, 1)
        self.assertIn("list_schools", output)
        self.state.list = []
        self.state.resolve = (200, [{"name": "x"}])
        code, output = self.run_verify(self.verify_environ())
        self.assertEqual(code, 1)
        self.assertIn("resolve_school", output)

    def test_verify_refuses_a_secret_key_and_missing_values(self):
        for overrides in (
            {"DIRECTORY_ANON_KEY": "sb_secret_oops"},
            {"DIRECTORY_ANON_KEY": ""},
            {"DIRECTORY_URL": ""},
        ):
            code, output = self.run_verify(self.verify_environ(**overrides))
            self.assertEqual(code, 1, overrides)
            self.assertIn("::error title=directory-verify::", output)
        self.assertEqual(self.state.requests, [])


class PublicConfigTest(unittest.TestCase):
    def file_with(self, content):
        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".json", encoding="utf-8") as f:
            f.write(content)
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_variables_win_over_the_file_and_are_not_mixed(self):
        good = self.file_with(json.dumps({"url": f"https://{DIRECTORY_REF}.supabase.co", "anon_key": "sb_publishable_file"}))
        self.assertEqual(
            dr.public_config({"DIRECTORY_URL": "https://zzzzzzzzzzzzzzzzzzzz.supabase.co/", "DIRECTORY_ANON_KEY": "sb_publishable_var", "DIRECTORY_PUBLIC_FILE": good}),
            ("https://zzzzzzzzzzzzzzzzzzzz.supabase.co", "sb_publishable_var"),
        )
        # متغيّر واحد يكفي ليُعدّ الإعداد من البيئة (دون خلط بالملف).
        self.assertEqual(
            dr.public_config({"DIRECTORY_URL": "https://zzzzzzzzzzzzzzzzzzzz.supabase.co", "DIRECTORY_PUBLIC_FILE": good}),
            ("https://zzzzzzzzzzzzzzzzzzzz.supabase.co", ""),
        )

    def test_the_build_name_of_the_key_variable_is_accepted(self):
        self.assertEqual(
            dr.public_config({"DIRECTORY_URL": "https://zzzzzzzzzzzzzzzzzzzz.supabase.co", "DIRECTORY_KEY": "sb_publishable_build"}),
            ("https://zzzzzzzzzzzzzzzzzzzz.supabase.co", "sb_publishable_build"),
        )

    def test_the_file_is_used_without_variables(self):
        good = self.file_with(json.dumps({"url": f"https://{DIRECTORY_REF}.supabase.co", "anon_key": "sb_publishable_file"}))
        self.assertEqual(
            dr.public_config({"DIRECTORY_PUBLIC_FILE": good}),
            (f"https://{DIRECTORY_REF}.supabase.co", "sb_publishable_file"),
        )

    def test_no_file_and_no_variables_means_no_directory(self):
        self.assertEqual(dr.public_config({"DIRECTORY_PUBLIC_FILE": NO_PUBLIC_FILE}), ("", ""))

    def test_the_committed_file_is_valid_when_present(self):
        if not os.path.exists(dr.PUBLIC_FILE):
            self.skipTest("directory/public.json لم يُنشأ بعد")
        url, key = dr.public_config({})
        self.assertRegex(url, r"^https://[a-z]{20}\.supabase\.co$")
        self.assertTrue(key.startswith("sb_publishable_"))


class ServiceKeyTest(unittest.TestCase):
    """مفتاح الدليل السرّي يُجلب برمز Supabase الشخصي بدل حفظه في أسرار المستودع."""

    def setUp(self):
        self.calls = []
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                outer.calls.append((self.path, self.headers.get("Authorization")))
                keys = outer.keys
                status = outer.status
                raw = json.dumps(keys if status == 200 else {"message": "denied"}).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

        self.keys = [
            {"type": "publishable", "name": "default", "api_key": "sb_publishable_x"},
            {"type": "secret", "name": "default", "api_key": SERVICE_KEY},
        ]
        self.status = 200
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.url = f"https://{DIRECTORY_REF}.supabase.co"

    def environ(self, **overrides):
        values = {"SUPABASE_ACCESS_TOKEN": "sbp_token", "SUPABASE_API_BASE": self.base}
        values.update(overrides)
        return values

    def test_the_key_is_fetched_with_the_token_for_the_directory_project(self):
        key = dr.service_key_for(self.environ(), self.url)
        self.assertEqual(key, SERVICE_KEY)
        path, auth = self.calls[0]
        self.assertTrue(path.startswith(f"/v1/projects/{DIRECTORY_REF}/api-keys"))
        self.assertEqual(auth, "Bearer sbp_token")

    def test_a_key_in_the_environment_is_used_without_any_request(self):
        self.assertEqual(dr.service_key_for(self.environ(DIRECTORY_SERVICE_KEY="sb_secret_env"), self.url), "sb_secret_env")
        self.assertEqual(self.calls, [])

    def test_without_a_token_or_for_another_kind_of_url_nothing_is_fetched(self):
        self.assertEqual(dr.service_key_for({}, self.url), "")
        self.assertEqual(dr.service_key_for(self.environ(), "http://127.0.0.1:9999"), "")
        self.assertEqual(self.calls, [])

    def test_a_token_without_permission_is_reported(self):
        self.status = 403
        with self.assertRaises(dr.sb.ApiError):
            dr.service_key_for(self.environ(), self.url)


if __name__ == "__main__":
    unittest.main()
