#!/usr/bin/env bash
# ============================================================
# fetch-curl.sh — 获取 curl 与其 TLS 依赖 mbedtls 的锁定源码
#   下载官方 GitHub release 资产并校验锁定 SHA-256 (唯一锁定通道)
#   构建见 scripts/build-curl.sh (每次全新解包)
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

mkdir -p "$COMPANION_REF_DIR"

sha256_check() {
  file="$1"; expect="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    echo "[fetch-curl][错误] 缺少 sha256sum/shasum" >&2
    return 1
  fi
  [ "$actual" = "$expect" ] || {
    echo "[fetch-curl][错误] SHA256 不匹配: $file (实际 $actual, 期望 $expect)" >&2
    return 1
  }
}

fetch_one() {
  # $1=目标文件 $2=URL $3=期望 sha256 $4=临时名
  if [ -f "$1" ] && sha256_check "$1" "$3"; then
    echo "[fetch-curl] 已有且校验通过: $1"
    return 0
  fi
  [ -f "$1" ] && { echo "[fetch-curl][警告] 删除校验失败缓存: $1" >&2; rm -f "$1"; }
  tmp="$(mktemp "$COMPANION_REF_DIR/.$4.XXXXXX")"
  echo "[fetch-curl] 下载 $2 ..."
  if curl -fL --connect-timeout 10 --max-time 300 -o "$tmp" "$2" \
      && sha256_check "$tmp" "$3"; then
    mv -f "$tmp" "$1"
  else
    rm -f "$tmp"
    echo "[fetch-curl][错误] 下载或校验失败: $2" >&2
    return 1
  fi
}

fetch_one "$COMPANION_REF_DIR/$CURL_TARBALL" "$CURL_URL" "$CURL_SHA256" ".curl"
fetch_one "$COMPANION_REF_DIR/$MBEDTLS_TARBALL" "$MBEDTLS_URL" "$MBEDTLS_SHA256" ".mbedtls"
echo "[fetch-curl] 完成: curl-$CURL_VER + mbedtls-$MBEDTLS_VER 已锁定"
