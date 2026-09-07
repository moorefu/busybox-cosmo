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
BB_URL="${BB_URL:-https://busybox.net/downloads/${BB_TARBALL}}"
# Buildroot 源码镜像保存的是同一份 BusyBox 发布 tarball；取源脚本仍以
# BB_SHA256 为唯一信任依据。可设为空字符串禁用备用入口。
BB_FALLBACK_URL="${BB_FALLBACK_URL-https://sources.buildroot.net/busybox/${BB_TARBALL}}"
# busybox.net 官方 tarball sha256 (取源脚本校验用)
BB_SHA256="${BB_SHA256:-34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2}"

# ---- 目录 ----
CONFIG_DIR="$ROOT/config"
PATCHES_DIR="$ROOT/patches"
SRC_DIR="$ROOT/src"            # 原版源码 (可重建)
WORK_DIR="${BUSYBOX_WORK_DIR:-$ROOT/work}" # 可指定新目录，绝不自动覆盖旧补丁树
DIST_DIR="$ROOT/dist"          # 产物输出
BASELINE_DIR="$ROOT/baseline"  # 历史已验证发布包基线
TOOLCHAIN_DIR="$ROOT/toolchain"

BB_PATCH_SERIES="$PATCHES_DIR/busybox/series"
# 这些符号由增量补丁新增源码引入(kconfig 新符号), prepare 时锚定并强制 =y
BB_FORCE_APP_LETS="CONFIG_MAKE CONFIG_PDPMAKE"

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

# APE 内嵌 loader (官方发行形态: apelink -l 打入, 直跑不改母本)
APE_LDR_X86="$TC/bin/ape-x86_64.elf"
APE_LDR_A64="$TC/bin/ape-aarch64.elf"
APE_M1_SRC="$TC/bin/ape-m1.c"
# 组装 apelink 参数: $1=arch(x86_64|aarch64) → 输出该架构内嵌参数
apelink_embed_args() {
  case "$1" in
    x86_64) echo "-l $APE_LDR_X86" ;;
    aarch64) echo "-l $APE_LDR_A64 -M $APE_M1_SRC" ;;
    *) echo "" ;;
  esac
}

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
