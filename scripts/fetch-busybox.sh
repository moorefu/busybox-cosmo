#!/usr/bin/env bash
# ============================================================
# fetch-busybox.sh — 获取 busybox 官方原版源码
#   1) 已存在 src/busybox-1.38.0/ 且校验通过 → 跳过
#   2) 否则从 busybox.net 下载 tarball 并解压, 校验 sha256
# 用法: scripts/fetch-busybox.sh
# 环境: BB_URL/BB_SHA256 可用 env 覆盖 (离线/镜像场景)
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

SRC="$SRC_DIR/busybox-$BB_VER"
TARBALL="$SRC_DIR/$BB_TARBALL"

mkdir -p "$SRC_DIR"

sha256_check() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    echo "[fetch][错误] 缺少 sha256sum/shasum，拒绝无校验提取" >&2
    return 1
  fi
  [ "$actual" = "$BB_SHA256" ] || {
    echo "[fetch][错误] SHA256 不匹配: $file (实际 $actual, 期望 $BB_SHA256)" >&2
    return 1
  }
}

# 已存在则校验目录标志 (.bb-src-ok)
if [ -f "$SRC/include/autoconf.h" ] || [ -d "$SRC/applets" ]; then
  [ -f "$SRC/.bb-src-ok" ] || {
    echo "[fetch][错误] 既有源码目录没有校验标志，拒绝假设其为原版: $SRC" >&2
    echo "[fetch] 请移走该目录后重新运行，以便从锁定 tarball 提取" >&2
    exit 1
  }
  grep -qx "sha256=$BB_SHA256" "$SRC/.bb-src-ok" || {
    echo "[fetch][错误] 源码标志与锁定 tarball 不匹配: $SRC/.bb-src-ok" >&2
    exit 1
  }
  echo "[fetch] busybox-$BB_VER 源码已就绪: $SRC"
  exit 0
fi

if [ -f "$TARBALL" ]; then
  echo "[fetch] 使用已有 tarball: $TARBALL"
else
  echo "[fetch] 下载 $BB_URL ..."
  tmp_tar="$(mktemp "$SRC_DIR/.busybox-download.XXXXXX")"
  curl -fL --retry 3 -o "$tmp_tar" "$BB_URL"
  mv -f "$tmp_tar" "$TARBALL"
fi

echo "[fetch] sha256 校验 ..."
sha256_check "$TARBALL" || { echo "[fetch] 校验失败 (可用 BB_SHA256= 覆盖)"; exit 1; }

echo "[fetch] 解压 ..."
tar xjf "$TARBALL" -C "$SRC_DIR"
printf 'sha256=%s\ntarball=%s\n' "$BB_SHA256" "$BB_TARBALL" > "$SRC/.bb-src-ok"
echo "[fetch] 完成: $SRC"
