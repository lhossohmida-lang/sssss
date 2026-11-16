"""اختبارات windows_dll_check.py على ملفات PE اصطناعية صغيرة (تعمل على أي نظام)."""

import contextlib
import io
import os
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import windows_dll_check as chk  # noqa: E402

SECTION_RVA = 0x1000
SECTION_OFFSET = 0x400


def make_pe(imports=(), delay=(), machine=chk.MACHINE_X64, pe32=False) -> bytes:
    """ملف PE أدنى فيه جدول استيراد وجدول استيراد مؤجَّل بالأسماء المعطاة (يكفي لاختبار المحلّل)."""
    names, name_offsets, cursor = b"", {}, 0
    import_size = 20 * (len(imports) + 1)
    delay_size = 32 * (len(delay) + 1)
    names_start = import_size + delay_size
    for name in [*imports, *delay]:
        name_offsets[name] = names_start + len(names)
        names += name.encode("ascii") + b"\0"
        cursor += 1
    body = bytearray()
    for name in imports:
        body += struct.pack("<IIIII", 0, 0, 0, SECTION_RVA + name_offsets[name], 0)
    body += b"\0" * 20
    for name in delay:
        body += struct.pack("<IIIIIIII", 1, SECTION_RVA + name_offsets[name], 0, 0, 0, 0, 0, 0)
    body += b"\0" * 32
    body += names

    optional_size = 224 if pe32 else 240
    optional = bytearray(optional_size)
    struct.pack_into("<H", optional, 0, chk.MAGIC_PE32 if pe32 else chk.MAGIC_PE32_PLUS)
    directories = 96 if pe32 else 112
    struct.pack_into("<I", optional, directories - 4, 16)
    if imports:
        struct.pack_into("<II", optional, directories + 8 * chk.DIR_IMPORT, SECTION_RVA, import_size)
    if delay:
        struct.pack_into("<II", optional, directories + 8 * chk.DIR_DELAY_IMPORT, SECTION_RVA + import_size, delay_size)

    header = bytearray(64)
    header[0:2] = b"MZ"
    struct.pack_into("<I", header, 0x3C, 0x40)
    coff = struct.pack("<HHIIIHH", machine, 1, 0, 0, 0, optional_size, 0x2022)
    section = struct.pack("<8sIIIIIIHHI", b".idata", len(body), SECTION_RVA, len(body), SECTION_OFFSET, 0, 0, 0, 0, 0x40000040)
    data = bytes(header) + b"PE\0\0" + coff + bytes(optional) + section
    return data.ljust(SECTION_OFFSET, b"\0") + bytes(body)


class Parse(unittest.TestCase):
    def test_reads_imports_delay_imports_and_machine(self):
        info = chk.parse_pe(make_pe(["KERNEL32.dll", "VCRUNTIME140.dll"], ["d3d9.dll"]))
        self.assertEqual(info.machine, chk.MACHINE_X64)
        self.assertEqual(info.imports, ["KERNEL32.dll", "VCRUNTIME140.dll"])
        self.assertEqual(info.delay_imports, ["d3d9.dll"])

    def test_a_file_without_imports(self):
        info = chk.parse_pe(make_pe())
        self.assertEqual((info.imports, info.delay_imports), ([], []))

    def test_32_bit_layout_is_read_too(self):
        info = chk.parse_pe(make_pe(["kernel32.dll"], machine=0x14C, pe32=True))
        self.assertEqual(info.machine, 0x14C)
        self.assertEqual(info.imports, ["kernel32.dll"])

    def test_garbage_and_truncated_files_raise_pe_error(self):
        for bad in (b"", b"not a pe file at all", make_pe(["a.dll"])[:100]):
            with self.assertRaises(chk.PeError):
                chk.parse_pe(bad)

    @unittest.skipUnless(sys.platform == "win32", "ملفات Windows الحقيقية")
    def test_a_real_windows_binary(self):
        with open(os.path.join(os.environ["SystemRoot"], "System32", "notepad.exe"), "rb") as f:
            info = chk.parse_pe(f.read())
        self.assertEqual(info.machine, chk.MACHINE_X64)
        self.assertTrue(any(name.lower() == "kernel32.dll" for name in info.imports + info.delay_imports))


