"""اختبارات supabase_bootstrap.py على خادم وهمي محلي (Management API وAuth وREST)."""

import contextlib
import io
import json
import os
import sys
import threading
import unittest
import urllib.parse
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import supabase_bootstrap as sb  # noqa: E402

REF = "abcdefghijklmnopqrst"
TOKEN = "sbp_" + "t" * 40
SECRET = "sb_secret_FAKE-SECRET-VALUE"
ANON = "sb_publishable_FAKE-PUBLIC"
PASSWORD = "Owner-Sentinel-Pass-1"
SERVICE_ROLE_JWT = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature"


class State:
    def __init__(self):
        self.status = "ACTIVE_HEALTHY"
        self.project_code = 200
        self.projects = [{"id": REF, "name": "school"}]
        self.keys_status = 200
        self.keys = [
            {"type": "publishable", "name": "default", "api_key": ANON},
            {"type": "secret", "name": "default", "api_key": SECRET},
        ]
        self.secret = SECRET
        self.patches = []
        self.users = {}  # email -> {"id", "password"}
        self.rows = []
        self.requests = []
        self.fail_rows = False
        self.push = None
        self.push_status = 204
        self.min_password = 6


def make_handler(state):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def send(self, status, payload=None):
            raw = b"" if payload is None else json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def body(self):
            length = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(length)) if length else None

        def handle_any(self, method):
            url = urllib.parse.urlparse(self.path)
            query = urllib.parse.parse_qs(url.query)
            path = url.path
            state.requests.append((method, path))
            management = self.headers.get("Authorization") == f"Bearer {TOKEN}"
            admin = self.headers.get("apikey") == state.secret

            if path == "/v1/projects" and method == "GET":
                return self.send(200, state.projects) if management else self.send(401, {"message": "bad"})
            if path == f"/v1/projects/{REF}" and method == "GET":
                if management and state.project_code != 200:
                    return self.send(state.project_code, {"message": "forbidden"})
                return self.send(200, {"status": state.status}) if management else self.send(401, {"message": "bad"})
            if path == f"/v1/projects/{REF}/api-keys" and method == "GET":
                if not management:
                    return self.send(401, {"message": "bad"})
                if state.keys_status != 200:
                    return self.send(state.keys_status, {"message": "forbidden"})
                return self.send(200, state.keys)
            if path == f"/v1/projects/{REF}/config/auth" and method == "PATCH":
                if not management:
                    return self.send(401, {"message": "bad"})
                state.patches.append(self.body())
                return self.send(200, {})

            if path.startswith("/auth/v1/admin/users/") and method == "PUT":
                if not admin:
                    return self.send(401, {"message": "bad key"})
                uid = path.rsplit("/", 1)[1]
                data = self.body()
                for email, user in state.users.items():
                    if user["id"] == uid:
                        if len(data.get("password", "")) < state.min_password:
                            return self.send(422, {"error_code": "weak_password", "msg": "weak"})
                        user["password"] = data["password"]
                        return self.send(200, {"id": uid, "email": email})
                return self.send(404, {"error_code": "user_not_found", "msg": "none"})

            if path.startswith("/auth/v1/admin/users/") and method == "DELETE":
                if not admin:
                    return self.send(401, {"message": "bad key"})
                uid = path.rsplit("/", 1)[1]
                for email, user in list(state.users.items()):
                    if user["id"] == uid:
                        del state.users[email]
                return self.send(200, {})

            if path == "/auth/v1/admin/users":
                if not admin:
                    return self.send(401, {"message": "bad key"})
                if method == "POST":
                    data = self.body()
                    email = data["email"]
                    if email in state.users:
                        return self.send(422, {"error_code": "email_exists", "msg": "exists"})
                    state.users[email] = {"id": f"uid-{len(state.users) + 1}", "password": data["password"]}
                    return self.send(200, {"id": state.users[email]["id"], "email": email})
                return self.send(
                    200, {"users": [{"id": u["id"], "email": e} for e, u in state.users.items()]}
                )

            if path == "/auth/v1/token" and method == "POST":
                data = self.body()
                user = state.users.get(data["email"])
                if self.headers.get("apikey") == ANON and user and user["password"] == data["password"]:
                    return self.send(200, {"access_token": f"user-token-{user['id']}"})
                return self.send(400, {"error_code": "invalid_credentials", "msg": "Invalid login"})

            if path == "/rest/v1/user_accounts":
                if method == "DELETE":
                    if not admin:
                        return self.send(401, {"message": "bad key"})
                    wanted = query["id"][0].removeprefix("eq.")
                    state.rows = [r for r in state.rows if r["id"] != wanted]
                    return self.send(204)
                if method == "POST":
                    if not admin:
                        return self.send(401, {"message": "bad key"})
                    if state.fail_rows:
                        return self.send(500, {"message": "boom"})
                    row = self.body()
                    if any(r["email"] == row["email"] for r in state.rows):
                        return self.send(409, {"message": "duplicate"})
                    state.rows.append(row)
                    return self.send(201)
                if method == "PATCH":
                    if not admin:
                        return self.send(401, {"message": "bad key"})
                    wanted = query["id"][0].removeprefix("eq.")
                    changes = self.body()
                    for r in state.rows:
                        if r["id"] == wanted:
                            r.update(changes)
                    return self.send(204)
                if "id" in query:
                    if not admin:
                        return self.send(401, {"message": "bad key"})
                    wanted = query["id"][0].removeprefix("eq.")
                    return self.send(200, [{"id": r["id"]} for r in state.rows if r["id"] == wanted])
                bearer = self.headers.get("Authorization", "")
                if self.headers.get("apikey") == ANON and bearer.startswith("Bearer user-token-"):
                    return self.send(200, [{"id": r["id"], "role": r["role"]} for r in state.rows])
                return self.send(401, {"message": "no session"})
            if path == "/rest/v1/rpc/set_push_config" and method == "POST":
                if not admin:
                    return self.send(401, {"message": "bad key"})
                if state.push_status != 204:
                    return self.send(state.push_status, {"message": "boom"})
                state.push = self.body()
                return self.send(204)
            self.send(404, {"message": "unknown"})

        def do_GET(self):
            self.handle_any("GET")

        def do_POST(self):
            self.handle_any("POST")

        def do_PATCH(self):
            self.handle_any("PATCH")

        def do_PUT(self):
            self.handle_any("PUT")

        def do_DELETE(self):
            self.handle_any("DELETE")

    return Handler


