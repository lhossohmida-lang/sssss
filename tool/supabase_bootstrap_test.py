"""اختبارات supabase_bootstrap.py على خادم وهمي محلي (Management API وAuth وREST)."""

import contextlib
import io
import json
import os
import sys
import threading
import unittest
import urllib.parse
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

            if path == f"/v1/projects/{REF}" and method == "GET":
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
                if method == "POST":
                    if not admin:
                        return self.send(401, {"message": "bad key"})
                    row = self.body()
                    if any(r["email"] == row["email"] for r in state.rows):
                        return self.send(409, {"message": "duplicate"})
                    state.rows.append(row)
                    return self.send(201)
                if "id" in query:
                    if not admin:
                        return self.send(401, {"message": "bad key"})
                    wanted = query["id"][0].removeprefix("eq.")
                    return self.send(200, [{"id": r["id"]} for r in state.rows if r["id"] == wanted])
                bearer = self.headers.get("Authorization", "")
                if self.headers.get("apikey") == ANON and bearer.startswith("Bearer user-token-"):
                    return self.send(200, [{"id": r["id"], "role": r["role"]} for r in state.rows])
                return self.send(401, {"message": "no session"})
            self.send(404, {"message": "unknown"})

        def do_GET(self):
            self.handle_any("GET")

        def do_POST(self):
            self.handle_any("POST")

        def do_PATCH(self):
            self.handle_any("PATCH")

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

    def test_bad_token_is_reported(self):
        bad = sb.Config(**{**self.config.__dict__, "token": "sbp_wrong"})
        with self.assertRaisesRegex(sb.ApiError, "مرفوض"):
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


if __name__ == "__main__":
    unittest.main()
