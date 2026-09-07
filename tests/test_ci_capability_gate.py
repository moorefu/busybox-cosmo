#!/usr/bin/env python3
"""能力门禁的正向与拒绝路径测试。"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "tests" / "ci-capability-gate.py"


def valid_report() -> dict[str, str]:
    report = {
        "capabilities.schema": "1",
        "busybox.entry": "available",
        "platform.os.family": "linux",
        "platform.arch.family": "x86_64",
        "identity.username": "available",
        "system.cpu_count": "available",
        "system.cpu_count.value": "4",
        "system.dns_domain": "available",
        "process.pid_probe": "available",
        "process.name_search": "builtin",
        "filesystem.temp": "available",
        "network.https.peer_verified": "unsupported",
    }
    for operation in (
        "archive.gzip.encode",
        "archive.gzip.decode",
        "archive.bzip2.encode",
        "archive.bzip2.decode",
        "archive.xz.decode",
        "archive.lzma.decode",
        "archive.zip.decode",
    ):
        report[operation] = "builtin"
    for operation in (
        "archive.xz.encode",
        "archive.lzma.encode",
        "archive.zip.encode",
        "archive.zstd.roundtrip",
    ):
        report[operation] = "unavailable"
        report[f"{operation}.tool"] = "none"
    return report


class CapabilityGateTests(unittest.TestCase):
    def run_gate(
        self, report: object, *, text: bool = True, env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "capabilities.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            return subprocess.run(
                [
                    sys.executable,
                    str(GATE),
                    str(path),
                    "--os",
                    "linux",
                    "--arch",
                    "x86_64",
                    "--name-search",
                    "builtin",
                ],
                check=False,
                capture_output=True,
                text=text,
                env=env,
            )

    def test_valid_report_passes(self) -> None:
        result = self.run_gate(valid_report())
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_cp1252_runner_still_emits_utf8_diagnostics(self) -> None:
        env = dict(os.environ, PYTHONIOENCODING="cp1252")
        result = self.run_gate(valid_report(), text=False, env=env)
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8"))
        self.assertIn("能力门禁通过", result.stdout.decode("utf-8"))

    def test_invalid_reports_are_rejected(self) -> None:
        cases: list[tuple[str, object]] = []

        missing_schema = valid_report()
        del missing_schema["capabilities.schema"]
        cases.append(("缺少 schema", missing_schema))

        bad_cpu = valid_report()
        bad_cpu["system.cpu_count.value"] = "0"
        cases.append(("CPU 非正数", bad_cpu))

        relative_tool = valid_report()
        relative_tool["archive.xz.encode"] = "external"
        relative_tool["archive.xz.encode.tool"] = "bin/xz"
        cases.append(("外部工具不是绝对路径", relative_tool))

        mismatched_tool = valid_report()
        mismatched_tool["archive.zip.encode.tool"] = "/usr/bin/zip"
        cases.append(("不可用能力却携带工具路径", mismatched_tool))

        cases.append(("顶层不是对象", []))

        for name, report in cases:
            with self.subTest(name=name):
                result = self.run_gate(report)
                self.assertNotEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    unittest.main()
