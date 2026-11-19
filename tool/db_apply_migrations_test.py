"""اختبارات أدوات `db_apply_migrations.py` الخالصة (الاتصال بالقاعدة يُجرَّب في CI)."""

import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import db_apply_migrations as m  # noqa: E402


class VersionTest(unittest.TestCase):
    def test_version_and_name(self):
        self.assertEqual(m.version_of(pathlib.Path("0010_group_price.sql")), ("0010", "group_price"))
        self.assertEqual(m.version_of(pathlib.Path("x/0001_schema.sql")), ("0001", "schema"))

    def test_unknown_name_is_rejected(self):
        with self.assertRaises(ValueError):
            m.version_of(pathlib.Path("notes.sql"))

    def test_files_are_ordered_and_pending_skips_applied(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = pathlib.Path(tmp)
            for name in ("0011_b.sql", "0002_a.sql", "0010_c.sql"):
                (folder / name).write_text("select 1;", encoding="utf-8")
            files = m.migration_files(folder)
            self.assertEqual([m.version_of(f)[0] for f in files], ["0002", "0010", "0011"])
            todo = m.pending(files, {"0002", "0010"})
            self.assertEqual([m.version_of(f)[0] for f in todo], ["0011"])
            self.assertEqual(m.pending(files, {"0002", "0010", "0011"}), [])

    def test_repository_migrations_all_parse(self):
        files = m.migration_files()
        self.assertTrue(files)
        versions = [m.version_of(f)[0] for f in files]
        self.assertEqual(versions, sorted(versions))
        self.assertEqual(len(versions), len(set(versions)))
        self.assertIn("0011", versions)


class ConnectionTest(unittest.TestCase):
    def test_default_hosts_cover_both_pooler_generations(self):
        self.assertEqual(
            m.pooler_hosts("eu-west-1"),
            ["aws-1-eu-west-1.pooler.supabase.com", "aws-0-eu-west-1.pooler.supabase.com"],
        )

    def test_hosts_can_be_overridden(self):
        self.assertEqual(m.pooler_hosts("x", " a.example , b.example,, "), ["a.example", "b.example"])

    def test_connection_env_uses_libpq_variables(self):
        env = m.connection_env("h.example", "abcd", "p@ss:/word")
        self.assertEqual(env["PGHOST"], "h.example")
        self.assertEqual(env["PGUSER"], "postgres.abcd")
        self.assertEqual(env["PGPASSWORD"], "p@ss:/word")
        self.assertEqual(env["PGSSLMODE"], "require")

    def test_first_line_skips_blank_lines(self):
        self.assertEqual(m.first_line("\n\n  تعذّر الاتصال \nثانياً"), "تعذّر الاتصال")
        self.assertEqual(m.first_line(""), "(بلا رسالة)")


if __name__ == "__main__":
    unittest.main()
