#!/usr/bin/env python3
"""在独立 Windows Console 内验证 bbtty；不会改变 runner 的终端状态。

父进程捕获日志，子进程用 CONIN$/CONOUT$ 给被测程序提供真实控制台句柄。
此驱动验证传统 Console；ConPTY 会话创建和输入字节流需单独验收。
"""
import ctypes
from ctypes import wintypes
import os
import subprocess
import sys


def worker(binary):
    import msvcrt

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetConsoleMode.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel.GetConsoleMode.restype = wintypes.BOOL
    kernel.SetConsoleMode.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel.SetConsoleMode.restype = wintypes.BOOL
    for name in ("GetConsoleCP", "GetConsoleOutputCP"):
        getattr(kernel, name).restype = wintypes.UINT
    for name in ("SetConsoleCP", "SetConsoleOutputCP"):
        getattr(kernel, name).argtypes = [wintypes.UINT]
        getattr(kernel, name).restype = wintypes.BOOL

    infd = os.open("CONIN$", os.O_RDWR | os.O_BINARY)
    outfd = os.open("CONOUT$", os.O_RDWR | os.O_BINARY)
    hin, hout = map(msvcrt.get_osfhandle, (infd, outfd))

    def mode(handle):
        value = wintypes.DWORD()
        if not kernel.GetConsoleMode(handle, ctypes.byref(value)):
            raise ctypes.WinError(ctypes.get_last_error())
        return value.value

    def state():
        return (mode(hin), mode(hout), kernel.GetConsoleCP(),
                kernel.GetConsoleOutputCP())

    def unchanged(expected, operation):
        actual = state()
        assert actual == expected, (operation, "输入模式/输出模式/输入CP/输出CP",
                                    expected, actual)

    def run(*args, console_output=True):
        return subprocess.run(
            [binary, *args], stdin=infd, stdout=subprocess.PIPE,
            stderr=outfd if console_output else subprocess.PIPE,
            timeout=15, check=False,
        )

    initial = state()
    try:
        # 显式建立可观测基线，避免 runner 初始模式碰巧等于 raw。
        assert kernel.SetConsoleMode(hin, initial[0] | 7)
        # 非 UTF-8 基线专门捕获 main 前的隐式代码页初始化。
        assert kernel.SetConsoleCP(437)
        assert kernel.SetConsoleOutputCP(437)
        before = state()
        dimensions = run("size")
        assert dimensions.returncode == 0, dimensions
        rows, columns = map(int, dimensions.stdout.split())
        assert rows > 0 and columns > 0, dimensions.stdout
        unchanged(before, "size 改动了 Console 状态")
        print("PASS Console 尺寸查询", flush=True)
        saved = run("save")
        assert saved.returncode == 0, saved
        unchanged(before, "save 改动了 Console 状态")
        token = saved.stdout.decode().strip()
        result = run("raw")
        assert result.returncode == 0, result
        assert result.stdout.decode().strip() == token, "raw 未返回修改前状态"
        changed = state()
        assert changed[0] & 7 == 0, "raw 未关闭 processed/line/echo"
        assert changed[0] & 0x200, "未启用 VT 输入"
        assert changed[1] & 5 == 5, "未启用 VT 输出"
        assert changed[2:] == before[2:], "raw 意外改变了代码页"
        assert run("save").returncode == 0
        unchanged(changed, "raw 后再次 save 破坏了状态")
        restored = run("restore", token)
        assert restored.returncode == 0, restored
        unchanged(before, "restore 未逐位恢复模式和代码页")
        print("PASS Console save/raw/restore 逐位往返", flush=True)

        # 保存时没有输出 Console；后来恢复时不能把输出模式清零。
        saved = run("save", console_output=False)
        assert saved.returncode == 0
        no_output_token = saved.stdout.decode().strip()
        assert no_output_token.split(":")[4] == "0", no_output_token
        assert run("restore", no_output_token).returncode == 0
        assert state() == before, "无输出令牌修改了当前输出模式"
        print("PASS 无输出令牌恢复不修改输出 Console", flush=True)

        bad_tokens = ["junk", token + "00", token.replace(":windows:", ":unix:")]
        fields = token.split(":")
        fields[4] = "2"
        bad_tokens.append(":".join(fields))
        fields[4] = "1"
        fields[5] = "-1"
        bad_tokens.append(":".join(fields))
        for bad in bad_tokens:
            result = run("restore", bad)
            # libc/intrin/exit.c 将退出码转换为 POSIX wait status。
            assert result.returncode == 2 << 8, (bad, result)
            unchanged(before, "拒绝令牌后 Console 被修改")
        print("PASS 损坏令牌拒绝且无副作用", flush=True)
    finally:
        kernel.SetConsoleMode(hin, initial[0])
        kernel.SetConsoleMode(hout, initial[1])
        kernel.SetConsoleCP(initial[2])
        kernel.SetConsoleOutputCP(initial[3])
        os.close(infd)
        os.close(outfd)


def main():
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="backslashreplace")
    if os.name != "nt":
        print("本测试需要 Windows Console", file=sys.stderr)
        return 2
    if len(sys.argv) not in (2, 3):
        return 2
    binary = os.path.abspath(sys.argv[1])
    if len(sys.argv) == 3 and sys.argv[2] == "--worker":
        worker(binary)
        return 0
    for command in ("save", "raw", "size"):
        result = subprocess.run([binary, command], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=15)
        # 本驱动由原生 Python 直跑 APE；exit.c 将 rc=1 编为 256。
        # 不混用 Cosmo wait 解码后的退出码，更不能接受任意非零。
        assert result.returncode == 1 << 8, (command, result)
    # save/raw 应明确指出非 Console; size 只承诺"取不到终端尺寸"的失败, 文案
    # 是本地化的 (无固定 ASCII), 只校验退出码, 不比对文案。
    for command in ("save", "raw"):
        result = subprocess.run([binary, command], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=15)
        assert b"Console" in result.stderr, (command, result)
    print("PASS 重定向句柄明确失败", flush=True)
    result = subprocess.run(
        [sys.executable, __file__, binary, "--worker"],
        creationflags=subprocess.CREATE_NEW_CONSOLE,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90,
    )
    print(result.stdout.decode("utf-8", errors="replace"), end="")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
