#!/usr/bin/env python3
"""يطبّق ترحيلات الخادم الناقصة على قاعدة مدرسة بكلمة سر القاعدة وحدها.

للحالة التي لا يصل فيها رمز Supabase الشخصي المخزَّن إلى مشروع المدرسة فيفشل `supabase-deploy` عند «Verify
access to the project» قبل أن يطبّق شيئاً. يتصل هذا الأمر بقاعدة المشروع عبر مجمّع الاتصالات (Supavisor) بالمستخدم
`postgres.<المعرّف>` وكلمة السر `SUPABASE_DB_PASSWORD`، ويطبّق ملفات `supabase/migrations` التي ليست في سجل
`supabase_migrations.schema_migrations` بالترتيب (كل ملف في معاملة واحدة، وكلها آمنة عند التكرار)، ويسجّلها في السجل
كما يفعل `supabase db push` فلا يعيدها النشر العادي بعد ذلك، ثم يتحقق من وجود الأعمدة والجداول الجديدة. لا يطبع
كلمة السر ولا يستعمل رمزاً شخصياً، ولا يمسّ الدوال ولا الأسرار (هذه من عمل `supabase-deploy`).

المتغيرات: SUPABASE_PROJECT_REF، SUPABASE_DB_PASSWORD؛ واختيارياً DB_POOLER_HOSTS (عناوين مفصولة بفواصل)
وDB_REGION (الافتراضي eu-west-1).
"""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = ROOT / "supabase" / "migrations"

# أعمدة وجداول الترحيلين 0010 و0011: يُتحقق منها بعد التطبيق.
VERIFY_SQL = """
select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and (
      (table_name = 'groups' and column_name in
        ('monthly_price', 'waiting_target', 'start_alerted_at', 'is_review'))
      or (table_name = 'group_students' and column_name = 'teacher_amount')
      or (table_name = 'students' and column_name = 'single_use'))) as cols,
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name in ('contacts', 'session_guests')) as tabs
"""
EXPECTED_VERIFY = "6|2"


def version_of(path: pathlib.Path) -> tuple[str, str]:
    """(الإصدار، الاسم) من اسم ملف مثل `0010_group_price.sql`، كما يخزّنهما `supabase db push`."""
    match = re.match(r"^(\d+)_(.+)\.sql$", path.name)
    if not match:
        raise ValueError(f"اسم ترحيل غير مفهوم: {path.name}")
    return match.group(1), match.group(2)


def migration_files(directory: pathlib.Path = MIGRATIONS_DIR) -> list[pathlib.Path]:
    return sorted(directory.glob("*.sql"), key=lambda p: version_of(p)[0])


def pending(files: list[pathlib.Path], applied: set[str]) -> list[pathlib.Path]:
    """الملفات التي ليس إصدارها في [applied]، بترتيبها."""
    return [f for f in files if version_of(f)[0] not in applied]


def pooler_hosts(region: str = "eu-west-1", override: str = "") -> list[str]:
    """عناوين مجمّع الاتصالات المحتملة: المشاريع الأحدث على `aws-1` والأقدم على `aws-0`."""
    if override.strip():
        return [h.strip() for h in override.split(",") if h.strip()]
    return [f"aws-1-{region}.pooler.supabase.com", f"aws-0-{region}.pooler.supabase.com"]


def connection_env(host: str, ref: str, password: str) -> dict[str, str]:
    """متغيرات libpq للاتصال (فلا يلزم ترميز كلمة السر في عنوان)."""
    env = dict(os.environ)
    env.update(
        PGHOST=host,
        PGPORT="5432",
        PGUSER=f"postgres.{ref}",
        PGPASSWORD=password,
        PGDATABASE="postgres",
        PGSSLMODE="require",
        PGCONNECT_TIMEOUT="20",
    )
    return env


def psql(env: dict[str, str], *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["psql", "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1", *args],
        env=env,
        capture_output=True,
        text=True,
        timeout=300,
    )


def first_line(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return line.strip()[:300]
    return "(بلا رسالة)"


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ref = os.environ.get("SUPABASE_PROJECT_REF", "").strip()
    password = os.environ.get("SUPABASE_DB_PASSWORD", "")
    if not ref or not password:
        print("ينقص SUPABASE_PROJECT_REF أو SUPABASE_DB_PASSWORD في بيئة المدرسة")
        return 2

    env = None
    for host in pooler_hosts(os.environ.get("DB_REGION") or "eu-west-1", os.environ.get("DB_POOLER_HOSTS") or ""):
        candidate = connection_env(host, ref, password)
        probe = psql(candidate, "-c", "select 1")
        if probe.returncode == 0:
            print(f"connected host={host}")
            env = candidate
            break
        print(f"cannot connect host={host}: {first_line(probe.stderr)}")
    if env is None:
        print("تعذّر الاتصال بقاعدة المشروع عبر المجمّع (راجع المعرّف وكلمة السر والمنطقة)")
        return 1

    history = psql(env, "-c", "select to_regclass('supabase_migrations.schema_migrations') is not null")
    has_history = history.returncode == 0 and history.stdout.strip() == "t"
    applied: set[str] = set()
    if has_history:
        rows = psql(env, "-c", "select version from supabase_migrations.schema_migrations")
        if rows.returncode != 0:
            print(f"تعذّرت قراءة سجل الترحيلات: {first_line(rows.stderr)}")
            return 1
        applied = {line.strip() for line in rows.stdout.splitlines() if line.strip()}
    print(f"applied-before={sorted(applied)}")

    todo = pending(migration_files(), applied)
    print(f"pending={[version_of(f)[0] for f in todo]}")
    for path in todo:
        version, name = version_of(path)
        result = psql(env, "--single-transaction", "-f", str(path))
        if result.returncode != 0:
            print(f"فشل تطبيق {path.name}: {first_line(result.stderr)}")
            return 1
        print(f"applied {path.name}")
        if has_history:
            record = psql(
                env,
                "-c",
                "insert into supabase_migrations.schema_migrations (version, name, statements) "
                f"values ('{version}', '{name}', '{{}}') on conflict (version) do nothing",
            )
            if record.returncode != 0:
                print(f"طُبّق {path.name} وتعذّر تسجيله: {first_line(record.stderr)}")
                return 1

    verify = psql(env, "-F", "|", "-c", VERIFY_SQL)
    if verify.returncode != 0 or verify.stdout.strip() != EXPECTED_VERIFY:
        print(f"verify=failed got={verify.stdout.strip()!r} {first_line(verify.stderr)}")
        return 1
    print("verify=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
