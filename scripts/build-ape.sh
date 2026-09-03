#!/usr/bin/env bash
# ============================================================
# build-ape.sh — 构建 busybox cosmopolitan APE
#   用法:
#     scripts/build-ape.sh x86_64          # 仅 x86_64
#     scripts/build-ape.sh aarch64         # 仅 aarch64
#     scripts/build-ape.sh all             # 两架构 + fat (默认)
#     scripts/build-ape.sh fat             # 用已有产物合成 fat
#
#   产物 (dist/):
#     busybox-<arch>.ape       单架构 APE
#     busybox-fat.ape          双架构 fat APE
#
# 环境变量:
#   COSMO=/path/to/toolchain   工具链 (默认 toolchain/cosmo)
#   SOURCE_DATE_EPOCH=...      可复现构建固定时间戳
#   JOBS=N                     并行度
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

TARGET="${1:-all}"
mkdir -p "$DIST_DIR"

# 工具链存在性
[ -x "$TC_X86_CC" ] || die "工具链缺失: $TC_X86_CC — 请先 toolchain/provision.sh 或设置 COSMO="
[ -x "$TC_APELINK" ] || die "缺 apelink: $TC_APELINK"

echo "==== busybox $BB_VER × Cosmopolitan 构建 ($TARGET) ===="
echo "工具链: $TC"

build_one() { # $1=arch
  local arch="$1" cc ld ar st tree
  case "$arch" in
    x86_64)  cc="$TC_X86_CC"; ld="$TC_X86_LD"; ar="$TC_X86_AR"; st="$TC_X86_ST"; tree="$TREE_X86" ;;
    aarch64) cc="$TC_A64_CC"; ld="$TC_A64_LD"; ar="$TC_A64_AR"; st="$TC_A64_ST"; tree="$TREE_A64" ;;
  esac

  echo "--- [$arch] 准备构建树 ---"
  scripts/prepare-worktree.sh "$arch"

  echo "--- [$arch] make (JOBS=$JOBS) ---"
  ( cd "$tree" && make -j"$JOBS" CC="$cc" LD="$ld" AR="$ar" STRIP="$st" )

  echo "--- [$arch] apelink → dist/busybox-$arch.ape ---"
  "$TC_APELINK" -o "$DIST_DIR/busybox-$arch.ape" "$tree/busybox_unstripped"
  echo "  -> $DIST_DIR/busybox-$arch.ape"
}

case "$TARGET" in
  x86_64)  build_one x86_64 ;;
  aarch64) build_one aarch64 ;;
  fat)
    [ -f "$TREE_X86/busybox_unstripped" ] && [ -f "$TREE_A64/busybox_unstripped" ] || die "缺单架构 unstripped ELF"
    echo "--- [fat] 合成双架构 (基于两架构 unstripped ELF) ---"
    "$TC_APELINK" -o "$DIST_DIR/busybox-fat.ape" "$TREE_X86/busybox_unstripped" "$TREE_A64/busybox_unstripped"
    echo "  -> $DIST_DIR/busybox-fat.ape"
    ;;
  all)
    build_one x86_64
    build_one aarch64
    echo "--- [fat] 合成双架构 ---"
    "$TC_APELINK" -o "$DIST_DIR/busybox-fat.ape" "$TREE_X86/busybox_unstripped" "$TREE_A64/busybox_unstripped"
    echo "  -> $DIST_DIR/busybox-fat.ape"
    ;;
  *) die "未知目标: $TARGET (x86_64|aarch64|fat|all)" ;;
esac

echo "==== 构建完成 ===="
ls -la "$DIST_DIR"/*.ape 2>/dev/null || true
