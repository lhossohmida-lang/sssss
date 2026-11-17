"""اختبارات فحص ما قبل النشر (preflight.py): الصيغ والأماكن، ولا قيمة سرّية في أي ناتج."""

import base64
import json
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import preflight  # noqa: E402

REF = "abcdefghijklmnopqrst"


def jwt(role: str) -> str:
    def part(obj) -> str:
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip("=")

    return f"{part({'alg': 'HS256'})}.{part({'role': role})}.signature"


ALL_PACKAGES = ["dz.school.admin", "dz.school.teacher", "dz.school.student"]


def client(package: str) -> dict:
    return {"client_info": {"android_client_info": {"package_name": package}}}


def services(package: str, project: str = "school-proj") -> str:
    return json.dumps({"project_info": {"project_id": project}, "client": [client(package)]})


def services_all(project: str = "school-proj", packages: list[str] = ALL_PACKAGES) -> str:
    """ملف Firebase واحد يحوي عميلاً لكل تطبيق (كالملف الحقيقي بعد تسجيل التطبيقات الثلاثة)."""
    return json.dumps({"project_info": {"project_id": project}, "client": [client(p) for p in packages]})


def service_account(project: str = "school-proj") -> str:
    return json.dumps(
        {
            "type": "service_account",
            "project_id": project,
            "private_key": "-----BEGIN PRIVATE KEY-----\nSENTINEL-PRIVATE\n-----END PRIVATE KEY-----\n",
            "client_email": f"fcm@{project}.iam.gserviceaccount.com",
        }
    )


def good_school() -> tuple[dict, dict]:
    secrets = {
        "SUPABASE_ACCESS_TOKEN": "sbp_" + "a1b2c3d4e5" * 4,
        "SUPABASE_DB_PASSWORD": "Sentinel-DB-Pass-9876",
        "OWNER_INITIAL_PASSWORD": "Sentinel-Owner-1",
        "SUPABASE_ANON_KEY": "sb_publishable_sentinelkey",
    }
    variables = {
        "SUPABASE_URL": f"https://{REF}.supabase.co",
        "SUPABASE_PROJECT_REF": REF,
        "OWNER_PHONE": "0550000000",
    }
    return secrets, variables