class FakeServerCase(unittest.TestCase):
    def setUp(self):
        self.state = State()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.state))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.config = sb.Config(
            token=TOKEN,
            ref=REF,
            url=self.base,
            anon_key=ANON,
            phone="0550000000",
            password=PASSWORD,
            api_base=self.base,
        )
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def environ(self, **overrides):
        env = {
            "SUPABASE_ACCESS_TOKEN": TOKEN,
            "SUPABASE_PROJECT_REF": REF,
            "SUPABASE_URL": self.base,
            "SUPABASE_ANON_KEY": ANON,
            "OWNER_PHONE": "0550000000",
            "OWNER_INITIAL_PASSWORD": PASSWORD,
            "SUPABASE_API_BASE": self.base,
        }
        env.update(overrides)
        return env


class Flow(FakeServerCase):
    def test_first_run_creates_the_owner_and_passes_the_smoke_test(self):
        out = sb.Bootstrap(self.config).bootstrap()
        self.assertEqual(out[-1], "signup=disabled owner=created account-row=created smoke=ok")
        self.assertEqual(self.state.patches, [{"disable_signup": True}])
        self.assertEqual(len(self.state.users), 1)
        (row,) = self.state.rows
        self.assertEqual(row["role"], "owner")
        self.assertEqual(row["email"], "0550000000@school.local")
        self.assertTrue(row["must_change_password"])
        self.assertIsNone(row["entity_id"])
        self.assertEqual(row["id"], self.state.users["0550000000@school.local"]["id"])

    def test_second_run_changes_nothing(self):
        sb.Bootstrap(self.config).bootstrap()
        out = sb.Bootstrap(self.config).bootstrap()
        self.assertEqual(out[-1], "signup=disabled owner=existed account-row=existed smoke=ok")
        self.assertEqual((len(self.state.users), len(self.state.rows)), (1, 1))

    def test_owner_who_changed_the_password_is_left_alone(self):
        sb.Bootstrap(self.config).bootstrap()
        self.state.users["0550000000@school.local"]["password"] = "changed-by-owner"
        out = sb.Bootstrap(self.config).bootstrap()
        self.assertTrue(out[-1].endswith("smoke=skipped"))
        self.assertEqual(self.state.users["0550000000@school.local"]["password"], "changed-by-owner")

    def test_existing_auth_user_without_an_account_row_gets_one(self):
        self.state.users["0550000000@school.local"] = {"id": "uid-9", "password": PASSWORD}
        out = sb.Bootstrap(self.config).bootstrap()
        self.assertEqual(out[-1], "signup=disabled owner=existed account-row=created smoke=ok")
        self.assertEqual(self.state.rows[0]["id"], "uid-9")

    def test_legacy_service_role_key_is_used_when_there_is_no_secret_key(self):
        self.state.keys = [{"type": "legacy", "name": "service_role", "api_key": SERVICE_ROLE_JWT}]
        self.state.secret = SERVICE_ROLE_JWT
        out = sb.Bootstrap(self.config).bootstrap()
        self.assertTrue(out[-1].endswith("smoke=ok"))


