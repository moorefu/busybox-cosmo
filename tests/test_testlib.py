"""验证测试设施自身：断言失败、信号和清理不能相互覆盖。"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

LIB = Path(__file__).resolve().with_name("testlib.sh")


class TestLibraryTests(unittest.TestCase):
    def run_script(self, script, keep=False):
        temp = tempfile.TemporaryDirectory(prefix="测试 space ")
        self.addCleanup(temp.cleanup)
        env = dict(os.environ, TEST_LIBRARY=str(LIB), KEEP_TEST_ROOT="1" if keep else "0")
        result = subprocess.run(["sh", "-c", '. "$TEST_LIBRARY"; ' + script], cwd=temp.name,
                                env=env, capture_output=True, text=True, timeout=5)
        return result, list(Path(temp.name).iterdir())

    def test_success_cleans_absolute_directory(self):
        result, files = self.run_script("bbtest_init selftest; printf data > value; exit 0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(files, [])

    def test_failure_status_and_log_survive_cleanup(self):
        result, files = self.run_script("bbtest_init selftest; bbtest_run sh -c 'echo detail >&2; exit 23'")
        self.assertEqual(result.returncode, 23)
        self.assertIn("detail", result.stderr)
        self.assertEqual(files, [])

    def test_soft_probe_keeps_log_quiet(self):
        result, files = self.run_script(
            "bbtest_init selftest; bbtest_try sh -c 'echo expected >&2; exit 7'; test $? = 7"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("expected", result.stderr)
        self.assertEqual(files, [])

    def test_keep_test_root(self):
        result, files = self.run_script("bbtest_init selftest; exit 19", keep=True)
        self.assertEqual(result.returncode, 19)
        self.assertEqual(len(files), 1)
        self.assertIn(str(files[0]), result.stderr)

    def test_cannot_create_directory_is_bounded(self):
        result, files = self.run_script("mkdir() { return 1; }; bbtest_init selftest")
        self.assertEqual(result.returncode, 2)
        self.assertIn("20", result.stderr)
        self.assertEqual(files, [])

    def test_term_cleans_and_returns_signal_status(self):
        result, files = self.run_script("bbtest_init selftest; kill -TERM $$; exit 0")
        self.assertEqual(result.returncode, 143)
        self.assertEqual(files, [])


if __name__ == "__main__":
    unittest.main()
