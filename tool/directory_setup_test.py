"""اختبارات directory_setup.py على Management API ودليل وهميين في خادم محلي واحد."""

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
import directory_setup as ds  # noqa: E402
import supabase_bootstrap as sb  # noqa: E402

TOKEN = "sbp_SENTINEL-PERSONAL-TOKEN"
SCHOOL_REF = "schoolschoolschoolsc"
NEW_REF = "directorydirectorydi"
PUBLISHABLE = "sb_publishable_directory-public-key"
SECRET = "sb_secret_SENTINEL-DIRECTORY-SECRET"
SQL = "create schema if not exists app;\n"


class State:
    def __init__(self):
        self.projects = [
            {
                "ref": SCHOOL_REF,
                "name": "school",
                "organization_slug": "myorg",
                "region": "eu-west-1",
                "status": "ACTIVE_HEALTHY",
            }
        ]
        self.requests = []
        self.created = []
        self.queries = []
        self.restored = []
        # حالات المشروع الجديد المتتابعة عند كل قراءة له.
        self.new_statuses = ["COMING_UP", "COMING_UP", "ACTIVE_HEALTHY"]
        self.query_failures = 0
        self.create_status = 201
        self.keys = [
            {"type": "secret", "name": "default", "api_key": SECRET},
            {"type": "publishable", "name": "default", "api_key": PUBLISHABLE},
        ]
        # ما يراه المفتاح العام من الدليل.
        self.register_as_anon = 403
        self.table_as_anon = 401


def make_handler(state):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, status, payload=None):
            raw = b"" if payload is None else json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def body(self):
            length = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(length)) if length else None

        def authorised(self):
            return self.headers.get("Authorization") == f"Bearer {TOKEN}"

        def route(self, method):
            payload = self.body() if method == "POST" else None
            state.requests.append((method, self.path))
            path = self.path.split("?")[0]
            if path.startswith("/v1/"):
                if not self.authorised():
                    return self.reply(401, {"message": "bad token"})
                if method == "GET" and path == "/v1/projects":
                    return self.reply(200, state.projects)
                if method == "POST" and path == "/v1/projects":
                    state.created.append(payload)
                    if state.create_status not in (200, 201):
                        message = "Forbidden" if state.create_status == 403 else "limit of free projects reached"
                        return self.reply(state.create_status, {"message": message})
                    state.projects.append(
                        {
                            "ref": NEW_REF,
                            "name": payload["name"],
                            "organization_slug": payload["organization_slug"],
                            "region": "eu-west-1",
                            "status": "COMING_UP",
                        }
                    )
                    return self.reply(201, {"ref": NEW_REF, "name": payload["name"], "status": "COMING_UP"})
                match = re.fullmatch(r"/v1/projects/([a-z]+)(/.*)?", path)
                if match:
                    ref, rest = match.group(1), match.group(2) or ""
                    project = next((p for p in state.projects if p["ref"] == ref), None)
                    if project is None:
                        return self.reply(404, {"message": "not found"})
                    if method == "GET" and rest == "":
                        if ref == NEW_REF and state.new_statuses:
                            project["status"] = state.new_statuses.pop(0)
                        return self.reply(200, project)
                    if method == "GET" and rest == "/api-keys":
                        return self.reply(200, state.keys)
                    if method == "POST" and rest == "/database/query":
                        if state.query_failures > 0:
                            state.query_failures -= 1
                            return self.reply(500, {"message": "connection to database not ready"})
                        if "BAD SQL" in payload["query"]:
                            return self.reply(400, {"message": 'syntax error at or near "BAD"'})
                        state.queries.append((ref, payload["query"]))
                        return self.reply(201)
                    if method == "POST" and rest == "/restore":
                        state.restored.append(ref)
                        project["status"] = "ACTIVE_HEALTHY"
                        return self.reply(200, {})
                return self.reply(404, {"message": "unknown"})
            # واجهة الدليل نفسها (rest/v1) كما يراها المفتاح العام.
            if method == "GET":
                return self.reply(state.table_as_anon, {"message": "permission denied"})
            if path.endswith("/list_schools"):
                return self.reply(200, [])
            if path.endswith("/resolve_school"):
                return self.reply(200, [])
            if path.endswith("/register_school"):
                return self.reply(state.register_as_anon, {"message": "permission denied"})
            return self.reply(404, {"message": "unknown"})

        def do_GET(self):
            self.route("GET")

        def do_POST(self):
            self.route("POST")

    return Handler


