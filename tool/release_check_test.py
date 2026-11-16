"""اختبارات release_check.py على خادم وهمي محلي لواجهة GitHub."""

import contextlib
import io
import json
import os
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import release_check as rc  # noqa: E402

REPO = "owner/school"
TAG = "preview-7"
TOKEN = "ghs_SENTINEL_TOKEN_VALUE"


def asset(name, **overrides):
    data = {
        "name": name,
        "state": "uploaded",
        "size": 5_000_000,
        "digest": "sha256:" + "ab" * 32,
        "browser_download_url": f"https://github.com/{REPO}/releases/download/{TAG}/{name}",
    }
    data.update(overrides)
    return data


def good_release(**overrides):
    release = {"tag_name": TAG, "draft": False, "prerelease": True, "assets": [asset(n) for n in rc.EXPECTED]}
    release.update(overrides)
    return release


class FakeApi:
    def __init__(self):
        self.responses = []  # (status, body) بالترتيب؛ الأخير يتكرر
        self.requests = []

    def next(self):
        item = self.responses[min(len(self.requests) - 1, len(self.responses) - 1)]
        return item


def handler(api):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            api.requests.append((self.path, self.headers.get("Authorization"), self.headers.get("User-Agent")))
            status, body = api.next()
            raw = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

    return Handler


class ReleaseCheck(unittest.TestCase):
    def setUp(self):
        self.api = FakeApi()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler(self.api))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.sleeps = []

    def run_main(self, *, token=TOKEN, attempts="3", **env):
        environ = {
            "GITHUB_REPOSITORY": REPO,
            "GITHUB_API_URL": self.base,
            "RELEASE_CHECK_ATTEMPTS": attempts,
            "RELEASE_CHECK_DELAY": "0",
            **env,
        }
        if token:
            environ["GITHUB_TOKEN"] = token
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = rc.main(["release_check.py", TAG], environ, sleep=self.sleeps.append)
        return code, out.getvalue()

    def test_a_complete_release_passes_and_lists_the_files(self):
        self.api.responses = [(200, good_release())]
        code, out = self.run_main()
        self.assertEqual(code, 0, out)
        for name in rc.EXPECTED:
            self.assertIn(name, out)
        self.assertIn("::notice title=release-check::ok tag=preview-7 assets=5", out)
        self.assertEqual(self.api.requests[0][0], f"/repos/{REPO}/releases/tags/{TAG}")

    def test_the_token_is_sent_but_never_printed(self):
        self.api.responses = [(200, good_release())]
        code, out = self.run_main()
        self.assertEqual(self.api.requests[0][1], f"Bearer {TOKEN}")
        self.assertNotIn(TOKEN, out)
        code, _ = self.run_main(token="")
        self.assertIsNone(self.api.requests[-1][1])

    def test_a_missing_file_is_named(self):
        release = good_release(assets=[asset(n) for n in rc.EXPECTED if n != "school-admin-setup.exe"])
        self.api.responses = [(200, release)]
        code, out = self.run_main(attempts="1")
        self.assertEqual(code, 1)
        self.assertIn("school-admin-setup.exe: غير موجود", out)

    def test_bad_digests_sizes_states_and_foreign_links_are_each_reported(self):
        bad = good_release(
            assets=[
                asset("school-admin.apk", digest=None),
                asset("school-teacher.apk", digest="sha1:" + "a" * 40),
                asset("school-student.apk", size=0),
                asset("school-admin-setup.exe", state="starter"),
                asset("school-admin-windows.zip", browser_download_url="https://evil.example/x.zip"),
            ]
        )
        self.api.responses = [(200, bad)]
        code, out = self.run_main(attempts="1")
        self.assertEqual(code, 1)
        self.assertIn("school-admin.apk: بلا بصمة", out)
        self.assertIn("school-teacher.apk: بلا بصمة", out)
        self.assertIn("school-student.apk: حجمه غير صالح", out)
        self.assertIn("school-admin-setup.exe: لم يكتمل رفعه", out)
        self.assertIn("school-admin-windows.zip: رابط التنزيل ليس من", out)

    def test_a_draft_release_fails(self):
        self.api.responses = [(200, good_release(draft=True))]
        self.assertEqual(self.run_main(attempts="1")[0], 1)

    def test_a_missing_release_and_server_errors_fail_with_the_status(self):
        for status in (404, 500):
            self.api.requests.clear()
            self.api.responses = [(status, {"message": "x"})]
            code, out = self.run_main(attempts="1")
            self.assertEqual(code, 1)
            self.assertIn(f"الواجهة ردّت {status}", out)

    def test_a_digest_that_arrives_late_is_retried(self):
        late = good_release(assets=[asset(n, digest=None) for n in rc.EXPECTED])
        self.api.responses = [(200, late), (200, late), (200, good_release())]
        code, out = self.run_main(attempts="5")
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.api.requests), 3)
        self.assertEqual(len(self.sleeps), 2)

    def test_it_gives_up_after_the_attempts_and_reports_the_last_problem(self):
        self.api.responses = [(200, good_release(assets=[]))]
        code, out = self.run_main(attempts="3")
        self.assertEqual(code, 1)
        self.assertEqual(len(self.api.requests), 3)
        self.assertEqual(len(self.sleeps), 2)

    def test_usage_and_environment_errors(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(rc.main(["release_check.py"], {}), 2)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(rc.main(["release_check.py", TAG], {}), 2)
        self.assertIn("GITHUB_REPOSITORY", out.getvalue())

    def test_problems_function_directly(self):
        self.assertEqual(rc.problems(good_release(), REPO, TAG), [])
        self.assertEqual(rc.problems(None, REPO, TAG), ["الإصدار غير موجود أو تعذّرت قراءته"])
        self.assertTrue(rc.problems(good_release(), REPO, "preview-8"), "الرابط يحمل وسماً آخر")


if __name__ == "__main__":
    unittest.main()
