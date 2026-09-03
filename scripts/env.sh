#!/usr/bin/env bash
# ============================================================
# env.sh — busybox × Cosmopolitan 工程公共环境
# 定义 ROOT/工具链/源码/构建树路径与版本常量
# 用法: source "$(dirname "$0")/env.sh"
# ============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- 版本常量 ----
BB_VER="1.38.0"
BB_TARBALL="busybox-${BB_VER}.tar.bz2"
BB_URL="https://busybox.net/downloads/${BB_TARBALL}"
# busybox.net 官方 tarball sha256 (取源脚本校验用)
BB_SHA256="34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2"

# ---- 目录 ----
CONFIG_DIR="$ROOT/config"
PATCHES_DIR="$ROOT/patches"
SRC_DIR="$ROOT/src"            # 原版源码 (可重建)
WORK_DIR="$ROOT/work"          # 各架构打补丁构建树 (可重建)
DIST_DIR="$ROOT/dist"          # 产物输出
BASELINE_DIR="$ROOT/baseline"  # 历史已验证发布包基线
TOOLCHAIN_DIR="$ROOT/toolchain"

# 完整 busybox 适配补丁 (含 82 文件)
BB_FULL_PATCH="$PATCHES_DIR/busybox-cosmo-full.patch"

# 工具链: 默认工程内拷入的定制工具链; 可用 COSMO 环境变量覆盖
if [ -n "${COSMO:-}" ]; then
  TC="$COSMO"
else
  TC="$TOOLCHAIN_DIR/cosmo"
fi

# 平台工具命名 (cosmocc 布局)
TC_X86_CC="$TC/bin/x86_64-unknown-cosmo-cc"
TC_X86_LD="$TC/bin/x86_64-linux-cosmo-gcc"
TC_X86_AR="$TC/bin/x86_64-linux-cosmo-ar"
TC_X86_ST="$TC/bin/x86_64-linux-cosmo-strip"
TC_A64_CC="$TC/bin/aarch64-unknown-cosmo-cc"
TC_A64_LD="$TC/bin/aarch64-linux-cosmo-gcc"
TC_A64_AR="$TC/bin/aarch64-linux-cosmo-ar"
TC_A64_ST="$TC/bin/aarch64-linux-cosmo-strip"
TC_APELINK="$TC/bin/apelink"

# 构建树命名
TREE_X86="$WORK_DIR/busybox-${BB_VER}-x86_64"
TREE_A64="$WORK_DIR/busybox-${BB_VER}-aarch64"

# 可复现构建: SOURCE_DATE_EPOCH 固定则产物逐位可复现
# (busybox 的 AUTOCONF_TIMESTAMP 取自该变量, 见 scripts/kconfig/confdata.c)
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  export SOURCE_DATE_EPOCH
  echo "[env] SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH (可复现构建)"
fi

JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 8)}"

die() { echo "[错误] $*" >&2; exit 1; }