class SchoolMode(unittest.TestCase):
    def test_school_name_and_listing_are_checked(self):
        secrets, variables = good_school()
        variables["SCHOOL_NAME"] = "مدرسة النور"
        variables["SCHOOL_LISTED"] = "false"
        report = preflight.evaluate("school", secrets, variables)
        self.assertEqual(report.errors, [])
        self.assertIn(("SCHOOL_NAME", "ok"), report.rows)
        self.assertIn(("SCHOOL_LISTED", "ok"), report.rows)

        variables["SCHOOL_NAME"] = "م"
        variables["SCHOOL_LISTED"] = "نعم"
        errors = " ".join(preflight.evaluate("school", secrets, variables).errors)
        self.assertIn("SCHOOL_NAME", errors)
        self.assertIn("SCHOOL_LISTED", errors)

        variables["SCHOOL_NAME"] = "مدرسة النور" + chr(10)
        errors = " ".join(preflight.evaluate("school", secrets, variables).errors)
        self.assertIn("SCHOOL_NAME", errors)

    def test_complete_environment_has_no_errors(self):
        secrets, variables = good_school()
        report = preflight.evaluate("school", secrets, variables)
        self.assertEqual(report.errors, [])
        self.assertTrue(all(state in ("ok", "not-set") for _, state in report.rows))

    def test_missing_required_names_are_errors(self):
        secrets, variables = good_school()
        del secrets["SUPABASE_DB_PASSWORD"]
        del variables["OWNER_PHONE"]
        report = preflight.evaluate("school", secrets, variables)
        self.assertEqual(
            sorted(e.split(":")[0] for e in report.errors),
            ["OWNER_PHONE", "SUPABASE_DB_PASSWORD"],
        )

    def test_anon_key_may_live_in_variables(self):
        secrets, variables = good_school()
        variables["SUPABASE_ANON_KEY"] = secrets.pop("SUPABASE_ANON_KEY")
        self.assertEqual(preflight.evaluate("school", secrets, variables).errors, [])

    def test_secret_key_is_never_accepted_as_the_public_key(self):
        for bad in ("sb_secret_sentinel", jwt("service_role")):
            secrets, variables = good_school()
            secrets["SUPABASE_ANON_KEY"] = bad
            errors = preflight.evaluate("school", secrets, variables).errors
            self.assertEqual(len(errors), 1, bad)
            self.assertIn("سرّي", errors[0])

    def test_legacy_anon_jwt_is_accepted(self):
        secrets, variables = good_school()
        secrets["SUPABASE_ANON_KEY"] = jwt("anon")
        self.assertEqual(preflight.evaluate("school", secrets, variables).errors, [])

    def test_url_must_match_the_project_ref_and_have_no_slash(self):
        secrets, variables = good_school()
        variables["SUPABASE_URL"] = "https://zzzzzzzzzzzzzzzzzzzz.supabase.co"
        self.assertEqual(len(preflight.evaluate("school", secrets, variables).errors), 1)
        variables["SUPABASE_URL"] = f"https://{REF}.supabase.co/"
        self.assertEqual(len(preflight.evaluate("school", secrets, variables).errors), 1)

    def test_secret_stored_as_variable_is_an_error(self):
        secrets, variables = good_school()
        variables["SUPABASE_DB_PASSWORD"] = secrets.pop("SUPABASE_DB_PASSWORD")
        errors = preflight.evaluate("school", secrets, variables).errors
        self.assertEqual(len(errors), 1)
        self.assertIn("Variables", errors[0])

    def test_format_problems(self):
        secrets, variables = good_school()
        secrets["SUPABASE_ACCESS_TOKEN"] = "not-a-token"
        secrets["OWNER_INITIAL_PASSWORD"] = "short"
        variables["OWNER_PHONE"] = "0450000000"
        report = preflight.evaluate("school", secrets, variables)
        self.assertEqual(
            sorted(e.split(":")[0] for e in report.errors),
            ["OWNER_INITIAL_PASSWORD", "OWNER_PHONE", "SUPABASE_ACCESS_TOKEN"],
        )

    def test_pasted_trailing_newline_is_caught(self):
        secrets, variables = good_school()
        secrets["SUPABASE_DB_PASSWORD"] += "\n"
        self.assertEqual(len(preflight.evaluate("school", secrets, variables).errors), 1)

    def test_special_characters_in_db_password_only_warn(self):
        secrets, variables = good_school()
        secrets["SUPABASE_DB_PASSWORD"] = "Sentinel-DB@Pass-9876"
        report = preflight.evaluate("school", secrets, variables)
        self.assertEqual(report.errors, [])
        self.assertEqual(len(report.warnings), 1)


class DemoAccountsPassword(unittest.TestCase):
    def test_it_is_optional_in_a_school(self):
        secrets, variables = good_school()
        report = preflight.evaluate("school", secrets, variables)
        self.assertEqual(report.errors, [])
        self.assertIn(("DEMO_ACCOUNTS_PASSWORD", "not-set"), report.rows)

    def test_a_good_value_is_accepted(self):
        secrets, variables = good_school()
        secrets["DEMO_ACCOUNTS_PASSWORD"] = "Demo-Sentinel-Pass-1"
        report = preflight.evaluate("school", secrets, variables)
        self.assertEqual(report.errors, [])
        self.assertIn(("DEMO_ACCOUNTS_PASSWORD", "ok"), report.rows)

    def test_short_or_padded_values_are_errors(self):
        for bad in ("short", "Demo-Sentinel-Pass-1\n"):
            secrets, variables = good_school()
            secrets["DEMO_ACCOUNTS_PASSWORD"] = bad
            errors = preflight.evaluate("school", secrets, variables).errors
            self.assertEqual(len(errors), 1, bad)
            self.assertTrue(errors[0].startswith("DEMO_ACCOUNTS_PASSWORD"))

    def test_it_must_be_a_secret_not_a_variable(self):
        secrets, variables = good_school()
        variables["DEMO_ACCOUNTS_PASSWORD"] = "Demo-Sentinel-Pass-1"
        errors = preflight.evaluate("school", secrets, variables).errors
        self.assertEqual(len(errors), 1)
        self.assertIn("Variables", errors[0])

    def test_at_repo_level_it_is_a_misplaced_school_value(self):
        errors = preflight.evaluate("repo", {"DEMO_ACCOUNTS_PASSWORD": "Demo-Sentinel-Pass-1"}, {}).errors
        self.assertEqual(len(errors), 1)
        self.assertIn("Environment", errors[0])


