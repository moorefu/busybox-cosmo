#!/usr/bin/env python3
"""xz.com / zip.com / zstd.com 伴生工具行为契约（与 bbtty-pty.py 并列）。

用法: python3 tests/companion-tools.py XZ.COM ZIP.COM [BUSYBOX] [--zstd ZSTD.COM]

覆盖 M1/M3 验收（docs/COMPANION-DELIVERY-PLAN.md）：
  xz/zstd: 编码→独立解码逐字节一致；损坏输入解码明确失败
  zip:
    - 创建→busybox unzip / python zipfile 解码一致 (deflate 方法)
    - 权限位与时间戳随归档保留（档案元数据层断言）
    - Zip Slip: 创建端允许 ../ 成员(Info-ZIP 语义), 解码端(busybox unzip)
      剥离 ../ 前缀且不逃逸出解压目录、不覆盖外部文件
    - 符号链接默认解引用为普通文件存储
    - 不存在的输入明确失败 (rc!=0)
"""
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import zipfile

try:
    import lzma  # noqa: F401
except ImportError:  # pragma: no cover
    lzma = None


def die(msg):
    print("FAIL:", msg)
    sys.exit(1)


def fail_if(cond, msg):
    if cond:
        die(msg)


def sh(args, cwd=None):
    # APE(.com) 在 macOS 上经 posix_spawn 会被拒, 统一经 sh exec 启动
    cmd = ["/bin/sh", "-c", 'exec "$0" "$@"', args[0]] + list(args[1:])
    return subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=60)


