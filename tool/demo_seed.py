#!/usr/bin/env python3
"""يملأ مدرسة العرض ببيانات وهمية واقعية: مستويات ومواد وأساتذة وأولياء وتلاميذ ومجموعات وحصص وحضور ودفعات.

يكتب في الخادم مباشرة بالمفتاح السرّي (يتجاوز RLS)، والتواريخ نسبية إلى اليوم فتبدو المدرسة شغّالة: ستة
أسابيع من الحصص السابقة، وحصص اليوم مفتوحة، ودورة مكتملة وأخرى جارية. المعرّفات محسومة فتتطابق مع
معرّفات التطبيق للسجلات ذات المفتاح الطبيعي (UUID v5 كما في `StableId`).

الاستعمال:
  python3 tool/demo_seed.py seed [--force]   # يزرع مرة واحدة؛ --force يعيد الكتابة (يضيف حصص تواريخ اليوم)
  python3 tool/demo_seed.py check            # يبني المجموعة دون اتصال ويطبع حجمها

المدخلات: SUPABASE_ACCESS_TOKEN وSUPABASE_PROJECT_REF وSUPABASE_URL (يُقرأ المفتاح السرّي من Supabase).
اختياري: DEMO_ACCOUNTS_PASSWORD لإنشاء حسابات دخول لأساتذة العرض وأوليائه (بلا كلمة سر لا تُنشأ حسابات).

حمايات: يرفض إن وُجد تلميذ ليس من بيانات العرض (معرّفه لا يبدأ بـ`demo-`) فلا يلمس مدرسة حقيقية أبداً،
ولا يطبع أي قيمة سرّية.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import time
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import supabase_bootstrap as sb  # noqa: E402

# نفس مساحة الأسماء في `packages/core/lib/src/domain/stable_id.dart`.
NAMESPACE = uuid.UUID("6f1d3c52-8b0a-5e1f-9c44-2a7b61d0e9aa")
EMAIL_DOMAIN = sb.EMAIL_DOMAIN
ALGIERS = timezone(timedelta(hours=1))
MARKER_KEY = "demo_seeded"
CHUNK = 400
WINDOW_DAYS = 41  # ستة أسابيع للخلف
SESSIONS_PER_CYCLE = 8
SESSION_MINUTES = 90

# أيام الأسبوع بترقيم `DateTime.weekday` في Dart (الاثنين 1 … الأحد 7)، وهو ما يعيده isoweekday.
WEEKDAY_PAIRS = [(6, 2), (7, 3), (1, 4), (2, 5)]

BOYS = ["محمد أمين", "يوسف", "إلياس", "رياض", "سفيان", "أنيس", "ياسين", "بلال", "عبد الرحمن", "زكرياء", "حمزة", "وليد", "نبيل", "أيوب", "إسحاق"]
GIRLS = ["ملاك", "إيمان", "سارة", "نور الهدى", "مريم", "آية", "شيماء", "ريان", "خديجة", "فاطمة الزهراء", "رانيا", "لينة", "هبة", "ياسمين", "أسماء"]
FAMILIES = ["بن علي", "مرابط", "بوعلام", "زيداني", "حداد", "بلقاسم", "قادري", "سعدي", "رحماني", "بن يحيى", "شريف", "بوزيد", "عمراني", "لعربي", "مسعودي", "بوقرة", "تواتي", "عيساوي", "بن عمار", "حمداني", "كرمة", "بوشامة"]
PARENT_FIRST = ["أحمد", "عبد القادر", "محمود", "كمال", "فاتح", "سمير", "لخضر", "جمال", "عادل", "هشام", "مراد", "حكيم", "نصر الدين", "بشير", "توفيق", "رضوان", "سليم", "مصطفى", "عمر", "إبراهيم", "ليلى", "نجاة", "صالح"]
CARRIERS = ["0550", "0551", "0552", "0660", "0661", "0662", "0770", "0771", "0772"]

# (اسم المادة، السعر الشهري، (الطور، السنة)).
SUBJECTS = [
    ("رياضيات", 2000, ("middle", 4)),
    ("اللغة العربية", 1500, ("middle", 4)),
    ("اللغة الفرنسية", 1500, ("middle", 4)),
    ("رياضيات", 2500, ("secondary", 3)),
    ("الفيزياء", 2500, ("secondary", 3)),
    ("علوم الطبيعة والحياة", 2000, ("secondary", 3)),
]
TEACHERS = [
    ("كريم بن علي", 1200),
    ("سعاد مرابط", 1000),
    ("ياسين بوعلام", 1200),
    ("نادية حداد", 1000),
    ("رشيد قادري", 1100),
]
ROOMS = [("القاعة 1", 30), ("القاعة 2", 25), ("القاعة 3", 25)]
# (المادة، الأستاذ، القاعة، زوج الأيام، بداية الحصة بالدقائق).
GROUPS = [
    (0, 0, 0, 0, 480),
    (1, 1, 1, 1, 600),
    (2, 3, 2, 2, 840),
    (3, 0, 0, 3, 960),
    (4, 2, 1, 0, 960),
    (5, 4, 2, 1, 960),
]
STAGE_ORDER = {"primary": 0, "middle": 1, "secondary": 2}
STAGE_GRADES = {"primary": 5, "middle": 4, "secondary": 3}
STAGE_LABEL = {"primary": "ابتدائي", "middle": "متوسط", "secondary": "ثانوي"}
STUDENT_COUNT = 30
DEMO_SCHOOL_NAME = "مدرسة العرض التجريبية"


def stable_id(kind: str, *parts: Any) -> str:
    """مطابق لـ `StableId._of`: UUID v5 على «النوع|الأجزاء»."""
    return str(uuid.uuid5(NAMESPACE, kind + "|" + "|".join(str(p) for p in parts)))


def level_id(stage: str, grade: int) -> str:
    return stable_id("default_level", stage, grade)


def phone(index: int, salt: int) -> str:
    """رقم نقال جزائري صالح (05/06/07 + 8 أرقام) مشتق من الفهرس، وغير مكرَّر."""
    carrier = CARRIERS[(index + salt) % len(CARRIERS)]
    return carrier + f"{(index * 7919 + salt * 104729 + 12345) % 1_000_000:06d}"


def qr_code(prefix: str, key: str) -> str:
    """رمز `S-`/`T-` بعشرة أحرف من الأبجدية الخالية من الملتبسة، مشتق من المفتاح (يبدو عشوائياً)."""
    alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    digest = int.from_bytes(hashlib.sha1(key.encode()).digest(), "big")
    chars = []
    for _ in range(10):
        digest, rest = divmod(digest, len(alphabet))
        chars.append(alphabet[rest])
    return f"{prefix}-{''.join(chars)}"


def roll(*parts: Any) -> float:
    """عدد في [0، 1) ثابت لمدخلاته: يغني عن العشوائية فتتكرر المجموعة نفسها."""
    digest = hashlib.sha1("|".join(str(p) for p in parts).encode()).digest()
    return int.from_bytes(digest[:4], "big") / 2**32


def due_amount(price: int, discount_type: str, value: int) -> int:
    if discount_type == "percent":
        return price * (100 - value) // 100
    if discount_type == "fixed":
        return max(0, price - value)
    if discount_type == "exempt":
        return 0
    return price


def ms_at(day: date, minutes: int = 0) -> int:
    start = datetime(day.year, day.month, day.day, tzinfo=ALGIERS)
    return int(start.timestamp() * 1000) + minutes * 60_000


@dataclass(frozen=True)
class Person:
    key: str  # معرّف الكيان (teacher أو parent)
    role: str
    name: str
    phone: str

    @property
    def email(self) -> str:
        return f"{self.phone}@{EMAIL_DOMAIN}"


def make_people() -> tuple[list[Person], list[Person]]:
    """الأساتذة والأولياء (بلا تواريخ): تلزم أرقامهم لإنشاء حسابات الدخول قبل بناء المجموعة."""
    teachers = [
        Person(f"demo-teacher-{i + 1}", "teacher", name, phone(i, 3)) for i, (name, _) in enumerate(TEACHERS)
    ]
    parents = []
    for i in range(len(PARENT_FIRST)):
        family = FAMILIES[i % len(FAMILIES)]
        parents.append(Person(f"demo-parent-{i + 1}", "parent", f"{PARENT_FIRST[i]} {family}", phone(i, 1)))
    return teachers, parents


def student_plan() -> list[dict[str, Any]]:
    """كل تلميذ: اسمه ووليّه ومستواه ومجموعاته وتخفيضه. نصف التلاميذ متوسط 4 والنصف ثانوي 3."""
    plan: list[dict[str, Any]] = []
    parent = 0
    for i in range(STUDENT_COUNT):
        sibling = i > 0 and i % 4 == 3  # كل رابع تلميذ أخ للسابق
        if i > 0 and not sibling:
            parent += 1
        girl = i % 2 == 1
        stage, grade = ("middle", 4) if i < STUDENT_COUNT // 2 else ("secondary", 3)
        base = 0 if stage == "middle" else 3
        groups = [base]
        if i % 2 == 0:
            groups.append(base + 1)
        if i % 3 == 0:
            groups.append(base + 2)
        discount = ("none", 0)
        if sibling:
            discount = ("percent", 20)
        elif i == 6:
            discount = ("exempt", 0)
        elif i == 10:
            discount = ("fixed", 300)
        first = (GIRLS if girl else BOYS)[(i // 2) % len(BOYS)]
        plan.append(
            {
                "index": i,
                "id": f"demo-student-{i + 1}",
                "first": first,
                "parent": parent,
                "stage": stage,
                "grade": grade,
                "groups": groups,
                "discount": discount,
            }
        )
    return plan


def daterange(start: date, end: date):
    day = start
    while day <= end:
        yield day
        day += timedelta(days=1)


Dataset = dict[str, list[dict[str, Any]]]


class Refused(sb.ApiError):
    """رفض مقصود حمايةً لبيانات حقيقية: تحذير لا فشل في المسار."""


def build_dataset(today: date, owner_id: str, accounts: Optional[dict[str, str]] = None) -> Dataset:
    """المجموعة كاملة بترتيب التبعيات. [accounts] بريد ← معرّف حساب Auth لمن أُنشئ له حساب دخول."""
    accounts = accounts or {}
    now = ms_at(today, 12 * 60)
    teachers, parents = make_people()
    data: Dataset = {}

    levels = []
    for stage, grades in STAGE_GRADES.items():
        for grade in range(1, grades + 1):
            levels.append(
                {
                    "id": level_id(stage, grade),
                    "created_at": 0,
                    "updated_at": 0,
                    "deleted_at": None,
                    "name": f"{grade} {STAGE_LABEL[stage]}",
                    "stage": stage,
                    "sort_order": (STAGE_ORDER[stage] + 1) * 100 + grade,
                }
            )
    data["levels"] = levels

    data["subjects"] = [
        {
            "id": f"demo-subject-{i + 1}",
            "created_at": 0,
            "updated_at": 0,
            "deleted_at": None,
            "name": name,
            "level_id": level_id(*level),
            "monthly_price": price,
        }
        for i, (name, price, level) in enumerate(SUBJECTS)
    ]
    data["rooms"] = [
        {"id": f"demo-room-{i + 1}", "created_at": 0, "updated_at": 0, "deleted_at": None, "name": name, "capacity": cap}
        for i, (name, cap) in enumerate(ROOMS)
    ]
    data["teachers"] = [
        {
            "id": t.key,
            "created_at": 0,
            "updated_at": 0,
            "deleted_at": None,
            "name": t.name,
            "phone": t.phone,
            "email": t.email if t.email in accounts else "",
            "photo_url": None,
            "photo_local_path": None,
            "rate_per_student": TEACHERS[i][1],
            "qr_code": qr_code("T", t.key),
            "auth_user_id": accounts.get(t.email),
        }
        for i, t in enumerate(teachers)
    ]
    subject_teacher = {}
    for subject, teacher, *_ in GROUPS:
        subject_teacher[(teacher, subject)] = True
    data["teacher_subjects"] = [
        {
            "teacher_id": f"demo-teacher-{teacher + 1}",
            "subject_id": f"demo-subject-{subject + 1}",
            "updated_at": 0,
            "deleted_at": None,
        }
        for teacher, subject in sorted(subject_teacher)
    ]

    plan = student_plan()
    window_start = today - timedelta(days=WINDOW_DAYS)

    # الحصص أولاً: تحدد الدورة الجارية لكل مجموعة.
    sessions: list[dict[str, Any]] = []
    group_sessions: dict[int, list[dict[str, Any]]] = {}
    for g, (_, _, room, pair, start) in enumerate(GROUPS):
        group_id = f"demo-group-{g + 1}"
        dates = [d for d in daterange(window_start, today) if d.isoweekday() in WEEKDAY_PAIRS[pair]]
        rows = []
        for k, day in enumerate(dates):
            cycle, number = k // SESSIONS_PER_CYCLE + 1, k % SESSIONS_PER_CYCLE + 1
            closed = day < today
            end = start + SESSION_MINUTES
            rows.append(
                {
                    "id": stable_id("session", group_id, day.isoformat(), start),
                    "created_at": ms_at(day, start - 60),
                    "updated_at": ms_at(day, end) if closed else ms_at(day, start - 60),
                    "deleted_at": None,
                    "group_id": group_id,
                    "cycle_number": cycle,
                    "session_number": number,
                    "date": day.isoformat(),
                    "start_minutes": start,
                    "end_minutes": end,
                    "room_id": f"demo-room-{room + 1}",
                    "status": "normal",
                    "closed_at": ms_at(day, end) if closed else None,
                }
            )
        group_sessions[g] = rows
        sessions.extend(rows)

    # الأفواج تُرقَّم لكل مادة وسنة (فوج 1، فوج 2 ضمن «رياضيات 3 ثانوي») كما يفعل التطبيق.
    scope_counts: dict[tuple[str, str], int] = {}
    group_numbers: list[int] = []
    for subject, *_ in GROUPS:
        name, _price, level = SUBJECTS[subject]
        scope = (name.strip().lower(), level_id(*level))
        scope_counts[scope] = scope_counts.get(scope, 0) + 1
        group_numbers.append(scope_counts[scope])

    data["groups"] = [
        {
            "id": f"demo-group-{g + 1}",
            "created_at": ms_at(window_start, 0),
            "updated_at": ms_at(window_start, 0),
            "deleted_at": None,
            "number": group_numbers[g],
            "subject_id": f"demo-subject-{subject + 1}",
            "teacher_id": f"demo-teacher-{teacher + 1}",
            "room_id": f"demo-room-{room + 1}",
            "sessions_per_cycle": SESSIONS_PER_CYCLE,
            "current_cycle_number": group_sessions[g][-1]["cycle_number"] if group_sessions[g] else 1,
            "rate_per_student": None,
            "archived_at": None,
        }
        for g, (subject, teacher, room, _, _) in enumerate(GROUPS)
    ]
    data["group_slots"] = [
        {
            "id": f"demo-slot-{g + 1}-{weekday}",
            "created_at": ms_at(window_start, 0),
            "updated_at": ms_at(window_start, 0),
            "deleted_at": None,
            "group_id": f"demo-group-{g + 1}",
            "weekday": weekday,
            "start_minutes": start,
            "end_minutes": start + SESSION_MINUTES,
            "room_id": f"demo-room-{room + 1}",
        }
        for g, (_, _, room, pair, start) in enumerate(GROUPS)
        for weekday in WEEKDAY_PAIRS[pair]
    ]

    used_parents = sorted({p["parent"] for p in plan})
    data["parents"] = [
        {
            "id": parents[i].key,
            "created_at": ms_at(window_start, 0),
            "updated_at": ms_at(window_start, 0),
            "deleted_at": None,
            "phone": parents[i].phone,
            "email": parents[i].email if parents[i].email in accounts else "",
            "name": parents[i].name,
            "auth_user_id": accounts.get(parents[i].email),
        }
        for i in used_parents
    ]
    students = []
    for p in plan:
        parent = parents[p["parent"]]
        students.append(
            {
                "id": p["id"],
                "created_at": ms_at(window_start, 0),
                "updated_at": ms_at(window_start, 0),
                "deleted_at": None,
                "first_name": p["first"],
                "last_name": FAMILIES[p["parent"] % len(FAMILIES)],
                "parent_phone": parent.phone,
                "photo_url": None,
                "photo_local_path": None,
                "level_id": level_id(p["stage"], p["grade"]),
                "uses_transport": False,
                "transport_price": 0,
                "transport_line_id": None,
                "qr_code": qr_code("S", p["id"]),
                "parent_account_id": parent.key,
            }
        )
    data["students"] = students

    enrolments = []
    members: dict[int, list[dict[str, Any]]] = {g: [] for g in range(len(GROUPS))}
    for p in plan:
        for g in p["groups"]:
            subject = GROUPS[g][0]
            price = SUBJECTS[subject][1]
            dtype, dvalue = p["discount"]
            group_id = f"demo-group-{g + 1}"
            row = {
                "id": stable_id("group_student", group_id, p["id"]),
                "created_at": ms_at(window_start, 0),
                "updated_at": ms_at(window_start, 0),
                "deleted_at": None,
                "group_id": group_id,
                "student_id": p["id"],
                "joined_at": ms_at(window_start, 0),
                "joined_at_cycle_number": 1,
                "joined_at_session_number": 1,
                "monthly_price": price,
                "discount_type": dtype,
                "discount_value": dvalue,
                "left_at": None,
            }
            enrolments.append(row)
            members[g].append({**row, "due": due_amount(price, dtype, dvalue)})
    data["group_students"] = enrolments
    data["sessions"] = sessions

    attendance = []
    for g, rows in group_sessions.items():
        for session in rows:
            if session["closed_at"] is None:
                continue
            for member in members[g]:
                r = roll("attendance", session["id"], member["student_id"])
                if r < 0.84:
                    status, method = "present", ("qr" if r < 0.76 else "manual")
                else:
                    status, method = "absent", "manual"
                scanned = None
                if method == "qr":
                    day = date.fromisoformat(session["date"])
                    scanned = ms_at(day, session["start_minutes"] - 8 + int(roll("scan", session["id"], member["student_id"]) * 14))
                attendance.append(
                    {
                        "id": stable_id("attendance", session["id"], member["student_id"]),
                        "created_at": scanned or session["closed_at"],
                        "updated_at": scanned or session["closed_at"],
                        "deleted_at": None,
                        "session_id": session["id"],
                        "student_id": member["student_id"],
                        "status": status,
                        "scanned_at": scanned,
                        "method": method,
                    }
                )
    data["attendance"] = attendance

    payments = []
    for g, rows in group_sessions.items():
        cycles = sorted({s["cycle_number"] for s in rows})
        for member in members[g]:
            if member["due"] <= 0:
                continue
            for cycle in cycles:
                first = next(s for s in rows if s["cycle_number"] == cycle)
                r = roll("payment", member["group_id"], member["student_id"], cycle)
                complete = cycle < cycles[-1]
                full_share, partial_share = (0.70, 0.82) if complete else (0.35, 0.35)
                if r < full_share:
                    amount = member["due"]
                elif r < partial_share:
                    amount = member["due"] // 2 // 50 * 50
                else:
                    continue
                day = min(today, date.fromisoformat(first["date"]) + timedelta(days=int(roll("when", member["student_id"], cycle) * 5)))
                stamp = ms_at(day, 11 * 60 + int(roll("hour", member["student_id"], g, cycle) * 240))
                payments.append(
                    {
                        "id": f"demo-payment-{g + 1}-{member['student_id'][len('demo-student-'):]}-{cycle}",
                        "created_at": stamp,
                        "updated_at": stamp,
                        "deleted_at": None,
                        "student_id": member["student_id"],
                        "type": "month",
                        "group_id": member["group_id"],
                        "cycle_number": cycle,
                        "period_key": None,
                        "amount": amount,
                        "received_by": owner_id,
                        "receipt_number": "",
                        "note": "",
                    }
                )
    payments.sort(key=lambda row: (row["created_at"], row["id"]))
    for number, row in enumerate(payments, 1):
        row["receipt_number"] = f"DEM-{number:04d}"
    data["payments"] = payments

    year = today.year if today.month >= 9 else today.year - 1
    semesters = [
        {"name": "الفصل الأول", "start": f"{year}-09-13", "end": f"{year}-12-17"},
        {"name": "الفصل الثاني", "start": f"{year + 1}-01-03", "end": f"{year + 1}-03-25"},
        {"name": "الفصل الثالث", "start": f"{year + 1}-04-04", "end": f"{year + 1}-06-12"},
    ]
    settings = {
        "school_name": DEMO_SCHOOL_NAME,
        "school_address": "حي 1 ماي، الجزائر العاصمة",
        "school_phone": "0661234567",
        "semesters": json.dumps(semesters, ensure_ascii=False),
        MARKER_KEY: today.isoformat(),
    }
    data["settings"] = [{"key": key, "value": value, "updated_at": now} for key, value in settings.items()]

    used_ids = {row["id"] for row in data["parents"]}
    user_accounts = []
    for person in [*teachers, *(p for p in parents if p.key in used_ids)]:
        uid = accounts.get(person.email)
        if uid:
            user_accounts.append(
                {
                    "id": uid,
                    "created_at": ms_at(window_start, 0),
                    "updated_at": ms_at(window_start, 0),
                    "deleted_at": None,
                    "email": person.email,
                    "role": person.role,
                    "entity_id": person.key,
                    "display_name": person.name,
                    "must_change_password": False,
                }
            )
    data["user_accounts"] = user_accounts
    return data


CONFLICT = {"teacher_subjects": "teacher_id,subject_id", "settings": "key"}


class DemoSeed:
    def __init__(self, bootstrap: "sb.Bootstrap", password: str = "", today: Optional[date] = None):
        self.boot = bootstrap
        self.cfg = bootstrap.cfg
        self.password = password
        self.today = today or datetime.now(ALGIERS).date()
        self.key = ""

    # ---- الخادم

    def _headers(self, extra: Optional[dict[str, str]] = None) -> dict[str, str]:
        return {**self.boot._admin(self.key), **(extra or {})}

    def _get(self, path: str) -> Any:
        status, payload = sb.call("GET", f"{self.cfg.url}/rest/v1/{path}", self._headers())
        if status != 200 or not isinstance(payload, list):
            raise sb.ApiError(f"تعذّرت القراءة من {path.split('?')[0]} ({status}) {sb.reason(payload)}", status)
        return payload

    def _owner_id(self) -> str:
        rows = self._get("user_accounts?role=eq.owner&select=id&limit=1")
        if not rows:
            raise sb.ApiError("لا حساب مالك في المدرسة بعد: شغّل مسار النشر (bootstrap) أولاً")
        return str(rows[0]["id"])

    def _guard(self, force: bool) -> bool:
        """False = مزروعة سابقاً فيُتخطى. يرمي إن وُجدت بيانات ليست بيانات عرض."""
        if self._get("students?select=id&id=not.like.demo-*&limit=1"):
            raise Refused("في المدرسة تلاميذ ليسوا من بيانات العرض: يُرفض الزرع حمايةً لبياناتها الحقيقية")
        named = self._get("settings?key=eq.school_name&select=value&limit=1")
        if named and named[0].get("value") != DEMO_SCHOOL_NAME:
            raise Refused("للمدرسة اسم غير اسم مدرسة العرض: يُرفض الزرع حمايةً لبياناتها الحقيقية")
        marker = self._get(f"settings?key=eq.{MARKER_KEY}&select=value&limit=1")
        return force or not marker

    def _ensure_user(self, person: Person) -> str:
        status, payload = sb.call(
            "POST",
            f"{self.cfg.url}/auth/v1/admin/users",
            self._headers(),
            {"email": person.email, "password": self.password, "email_confirm": True},
        )
        if status in (200, 201) and isinstance(payload, dict) and isinstance(payload.get("id"), str):
            return payload["id"]
        code = payload.get("error_code") if isinstance(payload, dict) else None
        if status in (409, 422) and code in (None, "email_exists", "user_already_exists"):
            for page in range(1, 51):
                st, body = sb.call(
                    "GET", f"{self.cfg.url}/auth/v1/admin/users?page={page}&per_page=200", self._headers()
                )
                if st != 200 or not isinstance(body, dict):
                    break
                users = body.get("users") or []
                for user in users:
                    if isinstance(user, dict) and str(user.get("email", "")).lower() == person.email:
                        return str(user["id"])
                if len(users) < 200:
                    break
            raise sb.ApiError("حساب موجود لكن تعذّر العثور على معرّفه")
        raise sb.ApiError(f"تعذّر إنشاء حساب عرض ({status}) {sb.reason(payload)}", status)

    def _delete(self, path: str) -> None:
        status, payload = sb.call(
            "DELETE", f"{self.cfg.url}/rest/v1/{path}", self._headers({"Prefer": "return=minimal"}), timeout=60
        )
        if status not in (200, 204):
            raise sb.ApiError(f"تعذّر حذف {path.split('?')[0]} ({status}) {sb.reason(payload)}", status)

    def _upsert(self, table: str, rows: list[dict[str, Any]]) -> None:
        target = CONFLICT.get(table, "id")
        for start in range(0, len(rows), CHUNK):
            status, payload = sb.call(
                "POST",
                f"{self.cfg.url}/rest/v1/{table}?on_conflict={target}",
                self._headers({"Prefer": "resolution=merge-duplicates,return=minimal"}),
                rows[start : start + CHUNK],
                timeout=60,
            )
            if status not in (200, 201, 204):
                raise sb.ApiError(f"تعذّر كتابة {table} ({status}) {sb.reason(payload)}", status)

    # ---- العملية

    def seed(self, force: bool = False) -> list[str]:
        self.key = self.boot.secret_key()
        if not self._guard(force):
            return ["demo-seed=skipped (زُرعت سابقاً؛ --force يعيد الكتابة)"]
        owner = self._owner_id()
        accounts: dict[str, str] = {}
        logins = ""
        if self.password:
            teachers, parents = make_people()
            used = {f"demo-parent-{p['parent'] + 1}" for p in student_plan()}
            people = [*teachers, *(p for p in parents if p.key in used)]
            for person in people:
                accounts[person.email] = self._ensure_user(person)
            first_parent = next(p for p in parents if p.key in used)
            logins = f"demo-logins teacher={teachers[0].phone} parent={first_parent.phone} (كلمة السر في سرّ DEMO_ACCOUNTS_PASSWORD)"
        data = build_dataset(self.today, owner, accounts)
        if force:
            # أرقام الوصولات تُعطى بالترتيب الزمني لتواريخ اليوم، فإعادة الزرع في يوم آخر تنقل رقم وصل قائم إلى معرّف آخر
            # فيصطدم بالفهرس الفريد `idx_payments_receipt` (409). تُحذف دفعات الزرع السابق (بياناتُ عرضٍ وحدها) قبل كتابة الجديدة.
            self._delete("payments?id=like.demo-payment-*")
        for table, rows in data.items():
            if rows:
                self._upsert(table, rows)
        sizes = " ".join(f"{table}={len(rows)}" for table, rows in data.items() if rows)
        lines = [f"demo-seed=ok {sizes} accounts={len(accounts)}"]
        if logins:
            lines.append(logins)
        return lines


def main(argv: list[str], environ: Optional[dict[str, str]] = None) -> int:
    environ = dict(os.environ) if environ is None else environ
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = argv[1:]
    force = "--force" in args
    command = next((a for a in args if not a.startswith("--")), "")
    if command == "check":
        data = build_dataset(datetime.now(ALGIERS).date(), "owner")
        print(" ".join(f"{t}={len(r)}" for t, r in data.items() if r))
        return 0
    if command != "seed":
        print("الاستعمال: demo_seed.py seed [--force] | check", file=sys.stderr)
        return 2
    cfg = sb.Config.from_env(environ)
    missing = [
        name
        for name, value in (
            ("SUPABASE_ACCESS_TOKEN", cfg.token),
            ("SUPABASE_PROJECT_REF", cfg.ref),
            ("SUPABASE_URL", cfg.url),
        )
        if not value
    ]
    if missing:
        print(f"::error title=demo-seed::مدخلات ناقصة: {', '.join(missing)}")
        return 1
    try:
        lines = DemoSeed(sb.Bootstrap(cfg), environ.get("DEMO_ACCOUNTS_PASSWORD", "")).seed(force)
    except Refused as error:
        print(f"::warning title=demo-seed::{sb.escape(str(error))}")
        return 0
    except sb.ApiError as error:
        print(f"::error title=demo-seed::{sb.escape(str(error))}")
        return 1
    for line in lines:
        print(line)
        print(f"::notice title=demo-seed::{sb.escape(line)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
