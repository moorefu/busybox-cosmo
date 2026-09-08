#!/usr/bin/env python3
"""bbtty 真实 PTY 行为契约（Unix：Linux/macOS）。

用法: python3 tests/bbtty-pty.py /path/to/bbtty.com

验收点（对应 docs/COMPANION-TOOLS.md 的 bbtty 协议）：
  - capabilities 输出 schema/后端声明；
  - 非终端下 save/raw/size 明确失败（rc=1），restore 不跨会话生效；
  - 真实 PTY 上 size 返回非零尺寸；
  - save→restore 无 raw 时逐位还原 termios；
  - raw 关闭 echo/canonical 后 restore 在同终端还原（除内核托管状态位，
    如 macOS 的 PENDIN 0x20000000——该位由内核在模式迁移时置上，用户态
    tcsetattr 无法清除，不是 bbtty 丢失状态）；
  - 跨 PTY restore 被令牌设备绑定拒绝（rc=2）且目标终端状态不变；
  - 损坏/后端不匹配令牌被拒绝（rc=2）。

注意：APE(.com) 在 macOS 上经 posix_spawn 会被拒，因此统一经
/bin/sh -c 'exec "$0" "$@"' 启动。
"""
import os
import pty
import select
import struct
import subprocess
import sys
import termios
import time

try:
    import fcntl  # noqa: F401  (POSIX only)
except ImportError:  # pragma: no cover
    sys.exit(1)

PENDIN = 0x20000000  # macOS/BSD：内核托管的输入挂起状态位
DARWIN = sys.platform.startswith("darwin")


def die(msg):
    print("FAIL:", msg)
    sys.exit(1)


def fail_if(cond, msg):
    if cond:
        die(msg)


def wait_child(p, master, timeout=8.0):
    """等子进程退出并排空 pty 主端输出；不关闭 master/slave。"""
    out = b""
    end = time.monotonic() + timeout
    while time.monotonic() < end and p.poll() is None:
        r, _, _ = select.select([master], [], [], 0.2)
        if r:
            try:
                chunk = os.read(master, 65536)
                if chunk:
                    out += chunk
            except OSError:
                break
    if p.poll() is None:
        p.kill()
        p.wait()
        die("子进程超时未退出")
    try:
        while True:
            r, _, _ = select.select([master], [], [], 0.1)
            if not r:
                break
            chunk = os.read(master, 65536)
            if not chunk:
                break
            out += chunk
    except OSError:
        pass
    return p.returncode, out


def spawn(argv, slave):
    """经 sh exec 启动（规避 macOS 对 APE 的 posix_spawn 拒绝）。"""
    cmd = ["/bin/sh", "-c", 'exec "$0" "$@"', argv[0]] + argv[1:]
    return subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True
    )


def run_direct(argv, stdin=None, stdout=None, stderr=None):
    """非 PTY 直跑（同样经 sh exec 规避 posix_spawn 拒绝）。"""
    cmd = ["/bin/sh", "-c", 'exec "$0" "$@"', argv[0]] + argv[1:]
    return subprocess.run(cmd, stdin=stdin, stdout=stdout, stderr=stderr, timeout=15)


def new_pty():
    return pty.openpty()


def norm_cc(cc):
    out = []
    for v in cc:
        out.append(v if isinstance(v, int) else v[0] if isinstance(v, bytes) and len(v) else v)
    return out


def flags_equal(a, b):
    """逐位比较 termios 元组；Darwin 上掩掉内核托管位 PENDIN。"""
    if len(a) != len(b):
        return False
    for i, (x, y) in enumerate(zip(a, b)):
        if i == 3 and DARWIN:
            if (x & ~PENDIN) != (y & ~PENDIN):
                return False
        elif i == 6:  # cc
            if norm_cc(x) != norm_cc(y):
                return False
        elif x != y:
            return False
    return True


