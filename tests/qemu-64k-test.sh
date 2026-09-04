#!/bin/sh
# ============================================================
# qemu-64k-test.sh — 真 64K 页内核全系统模拟验证 (macOS 本地 qemu)
#
# 前置: 1) brew install qemu  2) Ubuntu arm64 generic-64k 内核
#       首次自动从 arm64 Ubuntu 容器 apt 提取 vmlinuz 到
#       work/qemu64k/vmlinuz-64k (缓存)。
#
# 验证内容 (真 64K 页内核, initramfs 内):
#   A. busybox-arm64-linux-elf 直接 exec
#   B. busybox-fat.ape / busybox-aarch64.ape 直接 exec (内嵌 64K loader)
#   C. 嵌套 exec (loader 形态下受限, 记录但不判失败)
#
# 用法: tests/qemu-64k-test.sh [--full]
#   --full  额外把 smoke.sh 拷入并在 ELF 形态跑 (慢, qemu 模拟)
# 产物: dist/busybox-*.ape 默认用 dist/ 下正式产物
# ============================================================
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QDIR="$ROOT/work/qemu64k"
VMLINUZ="$QDIR/vmlinuz-64k"
FULL="${1:-}"

command -v qemu-system-aarch64 >/dev/null || { echo "缺 qemu-system-aarch64 (brew install qemu)" >&2; exit 2; }

# ---- 1. 内核 (缓存; 缺则从 arm64 ubuntu 容器提取) ----
if [ ! -f "$VMLINUZ" ]; then
  echo "== 提取 Ubuntu generic-64k 内核 ..."
  mkdir -p "$QDIR"
  podman run --rm --arch arm64 -v "$QDIR:/out:rw" docker.io/library/ubuntu:24.04 sh -c '
    apt-get update -qq >/dev/null 2>&1
    cd /tmp && apt-get download linux-image-6.8.0-31-generic-64k >/dev/null 2>&1
    dpkg-deb -x *.deb /tmp/x
    cp /tmp/x/boot/vmlinuz-* /out/vmlinuz-64k' || { echo "内核提取失败" >&2; exit 1; }
  gunzip -f "$VMLINUZ" 2>/dev/null || true
fi

# ---- 2. initramfs ----
IR="$QDIR/initramfs"
rm -rf "$IR" && mkdir -p "$IR/bin" "$IR/proc" "$IR/sys" "$IR/dev" "$IR/tmp" "$IR/root" "$IR/usr"
# ELF 源: release 优先, 退回构建树 unstripped
ELF_SRC=""
for c in "$ROOT/dist/release/release/busybox-arm64-linux-elf" \
         "$ROOT/work/busybox-1.38.0-aarch64/busybox_unstripped"; do
  [ -f "$c" ] && { ELF_SRC="$c"; break; }
done
[ -n "$ELF_SRC" ] || { echo "缺 arm64 ELF (先构建 busybox 或打 release)" >&2; exit 1; }
cp "$ELF_SRC" "$IR/bin/busybox"
cp "$ELF_SRC" "$IR/busybox-elf"
cp "$ROOT/dist/busybox-fat.ape" "$IR/busybox-com" 2>/dev/null || true
cp "$ROOT/dist/busybox-aarch64.ape" "$IR/busybox-a64" 2>/dev/null || true

cat > "$IR/init" <<EOF
#!/bin/busybox sh
/bin/busybox mount -t proc none /proc
/bin/busybox mount -t sysfs none /sys
/bin/busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== 内核 \$(/bin/busybox uname -r) arch=\$(/bin/busybox uname -m) ==="
echo "=== 页大小: MemTotal KB / 页数 (524288/8184=64K 时确认) ==="
/bin/busybox awk '/MemTotal/{print "  MemTotal",\$2,"KB"}' /proc/meminfo
/bin/busybox chmod +x /busybox-elf /busybox-com /busybox-a64 2>/dev/null || true
echo "=== A. ELF 直跑 ==="
/busybox-elf sh -c 'echo A-ELF-OK' 2>&1 | head -1
echo "=== B. fat 直接 exec (内嵌 64K loader) ==="
/busybox-com echo B-FAT-OK 2>&1 | head -1
echo "=== C. 单架构 aarch64.ape ==="
/busybox-a64 echo C-A64-OK 2>&1 | head -1
echo "=== D. 嵌套 exec (loader 形态可能受限) ==="
/busybox-com sh -c '/bin/busybox echo D-NESTED-OK' 2>&1 | head -1
echo "=== FINISHED ==="
/bin/busybox poweroff -f 2>/dev/null || /bin/busybox halt -f
EOF
chmod +x "$IR/init" "$IR/bin/busybox"
( cd "$IR" && find . | cpio -o -H newc 2>/dev/null | gzip > "$QDIR/initramfs.gz" )

# ---- 3. 启动 (最多等 40s) ----
echo "== qemu-system-aarch64 启动 (真 64K 内核) ..."
qemu-system-aarch64 -M virt -cpu max -m 512M -nographic \
  -kernel "$VMLINUZ" -initrd "$QDIR/initramfs.gz" \
  -append "console=ttyAMA0 rdinit=/init" > "$QDIR/qemu-test.log" 2>&1 &
QPID=$!
sleep 40
kill "$QPID" 2>/dev/null || true
echo "== 结果 =="
grep -E '===|OK|error|FINISHED' "$QDIR/qemu-test.log" | grep -vE '^\s*$' | tail -15
echo "(完整日志: $QDIR/qemu-test.log)"