class Refusals(FakeServerCase):
    def test_paused_project_is_refused_before_anything_changes(self):
        self.state.status = "INACTIVE"
        with self.assertRaisesRegex(sb.ApiError, "ليس نشطاً"):
            sb.Bootstrap(self.config).bootstrap()
        self.assertEqual((self.state.patches, self.state.users), ([], {}))

    def test_missing_key_permission_has_a_clear_message(self):
        self.state.keys_status = 403
        with self.assertRaisesRegex(sb.ApiError, "API Key Secrets"):
            sb.Bootstrap(self.config).verify()

    def test_a_token_without_access_names_the_projects_it_does_see(self):
        self.state.project_code = 403
        self.state.projects = [{"id": "smlygpzdndtousbngdod", "name": "directory"}]
        with self.assertRaisesRegex(sb.ApiError, "Project Settings.*directory \\(smlygp…\\)") as raised:
            sb.Bootstrap(self.config).verify()
        self.assertNotIn(TOKEN, str(raised.exception), "لا تُذكر قيمة الرمز في سجل علني")

    def test_a_token_that_sees_nothing_says_so(self):
        self.state.project_code = 404
        self.state.projects = []
        with self.assertRaisesRegex(sb.ApiError, "لا يصل إليه الرمز.*لا شيء"):
            sb.Bootstrap(self.config).verify()

    def test_bad_token_is_reported(self):
        bad = sb.Config(**{**self.config.__dict__, "token": "sbp_wrong"})
        with self.assertRaisesRegex(sb.ApiError, "مرفوض"):
            sb.Bootstrap(bad).verify()

    def test_the_token_hint_describes_the_value_without_revealing_it(self):
        cases = {
            "": "فارغ",
            "sbp_fc868b8a26f0********274b": "نجوم",
            "wrong": "لا تبدأ بـ sbp_",
            "sbp_ab cd": "فراغ",
            "sbp_" + "a" * 40: "شكل القيمة المحفوظة سليم",
        }
        for token, expected in cases.items():
            hint = sb.token_hint(token)
            self.assertIn(expected, hint, token)
            if token:
                self.assertNotIn(token, hint, "لا تُذكر قيمة الرمز في سجل علني")

    def test_a_pasted_token_loses_its_surrounding_whitespace(self):
        self.assertEqual(sb.Config.from_env({"SUPABASE_ACCESS_TOKEN": "  sbp_abc\n"}).token, "sbp_abc")

    def test_a_bad_token_message_carries_the_hint(self):
        bad = sb.Config(**{**self.config.__dict__, "token": "sbp_not*real"})
        with self.assertRaisesRegex(sb.ApiError, "نجوم"):
            sb.Bootstrap(bad).verify()

    def test_masked_secret_key_is_rejected(self):
        self.state.keys = [{"type": "secret", "name": "default", "api_key": "sb_secret_ab••••••"}]
        with self.assertRaisesRegex(sb.ApiError, "مخفي"):
            sb.Bootstrap(self.config).verify()

    def test_no_secret_key_at_all(self):
        self.state.keys = [{"type": "publishable", "name": "default", "api_key": ANON}]
        with self.assertRaisesRegex(sb.ApiError, "لا يوجد مفتاح سرّي"):
            sb.Bootstrap(self.config).verify()

    def test_unreachable_server(self):
        down = sb.Config(**{**self.config.__dict__, "api_base": "http://127.0.0.1:9"})
        with self.assertRaisesRegex(sb.ApiError, "تعذّر الاتصال"):
            sb.Bootstrap(down).verify()