def pty_roundtrip(bbtty, argv, setup_lflag=None):
    """开 PTY，可选先改 lflag，执行 argv（bbtty 子命令），返回
    (token输出, before 状态, after状态) 并保持 slave 打开。"""
    master, slave = new_pty()
    before = termios.tcgetattr(slave)
    if setup_lflag is not None:
        lst = list(before)
        lst[3] |= setup_lflag
        termios.tcsetattr(slave, termios.TCSANOW, lst)
        before = termios.tcgetattr(slave)
    p = spawn([bbtty] + argv, slave)
    rc, out = wait_child(p, master)
    after = termios.tcgetattr(slave)
    os.close(master)
    os.close(slave)
    return rc, out, before, after


def check_restore_same_pty(bbtty, command):
    """保存、修改和恢复期间保持同一个 PTY 打开，不依赖设备号复用。"""
    master, slave = new_pty()
    try:
        before = termios.tcgetattr(slave)
        before[3] |= termios.ECHO | termios.ICANON
        termios.tcsetattr(slave, termios.TCSANOW, before)
        before = termios.tcgetattr(slave)
        rc, out = wait_child(spawn([bbtty, command], slave), master)
        fail_if(rc != 0, "%s rc=%d %r" % (command, rc, out))
        token = out.strip().decode()
        fail_if(not token.startswith("bbtty-v1:unix:"), "令牌前缀错误")
        changed = termios.tcgetattr(slave)
        if command == "raw":
            fail_if(changed[3] & (termios.ECHO | termios.ICANON),
                    "raw 后 ECHO/ICANON 仍开启")
            fail_if(norm_cc(changed[6])[termios.VMIN] != 1 or
                    norm_cc(changed[6])[termios.VTIME] != 0,
                    "raw 的 VMIN/VTIME 不正确")
        else:
            fail_if(not flags_equal(before, changed), "save 改动了终端")
            changed[3] &= ~termios.ECHO
            termios.tcsetattr(slave, termios.TCSANOW, changed)
        rc, out = wait_child(spawn([bbtty, "restore", token], slave), master)
        fail_if(rc != 0, "restore rc=%d %r" % (rc, out))
        fail_if(not flags_equal(before, termios.tcgetattr(slave)),
                "%s→restore 未恢复同一终端状态" % command)
        return token
    finally:
        os.close(master)
        os.close(slave)