class RepoMode(unittest.TestCase):
    def test_developer_names_are_optional_until_they_exist(self):
        report = preflight.evaluate("repo", {}, {})
        self.assertEqual(report.errors, [])
        self.assertTrue(all(state == "not-set" for _, state in report.rows))

    def test_school_values_at_repo_level_are_errors(self):
        secrets, variables = good_school()
        report = preflight.evaluate("repo", secrets, variables)
        self.assertEqual(len(report.errors), len(secrets) + len(variables))
        self.assertTrue(all("Environment" in e for e in report.errors))

    def test_llm_values_at_repo_level_only_warn_but_school_values_still_fail(self):
        secrets = {"LLM_API_KEY": "sk-or-sentinel-key", "SUPABASE_DB_PASSWORD": "Sentinel-DB-Pass-9876"}
        variables = {"LLM_MODEL": "google/model:free"}
        report = preflight.evaluate("repo", secrets, variables)
        self.assertEqual([e.split(":")[0] for e in report.errors], ["SUPABASE_DB_PASSWORD"])
        self.assertEqual(sorted(w.split(":")[0] for w in report.warnings), ["LLM_API_KEY", "LLM_MODEL"])

    def test_good_developer_values(self):
        keystore = base64.b64encode(b"\x30\x82" + b"x" * 600).decode()
        secrets = {
            "SCHOOL_KEYSTORE_BASE64": keystore,
            "SCHOOL_KEYSTORE_PASSWORD": "pw-sentinel-1",
            "SCHOOL_KEY_ALIAS": "school",
            "SCHOOL_KEY_PASSWORD": "pw-sentinel-1",
            "GOOGLE_DESKTOP_CLIENT_SECRET": "GOCSPX-sentinel",
            "GOOGLE_SERVICES_ADMIN": services("dz.school.admin"),
            "GOOGLE_SERVICES_TEACHER": services("dz.school.teacher"),
            "GOOGLE_SERVICES_STUDENT": services("dz.school.student"),
            "GOOGLE_SERVICES_JSON": services_all(),
            "FIREBASE_SERVICE_ACCOUNT": service_account(),
            "DIRECTORY_SERVICE_KEY": "sb_secret_sentinel-directory-key",
        }
        variables = {
            "GOOGLE_DRIVE_WINDOWS_CLIENT_ID": "123-abc.apps.googleusercontent.com",
            "GOOGLE_SERVER_CLIENT_ID": "456-def.apps.googleusercontent.com",
            "DIRECTORY_URL": f"https://{REF}.supabase.co",
            "DIRECTORY_ANON_KEY": "sb_publishable_directorykey",
        }
        report = preflight.evaluate("repo", secrets, variables)
        self.assertEqual(report.errors, [])
        self.assertTrue(all(state == "ok" for _, state in report.rows))

    def test_directory_values_are_checked(self):
        # المفتاح العام لا يصلح مكان السرّي، والسرّي لا يصلح مكان العام.
        report = preflight.evaluate(
            "repo",
            {"DIRECTORY_SERVICE_KEY": "sb_publishable_oops"},
            {"DIRECTORY_URL": "https://example.com", "DIRECTORY_ANON_KEY": "sb_secret_oops"},
        )
        names = " ".join(report.errors)
        self.assertIn("DIRECTORY_SERVICE_KEY", names)
        self.assertIn("DIRECTORY_URL", names)
        self.assertIn("DIRECTORY_ANON_KEY", names)

    def test_directory_secret_key_in_variables_is_an_error(self):
        report = preflight.evaluate(
            "repo", {}, {"DIRECTORY_SERVICE_KEY": "sb_secret_sentinel-directory-key"}
        )
        self.assertTrue(any(e.startswith("DIRECTORY_SERVICE_KEY") for e in report.errors))

    def test_directory_service_role_jwt_is_accepted(self):
        jwt = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature"
        report = preflight.evaluate("repo", {"DIRECTORY_SERVICE_KEY": jwt}, {})
        self.assertEqual(report.errors, [])
        self.assertIn(("DIRECTORY_SERVICE_KEY", "ok"), report.rows)

    def test_firebase_files_must_match_their_app_and_project(self):
        secrets = {
            "GOOGLE_SERVICES_ADMIN": services("dz.school.teacher"),
            "GOOGLE_SERVICES_TEACHER": services("dz.school.teacher", "other-proj"),
            "FIREBASE_SERVICE_ACCOUNT": service_account("school-proj"),
        }
        errors = preflight.evaluate("repo", secrets, {}).errors
        self.assertTrue(any(e.startswith("GOOGLE_SERVICES_ADMIN") for e in errors))
        self.assertTrue(any("مشاريع مختلفة" in e for e in errors))

    def test_one_shared_firebase_file_may_cover_the_three_apps(self):
        report = preflight.evaluate("repo", {"GOOGLE_SERVICES_JSON": services_all()}, {})
        self.assertEqual(report.errors, [])
        self.assertIn(("GOOGLE_SERVICES_JSON", "ok"), report.rows)

    def test_shared_firebase_file_must_have_every_app(self):
        shared = services_all(packages=["dz.school.admin", "dz.school.student"])
        errors = preflight.evaluate("repo", {"GOOGLE_SERVICES_JSON": shared}, {}).errors
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("GOOGLE_SERVICES_JSON"))
        self.assertIn("dz.school.teacher", errors[0])
        self.assertNotIn("dz.school.admin", errors[0])

    def test_shared_firebase_file_must_match_the_service_account_project(self):
        secrets = {
            "GOOGLE_SERVICES_JSON": services_all("other-proj"),
            "FIREBASE_SERVICE_ACCOUNT": service_account("school-proj"),
        }
        errors = preflight.evaluate("repo", secrets, {}).errors
        self.assertTrue(any("مشاريع مختلفة" in e for e in errors))

    def test_shared_firebase_file_is_a_secret_not_a_variable(self):
        errors = preflight.evaluate("repo", {}, {"GOOGLE_SERVICES_JSON": services_all()}).errors
        self.assertEqual(len(errors), 1)
        self.assertIn("Variables", errors[0])

    def test_keystore_must_be_base64_of_a_keystore(self):
        for bad in ("***", base64.b64encode(b"tiny").decode(), base64.b64encode(b"x" * 900).decode()):
            errors = preflight.evaluate("repo", {"SCHOOL_KEYSTORE_BASE64": bad}, {}).errors
            self.assertEqual(len(errors), 1, bad)

    def test_key_password_mismatch_only_warns(self):
        secrets = {"SCHOOL_KEYSTORE_PASSWORD": "one-sentinel", "SCHOOL_KEY_PASSWORD": "two-sentinel"}
        report = preflight.evaluate("repo", secrets, {})
        self.assertEqual(report.errors, [])
        self.assertEqual(len(report.warnings), 1)


