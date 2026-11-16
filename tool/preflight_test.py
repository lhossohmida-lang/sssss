"""اختبارات فحص ما قبل النشر (preflight.py): الصيغ والأماكن، ولا قيمة سرّية في أي ناتج."""

import base64
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import preflight  # noqa: E402

REF = "abcdefghijklmnopqrst"


def jwt(role: str) -> str:
    def part(obj) -> str:
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip("=")

    return f"{part({'alg': 'HS256'})}.{part({'role': role})}.signature"


def services(package: str, project: str = "school-proj") -> str:
    return json.dumps(
        {
            "project_info": {"project_id": project},
            "client": [{"client_info": {"android_client_info": {"package_name": package}}}],
        }
    )


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
            "FIREBASE_SERVICE_ACCOUNT": service_account(),
        }
        variables = {
            "GOOGLE_DRIVE_WINDOWS_CLIENT_ID": "123-abc.apps.googleusercontent.com",
            "GOOGLE_SERVER_CLIENT_ID": "456-def.apps.googleusercontent.com",
        }
        report = preflight.evaluate("repo", secrets, variables)
        self.assertEqual(report.errors, [])
        self.assertTrue(all(state == "ok" for _, state in report.rows))

    def test_firebase_files_must_match_their_app_and_project(self):
        secrets = {
            "GOOGLE_SERVICES_ADMIN": services("dz.school.teacher"),
            "GOOGLE_SERVICES_TEACHER": services("dz.school.teacher", "other-proj"),
            "FIREBASE_SERVICE_ACCOUNT": service_account("school-proj"),
        }
        errors = preflight.evaluate("repo", secrets, {}).errors
        self.assertTrue(any(e.startswith("GOOGLE_SERVICES_ADMIN") for e in errors))
        self.assertTrue(any("مشاريع مختلفة" in e for e in errors))

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
                "SECRET_PASTED_AS_NAME_SENTINEL": "x",
            }
        )
        variables["OWNER_PHONE"] = "0450000000"
        for mode in ("school", "repo"):
            report = preflight.evaluate(mode, secrets, variables)
            output = preflight.render(report, mode, "demo") + "\n".join(
                preflight.annotations(report, mode)
            )
            for value in list(secrets.values()) + ["SENTINEL"]:
                if value in ("x",):
                    continue
                self.assertNotIn(value, output, mode)
            self.assertNotIn("SENTINEL", output)
            self.assertNotIn("SECRET_PASTED_AS_NAME_SENTINEL", output)
            self.assertGreaterEqual(report.unknown, 1)

    def test_annotation_text_is_escaped_to_one_line(self):
        report = preflight.Report(errors=["a\nb%c"])
        line = preflight.annotations(report, "school")[1]
        self.assertNotIn("\n", line)
        self.assertIn("a%0Ab%25c", line)


if __name__ == "__main__":
    unittest.main()
