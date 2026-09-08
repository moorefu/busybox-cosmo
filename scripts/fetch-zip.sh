#!/usr/bin/env bash
# ============================================================
# fetch-zip.sh — 获取 zip 锁定源码 (Debian 3.0-16 快照, 供应线第一步)
#   1) work/companions/zip-3.0/ 已存在且标志匹配 → 跳过
#   2) 否则下载两个锁定文件并校验 sha256:
#        refs/companions/zip_3.0.orig.tar.gz      (Info-ZIP 原包)
#        refs/companions/zip_3.0-16.debian.tar.xz (Debian 安全补丁集)
#   构建见 scripts/build-zip.sh (每次全新解包 + 按 series 打补丁)
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

ZIP_SRC="$WORK_DIR/companions/zip-$ZIP_VER"
ZIP_TARBALL_PATH="$COMPANION_REF_DIR/$ZIP_TARBALL"
ZIP_DEB_TARBALL_PATH="$COMPANION_REF_DIR/$ZIP_DEB_TARBALL"

mkdir -p "$COMPANION_REF_DIR"

sha256_check() {
  file="$1"; expect="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    echo "[fetch-zip][错误] 缺少 sha256sum/shasum，拒绝无校验提取" >&2
    return 1
  fi
  [ "$actual" = "$expect" ] || {
    echo "[fetch-zip][错误] SHA256 不匹配: $file (实际 $actual, 期望 $expect)" >&2
    return 1
  }
}

fetch_one() {
  # $1=目标文件 $2=URL $3=期望 sha256 $4=临时名
  if [ -f "$1" ] && sha256_check "$1" "$3"; then
    echo "[fetch-zip] 已有且校验通过: $1"
    return 0
  fi
  [ -f "$1" ] && { echo "[fetch-zip][警告] 删除校验失败缓存: $1" >&2; rm -f "$1"; }
  tmp="$(mktemp "$COMPANION_REF_DIR/$4.XXXXXX")"
  echo "[fetch-zip] 下载 $2 ..."
  if curl -fL --connect-timeout 10 --max-time 180 -o "$tmp" "$2" \
      && sha256_check "$tmp" "$3"; then
    mv -f "$tmp" "$1"
  else
    rm -f "$tmp"
    echo "[fetch-zip][错误] 下载或校验失败: $2" >&2
    return 1
  fi
}

# 构建树由 build-zip.sh 每次从锁定文件重建, 这里只保证两个锁定文件就绪
fetch_one "$ZIP_TARBALL_PATH" "$ZIP_URL" "$ZIP_SHA256" ".zip-orig"
fetch_one "$ZIP_DEB_TARBALL_PATH" "$ZIP_DEB_URL" "$ZIP_DEB_SHA256" ".zip-debian"
echo "[fetch-zip] 完成: 原包 + Debian ${ZIP_VER}-${ZIP_DEB_REV} 补丁集已锁定"
