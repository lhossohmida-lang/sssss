"""اختبارات demo_seed.py: سلامة المجموعة مقابل مخطط الخادم الحقيقي، وقواعد التطبيق، والزرع على خادم وهمي."""

import contextlib
import io
import json
import os
import re
import sys
import threading
import unittest
import urllib.parse
from datetime import date, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import demo_seed as demo  # noqa: E402
import supabase_bootstrap as sb  # noqa: E402

SCHEMA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "supabase", "migrations", "0001_schema.sql")
TODAY = date(2026, 11, 16)  # اثنين
OWNER = "owner-uid-1"


def parse_schema():
    """الجداول وأعمدتها (الاسم ← (إلزامي بلا افتراضي؟)) والفهارس الفريدة والمفاتيح الأساسية من ملف الترحيل."""
    with open(SCHEMA, encoding="utf-8") as f:
        text = f.read()
    tables = {}
    for match in re.finditer(r'create table if not exists public\."(\w+)" \((.*?)\n\);', text, re.S):
        columns, primary = {}, []
        for line in match.group(2).splitlines():
            line = line.strip().rstrip(",")
            pk = re.match(r"primary key \((.*)\)", line)
            if pk:
                primary = [c.strip().strip('"') for c in pk.group(1).split(",")]
                continue
            col = re.match(r'"(\w+)" (\w+)(.*)', line)
            if col:
                rest = col.group(3).lower()
                columns[col.group(1)] = "not null" in rest and "default" not in rest
        tables[match.group(1)] = {"columns": columns, "primary": primary}
    unique = {}
    for match in re.finditer(r'create unique index if not exists "\w+" on public\."(\w+)" \(([^)]*)\)', text):
        unique.setdefault(match.group(1), []).append([c.strip().strip('"') for c in match.group(2).split(",")])
    return tables, unique


SCHEMA_TABLES, SCHEMA_UNIQUE = parse_schema()

PHONE = re.compile(r"^0[567]\d{8}$")
QR = re.compile(r"^[ST]-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{10}$")


