#!/usr/bin/env bash
# ============================================================
# fetch-sources.sh — 下载构建定制工具链所需的"官方上游"材料
#
# 需要两份官方材料 (锁定版本, sha256 校验):
#   1. cosmopolitan master 源码   jart/cosmopolitan @ 3293fad0a9eac7865c019be98fb993eeb933405e
#      本工程 cosmo 定制补丁(patches/cosmo/*)就是相对该 commit 制作的
#   2. 官方 cosmocc 3.9.2 工具链   (cosmocc-3.9.2.zip)
#      a) 作为编译驱动基座(驱动不需要从源码构建——它本身是 GCC14/LLVM 发行)
#      b) master libc 自举构建时用它的 bin/make + bin/*-cosmo-cc
#   3. (可选) superconfigure GCC 下载脚本 (package.sh 完整打包时才需要)
#
# 产物 (toolchain/download/):
#   cosmopolitan-3293fad.tar.gz / cosmocc-3.9.2.zip / 各自 .sha256
#
# 用法: toolchain/fetch-sources.sh [--force]
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DL="$ROOT/toolchain/download"
mkdir -p "$DL"

# ---- 锁定版本 ----
COSMO_COMMIT="3293fad0a9eac7865c019be98fb993eeb933405e"
COSMO_TARBALL="cosmopolitan-$COSMO_COMMIT.tar.gz"
COSMO_SHA256="cde290834d592c6abb29efda2b55c86a6ae816cbd8b40e59503925767967305c"
COSMO_URL="https://github.com/jart/cosmopolitan/archive/$COSMO_COMMIT.tar.gz"

COSMOCC_VER="3.9.2"
COSMOCC_ZIP="cosmocc-$COSMOCC_VER.zip"
COSMOCC_SHA256="f4ff13af65fcd309f3f1cfd04275996fb7f72a4897726628a8c9cf732e850193"
COSMOCC_URL="https://cosmo.zip/pub/cosmocc/$COSMOCC_ZIP"

sha_check() { # $1=file $2=sha256
  if command -v sha256sum >/dev/null 2>&1; then
    echo "$2  $1" | sha256sum -c - >/dev/null 2>&1
  else
    [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$2" ]
  fi
}

fetch_one() { # $1=name $2=url $3=sha $4=finalpath
  local name="$1" url="$2" sha="$3" final="$4"
  if [ -f "$final" ] && sha_check "$final" "$sha"; then
    echo "[fetch] $name 已就绪 ($final)"
    return 0
  fi
  echo "[fetch] 下载 $name ..."
  echo "$url"
  curl -fL --retry 3 --max-time 900 -o "$final.tmp" "$url"
  if ! sha_check "$final.tmp" "$sha"; then
    echo "[fetch] sha256 校验失败: $name" >&2
    echo "  期望 $sha" >&2
    rm -f "$final.tmp"
    return 1
  fi
  mv "$final.tmp" "$final"
  echo "[fetch] OK: $final"
}

fetch_one "cosmopolitan master 源码" "$COSMO_URL" "$COSMO_SHA256" "$DL/$COSMO_TARBALL"
fetch_one "cosmocc $COSMOCC_VER"      "$COSMOCC_URL" "$COSMOCC_SHA256" "$DL/$COSMOCC_ZIP"

echo ""
echo "==== 下载完成 (toolchain/download/) ===="
ls -la "$DL" | grep -E 'cosmopolitan-|cosmocc-'
echo "commit: $COSMO_COMMIT"
echo "cosmocc: $COSMOCC_VER"