def main():
    argv = sys.argv[1:]
    zstd = None
    if "--zstd" in argv:
        i = argv.index("--zstd")
        if i + 1 >= len(argv):
            return 2
        zstd = os.path.abspath(argv[i + 1])
        del argv[i:i + 2]
    if len(argv) not in (2, 3):
        print("用法: python3 tests/companion-tools.py XZ.COM ZIP.COM "
              "[BUSYBOX] [--zstd ZSTD.COM]", file=sys.stderr)
        return 2
    xz = os.path.abspath(argv[0])
    zipb = os.path.abspath(argv[1])
    busybox = os.path.abspath(argv[2]) if len(argv) == 3 else None
    for f in (xz, zipb):
        fail_if(not os.path.isfile(f), "缺少伴生工具: %s" % f)
    if zstd:
        fail_if(not os.path.isfile(zstd), "zstd 不存在: %s" % zstd)
    if busybox:
        fail_if(not os.path.isfile(busybox), "busybox 不存在: %s" % busybox)
    tmp = tempfile.mkdtemp(prefix="companion-tools.")
    try:
        # ---------- xz ----------
        raw = os.urandom(65536)
        data_file = os.path.join(tmp, "in.bin")
        with open(data_file, "wb") as f:
            f.write(raw)
        r = sh([xz, "-c", data_file])
        fail_if(r.returncode != 0, "xz 编码失败 rc=%d %s"
                % (r.returncode, r.stderr.decode(errors="replace")))
        if lzma:
            out = lzma.decompress(r.stdout)
            fail_if(out != raw, "lzma(独立) 解码 xz.com 产物不一致")
        if busybox:
            xzf = os.path.join(tmp, "in.xz")
            with open(xzf, "wb") as f:
                f.write(r.stdout)
            r2 = sh([busybox, "xz", "-dc", xzf])
            fail_if(r2.returncode != 0, "busybox xz 解码失败: %s"
                    % r2.stderr.decode(errors="replace"))
            fail_if(r2.stdout != raw, "busybox xz 解码内容不一致")
        # 损坏输入明确失败
        junk = os.path.join(tmp, "junk.xz")
        with open(junk, "wb") as f:
            f.write(b"\x00not-an-xz-stream\x00" * 8)
        r = sh([xz, "-dc", junk])
        fail_if(r.returncode == 0, "损坏 .xz 应解码失败 rc!=0")
        print("PASS xz 往返与错误路径")

        # ---------- zip: 基础创建 ----------
        src = os.path.join(tmp, "src")
        os.makedirs(os.path.join(src, "sub"))
        with open(os.path.join(src, "a.txt"), "w") as f:
            f.write("hello busybox-cosmo\n")
        with open(os.path.join(src, "sub", "b.bin"), "wb") as f:
            f.write(os.urandom(65536))
        exe_path = os.path.join(src, "run.sh")
        with open(exe_path, "w") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod(exe_path, 0o750)
        os.makedirs(os.path.join(src, "emptyd"))  # 空目录
        mtime = int(time.time()) - 120
        os.utime(exe_path, (mtime, mtime))
        ar = os.path.join(tmp, "out.zip")
        r = sh([zipb, "-q", "-r", ar, "."], cwd=src)
        fail_if(r.returncode != 0, "zip 创建失败 rc=%d %s"
                % (r.returncode, r.stderr.decode(errors="replace")))
        z = zipfile.ZipFile(ar)
        names = z.namelist()
        fail_if("a.txt" not in names or "sub/b.bin" not in names,
                "zip 缺少成员: %r" % names)
        fail_if(not any(n.endswith("/") and n.rstrip("/") in ("sub", "emptyd")
                        for n in names), "zip 未记录目录成员: %r" % names)
        info = z.getinfo("sub/b.bin")
        fail_if(info.compress_type != zipfile.ZIP_DEFLATED,
                "默认应为 deflate, 实际 method=%d" % info.compress_type)
        info_exe = z.getinfo("run.sh")
        mode = (info_exe.external_attr >> 16) & 0o777
        fail_if(not (mode & 0o100), "run.sh 可执行位未写入归档 (mode=%o)" % mode)
        fi = info_exe
        # zipfile date_time 为本地分钟精度; 允许 ±2 分钟
        dt = time.mktime(fi.date_time + (0, 0, -1))
        fail_if(abs(dt - mtime) > 120, "时间戳未保留: archive=%s src=%d"
                % (fi.date_time, mtime))
        # 内容一致
        fail_if(z.read("a.txt") != b"hello busybox-cosmo\n", "a.txt 内容不一致")
        with open(os.path.join(src, "sub", "b.bin"), "rb") as f:
            fail_if(z.read("sub/b.bin") != f.read(), "b.bin 内容不一致")
        z.close()
        print("PASS zip 创建 (deflate/目录/权限/时间戳/内容)")

        # 解码往返 (busybox unzip)
        if busybox:
            ex = os.path.join(tmp, "extract")
            os.makedirs(ex)
            r = sh([busybox, "unzip", "-q", "-o", ar], cwd=ex)
            fail_if(r.returncode != 0, "busybox unzip 失败: %s"
                    % r.stderr.decode(errors="replace"))
            for rel in ("a.txt", "sub/b.bin"):
                with open(os.path.join(src, rel), "rb") as f:
                    want = f.read()
                with open(os.path.join(ex, rel), "rb") as f:
                    fail_if(f.read() != want, "解压后 %s 不一致" % rel)
            print("PASS zip→busybox unzip 往返")

        # ---------- zip: Zip Slip 语义 (创建端保留 ../ 成员名, 解码端不逃逸) ----------
        # 攻击者文件放在打包根之外: ../evil.txt 携带 'evil' 内容
        slip_root = os.path.join(tmp, "slip")
        slip_src = os.path.join(slip_root, "src")
        os.makedirs(slip_src)
        with open(os.path.join(slip_root, "evil.txt"), "wb") as f:
            f.write(b"evil")
        with open(os.path.join(slip_src, "in.txt"), "w") as f:
            f.write("benign\n")
        slip_ar = os.path.join(tmp, "slip.zip")
        r = sh([zipb, "-q", slip_ar, "../evil.txt", "in.txt"], cwd=slip_src)
        fail_if(r.returncode != 0, "zip ../ 成员创建失败 rc=%d %s"
                % (r.returncode, r.stderr.decode(errors="replace")))
        z = zipfile.ZipFile(slip_ar)
        slip_members = z.namelist()
        z.close()
        fail_if("../evil.txt" not in slip_members,
                "创建端应保留 ../ 成员名(Info-ZIP 语义): %r" % slip_members)
        if busybox:
            # 嵌套解压目录: 若解码端不剥离 ../, 将落到 dst/ 而非 dst/ex/
            slip_ex = os.path.join(slip_root, "dst", "ex")
            os.makedirs(slip_ex)
            r = sh([busybox, "unzip", "-q", "-o", slip_ar], cwd=slip_ex)
            fail_if(r.returncode != 0, "busybox unzip 处理 ../ 失败: %s"
                    % r.stderr.decode(errors="replace"))
            fail_if(os.path.exists(os.path.join(slip_root, "dst", "evil.txt")),
                    "解码越出解压目录写文件")
            evil_out = os.path.join(slip_ex, "evil.txt")
            fail_if(not os.path.exists(evil_out),
                    "../evil.txt 未在解压目录内生成 (去前缀后应落在 ex/)")
            with open(evil_out, "rb") as f:
                fail_if(f.read() != b"evil", "../evil.txt 解码内容不一致")
            with open(os.path.join(slip_root, "evil.txt"), "rb") as f:
                fail_if(f.read() != b"evil", "源攻击文件被改动")
            print("PASS zip ../ 成员: 解码端剥离前缀且不逃逸、不改动外部文件")

        # ---------- zip: 符号链接默认解引用为普通文件 ----------
        link_src = os.path.join(tmp, "linksrc")
        os.makedirs(link_src)
        target_content = b"symlink-target-data"
        target_f = os.path.join(tmp, "real-target.txt")
        with open(target_f, "wb") as f:
            f.write(target_content)
        os.symlink(target_f, os.path.join(link_src, "lnk"))
        link_ar = os.path.join(tmp, "link.zip")
        r = sh([zipb, "-q", "-r", link_ar, "."], cwd=link_src)
        fail_if(r.returncode != 0, "zip 符号链接归档失败: %s"
                % r.stderr.decode(errors="replace"))
        z = zipfile.ZipFile(link_ar)
        li = z.getinfo("lnk")
        mode = (li.external_attr >> 16) & 0o170000
        fail_if(mode != stat.S_IFREG, "符号链接应默认解引用为普通文件, "
                "实际类型 0%o" % mode)
        fail_if(z.read("lnk") != target_content, "解引用内容不一致")
        z.close()
        print("PASS zip 符号链接默认解引用")

        # ---------- zip: 不存在的输入明确失败 ----------
        r = sh([zipb, "-q", os.path.join(tmp, "nope.zip"), "missing-file"])
        fail_if(r.returncode == 0, "zip 添加不存在文件应失败 rc!=0")
        print("PASS zip 错误路径明确失败")

        # ---------- zstd (可选, --zstd) ----------
        if zstd:
            zraw = os.urandom(262144) + b"zstd-payload"
            zf = os.path.join(tmp, "z.in")
            with open(zf, "wb") as f:
                f.write(zraw)
            r = sh([zstd, "-q", "-c", zf])
            fail_if(r.returncode != 0, "zstd 编码失败 rc=%d %s"
                    % (r.returncode, r.stderr.decode(errors="replace")))
            zst = os.path.join(tmp, "z.zst")
            with open(zst, "wb") as f:
                f.write(r.stdout)
            r = sh([zstd, "-q", "-d", "-c", zst])
            fail_if(r.returncode != 0, "zstd 解码失败 rc=%d %s"
                    % (r.returncode, r.stderr.decode(errors="replace")))
            fail_if(r.stdout != zraw, "zstd 往返不一致")
            junk = os.path.join(tmp, "j.zst")
            with open(junk, "wb") as f:
                f.write(b"not-a-zstd-stream")
            r = sh([zstd, "-q", "-d", "-c", junk])
            fail_if(r.returncode == 0, "损坏 .zst 应解码失败 rc!=0")
            print("PASS zstd 往返与错误路径")

        print("伴生工具契约: 全部通过")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
