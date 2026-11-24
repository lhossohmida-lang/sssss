import tempfile
import unittest
from pathlib import Path

import pwa_sw


class PwaServiceWorkerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for rel in (
            "index.html",
            "flutter_bootstrap.js",
            "manifest.json",
            "sqlite3.wasm",
            "drift_worker.js",
            "drift_worker.js.map",
            "assets/fonts/Cairo.ttf",
            "icons/Icon-192.png",
            "main.dart.js",
            "main.dart.wasm",
            "main.dart.mjs",
            "canvaskit/canvaskit.wasm",
            "flutter_service_worker.js",
            ".last_build_id",
        ):
            path = self.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(rel.encode())

    def test_the_shell_is_precached_and_compiled_code_is_cached_on_first_use(self):
        shell = pwa_sw.precached(pwa_sw.site_files(self.root))
        for rel in ("index.html", "flutter_bootstrap.js", "sqlite3.wasm", "drift_worker.js", "assets/fonts/Cairo.ttf"):
            self.assertIn(rel, shell)
        for rel in ("main.dart.js", "main.dart.wasm", "main.dart.mjs", "canvaskit/canvaskit.wasm"):
            self.assertNotIn(rel, shell)

    def test_build_leftovers_are_never_cached(self):
        files = pwa_sw.site_files(self.root)
        for rel in ("flutter_service_worker.js", ".last_build_id", "drift_worker.js.map", "sw.js"):
            self.assertNotIn(rel, files)

    def test_the_cache_name_follows_the_content(self):
        files = pwa_sw.site_files(self.root)
        before = pwa_sw.version(self.root, files)
        self.assertEqual(before, pwa_sw.version(self.root, files))
        (self.root / "main.dart.wasm").write_bytes(b"new build")
        self.assertNotEqual(before, pwa_sw.version(self.root, files))

    def test_the_worker_is_written_per_app(self):
        out = pwa_sw.write(self.root, "admin")
        text = out.read_text(encoding="utf-8")
        self.assertIn('const PREFIX = "school-admin-";', text)
        self.assertIn('"./", "assets/fonts/Cairo.ttf"', text)
        self.assertIn("request.mode === 'navigate'", text)
        self.assertNotIn("supabase", text.lower().replace("(supabase)", ""))
        # العامل نفسه ليس في قائمة الحفظ، ويعاد توليده بالبصمة نفسها.
        self.assertNotIn('"sw.js"', text)
        self.assertEqual(text, pwa_sw.write(self.root, "admin").read_text(encoding="utf-8"))

    def test_a_folder_without_index_is_refused(self):
        (self.root / "index.html").unlink()
        with self.assertRaises(SystemExit):
            pwa_sw.write(self.root, "admin")


if __name__ == "__main__":
    unittest.main()
