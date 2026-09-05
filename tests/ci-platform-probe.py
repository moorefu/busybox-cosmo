#!/usr/bin/env python3
"""在 GitHub Actions 真机上收集待定兼容性的最小证据。

探针默认只报告结果；调用者可根据输出决定是否把某个平台提升为发布门禁。
返回值：0=通过或明确跳过，1=发现回归，2=参数/基础设施错误。
"""

from __future__ import annotations

import argparse
import os
import pty
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def run(cmd: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    kwargs.setdefault("timeout", 30)
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def has_applet(busybox: str, name: str) -> bool:
    result = run([busybox, "--list"])
    return result.returncode == 0 and name in result.stdout.split()


def probe_argv(busybox: str) -> bool:
    if not has_applet(busybox, "sh"):
        print("SKIP argv: 未编译 sh applet")
        return True
    args = [f"arg-{i:03d}" for i in range(256)]
    script = 'bb="$1"; shift; exec "$bb" sh -c \'printf "%s" "$#"\' inner "$@"'
    result = run([busybox, "sh", "-c", script, "outer", busybox, *args])
    ok = result.returncode == 0 and result.stdout == "256"
    print(f"{'PASS' if ok else 'FAIL'} argv-256: rc={result.returncode} stdout={result.stdout!r}")
    if not ok:
        print(result.stderr, file=sys.stderr, end="")
    return ok


def tty_value(output: str, name: str) -> str | None:
    match = re.search(r"(?:^|[;\s])" + re.escape(name) + r"\s*=\s*([^;,\s]+)", output)
    return match.group(1) if match else None


def run_on_slave(cmd: list[str], slave: int) -> subprocess.CompletedProcess[str]:
    return run(cmd, stdin=slave)


def probe_termios(busybox: str) -> bool:
    if not has_applet(busybox, "stty"):
        print("SKIP termios: 未编译 stty applet")
        return True
    host_stty = shutil.which("stty")
    if not host_stty:
        print("SKIP termios: runner 没有宿主 stty")
        return True

    master, slave = pty.openpty()
    try:
        # 两个方向各改一次，避免只验证 BusyBox 自己读回自己的错误槽位。
        bb_set = run_on_slave([busybox, "stty", "erase", "^X"], slave)
        host_read = run_on_slave([host_stty, "-a"], slave)
        host_set = run_on_slave([host_stty, "erase", "^Y"], slave)
        bb_read = run_on_slave([busybox, "stty", "-a"], slave)
    finally:
        os.close(master)
        os.close(slave)

    bb_ok = bb_set.returncode == 0 and tty_value(host_read.stdout, "erase") == "^X"
    host_ok = host_set.returncode == 0 and tty_value(bb_read.stdout, "erase") == "^Y"
    ok = bb_ok and host_ok
    print(
        f"{'PASS' if ok else 'FAIL'} termios erase: "
        f"busybox->host={tty_value(host_read.stdout, 'erase')!r}, "
        f"host->busybox={tty_value(bb_read.stdout, 'erase')!r}"
    )
    if not ok:
        for label, result in (("busybox-set", bb_set), ("host-read", host_read), ("host-set", host_set), ("busybox-read", bb_read)):
            print(f"--- {label} rc={result.returncode} ---\n{result.stdout}{result.stderr}", file=sys.stderr, end="")
    return ok


def probe_tar(busybox: str) -> bool:
    if not has_applet(busybox, "tar"):
        print("SKIP tar-xz: 未编译 tar applet")
        return True
    xz = shutil.which("xz")
    if not xz:
        print("SKIP tar-xz: runner 没有宿主 xz 编码器")
        return True

    with tempfile.TemporaryDirectory(prefix="busybox-ci-tar-") as root:
        root_path = Path(root)
        source = root_path / "source"
        source.mkdir()
        (source / "payload").write_text("tar-xz-kat\n", encoding="utf-8")
        archive = root_path / "payload.txz"
        env = os.environ.copy()
        # 保留 launcher 所需的 dirname/uname 等宿主命令，只把 xz 所在目录放在 PATH 前面。
        original_path = env.get("PATH", "")
        env["PATH"] = str(Path(xz).parent) + os.pathsep + original_path
        encoded = run([busybox, "tar", "cJf", str(archive), "source"], cwd=root, env=env)
        decoded = run([busybox, "tar", "xJf", str(archive), "-O", "source/payload"], cwd=root, env=env)

        # PATH 首位放一个失败假编码器，必须清晰失败，不能误走 BusyBox xz 自执行。
        no_xz = root_path / "no-xz"
        no_xz.mkdir()
        fake_xz = no_xz / "xz"
        fake_xz.write_text("#!/bin/sh\nexit 127\n", encoding="utf-8")
        fake_xz.chmod(0o755)
        missing = run(
            [busybox, "tar", "cJf", str(root_path / "missing.txz"), "source"],
            cwd=root,
            env={**env, "PATH": str(no_xz) + os.pathsep + original_path},
        )
        ok = (
            encoded.returncode == 0
            and archive.stat().st_size > 0
            and decoded.returncode == 0
            and decoded.stdout == "tar-xz-kat\n"
            and missing.returncode != 0
        )
        print(
            f"{'PASS' if ok else 'FAIL'} tar-xz: encode_rc={encoded.returncode} "
            f"bytes={archive.stat().st_size if archive.exists() else 0} "
            f"decode_rc={decoded.returncode} missing_xz_rc={missing.returncode}"
        )
        if not ok:
            for label, result in (("encode", encoded), ("decode", decoded), ("missing-xz", missing)):
                print(f"--- {label} rc={result.returncode} ---\n{result.stdout}{result.stderr}", file=sys.stderr, end="")
        return ok


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("busybox")
    parser.add_argument("--only", choices=("all", "argv", "termios", "tar"), default="all")
    args = parser.parse_args()
    busybox = os.path.abspath(args.busybox)
    if not os.access(busybox, os.X_OK):
        print(f"错误：BusyBox 不可执行: {busybox}", file=sys.stderr)
        return 2
    checks = {
        "argv": probe_argv,
        "termios": probe_termios,
        "tar": probe_tar,
    }
    selected = checks.items() if args.only == "all" else ((args.only, checks[args.only]),)
    ok = True
    for name, check in selected:
        try:
            ok = check(busybox) and ok
        except (OSError, PermissionError, subprocess.TimeoutExpired) as exc:
            print(f"ERROR {name}: 无法启动 BusyBox: {exc}", file=sys.stderr)
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