class NothingSecretIsPrinted(unittest.TestCase):
    def test_outputs_contain_names_and_reasons_only(self):
        secrets, variables = good_school()
        secrets.update(
            {
                "SUPABASE_ACCESS_TOKEN": "sbp_SENTINEL-TOKEN-VALUE-0123456789",
                "SCHOOL_KEYSTORE_PASSWORD": "SENTINEL-KEYSTORE",
                "SCHOOL_KEY_PASSWORD": "SENTINEL-OTHER",
                "FIREBASE_SERVICE_ACCOUNT": service_account(),
                "GOOGLE_SERVICES_ADMIN": services("dz.school.teacher"),
            }
        )
        variables["OWNER_PHONE"] = "0450000000"
        for mode in ("school", "repo"):
            report = preflight.evaluate(mode, secrets, variables)
            output = preflight.render(report, mode, "demo") + "\n".join(
                preflight.annotations(report, mode)
            )
            for value in secrets.values():
                self.assertNotIn(value, output, mode)
            self.assertNotIn("SENTINEL", output)

    def test_annotation_text_is_escaped_to_one_line(self):
        report = preflight.Report(errors=["a\nb%c"])
        line = preflight.annotations(report, "school")[1]
        self.assertNotIn("\n", line)
        self.assertIn("a%0Ab%25c", line)