class TempOwner(FakeServerCase):
    def test_create_makes_a_working_owner_account(self):
        bootstrap = sb.Bootstrap(self.config)
        self.assertEqual(bootstrap.temp_owner_create(), ["temp-owner=created"])
        exports = bootstrap.exports
        email = exports["CI_OWNER_EMAIL"]
        self.assertTrue(email.startswith("ci-owner-") and email.endswith("@school.local"))
        self.assertEqual(self.state.users[email]["password"], exports["CI_OWNER_PASSWORD"])
        (row,) = self.state.rows
        self.assertEqual((row["id"], row["role"]), (exports["CI_OWNER_ID"], "owner"))
        self.assertFalse(row["must_change_password"])

    def test_delete_removes_every_temp_owner_and_keeps_the_real_one(self):
        sb.Bootstrap(self.config).bootstrap()
        for _ in range(2):
            sb.Bootstrap(self.config).temp_owner_create()
        self.assertEqual((len(self.state.users), len(self.state.rows)), (3, 3))
        self.assertEqual(sb.Bootstrap(self.config).temp_owner_delete(), ["temp-owners-removed=2"])
        self.assertEqual(list(self.state.users), ["0550000000@school.local"])
        self.assertEqual([r["email"] for r in self.state.rows], ["0550000000@school.local"])

    def test_a_failed_row_insert_leaves_no_orphan_user(self):
        self.state.fail_rows = True
        with self.assertRaisesRegex(sb.ApiError, "صف مالك الفحوص"):
            sb.Bootstrap(self.config).temp_owner_create()
        self.assertEqual(self.state.users, {})

    def test_main_exports_to_github_env_and_masks_only_the_password(self):
        env_file = os.path.join(os.environ.get("TEMP", "/tmp"), f"gh-env-{uuid.uuid4().hex}")
        self.addCleanup(lambda: os.path.exists(env_file) and os.remove(env_file))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = sb.main(["x", "temp-owner-create"], {**self.environ(), "GITHUB_ENV": env_file})
        self.assertEqual(code, 0)
        with open(env_file, encoding="utf-8") as f:
            written = dict(line.split("=", 1) for line in f.read().splitlines())
        self.assertEqual(sorted(written), ["CI_OWNER_EMAIL", "CI_OWNER_ID", "CI_OWNER_PASSWORD"])
        password = written["CI_OWNER_PASSWORD"]
        masked = [line for line in out.getvalue().splitlines() if password in line]
        self.assertEqual(masked, [f"::add-mask::{password}"])
        for secret in (TOKEN, SECRET, ANON):
            self.assertNotIn(secret, out.getvalue())

    def test_delete_command_needs_no_owner_credentials(self):
        env = {k: v for k, v in self.environ().items() if k in ("SUPABASE_ACCESS_TOKEN", "SUPABASE_PROJECT_REF", "SUPABASE_URL", "SUPABASE_API_BASE")}
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = sb.main(["x", "temp-owner-delete"], env)
        self.assertEqual(code, 0)
        self.assertIn("temp-owners-removed=0", out.getvalue())