class Folder(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = self.tmp.name

    def put(self, name, **kwargs):
        raw = kwargs.pop("raw", None)
        with open(os.path.join(self.dir, name), "wb") as f:
            f.write(raw if raw is not None else make_pe(**kwargs))

    def check(self, **kwargs):
        return chk.check(self.dir, chk.load_os_names(None), **kwargs)

    def test_a_complete_app_passes(self):
        self.put("admin.exe", imports=["KERNEL32.dll", "flutter_windows.dll", "VCRUNTIME140.dll", "api-ms-win-crt-runtime-l1-1-0.dll"])
        self.put("flutter_windows.dll", imports=["user32.dll", "D3D9.dll", "msvcp140.dll"])
        self.put("vcruntime140.dll", imports=["kernel32.dll"])
        self.put("msvcp140.dll", imports=["kernel32.dll", "vcruntime140.dll"])
        report = self.check()
        self.assertTrue(report.ok, chk.describe(report))
        self.assertEqual(report.bundled_runtime, ["msvcp140.dll", "vcruntime140.dll"])

    def test_the_missing_visual_cpp_runtime_is_the_error_it_exists_to_catch(self):
        self.put("admin.exe", imports=["kernel32.dll", "MSVCP140.dll", "VCRUNTIME140.dll", "VCRUNTIME140_1.dll"])
        self.put("plugin.dll", imports=["vcruntime140.dll"])
        report = self.check()
        self.assertFalse(report.ok)
        self.assertEqual(sorted(report.missing), ["msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"])
        self.assertEqual(sorted(report.missing["vcruntime140.dll"]), ["admin.exe", "plugin.dll"])

    def test_names_are_case_insensitive(self):
        self.put("Admin.EXE", imports=["VCRUNTIME140.DLL"])
        self.put("VCRuntime140.dll")
        self.assertTrue(self.check().ok)

    def test_an_unknown_third_party_dll_is_missing(self):
        self.put("admin.exe", imports=["kernel32.dll", "somevendor.dll"])
        self.assertEqual(list(self.check().missing), ["somevendor.dll"])

    def test_delay_loaded_dlls_only_warn(self):
        self.put("admin.exe", imports=["kernel32.dll"], delay=["optional-extra.dll", "d3d9.dll"])
        report = self.check()
        self.assertTrue(report.ok)
        self.assertEqual(list(report.delay_missing), ["optional-extra.dll"])

    def test_a_dll_both_imported_and_delay_imported_is_reported_once_as_missing(self):
        self.put("a.exe", imports=["gone.dll"])
        self.put("b.dll", imports=["kernel32.dll"], delay=["gone.dll"])
        report = self.check()
        self.assertEqual(list(report.missing), ["gone.dll"])
        self.assertEqual(report.delay_missing, {})

    def test_a_tolerated_pair_is_not_an_error_but_other_importers_still_are(self):
        self.put("dartjni.dll", imports=["kernel32.dll", "jvm.dll"])
        self.put("other.dll", imports=["jvm.dll"])
        tolerated = chk.parse_tolerated(["dartjni.dll:jvm.dll"])
        report = self.check(tolerated=tolerated)
        self.assertEqual(report.tolerated, ["dartjni.dll ← jvm.dll"])
        self.assertEqual(report.missing, {"jvm.dll": ["other.dll"]})

    def test_tolerate_syntax_is_validated(self):
        for bad in ("nocolon", ":x.dll", "a.dll:"):
            with self.assertRaises(ValueError):
                chk.parse_tolerated([bad])

    def test_a_32_bit_binary_is_reported(self):
        self.put("old.dll", imports=["kernel32.dll"], machine=0x14C, pe32=True)
        report = self.check()
        self.assertFalse(report.ok)
        self.assertEqual(report.wrong_machine, ["old.dll (0x014c)"])

    def test_a_broken_dll_is_reported_not_skipped(self):
        self.put("broken.dll", raw=b"MZ garbage")
        report = self.check()
        self.assertFalse(report.ok)
        self.assertEqual(report.unreadable, ["broken.dll"])

    def test_other_files_are_ignored(self):
        self.put("admin.exe", imports=["kernel32.dll"])
        with open(os.path.join(self.dir, "readme.txt"), "w") as f:
            f.write("x")
        os.mkdir(os.path.join(self.dir, "data"))
        self.assertTrue(self.check().ok)
        self.assertEqual(self.check().files, ["admin.exe"])

    def test_the_os_list_file_adds_names(self):
        self.put("admin.exe", imports=["customwindows.dll"])
        self.assertFalse(self.check().ok)
        path = os.path.join(self.dir, "..", "os-list-test.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write("CustomWindows.dll\n\n")
        self.addCleanup(lambda: os.path.exists(path) and os.remove(path))
        names = chk.load_os_names(path)
        self.assertTrue(chk.check(self.dir, names).ok)

    def test_the_builtin_list_never_contains_the_visual_cpp_runtime(self):
        for name in chk.BUILTIN_OS:
            self.assertFalse(name.startswith(("vcruntime", "msvcp", "concrt", "vcomp")), name)


class Cli(unittest.TestCase):
    def run_main(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = chk.main(["windows_dll_check.py", *args])
        return code, out.getvalue()

    def test_exit_codes_and_annotations(self):
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "admin.exe"), "wb") as f:
                f.write(make_pe(imports=["kernel32.dll", "VCRUNTIME140.dll"]))
            code, out = self.run_main(tmp)
            self.assertEqual(code, 1)
            self.assertIn("::error title=windows-dll-check::", out)
            self.assertIn("vcruntime140.dll", out)
            with open(os.path.join(tmp, "vcruntime140.dll"), "wb") as f:
                f.write(make_pe(imports=["kernel32.dll"]))
            code, out = self.run_main(tmp)
            self.assertEqual(code, 0)
            self.assertIn("::notice title=windows-dll-check::ok files=2", out)
            self.assertNotIn("::error", out)

    def test_delay_warning_is_an_annotation(self):
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "admin.exe"), "wb") as f:
                f.write(make_pe(imports=["kernel32.dll"], delay=["optional.dll"]))
            code, out = self.run_main(tmp)
            self.assertEqual(code, 0)
            self.assertIn("::warning title=windows-dll-check::optional.dll", out)

    def test_missing_folder_and_bad_tolerate_are_usage_errors(self):
        self.assertEqual(self.run_main(os.path.join(tempfile.gettempdir(), "no-such-folder-xyz"))[0], 2)
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.run_main(tmp, "--tolerate", "bad")[0], 2)


if __name__ == "__main__":
    unittest.main()
