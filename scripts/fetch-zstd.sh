#!/usr/bin/env bash
# ============================================================
# fetch-zstd.sh — 获取 zstd 锁定源码 (v1.5.7, 供应线第一步)
#   下载官方 GitHub release 资产并校验锁定 SHA-256 (唯一锁定通道, 见 env.sh)
#   构建见 scripts/build-zstd.sh (每次全新解包)
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

TARBALL_PATH="$COMPANION_REF_DIR/$ZSTD_TARBALL"
mkdir -p "$COMPANION_REF_DIR"

sha256_check() {
  file="$1"; expect="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    echo "[fetch-zstd][错误] 缺少 sha256sum/shasum" >&2
    return 1
  fi
  [ "$actual" = "$expect" ] || {
    echo "[fetch-zstd][错误] SHA256 不匹配: $file (实际 $actual, 期望 $expect)" >&2
    return 1
  }
}

if [ -f "$TARBALL_PATH" ] && sha256_check "$TARBALL_PATH" "$ZSTD_SHA256"; then
  echo "[fetch-zstd] 已有且校验通过: $TARBALL_PATH"
  exit 0
fi
[ -f "$TARBALL_PATH" ] && { echo "[fetch-zstd][警告] 删除校验失败缓存" >&2; rm -f "$TARBALL_PATH"; }
tmp="$(mktemp "$COMPANION_REF_DIR/.zstd-download.XXXXXX")"
echo "[fetch-zstd] 下载 $ZSTD_URL ..."
if curl -fL --connect-timeout 10 --max-time 240 -o "$tmp" "$ZSTD_URL" \
    && sha256_check "$tmp" "$ZSTD_SHA256"; then
  mv -f "$tmp" "$TARBALL_PATH"
else
  rm -f "$tmp"
  echo "[fetch-zstd][错误] 下载或校验失败" >&2
  exit 1
fi
echo "[fetch-zstd] 完成: $TARBALL_PATH"
