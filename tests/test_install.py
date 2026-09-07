#!/usr/bin/env python3
"""安装器输入边界测试。"""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "install.sh"


class InstallerTests(unittest.TestCase):
    def test_unsafe_prefix_is_rejected_before_writing_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "injected"
            cases = (
                f'{tmp}/x"; touch {marker}; #',
                f"{tmp}/x$(touch {marker})",
                f"{tmp}/line\nbreak",
                f"{tmp}/back\\slash",
            )
            for prefix in cases:
                with self.subTest(prefix=prefix):
                    result = subprocess.run(
                        ["sh", str(INSTALLER), "--prefix", prefix],
                        cwd=ROOT,
                        env={**os.environ, "HOME": tmp},
                        check=False,
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertIn("不安全字符", result.stderr)
                    self.assertFalse(marker.exists())

    def test_uninstall_rejects_out_of_prefix_manifest_before_deleting(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            prefix = Path(tmp) / "install"
            installed = prefix / "bin" / "busybox"
            installed.parent.mkdir(parents=True)
            installed.write_text("installed", encoding="utf-8")
            outside = Path(tmp) / "outside"
            outside.write_text("keep", encoding="utf-8")
            manifest = prefix / ".busybox-cosmo-manifest"
            manifest.write_text(f"{installed}\n{outside}\n", encoding="utf-8")

            result = subprocess.run(
                ["sh", str(INSTALLER), "--prefix", str(prefix), "--uninstall"],
                cwd=ROOT,
                env={**os.environ, "HOME": tmp},
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("越界目标", result.stderr)
            self.assertTrue(installed.exists(), "校验失败前不应部分卸载")
            self.assertTrue(outside.exists())

    def test_manifest_symlink_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            prefix = Path(tmp) / "install"
            prefix.mkdir()
            outside = Path(tmp) / "outside-manifest"
            outside.write_text("keep", encoding="utf-8")
            (prefix / ".busybox-cosmo-manifest").symlink_to(outside)

            result = subprocess.run(
                ["sh", str(INSTALLER), "--prefix", str(prefix), "--uninstall"],
                cwd=ROOT,
                env={**os.environ, "HOME": tmp},
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("符号链接安装清单", result.stderr)
            self.assertEqual(outside.read_text(encoding="utf-8"), "keep")


if __name__ == "__main__":
    unittest.main()