class Dataset(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = demo.build_dataset(TODAY, OWNER)

    def ids(self, table):
        return {row["id"] for row in self.data[table]}

    def test_the_parser_found_the_real_schema(self):
        self.assertIn("students", SCHEMA_TABLES)
        self.assertEqual(SCHEMA_TABLES["settings"]["primary"], ["key"])
        self.assertTrue(SCHEMA_TABLES["students"]["columns"]["first_name"])
        self.assertFalse(SCHEMA_TABLES["students"]["columns"]["synced_at"])

    def test_every_row_matches_its_table_in_the_schema(self):
        for table, rows in self.data.items():
            self.assertIn(table, SCHEMA_TABLES, table)
            columns = SCHEMA_TABLES[table]["columns"]
            keys = set(rows[0]) if rows else set()
            for row in rows:
                self.assertEqual(set(row), keys, f"{table}: مفاتيح غير موحّدة")
            self.assertLessEqual(keys - {"synced_at"}, set(columns), f"{table}: عمود غير موجود")
            for name, required in columns.items():
                if required and rows:
                    self.assertIn(name, keys, f"{table}.{name} إلزامي ومفقود")
            for row in rows:
                for name, required in columns.items():
                    if required:
                        self.assertIsNotNone(row.get(name), f"{table}.{name} إلزامي وقيمته فارغة")

    def test_synced_at_is_left_to_the_server(self):
        for rows in self.data.values():
            for row in rows:
                self.assertNotIn("synced_at", row)

    def test_primary_and_unique_keys_hold(self):
        for table, rows in self.data.items():
            primary = SCHEMA_TABLES[table]["primary"]
            keys = [tuple(r[c] for c in primary) for r in rows]
            self.assertEqual(len(keys), len(set(keys)), f"{table}: مفتاح أساسي مكرر")
            for index in SCHEMA_UNIQUE.get(table, []):
                values = [tuple(r[c] for c in index) for r in rows]
                self.assertEqual(len(values), len(set(values)), f"{table}: فهرس فريد {index}")

    def test_references_resolve(self):
        def refs(table, column, target):
            for row in self.data[table]:
                value = row[column]
                if value is not None:
                    self.assertIn(value, self.ids(target), f"{table}.{column}={value}")

        refs("subjects", "level_id", "levels")
        refs("groups", "subject_id", "subjects")
        refs("groups", "teacher_id", "teachers")
        refs("groups", "room_id", "rooms")
        refs("group_slots", "group_id", "groups")
        refs("group_slots", "room_id", "rooms")
        refs("students", "level_id", "levels")
        refs("students", "parent_account_id", "parents")
        refs("group_students", "group_id", "groups")
        refs("group_students", "student_id", "students")
        refs("sessions", "group_id", "groups")
        refs("sessions", "room_id", "rooms")
        refs("attendance", "session_id", "sessions")
        refs("attendance", "student_id", "students")
        refs("payments", "student_id", "students")
        refs("payments", "group_id", "groups")
        for row in self.data["teacher_subjects"]:
            self.assertIn(row["teacher_id"], self.ids("teachers"))
            self.assertIn(row["subject_id"], self.ids("subjects"))

    def test_sizes_are_a_believable_school(self):
        self.assertEqual(len(self.data["students"]), 30)
        self.assertEqual(len(self.data["levels"]), 12)
        self.assertEqual(len(self.data["groups"]), 6)
        self.assertGreaterEqual(len(self.data["parents"]), 20)
        self.assertEqual(
            {s["parent_account_id"] for s in self.data["students"]}, self.ids("parents"), "وليّ بلا تلميذ"
        )
        self.assertGreater(len(self.data["attendance"]), 400)
        self.assertGreater(len(self.data["payments"]), 30)

    def test_people_have_valid_distinct_phones_and_qr_codes(self):
        phones = [t["phone"] for t in self.data["teachers"]] + [p["phone"] for p in self.data["parents"]]
        self.assertEqual(len(phones), len(set(phones)))
        for number in phones:
            self.assertRegex(number, PHONE)
        self.assertNotIn("0550000000", phones)  # هاتف مالك مدرسة العرض
        for student in self.data["students"]:
            self.assertRegex(student["qr_code"], QR)
            self.assertTrue(student["qr_code"].startswith("S-"))
            self.assertEqual(student["parent_phone"], next(p for p in self.data["parents"] if p["id"] == student["parent_account_id"])["phone"])
        for teacher in self.data["teachers"]:
            self.assertTrue(teacher["qr_code"].startswith("T-"))
            self.assertRegex(teacher["qr_code"], QR)

    def test_names_are_real_arabic_not_placeholders(self):
        arabic = re.compile(r"[؀-ۿ]")
        for table in ("teachers", "parents", "subjects", "rooms"):
            for row in self.data[table]:
                self.assertRegex(row["name"], arabic)
        for student in self.data["students"]:
            self.assertRegex(student["first_name"], arabic)
            self.assertRegex(student["last_name"], arabic)
            self.assertNotRegex(student["first_name"] + student["last_name"], r"\d")

    def test_levels_mirror_the_apps_defaults(self):
        by_name = {row["name"]: row for row in self.data["levels"]}
        self.assertEqual(by_name["4 متوسط"]["sort_order"], 204)
        self.assertEqual(by_name["3 ثانوي"]["stage"], "secondary")
        self.assertEqual(by_name["3 ثانوي"]["id"], demo.level_id("secondary", 3))
        self.assertEqual(by_name["1 ابتدائي"]["sort_order"], 101)

    def test_stable_ids_match_the_dart_implementation(self):
        # قيم حُسبت من `StableId` في Dart نفسه.
        self.assertEqual(demo.level_id("middle", 4), "edbdd620-ec20-545b-8652-afe85ac086a6")
        self.assertEqual(
            demo.stable_id("session", "demo-group-1", "2026-11-14", 480), "b0b5ecc5-69f7-583e-b3a0-0dfbc9725d76"
        )
        self.assertEqual(
            demo.stable_id("attendance", "sess-1", "demo-student-1"), "5b9543de-a27b-580a-8a4d-cb3372f2e98f"
        )
        self.assertEqual(
            demo.stable_id("group_student", "demo-group-1", "demo-student-1"), "b99b50bc-3b59-5810-a04b-9a8725bba3bf"
        )

    def test_enrolment_and_session_ids_use_the_apps_derivation(self):
        for row in self.data["group_students"]:
            self.assertEqual(row["id"], demo.stable_id("group_student", row["group_id"], row["student_id"]))
        for row in self.data["sessions"]:
            self.assertEqual(
                row["id"], demo.stable_id("session", row["group_id"], row["date"], row["start_minutes"])
            )
        for row in self.data["attendance"]:
            self.assertEqual(row["id"], demo.stable_id("attendance", row["session_id"], row["student_id"]))

    def test_groups_students_match_levels_and_prices(self):
        subject = {s["id"]: s for s in self.data["subjects"]}
        group = {g["id"]: g for g in self.data["groups"]}
        student = {s["id"]: s for s in self.data["students"]}
        for row in self.data["group_students"]:
            level = subject[group[row["group_id"]]["subject_id"]]["level_id"]
            self.assertEqual(student[row["student_id"]]["level_id"], level, "مادة من غير مستوى التلميذ")
            self.assertEqual(row["monthly_price"], subject[group[row["group_id"]]["subject_id"]]["monthly_price"])
            self.assertIn(row["discount_type"], ("none", "percent", "fixed", "exempt"))
        types = {r["discount_type"] for r in self.data["group_students"]}
        self.assertEqual(types, {"none", "percent", "fixed", "exempt"}, "يلزم عرض كل أنواع التخفيض")

    def test_sessions_follow_the_weekly_schedule_and_cycle_rules(self):
        slots = {}
        for slot in self.data["group_slots"]:
            slots.setdefault(slot["group_id"], set()).add(slot["weekday"])
        for group in self.data["groups"]:
            rows = sorted((s for s in self.data["sessions"] if s["group_id"] == group["id"]), key=lambda s: s["date"])
            self.assertTrue(rows)
            for k, session in enumerate(rows):
                day = date.fromisoformat(session["date"])
                self.assertIn(day.isoweekday(), slots[group["id"]])
                self.assertLessEqual(day, TODAY)
                self.assertGreaterEqual(day, TODAY - timedelta(days=demo.WINDOW_DAYS))
                self.assertEqual(session["cycle_number"], k // 8 + 1)
                self.assertEqual(session["session_number"], k % 8 + 1)
                self.assertEqual(session["status"], "normal")
                self.assertEqual(session["end_minutes"] - session["start_minutes"], demo.SESSION_MINUTES)
                self.assertEqual(session["closed_at"] is None, day == TODAY, "تُغلق الحصص السابقة وحدها")
            self.assertEqual(group["current_cycle_number"], rows[-1]["cycle_number"])
            self.assertEqual(group["sessions_per_cycle"], 8)

    def test_no_room_or_teacher_double_booking(self):
        groups = {g["id"]: g for g in self.data["groups"]}
        seen_room, seen_teacher = {}, {}
        for slot in self.data["group_slots"]:
            group = groups[slot["group_id"]]
            for registry, owner in ((seen_room, slot["room_id"]), (seen_teacher, group["teacher_id"])):
                for start, end in registry.get((owner, slot["weekday"]), []):
                    self.assertTrue(
                        slot["end_minutes"] <= start or slot["start_minutes"] >= end,
                        f"تعارض موعد {owner} يوم {slot['weekday']}",
                    )
                registry.setdefault((owner, slot["weekday"]), []).append((slot["start_minutes"], slot["end_minutes"]))

    def test_attendance_is_for_closed_sessions_and_enrolled_students_only(self):
        sessions = {s["id"]: s for s in self.data["sessions"]}
        enrolled = {(r["group_id"], r["student_id"]) for r in self.data["group_students"]}
        for row in self.data["attendance"]:
            session = sessions[row["session_id"]]
            self.assertIsNotNone(session["closed_at"])
            self.assertIn((session["group_id"], row["student_id"]), enrolled)
            self.assertIn(row["status"], ("present", "absent"))
            self.assertIn(row["method"], ("qr", "manual"))
            self.assertEqual(row["scanned_at"] is not None, row["method"] == "qr")
        expected = sum(
            1
            for s in self.data["sessions"]
            if s["closed_at"] is not None
            for r in self.data["group_students"]
            if r["group_id"] == s["group_id"]
        )
        self.assertEqual(len(self.data["attendance"]), expected)
        statuses = {r["status"] for r in self.data["attendance"]}
        self.assertEqual(statuses, {"present", "absent"})

    def test_payments_are_consistent_with_prices_and_cycles(self):
        enrolment = {(r["group_id"], r["student_id"]): r for r in self.data["group_students"]}
        group = {g["id"]: g for g in self.data["groups"]}
        receipts = [p["receipt_number"] for p in self.data["payments"]]
        self.assertEqual(len(receipts), len(set(receipts)))
        self.assertEqual(receipts, [f"DEM-{n:04d}" for n in range(1, len(receipts) + 1)])
        stamps = [p["created_at"] for p in self.data["payments"]]
        self.assertEqual(stamps, sorted(stamps))
        for payment in self.data["payments"]:
            row = enrolment[(payment["group_id"], payment["student_id"])]
            due = demo.due_amount(row["monthly_price"], row["discount_type"], row["discount_value"])
            self.assertGreater(due, 0, "لا دفع على معفى")
            self.assertTrue(0 < payment["amount"] <= due)
            self.assertEqual(payment["amount"] % 50, 0)
            self.assertEqual(payment["type"], "month")
            self.assertEqual(payment["received_by"], OWNER)
            self.assertLessEqual(payment["cycle_number"], group[payment["group_id"]]["current_cycle_number"])
            self.assertLessEqual(payment["created_at"], demo.ms_at(TODAY, 24 * 60))
        cycles = {p["cycle_number"] for p in self.data["payments"]}
        self.assertEqual(cycles, {1, 2}, "دورة مكتملة وأخرى جارية")
        full = sum(1 for p in self.data["payments"] if p["cycle_number"] == 1)
        self.assertGreater(full, 20)

    def test_discount_arithmetic(self):
        self.assertEqual(demo.due_amount(2000, "none", 0), 2000)
        self.assertEqual(demo.due_amount(2000, "percent", 20), 1600)
        self.assertEqual(demo.due_amount(2000, "fixed", 300), 1700)
        self.assertEqual(demo.due_amount(2000, "fixed", 5000), 0)
        self.assertEqual(demo.due_amount(2000, "exempt", 0), 0)

    def test_settings_are_the_apps_keys_with_a_marker(self):
        settings = {r["key"]: r["value"] for r in self.data["settings"]}
        self.assertEqual(settings["school_name"], demo.DEMO_SCHOOL_NAME)
        self.assertEqual(settings[demo.MARKER_KEY], TODAY.isoformat())
        semesters = json.loads(settings["semesters"])
        self.assertEqual(len(semesters), 3)
        self.assertEqual(semesters[0]["start"], "2026-09-13")
        for semester in semesters:
            self.assertLess(semester["start"], semester["end"])

    def test_school_year_rolls_over_in_summer(self):
        data = demo.build_dataset(date(2027, 3, 10), OWNER)
        semesters = json.loads({r["key"]: r["value"] for r in data["settings"]}["semesters"])
        self.assertEqual(semesters[0]["start"], "2026-09-13")

    def test_the_same_day_gives_the_same_data_and_another_day_other_sessions(self):
        again = demo.build_dataset(TODAY, OWNER)
        self.assertEqual(again, self.data)
        later = demo.build_dataset(TODAY + timedelta(days=7), OWNER)
        self.assertNotEqual({s["id"] for s in later["sessions"]}, self.ids("sessions"))
        self.assertEqual(self.ids("students"), {s["id"] for s in later["students"]})

    def test_every_weekday_has_an_open_session_today(self):
        for offset in range(7):
            day = TODAY + timedelta(days=offset)
            data = demo.build_dataset(day, OWNER)
            open_today = [s for s in data["sessions"] if s["closed_at"] is None]
            self.assertTrue(open_today, f"لا حصة مفتوحة يوم {day} ({day.isoweekday()})")

    def test_without_accounts_nothing_links_to_auth(self):
        for row in self.data["teachers"] + self.data["parents"]:
            self.assertEqual(row["email"], "")
            self.assertIsNone(row["auth_user_id"])
        self.assertEqual(self.data["user_accounts"], [])

    def test_with_accounts_rows_link_to_the_auth_users(self):
        teachers, parents = demo.make_people()
        used = {s["parent_account_id"] for s in self.data["students"]}
        people = [*teachers, *(p for p in parents if p.key in used)]
        accounts = {p.email: f"uid-{i}" for i, p in enumerate(people)}
        data = demo.build_dataset(TODAY, OWNER, accounts)
        self.assertEqual(len(data["user_accounts"]), len(people))
        by_entity = {a["entity_id"]: a for a in data["user_accounts"]}
        for teacher in data["teachers"]:
            account = by_entity[teacher["id"]]
            self.assertEqual(account["role"], "teacher")
            self.assertEqual(account["id"], teacher["auth_user_id"])
            self.assertEqual(account["email"], teacher["email"])
            self.assertTrue(teacher["email"].endswith("@school.local"))
        for parent in data["parents"]:
            self.assertEqual(by_entity[parent["id"]]["role"], "parent")
            self.assertEqual(by_entity[parent["id"]]["id"], parent["auth_user_id"])
        for account in data["user_accounts"]:
            self.assertFalse(account["must_change_password"])
        emails = [a["email"] for a in data["user_accounts"]]
        self.assertEqual(len(emails), len(set(emails)))

    def test_people_plan_covers_every_parent_the_students_use(self):
        _, parents = demo.make_people()
        needed = {p["parent"] for p in demo.student_plan()}
        self.assertLess(max(needed), len(parents))


# ---- الزرع على خادم وهمي

REF = "abcdefghijklmnopqrst"
TOKEN = "sbp_" + "t" * 40
SECRET = "sb_secret_FAKE-DEMO-SEED-SECRET"
PASSWORD = "Demo-Accounts-Sentinel-1"


class FakeState:
    def __init__(self):
        self.tables = {}  # الاسم ← {المفتاح: صف}
        self.users = {}
        self.requests = []
        self.owner = True
        self.real_student = False
        self.school_name = None
        self.fail_table = None
        self.unique_receipts = False  # يحاكي الفهرس الفريد idx_payments_receipt


def handler(state):
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

        def route(self, method):
            url = urllib.parse.urlparse(self.path)
            query = urllib.parse.parse_qs(url.query)
            path = url.path
            # يُقرأ الجسم قبل أي رد فلا تنقطع الصلة والعميل ما زال يرسل (جسم كبير).
            payload = self.body() if method == "POST" else None
            state.requests.append((method, path, self.headers.get("Prefer")))
            if path == f"/v1/projects/{REF}/api-keys":
                if self.headers.get("Authorization") != f"Bearer {TOKEN}":
                    return self.send(401, {"message": "bad"})
                return self.send(200, [{"type": "secret", "name": "default", "api_key": SECRET}])
            if self.headers.get("apikey") != SECRET:
                return self.send(401, {"message": "bad key"})
            if path == "/auth/v1/admin/users":
                if method == "POST":
                    data = payload
                    if data["email"] in state.users:
                        return self.send(422, {"error_code": "email_exists"})
                    assert data["password"] == PASSWORD
                    state.users[data["email"]] = f"uid-{len(state.users) + 1}"
                    return self.send(200, {"id": state.users[data["email"]]})
                return self.send(200, {"users": [{"id": u, "email": e} for e, u in state.users.items()]})
            table = path.removeprefix("/rest/v1/")
            if method == "GET":
                if table == "user_accounts":
                    return self.send(200, [{"id": "owner-uid-1"}] if state.owner else [])
                if table == "students":
                    return self.send(200, [{"id": "real-1"}] if state.real_student else [])
                if table == "settings":
                    key = query.get("key", [""])[0].removeprefix("eq.")
                    if key == "school_name":
                        return self.send(200, [{"value": state.school_name}] if state.school_name else [])
                    row = state.tables.get("settings", {}).get((key,))
                    return self.send(200, [row] if row else [])
                return self.send(200, [])
            if method == "POST":
                if table == state.fail_table:
                    return self.send(500, {"message": "boom"})
                rows = payload
                conflict = query["on_conflict"][0].split(",")
                bucket = state.tables.setdefault(table, {})
                for row in rows:
                    if state.unique_receipts and table == "payments":
                        for other in bucket.values():
                            if other["receipt_number"] == row["receipt_number"] and other["id"] != row["id"]:
                                return self.send(
                                    409, {"message": 'duplicate key value violates unique constraint "idx_payments_receipt"'}
                                )
                    bucket[tuple(row[c] for c in conflict)] = row
                return self.send(201)
            if method == "DELETE":
                prefix = query.get("id", [""])[0].removeprefix("like.").rstrip("*")
                bucket = state.tables.get(table, {})
                for key in [k for k, row in bucket.items() if prefix and row["id"].startswith(prefix)]:
                    del bucket[key]
                return self.send(204)
            return self.send(404, {"message": "unknown"})

        def do_GET(self):
            self.route("GET")

        def do_POST(self):
            self.route("POST")

        def do_DELETE(self):
            self.route("DELETE")

    return Handler


class Seeding(unittest.TestCase):
    def setUp(self):
        self.state = FakeState()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler(self.state))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"

    def environ(self, **extra):
        return {
            "SUPABASE_ACCESS_TOKEN": TOKEN,
            "SUPABASE_PROJECT_REF": REF,
            "SUPABASE_URL": self.base,
            "SUPABASE_API_BASE": self.base,
            **extra,
        }

    def seeder(self, password=""):
        cfg = sb.Config.from_env(self.environ())
        return demo.DemoSeed(sb.Bootstrap(cfg), password, today=TODAY)

    def run_main(self, *args, **extra):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = demo.main(["demo_seed.py", *args], self.environ(**extra))
        return code, out.getvalue()

    def test_seeds_every_table_in_dependency_order_with_the_secret_key(self):
        lines = self.seeder().seed()
        self.assertTrue(lines[0].startswith("demo-seed=ok"))
        posts = [path.removeprefix("/rest/v1/") for method, path, _ in self.state.requests if method == "POST"]
        order = list(dict.fromkeys(posts))
        for earlier, later in [
            ("levels", "subjects"),
            ("subjects", "groups"),
            ("teachers", "groups"),
            ("groups", "sessions"),
            ("sessions", "attendance"),
            ("students", "payments"),
        ]:
            self.assertLess(order.index(earlier), order.index(later), (earlier, later))
        self.assertEqual(len(self.state.tables["students"]), 30)
        self.assertIn(("demo_seeded",), self.state.tables["settings"])
        self.assertTrue(all(prefer == "resolution=merge-duplicates,return=minimal" for m, _, prefer in self.state.requests if m == "POST"))

    def test_large_tables_are_sent_in_chunks(self):
        self.seeder().seed()
        attendance_posts = [r for r in self.state.requests if r[0] == "POST" and r[1].endswith("/attendance")]
        self.assertGreaterEqual(len(attendance_posts), 2)

    def test_the_owner_is_the_receiver_of_payments(self):
        self.seeder().seed()
        receivers = {row["received_by"] for row in self.state.tables["payments"].values()}
        self.assertEqual(receivers, {"owner-uid-1"})

    def test_a_second_run_is_skipped_and_force_rewrites(self):
        self.seeder().seed()
        before = len([r for r in self.state.requests if r[0] == "POST"])
        again = self.seeder().seed()
        self.assertIn("skipped", again[0])
        self.assertEqual(len([r for r in self.state.requests if r[0] == "POST"]), before)
        forced = self.seeder().seed(force=True)
        self.assertTrue(forced[0].startswith("demo-seed=ok"))
        self.assertGreater(len([r for r in self.state.requests if r[0] == "POST"]), before)

    def test_a_forced_reseed_on_another_day_renumbers_receipts_without_a_conflict(self):
        # الأرقام تُعطى بالترتيب الزمني: في يوم آخر ينتقل رقم وصل قائم إلى معرّف آخر (409 على الفهرس الفريد).
        later = TODAY + timedelta(days=3)
        old = {p["id"]: p["receipt_number"] for p in demo.build_dataset(TODAY, OWNER, {})["payments"]}
        new = {p["id"]: p["receipt_number"] for p in demo.build_dataset(later, OWNER, {})["payments"]}
        moved = [i for i in old if i in new and old[i] != new[i]]
        self.assertTrue(moved, "المقدّمة: أرقام وصولات تتحرك بين اليومين")

        self.state.unique_receipts = True
        self.seeder().seed()
        cfg = sb.Config.from_env(self.environ())
        again = demo.DemoSeed(sb.Bootstrap(cfg), "", today=later).seed(force=True)
        self.assertTrue(again[0].startswith("demo-seed=ok"), again)

        stored = {row["id"]: row["receipt_number"] for row in self.state.tables["payments"].values()}
        self.assertEqual(stored, new)
        self.assertEqual(len(set(stored.values())), len(stored))
        deletes = [r for r in self.state.requests if r[0] == "DELETE"]
        self.assertEqual([r[1] for r in deletes], ["/rest/v1/payments"])

    def test_a_first_run_deletes_nothing(self):
        self.seeder().seed()
        self.assertEqual([r for r in self.state.requests if r[0] == "DELETE"], [])

    def test_real_students_in_the_school_refuse_the_seed(self):
        self.state.real_student = True
        with self.assertRaisesRegex(sb.ApiError, "حماية"):
            self.seeder().seed()
        self.assertEqual(self.state.tables, {})

    def test_a_named_real_school_refuses_the_seed(self):
        self.state.school_name = "مدرسة النور"
        with self.assertRaisesRegex(sb.ApiError, "حماية"):
            self.seeder().seed()
        self.assertEqual(self.state.tables, {})

    def test_the_demo_name_is_accepted(self):
        self.state.school_name = demo.DEMO_SCHOOL_NAME
        self.assertTrue(self.seeder().seed()[0].startswith("demo-seed=ok"))

    def test_a_missing_owner_stops_before_writing(self):
        self.state.owner = False
        with self.assertRaisesRegex(sb.ApiError, "مالك"):
            self.seeder().seed()
        self.assertEqual(self.state.tables, {})

    def test_a_server_failure_names_the_table(self):
        self.state.fail_table = "payments"
        with self.assertRaisesRegex(sb.ApiError, "payments"):
            self.seeder().seed()

    def test_no_password_creates_no_accounts(self):
        self.seeder().seed()
        self.assertEqual(self.state.users, {})
        self.assertNotIn("user_accounts", self.state.tables)

    def test_a_password_creates_accounts_and_links_them(self):
        lines = self.seeder(PASSWORD).seed()
        self.assertEqual(len(self.state.users), 5 + len(self.state.tables["parents"]))
        self.assertIn(f"accounts={len(self.state.users)}", lines[0])
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[1].startswith("demo-logins teacher=0"))
        self.assertNotIn(PASSWORD, "".join(lines))
        accounts = self.state.tables["user_accounts"]
        self.assertEqual(len(accounts), len(self.state.users))
        for (uid,), row in accounts.items():
            self.assertEqual(self.state.users[row["email"]], uid)
        teacher = next(iter(self.state.tables["teachers"].values()))
        self.assertTrue(teacher["auth_user_id"].startswith("uid-"))

    def test_existing_accounts_are_reused(self):
        self.seeder(PASSWORD).seed()
        users = dict(self.state.users)
        self.seeder(PASSWORD).seed(force=True)
        self.assertEqual(self.state.users, users)

    def test_main_prints_notices_and_never_a_secret(self):
        code, out = self.run_main("seed", DEMO_ACCOUNTS_PASSWORD=PASSWORD)
        self.assertEqual(code, 0, out)
        self.assertIn("::notice title=demo-seed::", out)
        for secret in (SECRET, TOKEN, PASSWORD):
            self.assertNotIn(secret, out)

    def test_main_reports_a_protective_refusal_as_a_warning_not_a_failure(self):
        self.state.real_student = True
        code, out = self.run_main("seed")
        self.assertEqual(code, 0)
        self.assertIn("::warning title=demo-seed::", out)
        self.assertNotIn("::error", out)
        self.assertNotIn(SECRET, out)
        self.assertEqual(self.state.tables, {})

    def test_main_reports_a_server_failure_as_an_error(self):
        self.state.fail_table = "levels"
        code, out = self.run_main("seed")
        self.assertEqual(code, 1)
        self.assertIn("::error title=demo-seed::", out)
        self.assertNotIn(SECRET, out)

    def test_main_names_missing_inputs(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = demo.main(["demo_seed.py", "seed"], {})
        self.assertEqual(code, 1)
        for name in ("SUPABASE_ACCESS_TOKEN", "SUPABASE_PROJECT_REF", "SUPABASE_URL"):
            self.assertIn(name, out.getvalue())

    def test_check_command_needs_no_network(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(demo.main(["demo_seed.py", "check"], {}), 0)
        self.assertIn("students=30", out.getvalue())

    def test_unknown_command_is_a_usage_error(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(demo.main(["demo_seed.py", "nope"], {}), 2)


if __name__ == "__main__":
    unittest.main()