class DirectorySetupTest(unittest.TestCase):
    def setUp(self):
        self.state = State()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.state))
        threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.slept = []
        self.env_file = tempfile.NamedTemporaryFile("w+", delete=False, suffix=".env")
        self.env_file.close()
        self.addCleanup(os.unlink, self.env_file.name)

    def environ(self, **overrides):
        values = {
            "SUPABASE_ACCESS_TOKEN": TOKEN,
            "SUPABASE_PROJECT_REF": SCHOOL_REF,
            "SUPABASE_API_BASE": self.base,
            "GITHUB_ENV": self.env_file.name,
        }
        values.update(overrides)
        return values

    def hooks(self, **overrides):
        """بيئة main: بلا انتظار حقيقي، وعنوان المشروع هو الخادم الوهمي."""
        return self.environ(
            DIRECTORY_SETUP_POLL="0",
            DIRECTORY_PROJECT_URL_TEMPLATE=self.base,
            **overrides,
        )

    def run_setup(self, **overrides):
        return ds.setup(
            self.environ(),
            sleep=self.slept.append,
            poll=0.5,
            timeout=30,
            migrations=[("0001_directory.sql", SQL)],
            url_for=lambda ref: self.base,
            **overrides,
        )

    def texts(self, notes):
        return " | ".join(text for _, text in notes)

    # ---- الإنشاء

    def test_creates_the_directory_next_to_the_school_and_prepares_it(self):
        notes, public = self.run_setup()
        self.assertEqual(len(self.state.created), 1)
        body = self.state.created[0]
        self.assertEqual(body["name"], "directory")
        self.assertEqual(body["organization_slug"], "myorg", "في منظمة المدرسة نفسها")
        self.assertEqual(body["region_selection"], {"type": "specific", "code": "eu-west-1"})
        self.assertGreaterEqual(len(body["db_pass"]), 24)
        self.assertNotRegex(body["db_pass"], r"[@:/?#%&]", "كلمة سر آمنة في الروابط")
        # انتظر حتى اكتمل التجهيز (قراءتان بحالة COMING_UP).
        self.assertEqual(len(self.slept), 2)
        self.assertEqual(self.state.queries, [(NEW_REF, SQL)])
        self.assertEqual(public, {"url": self.base, "anon_key": PUBLISHABLE})
        text = self.texts(notes)
        self.assertIn("أُنشئ مشروع الدليل", text)
        self.assertIn("الدليل سليم", text)
        self.assertIn("directory-public", text)

    def test_no_secret_or_password_is_ever_printed(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = ds.main(["directory_setup.py", "setup"], self.hooks())
        self.assertEqual(code, 0, out.getvalue())
        body = self.state.created[0]
        for secret in (TOKEN, SECRET, body["db_pass"]):
            self.assertNotIn(secret, out.getvalue())

    def test_an_existing_directory_is_reused_and_not_recreated(self):
        self.state.projects.append(
            {"ref": NEW_REF, "name": "directory", "organization_slug": "myorg", "region": "eu-west-1", "status": "ACTIVE_HEALTHY"}
        )
        self.state.new_statuses = []
        notes, public = self.run_setup()
        self.assertEqual(self.state.created, [], "لا مشروع ثانٍ")
        self.assertEqual(self.slept, [])
        self.assertEqual(self.state.queries, [(NEW_REF, SQL)], "الترحيلات تُطبَّق من جديد (آمنة عند التكرار)")
        self.assertIn("موجود", self.texts(notes))
        self.assertEqual(public["anon_key"], PUBLISHABLE)

    def test_a_paused_directory_is_restored(self):
        self.state.projects.append(
            {"ref": NEW_REF, "name": "directory", "organization_slug": "myorg", "region": "eu-west-1", "status": "INACTIVE"}
        )
        self.state.new_statuses = ["INACTIVE"]
        notes, _ = self.run_setup()
        self.assertEqual(self.state.restored, [NEW_REF])
        self.assertIn("متوقفاً", self.texts(notes))

    def test_an_unknown_region_falls_back_to_the_european_group(self):
        self.state.projects[0]["region"] = "moon-1"
        self.run_setup()
        self.assertEqual(self.state.created[0]["region_selection"], {"type": "smartGroup", "code": "emea"})

    # ---- الترحيل

    def test_a_database_not_ready_yet_is_retried(self):
        self.state.query_failures = 3
        self.run_setup()
        self.assertEqual(self.state.queries, [(NEW_REF, SQL)])
        self.assertGreaterEqual(len(self.slept), 3 + 2)

    def test_a_sql_error_is_not_retried_and_names_the_reason(self):
        with self.assertRaises(sb.ApiError) as raised:
            ds.setup(
                self.environ(),
                sleep=self.slept.append,
                poll=0.5,
                migrations=[("0001_directory.sql", "BAD SQL;")],
                url_for=lambda ref: self.base,
            )
        self.assertIn("syntax error", str(raised.exception))
        self.assertEqual(self.state.queries, [])

    # ---- الأخطاء

    def test_the_free_plan_limit_gives_a_clear_next_step(self):
        self.state.create_status = 402
        with self.assertRaises(sb.ApiError) as raised:
            self.run_setup()
        message = str(raised.exception)
        self.assertIn("limit of free projects", message)
        self.assertIn("مشروعين", message)
        self.assertIn("يدوياً", message)

    def test_a_token_that_cannot_create_projects_is_told_apart_from_the_plan_limit(self):
        # 403: رمز محدود لا يملك إنشاء المشاريع (حدث فعلاً)؛ الحلّ غير حلّ حدّ الخطة المجانية.
        self.state.create_status = 403
        with self.assertRaises(sb.ApiError) as raised:
            self.run_setup()
        message = str(raised.exception)
        self.assertIn("403", message)
        self.assertIn("Forbidden", message)
        self.assertIn("SUPABASE_ACCESS_TOKEN", message)
        self.assertIn("Full access", message)
        self.assertIn("directory", message)
        self.assertIn("school", message, "يذكر المشاريع التي يراها الرمز")
        self.assertNotIn("مشروعين", message, "ليس حدّ الخطة المجانية")

    def test_a_wrong_token_is_reported(self):
        with self.assertRaises(sb.ApiError) as raised:
            ds.setup(
                self.environ(SUPABASE_ACCESS_TOKEN="wrong"),
                sleep=self.slept.append,
                poll=0,
                migrations=[("x.sql", SQL)],
                url_for=lambda ref: self.base,
            )
        self.assertIn("مرفوض", str(raised.exception))
        self.assertIn("sbp_", str(raised.exception), "يدلّ على أن القيمة ليست رمزاً شخصياً")

    def rejected(self, token):
        with self.assertRaises(sb.ApiError) as raised:
            ds.setup(
                self.environ(SUPABASE_ACCESS_TOKEN=token),
                sleep=self.slept.append,
                poll=0,
                migrations=[("x.sql", SQL)],
                url_for=lambda ref: self.base,
            )
        message = str(raised.exception)
        self.assertIn("مرفوض", message)
        self.assertNotIn(token.strip(), message, "السجلات علنية: لا تُذكر قيمة الرمز")
        return message

    def test_a_masked_token_pasted_from_the_list_is_named(self):
        # رمز القائمة المقنَّع (نجوم في وسطه) لا الرمز الكامل: خطأ لصق شائع، وكان سبب فشل فعلي.
        message = self.rejected("sbp_fc868b8a26f0********274b")
        self.assertIn("نجوم", message)
        self.assertIn("Copy", message)

    def test_a_well_formed_but_unknown_token_says_so(self):
        message = self.rejected("sbp_" + "0123456789abcdef" * 2 + "01234567")
        self.assertIn("شكل القيمة المحفوظة سليم", message)
        self.assertIn("أنشئ رمزاً جديداً", message)

    def test_a_token_with_a_space_inside_is_named(self):
        self.assertIn("فراغ", self.rejected("sbp_abc def"))

    def test_an_empty_token_secret_is_named_by_the_missing_input_check(self):
        with self.assertRaises(sb.ApiError) as raised:
            ds.setup(
                self.environ(SUPABASE_ACCESS_TOKEN="  \n"),
                sleep=self.slept.append,
                poll=0,
                migrations=[("x.sql", SQL)],
                url_for=lambda ref: self.base,
            )
        self.assertIn("SUPABASE_ACCESS_TOKEN", str(raised.exception))

    def test_a_token_pasted_with_stray_whitespace_still_works(self):
        # اللصق يترك غالباً سطراً جديداً أو فراغاً حول الرمز.
        notes, public = ds.setup(
            self.environ(SUPABASE_ACCESS_TOKEN=f"  {TOKEN}\n"),
            sleep=self.slept.append,
            poll=0.5,
            timeout=30,
            migrations=[("0001_directory.sql", SQL)],
            url_for=lambda ref: self.base,
        )
        self.assertEqual(public["anon_key"], PUBLISHABLE)

    def test_missing_inputs_are_named(self):
        with self.assertRaises(sb.ApiError) as raised:
            ds.setup({"SUPABASE_API_BASE": self.base}, migrations=[("x.sql", SQL)])
        self.assertIn("SUPABASE_ACCESS_TOKEN", str(raised.exception))
        self.assertIn("SUPABASE_PROJECT_REF", str(raised.exception))

    def test_a_failed_project_stops_the_wait(self):
        self.state.new_statuses = ["COMING_UP", "INIT_FAILED"]
        with self.assertRaises(sb.ApiError) as raised:
            self.run_setup()
        self.assertIn("INIT_FAILED", str(raised.exception))

    def test_a_directory_that_never_gets_ready_times_out(self):
        self.state.new_statuses = ["COMING_UP"] * 500
        with self.assertRaises(sb.ApiError) as raised:
            ds.setup(
                self.environ(),
                sleep=self.slept.append,
                poll=10,
                timeout=30,
                migrations=[("x.sql", SQL)],
                url_for=lambda ref: self.base,
            )
        self.assertIn("مهلة", str(raised.exception))
        self.assertEqual(self.state.queries, [])

    def test_no_publishable_key_is_an_error(self):
        self.state.keys = [{"type": "secret", "name": "default", "api_key": SECRET}]
        with self.assertRaises(sb.ApiError) as raised:
            self.run_setup()
        self.assertIn("Publishable", str(raised.exception))

    def test_a_directory_open_to_the_public_key_fails_the_check(self):
        self.state.register_as_anon = 200
        with self.assertRaises(sb.ApiError) as raised:
            self.run_setup()
        self.assertIn("مفتوح", str(raised.exception))

    # ---- main

    def test_main_prints_the_public_output_under_its_own_title(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = ds.main(["directory_setup.py", "setup"], self.hooks())
        self.assertEqual(code, 0, out.getvalue())
        match = re.search(r"^::notice title=directory-public::(.*)$", out.getvalue(), re.M)
        self.assertTrue(match, out.getvalue())
        public = json.loads(match.group(1))
        self.assertEqual(public["anon_key"], PUBLISHABLE)
        self.assertEqual(public["url"], self.base)

    def test_main_reports_a_failure_as_an_error_annotation(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = ds.main(["directory_setup.py", "setup"], self.environ(SUPABASE_ACCESS_TOKEN="wrong"))
        self.assertEqual(code, 1)
        self.assertIn("::error title=directory-setup::", out.getvalue())

    def test_usage_error(self):
        self.assertEqual(ds.main(["directory_setup.py", "nope"], {}), 2)

    # ---- البناء: الحلّ والتصدير

    def test_the_build_gets_the_values_from_the_public_file(self):
        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".json", encoding="utf-8") as f:
            json.dump({"url": "https://abcdefghijklmnopqrst.supabase.co", "anon_key": PUBLISHABLE}, f)
        self.addCleanup(os.unlink, f.name)
        lines = ds.export_public({"DIRECTORY_PUBLIC_FILE": f.name, "GITHUB_ENV": self.env_file.name})
        self.assertIn("abcdefghijklmnopqrst", lines[0])
        with open(self.env_file.name, encoding="utf-8") as env:
            content = env.read()
        self.assertIn("DIRECTORY_URL=https://abcdefghijklmnopqrst.supabase.co", content)
        self.assertIn(f"DIRECTORY_KEY={PUBLISHABLE}", content)

    def test_repository_variables_win_over_the_file(self):
        ds.export_public(
            {
                "DIRECTORY_URL": "https://zzzzzzzzzzzzzzzzzzzz.supabase.co",
                "DIRECTORY_ANON_KEY": "sb_publishable_override",
                "GITHUB_ENV": self.env_file.name,
            }
        )
        with open(self.env_file.name, encoding="utf-8") as env:
            content = env.read()
        self.assertIn("DIRECTORY_URL=https://zzzzzzzzzzzzzzzzzzzz.supabase.co", content)
        self.assertIn("DIRECTORY_KEY=sb_publishable_override", content)

    def test_without_values_the_build_stays_in_pairing_mode(self):
        lines = ds.export_public({"DIRECTORY_PUBLIC_FILE": os.path.join(tempfile.gettempdir(), "no-such.json"), "GITHUB_ENV": self.env_file.name})
        self.assertIn("رمز الربط", lines[0])
        with open(self.env_file.name, encoding="utf-8") as env:
            self.assertEqual(env.read(), "")

    def test_an_invalid_public_file_is_ignored(self):
        for content in ('{"url": "http://evil.example", "anon_key": "sb_publishable_x"}', '{"url": "https://abcdefghijklmnopqrst.supabase.co", "anon_key": "sb_secret_oops"}', "not json", "[]"):
            with tempfile.NamedTemporaryFile("w", delete=False, suffix=".json", encoding="utf-8") as f:
                f.write(content)
            self.addCleanup(os.unlink, f.name)
            self.assertEqual(dr.public_config({"DIRECTORY_PUBLIC_FILE": f.name}), ("", ""), content)

    def test_the_real_migration_is_found_and_safe_to_repeat(self):
        files = ds.migration_files()
        self.assertTrue(files)
        name, sql = files[0]
        self.assertTrue(name.endswith(".sql"))
        self.assertIn("create schema if not exists app", sql)
        # آمن عند التكرار: لا create table بلا if not exists.
        self.assertEqual(len(re.findall(r"create table (?!if not exists)", sql)), 0)


if __name__ == "__main__":
    unittest.main()