def main():
    if len(sys.argv) != 2:
        print("用法: python3 tests/bbtty-pty.py /path/to/bbtty.com", file=sys.stderr)
        return 1
    bbtty = os.path.abspath(sys.argv[1])
    if os.name != "posix":
        print("SKIP: 仅 Unix 支持（Windows 由独立的 Console/ConPTY 驱动验收）")
        return 0
    fail_if(not os.path.isfile(bbtty), "bbtty 不存在: %s" % bbtty)

    # 1) capabilities
    r = run_direct(
        [bbtty, "capabilities"], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    fail_if(r.returncode != 0, "capabilities 退出码 %d" % r.returncode)
    keys = dict(
        line.split("=", 1)
        for line in r.stdout.decode(errors="replace").splitlines()
        if "=" in line
    )
    fail_if(keys.get("bbtty.schema") != "1", "schema 缺失/错误: %r" % r.stdout)
    fail_if(keys.get("bbtty.backend") != "termios", "Unix 应报 termios 后端")
    fail_if(keys.get("bbtty.posix_stty_compatible") != "no", "不得伪装 stty 兼容")
    print("PASS capabilities")

    # 2) 非终端下明确失败（管道重定向验收）
    devnull = subprocess.DEVNULL
    for argv in (["save"], ["raw"], ["size"]):
        r = run_direct(
            [bbtty] + argv, stdin=devnull, stdout=devnull, stderr=subprocess.PIPE
        )
        fail_if(r.returncode != 1, "%s 非终端应 rc=1，实际 %d (%s)"
                % (argv[0], r.returncode, r.stderr.decode(errors="replace").strip()))

    # 3) 真实 PTY 上的 size
    master, slave = new_pty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 41, 132, 0, 0))
    p = spawn([bbtty, "size"], slave)
    rc, out = wait_child(p, master)
    os.close(master)
    os.close(slave)
    fail_if(rc != 0, "size rc=%d" % rc)
    fail_if(out.strip() != b"41 132", "size 输出 %r" % out)
    print("PASS size(PTY)")

    # 4) save→restore 逐位还原（无 raw 干预的保真度）
    check_restore_same_pty(bbtty, "save")
    print("PASS save→restore bitwise")

    # 5) raw 关闭 echo/canonical，restore 同终端还原（掩内核状态位）
    token = check_restore_same_pty(bbtty, "raw")
    if DARWIN:
        print("PASS raw→restore (macOS 掩 PENDIN)")
    else:
        print("PASS raw→restore bitwise")

    # 6) 跨 PTY restore 被设备绑定拒绝，且目标终端不受影响
    #    注意：PTY A 必须保持打开，否则 macOS 可能把同一设备号复用给 B。
    master_a, slave_a = new_pty()
    p = spawn([bbtty, "raw"], slave_a)
    rc, out = wait_child(p, master_a)
    fail_if(rc != 0, "raw 失败 rc=%d" % rc)
    token_a = out.strip().decode()
    master_b, slave_b = new_pty()
    before_b = termios.tcgetattr(slave_b)
    p = spawn([bbtty, "restore", token_a], slave_b)
    rc, out = wait_child(p, master_b)
    after_b = termios.tcgetattr(slave_b)
    os.close(master_b)
    os.close(slave_b)
    os.close(master_a)
    os.close(slave_a)
    fail_if(rc != 2, "跨终端 restore 应 rc=2，实际 %d (%s)"
            % (rc, out.decode(errors="replace").strip()))
    fail_if(after_b != before_b, "被拒绝的 restore 改动了目标终端")
    print("PASS 跨终端 restore 拒绝且无副作用")

    # 7) 损坏令牌 / 后端不匹配
    for bad in ("junk-token", "bbtty-v1:windows:ffffffff:00000000:1:65001:65001"):
        rc, out, _, _ = pty_roundtrip(bbtty, ["restore", bad])
        fail_if(rc != 2, "损坏令牌 %r 应 rc=2，实际 %d" % (bad, rc))
    rc, out, _, _ = pty_roundtrip(bbtty, ["restore", token + "00"])
    fail_if(rc != 2, "带尾随垃圾的令牌应 rc=2，实际 %d" % rc)
    print("PASS 损坏/异后端令牌拒绝")

    # 8) 令牌格式有效但标准输入已不是终端：rc=1，不得静默成功
    r = run_direct(
        [bbtty, "restore", token], stdin=devnull, stdout=devnull,
        stderr=subprocess.PIPE,
    )
    fail_if(r.returncode != 1, "非终端 restore 应 rc=1，实际 %d (%s)"
            % (r.returncode, r.stderr.decode(errors="replace").strip()))
    print("PASS 非终端 restore 明确失败")

    # 9) 命令替换捕获 token，SIGTERM 触发 EXIT trap，在原 PTY 恢复。
    master, slave = new_pty()
    try:
        before = termios.tcgetattr(slave)
        script = '''
token=$("$1" raw) || exit 1
trap '"$1" restore "$token"' 0
trap 'exit 143' TERM
kill -TERM $$
exit 99
'''
        rc, out = wait_child(spawn(["/bin/sh", "-c", script, "bbtty-trap", bbtty], slave), master)
        fail_if(rc != 143, "SIGTERM trap 退出码错误: %d %r" % (rc, out))
        fail_if(not flags_equal(before, termios.tcgetattr(slave)),
                "SIGTERM 后 EXIT trap 未恢复终端")
        print("PASS SIGTERM/EXIT trap 恢复原终端")
    finally:
        os.close(master)
        os.close(slave)

    print("bbtty PTY 契约: 全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