class Main(FakeServerCase):
    def run_main(self, command, environ):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = sb.main(["x", command], environ)
        return code, out.getvalue()

    def test_success_output_has_no_secret_value(self):
        code, output = self.run_main("bootstrap", self.environ())
        self.assertEqual(code, 0)
        self.assertIn("::notice title=supabase-bootstrap::", output)
        for secret in (TOKEN, SECRET, ANON, PASSWORD):
            self.assertNotIn(secret, output)

    def test_failure_output_has_no_secret_value(self):
        self.state.keys_status = 403
        code, output = self.run_main("bootstrap", self.environ())
        self.assertEqual(code, 1)
        self.assertIn("::error title=supabase-bootstrap::", output)
        for secret in (TOKEN, SECRET, ANON, PASSWORD):
            self.assertNotIn(secret, output)

    def test_missing_variables_are_listed_by_name_only(self):
        env = self.environ()
        del env["OWNER_INITIAL_PASSWORD"]
        code, output = self.run_main("bootstrap", env)
        self.assertEqual(code, 1)
        self.assertIn("OWNER_INITIAL_PASSWORD", output)
        self.assertNotIn(TOKEN, output)

    def test_verify_needs_only_the_token_and_the_project(self):
        env = {k: v for k, v in self.environ().items() if k in ("SUPABASE_ACCESS_TOKEN", "SUPABASE_PROJECT_REF", "SUPABASE_API_BASE")}
        code, output = self.run_main("verify", env)
        self.assertEqual(code, 0)
        self.assertIn("project=ACTIVE_HEALTHY token=ok", output)



class PushConfig(FakeServerCase):
    PUSH_SECRET = "p" * 64

    def run_main(self, **overrides):
        env = self.environ(PUSH_SECRET=self.PUSH_SECRET, **overrides)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = sb.main(["supabase_bootstrap.py", "push-config"], env)
        return status, out.getvalue()

    def test_sends_the_function_url_and_the_shared_secret_with_the_secret_key(self):
        status, out = self.run_main()
        self.assertEqual(status, 0, out)
        self.assertEqual(
            self.state.push,
            {"p_url": f"{self.base}/functions/v1/send-push", "p_secret": self.PUSH_SECRET},
        )
        self.assertIn("push-config=ok", out)
        self.assertNotIn(self.PUSH_SECRET, out)
        self.assertNotIn(SECRET, out)

    def test_a_missing_secret_is_named_and_nothing_is_sent(self):
        env = self.environ()
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = sb.main(["supabase_bootstrap.py", "push-config"], env)
        self.assertEqual(status, 1)
        self.assertIn("PUSH_SECRET", out.getvalue())
        self.assertIsNone(self.state.push)

    def test_a_server_refusal_is_an_error_without_the_secret(self):
        self.state.push_status = 500
        status, out = self.run_main()
        self.assertEqual(status, 1)
        self.assertIn("::error", out)
        self.assertNotIn(self.PUSH_SECRET, out)


if __name__ == "__main__":
    unittest.main()