class Collection(unittest.TestCase):
    def test_values_come_from_named_env_vars(self):
        names = preflight.names_for("school")
        environ = {"SUPABASE_URL": "u", "VAR_OWNER_PHONE": "p", "UNRELATED": "z"}
        secrets, variables = preflight.collect(names, environ)
        self.assertEqual(secrets["SUPABASE_URL"], "u")
        self.assertEqual(variables["OWNER_PHONE"], "p")
        self.assertNotIn("UNRELATED", secrets)

    def test_repo_mode_covers_every_name(self):
        every = {i.name for i in preflight.SCHOOL_ITEMS} | {i.name for i in preflight.DEVELOPER_ITEMS}
        self.assertEqual(set(preflight.names_for("repo")), every)
        self.assertEqual(len(preflight.names_for("repo")), len(every))


class WorkflowFile(unittest.TestCase):
    """ملف المسار يمرّر كل اسم صراحةً (وبلا toJSON(secrets) الذي يوقفه GitHub)."""

    path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", ".github", "workflows", "preflight.yml"
    )

    def jobs(self) -> dict[str, str]:
        with open(self.path, encoding="utf-8") as f:
            text = f.read()
        self.assertIsNone(re.search(r"\$\{\{[^}]*toJSON", text), "toJSON داخل تعبير")
        parts = re.split(r"^  (repo-level|school|signing-key):\n", text, flags=re.M)
        return {parts[i]: parts[i + 1] for i in range(1, len(parts) - 1, 2)}

    def test_each_job_passes_exactly_its_names(self):
        jobs = self.jobs()
        for mode, job in (("repo-level", "repo"), ("school", "school")):
            names = preflight.names_for(job)
            body = jobs[mode]
            passed_secrets = re.findall(r"^\s+([A-Z0-9_]+): \$\{\{ secrets\.([A-Z0-9_]+) \}\}$", body, re.M)
            passed_vars = re.findall(r"^\s+VAR_([A-Z0-9_]+): \$\{\{ vars\.([A-Z0-9_]+) \}\}$", body, re.M)
            self.assertTrue(all(a == b for a, b in passed_secrets), mode)
            self.assertTrue(all(a == b for a, b in passed_vars), mode)
            self.assertEqual(sorted(a for a, _ in passed_secrets), sorted(names), mode)
            self.assertEqual(sorted(a for a, _ in passed_vars), sorted(names), mode)

    def test_signing_key_job_reads_only_the_four_signing_secrets(self):
        body = self.jobs()["signing-key"]
        names = re.findall(
            r"^\s+([A-Z0-9_]+): \$\{\{ secrets\.([A-Z0-9_]+) \}\}$", body, re.M
        )
        self.assertTrue(all(a == b for a, b in names))
        self.assertEqual(
            sorted(a for a, _ in names),
            [
                "SCHOOL_KEYSTORE_BASE64",
                "SCHOOL_KEYSTORE_PASSWORD",
                "SCHOOL_KEY_ALIAS",
                "SCHOOL_KEY_PASSWORD",
            ],
        )
        self.assertNotIn("environment:", body)

    def test_only_the_school_job_has_an_environment(self):
        jobs = self.jobs()
        self.assertNotIn("environment:", jobs["repo-level"])
        self.assertIn("environment: ${{ inputs.school || 'demo' }}", jobs["school"])


if __name__ == "__main__":
    unittest.main()
