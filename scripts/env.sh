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

# ---- 伴生工具版本常量 (供应线: 锁定源码自建, 见 docs/COMPANION-DELIVERY-PLAN.md) ----
# xz: 走 5.4 LTS 线, 规避 2024-3094 后门版本 (5.6.0/5.6.1)。首个锁定值取自
# 官方 tukaani.org(302→github.com/tukaani-project/xz releases v5.4.7) 下载的
# 原始 tarball, 交叉构建用 --host 关闭运行期探测; 未来升级先换常量再重验。
XZ_VER="5.4.7"
XZ_TARBALL="xz-${XZ_VER}.tar.xz"
XZ_URL="${XZ_URL:-https://tukaani.org/xz/${XZ_TARBALL}}"
XZ_SHA256="${XZ_SHA256:-016182c70bb5c7c9eb3465030e3a7f6baa25e17b0e8c0afe92772e6021843ce2}"
# 伴生工具源码缓存/构建树 (work/ 与 refs/ 均被 gitignore, 可重建)
REF_DIR="$ROOT/refs"
COMPANION_REF_DIR="$REF_DIR/companions"

# zip: 采用 Debian 维护的 3.0-16 "原包+补丁" 快照 (含 unicode 溢出/
# CVE-2018-13410/符号链接/命令注入等修复)。zip 3.0 内置 deflate, 不依赖 zlib;
# bzip2 方法未启用 (发行版同样只依赖 libbz2-dev, 我们连它也不引入)。
ZIP_VER="3.0"
ZIP_DEB_REV="16"
ZIP_TARBALL="zip_${ZIP_VER}.orig.tar.gz"
ZIP_URL="${ZIP_URL:-https://deb.debian.org/debian/pool/main/z/zip/${ZIP_TARBALL}}"
ZIP_SHA256="${ZIP_SHA256:-f0e8bb1f9b7eb0b01285495a2699df3a4b766784c1765a8f1aeedf63c0806369}"
ZIP_DEB_TARBALL="zip_${ZIP_VER}-${ZIP_DEB_REV}.debian.tar.xz"
ZIP_DEB_URL="${ZIP_DEB_URL:-https://deb.debian.org/debian/pool/main/z/zip/${ZIP_DEB_TARBALL}}"
ZIP_DEB_SHA256="${ZIP_DEB_SHA256:-fa79a0226f00f487b290489f62e1cd7f4a338df529a1e413fea4d168b8eee8f7}"

# cacert.pem: 固定 curl.se/ca 的 Mozilla 转换快照 (MPL-2.0)。锁定值经官方
# .sha256 sidecar 校验; 升级时先换 CA_VER/CA_SHA256 再重跑 fetch-cacert.sh。
CA_VER="2026-08-13"
CA_PEM="cacert-${CA_VER}.pem"
CA_URL="${CA_URL:-https://curl.se/ca/${CA_PEM}}"
CA_SHA256="${CA_SHA256:-f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9}"

# zstd: 官方 facebook/zstd v1.5.7 (GitHub release 资产为唯一锁定通道, 与 zlib 同例)。
# 许可 BSD-3-Clause 与 GPLv2 双许可, 选用 BSD-3-Clause 分发。
ZSTD_VER="1.5.7"
ZSTD_TARBALL="zstd-${ZSTD_VER}.tar.gz"
ZSTD_URL="${ZSTD_URL:-https://github.com/facebook/zstd/releases/download/v${ZSTD_VER}/${ZSTD_TARBALL}}"
ZSTD_SHA256="${ZSTD_SHA256:-eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3}"

# curl: 官方 curl 8.13.0; TLS 后端 mbedtls (cosmo 无 openssl/zlib, 见
# COMPANION-DELIVERY-PLAN.md "curl TLS 后端选型")。--without-zlib 构建。
CURL_VER="8.13.0"
CURL_TARBALL="curl-${CURL_VER}.tar.gz"
CURL_URL="${CURL_URL:-https://github.com/curl/curl/releases/download/curl-8_13_0/${CURL_TARBALL}}"
CURL_SHA256="${CURL_SHA256:-c261a4db579b289a7501565497658bbd52d3138fdbaccf1490fa918129ab45bc}"

# mbedtls (curl 的 TLS 依赖): 官方 3.6.2 LTS 线
MBEDTLS_VER="3.6.2"
MBEDTLS_TARBALL="mbedtls-${MBEDTLS_VER}.tar.bz2"
MBEDTLS_URL="${MBEDTLS_URL:-https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-${MBEDTLS_VER}/${MBEDTLS_TARBALL}}"
MBEDTLS_SHA256="${MBEDTLS_SHA256:-8b54fb9bcf4d5a7078028e0520acddefb7900b3e66fec7f7175bb5b7d85ccdca}"

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