class ResetOwnerPassword(FakeServerCase):
    EMAIL = "0550000000@school.local"

    def bootstrap_then_forget(self):
        """مالك أُنشئ ثم لم تعد كلمة سره تطابق السرّ (نُسيت أو غُيّر السرّ)."""
        sb.Bootstrap(self.config).bootstrap()
        self.state.users[self.EMAIL]["password"] = "something-else-entirely"
        self.state.rows[0]["must_change_password"] = False

    def test_reset_sets_the_password_forces_the_change_and_signs_in(self):
        self.bootstrap_then_forget()
        out = sb.Bootstrap(self.config).reset_owner_password()
        self.assertEqual(out[-1], "owner-password=reset must-change=true smoke=ok")
        self.assertEqual(self.state.users[self.EMAIL]["password"], PASSWORD)
        self.assertTrue(self.state.rows[0]["must_change_password"])
        self.assertEqual((len(self.state.users), len(self.state.rows)), (1, 1))

    def test_normal_bootstrap_reports_skipped_for_a_password_that_no_longer_matches(self):
        self.bootstrap_then_forget()
        out = sb.Bootstrap(self.config).bootstrap()
        self.assertTrue(out[-1].endswith("smoke=skipped"), "هذه العلامة تدل على أن السرّ لا يطابق الحساب")

    def test_without_an_owner_nothing_is_created(self):
        with self.assertRaises(sb.ApiError) as raised:
            sb.Bootstrap(self.config).reset_owner_password()
        self.assertIn("غير موجود", str(raised.exception))
        self.assertEqual(self.state.users, {})
        self.assertNotIn(("PUT", "/auth/v1/admin/users/uid-1"), self.state.requests)

    def test_a_missing_account_row_is_created(self):
        self.state.users[self.EMAIL] = {"id": "uid-9", "password": "old-one-here"}
        out = sb.Bootstrap(self.config).reset_owner_password()
        self.assertTrue(out[-1].endswith("smoke=ok"))
        (row,) = self.state.rows
        self.assertEqual((row["id"], row["role"], row["must_change_password"]), ("uid-9", "owner", True))

    def test_a_short_password_is_refused_before_anything_changes(self):
        self.bootstrap_then_forget()
        config = sb.Config(**{**self.config.__dict__, "password": "short"})
        with self.assertRaises(sb.ApiError) as raised:
            sb.Bootstrap(config).reset_owner_password()
        self.assertIn("أقل من 8", str(raised.exception))
        self.assertNotIn("short", str(raised.exception))
        self.assertEqual(self.state.users[self.EMAIL]["password"], "something-else-entirely")

    def test_a_password_the_server_calls_weak_is_reported_without_its_value(self):
        self.bootstrap_then_forget()
        self.state.min_password = 40
        with self.assertRaises(sb.ApiError) as raised:
            sb.Bootstrap(self.config).reset_owner_password()
        self.assertIn("ضعيفة", str(raised.exception))
        self.assertNotIn(PASSWORD, str(raised.exception))

    def test_main_prints_a_notice_without_any_secret_value(self):
        self.bootstrap_then_forget()
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = sb.main(["x", "reset-owner-password"], self.environ())
        self.assertEqual(code, 0)
        self.assertIn("::notice title=supabase-reset-owner-password::", out.getvalue())
        self.assertIn("owner-password=reset", out.getvalue())
        for secret in (TOKEN, SECRET, ANON, PASSWORD):
            self.assertNotIn(secret, out.getvalue())

    def test_main_lists_missing_variables_by_name_only(self):
        env = self.environ()
        del env["OWNER_INITIAL_PASSWORD"]
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = sb.main(["x", "reset-owner-password"], env)
        self.assertEqual(code, 1)
        self.assertIn("OWNER_INITIAL_PASSWORD", out.getvalue())
        self.assertNotIn(TOKEN, out.getvalue())


class WhitespaceInSecrets(FakeServerCase):
    def test_a_trailing_newline_pasted_with_the_password_is_dropped(self):
        config = sb.Config.from_env(self.environ(OWNER_INITIAL_PASSWORD=PASSWORD + chr(10), OWNER_PHONE=" 0550000000 "))
        self.assertEqual((config.password, config.phone), (PASSWORD, "0550000000"))
        out = sb.Bootstrap(config).bootstrap()
        self.assertEqual(self.state.users["0550000000@school.local"]["password"], PASSWORD)
        self.assertTrue(out[-1].endswith("smoke=ok"))
