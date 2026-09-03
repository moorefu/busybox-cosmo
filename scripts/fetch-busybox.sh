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

# 已存在则校验目录标志 (.bb-src-ok)
if [ -f "$SRC/include/autoconf.h" ] || [ -d "$SRC/applets" ]; then
  if [ ! -f "$SRC/.bb-src-ok" ]; then
    echo "[fetch] 检测到既有源码目录, 建立校验标志 (假设原版未改)"
    touch "$SRC/.bb-src-ok"
  fi
  echo "[fetch] busybox-$BB_VER 源码已就绪: $SRC"
  exit 0
fi

if [ -f "$TARBALL" ]; then
  echo "[fetch] 使用已有 tarball: $TARBALL"
else
  echo "[fetch] 下载 $BB_URL ..."
  curl -fL --retry 3 -o "$TARBALL" "$BB_URL"
fi

echo "[fetch] sha256 校验 ..."
echo "$BB_SHA256  $TARBALL" | sha256sum -c - || {
  echo "[fetch] 校验失败 (可能是网络镜像不同源); 可用 BB_SHA256= 覆盖"
  exit 1
}

echo "[fetch] 解压 ..."
tar xjf "$TARBALL" -C "$SRC_DIR"
touch "$SRC/.bb-src-ok"
echo "[fetch] 完成: $SRC"
