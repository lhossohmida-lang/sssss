#!/usr/bin/env bash
# يطبّق ملفات supabase/migrations على قاعدة PostgreSQL نظيفة ثم يشغّل
# supabase/tests. يعمل محلياً (عنقود PostgreSQL 16 للنظام) وفي GitHub Actions
# (عبر PGHOST / PGUSER / PGPASSWORD).
set -euo pipefail
cd "$(dirname "$0")/.."
DB="school_test"

run_psql() {
  # رسائل NOTICE تُخفى؛ أي خطأ يوقف التنفيذ.
  if [ -n "${PGHOST:-}" ]; then
    PGOPTIONS="--client-min-messages=warning" psql -q -o /dev/null -v ON_ERROR_STOP=1 "$@"
  else
    su postgres -c "PGOPTIONS=--client-min-messages=warning psql -q -o /dev/null -v ON_ERROR_STOP=1 $(printf '%q ' "$@")"
  fi
}

if [ -z "${PGHOST:-}" ]; then
  pg_lsclusters | grep -q online || pg_ctlcluster 16 main start
  for _ in $(seq 1 20); do
    su postgres -c "pg_isready -q" && break
    sleep 0.5
  done
fi

run_psql -d postgres -c "drop database if exists ${DB}" -c "create database ${DB}"

# نسخة يقرؤها مستخدم postgres المحلي.
WORK="$(mktemp -d)"
cp -r supabase "$WORK/"
chmod -R a+rX "$WORK"

# بديل الأدوار والدالة auth.uid() التي يوفّرها Supabase جاهزة.
run_psql -d "$DB" -f "$WORK/supabase/local/000_auth_shim.sql"

for file in "$WORK"/supabase/migrations/*.sql; do
  # التطبيق مرتين يثبت أن الملف آمن عند إعادة التشغيل.
  run_psql -d "$DB" -f "$file"
  run_psql -d "$DB" -f "$file"
done
for file in "$WORK"/supabase/tests/*.sql; do
  echo "== $(basename "$file")"
  run_psql -d "$DB" -f "$file"
done
rm -rf "$WORK"
echo "PG TESTS PASSED"
