"""اختبارات ci_error.py: إخفاء الأسرار والهروب وقص الذيل."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ci_error  # noqa: E402


class Sanitize(unittest.TestCase):
    def test_secrets_are_masked_longest_first(self):
        text = "connect postgres://u:SuperSecret123@host and SuperSecret"
        out = ci_error.sanitize(text, ["SuperSecret", "SuperSecret123"])
        self.assertNotIn("SuperSecret", out)
        self.assertEqual(out, "connect postgres://u:***@host and ***")

    def test_short_and_empty_values_are_not_masked(self):
        self.assertEqual(ci_error.sanitize("a ab abc", ["", "a", "ab", "abc"]), "a ab abc")


class Annotation(unittest.TestCase):
    def test_keeps_only_the_tail_and_escapes_to_one_line(self):
        text = "\n".join(f"line {i}" for i in range(100)) + "\n100% done"
        line = ci_error.annotation("title", text, [], tail=3)
        self.assertTrue(line.startswith("::error title=title::"))
        self.assertNotIn("\n", line)
        self.assertEqual(line.split("::", 2)[2], "line 98%0Aline 99%0A100%25 done")

    def test_long_lines_are_cut_and_secrets_never_appear(self):
        line = ci_error.annotation("t", "x" * 1000 + "TOKEN-VALUE-1", ["TOKEN-VALUE-1"], width=300)
        self.assertEqual(len(line.split("::", 2)[2]), 300)
        self.assertNotIn("TOKEN-VALUE-1", line)
        line = ci_error.annotation("t", "fail with TOKEN-VALUE-1", ["TOKEN-VALUE-1"])
        self.assertNotIn("TOKEN-VALUE-1", line)
        self.assertIn("***", line)


if __name__ == "__main__":
    unittest.main()
