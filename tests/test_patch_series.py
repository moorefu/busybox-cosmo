"""补丁管理回归；不需要工具链或网络。"""
import contextlib
import hashlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("series", ROOT / "scripts/patch-series.py")
series = importlib.util.module_from_spec(spec)
spec.loader.exec_module(series)


class PatchSeriesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        (self.source / "value").write_text("before\n")
        self.target = self.root / "target"
        self.series = self.root / "series"
        self.series.write_text("# 注释\n\na.patch\n")
        self.patch = self.root / "a.patch"
        self.patch.write_text("--- a/value\n+++ b/value\n@@ -1 +1 @@\n-before\n+after\n")

    def apply(self):
        with contextlib.redirect_stdout(io.StringIO()):
            series.apply(self.series, self.source, self.target)

    def test_apply_and_reuse(self):
        self.apply()
        self.assertEqual((self.target / "value").read_text(), "after\n")
        self.apply()
        self.assertEqual((self.source / "value").read_text(), "before\n")

    def test_changed_patch_rejects_reuse(self):
        self.apply()
        self.patch.write_text(self.patch.read_text().replace("after", "changed"))
        with self.assertRaises(ValueError):
            self.apply()
        self.assertEqual((self.target / "value").read_text(), "after\n")

    def test_failed_series_leaves_no_target(self):
        (self.root / "b.patch").write_text(self.patch.read_text())
        self.series.write_text("a.patch\nb.patch\n")
        with self.assertRaises(subprocess.CalledProcessError):
            self.apply()
        self.assertFalse(self.target.exists())
        self.assertEqual(list(self.root.glob(".patch-stage-*")), [])

    def test_unmarked_tree_is_preserved(self):
        self.target.mkdir()
        (self.target / "user-file").write_text("保留")
        with self.assertRaises(ValueError):
            self.apply()
        self.assertEqual((self.target / "user-file").read_text(), "保留")

    def test_order_changes_fingerprint(self):
        (self.root / "b.patch").write_bytes(self.patch.read_bytes())
        self.series.write_text("a.patch\nb.patch\n")
        first = series.fingerprint(self.series)
        self.series.write_text("b.patch\na.patch\n")
        self.assertNotEqual(first, series.fingerprint(self.series))

    def test_invalid_series(self):
        for text in ["", "a.patch\na.patch\n", "../a.patch\n", "/a.patch\n", "missing.patch\n"]:
            with self.subTest(text=text):
                self.series.write_text(text)
                with self.assertRaises(ValueError):
                    series.read_series(self.series)


class BusyBoxResultTests(unittest.TestCase):
    def test_result_against_locked_manifest(self):
        source = ROOT / "src/busybox-1.38.0"
        if not source.is_dir():
            self.skipTest("先运行 make fetch 可开启真实源码验证")
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "patched"
            series.apply(ROOT / "patches/busybox/series", source, target)
            manifest = (ROOT / "patches/busybox/result.sha256").read_text().splitlines()
            expected_names = []
            for line in manifest:
                digest, name = line.split("  ", 1)
                expected_names.append(name)
                with self.subTest(file=name):
                    self.assertEqual(hashlib.sha256((target / name).read_bytes()).hexdigest(), digest)
            changed = []
            for path in target.rglob("*"):
                if not path.is_file() or path.name == ".bb-series-ok":
                    continue
                name = path.relative_to(target).as_posix()
                original = source / name
                if not original.is_file() or original.read_bytes() != path.read_bytes():
                    changed.append(name)
            self.assertEqual(sorted(expected_names), expected_names, "结果清单必须稳定排序")
            self.assertEqual(sorted(changed), expected_names, "补丁结果清单缺项或含多余项")
            self.assertFalse((target / "include/usage.h").exists(), "生成文件不应入补丁")
            subprocess.run(["sh", "scripts/gen_build_files.sh", ".", "."], cwd=target, check=True,
                           stdout=subprocess.DEVNULL)
            usage = (target / "include/usage.h").read_text()
            self.assertIn("MAKE", usage.upper())
            self.assertIn("tar_trivial_usage", usage)


if __name__ == "__main__":
    unittest.main()
