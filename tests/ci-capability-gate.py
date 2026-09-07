#!/usr/bin/env python3
"""校验 bbcosmo 能力报告与 CI runner 的平台契约。"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--os", required=True, dest="os_family")
    parser.add_argument("--arch", required=True, dest="arch_family")
    parser.add_argument("--name-search", required=True, choices=("builtin", "unsupported"))
    args = parser.parse_args()

    try:
        data = json.loads(args.report.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"能力报告不可读: {exc}", file=sys.stderr)
        return 2
    if not isinstance(data, dict):
        print("能力报告顶层必须是 JSON 对象", file=sys.stderr)
        return 2

    errors: list[str] = []

    def portable_isabs(value: str) -> bool:
        # Cosmopolitan 在 Windows 上可能输出 /c/path，宿主 Python 则使用 C:\\path。
        return os.path.isabs(value) or re.match(r"^/[A-Za-z](?:/|$)", value) is not None

    def require(key: str, expected: str) -> None:
        actual = data.get(key)
        if actual != expected:
            errors.append(f"{key}: 期望 {expected!r}，实际 {actual!r}")

    require("capabilities.schema", "1")
    require("busybox.entry", "available")
    require("platform.os.family", args.os_family)
    require("platform.arch.family", args.arch_family)
    for key in (
        "identity.username",
        "system.cpu_count",
        "system.dns_domain",
        "process.pid_probe",
        "filesystem.temp",
    ):
        require(key, "available")

    cpu_value = data.get("system.cpu_count.value", "")
    if not cpu_value.isdecimal() or int(cpu_value) < 1:
        errors.append(f"system.cpu_count.value: 应为正整数，实际 {cpu_value!r}")

    for key in (
        "archive.gzip.encode",
        "archive.gzip.decode",
        "archive.bzip2.encode",
        "archive.bzip2.decode",
        "archive.xz.decode",
        "archive.lzma.decode",
        "archive.zip.decode",
    ):
        require(key, "builtin")

    for operation in ("archive.xz.encode", "archive.lzma.encode", "archive.zip.encode"):
        source = data.get(operation)
        tool = data.get(f"{operation}.tool")
        if source == "external":
            if not isinstance(tool, str) or not portable_isabs(tool):
                errors.append(f"{operation}.tool: external 必须对应绝对路径，实际 {tool!r}")
        elif source == "unavailable":
            if tool != "none":
                errors.append(f"{operation}.tool: unavailable 必须对应 'none'，实际 {tool!r}")
        else:
            errors.append(f"{operation}: 未知来源 {source!r}")

    require("process.name_search", args.name_search)
    require("network.https.peer_verified", "unsupported")

    if errors:
        print("能力门禁失败:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        "能力门禁通过: "
        f"os={args.os_family} arch={args.arch_family} "
        f"name_search={args.name_search} cpu={cpu_value}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
