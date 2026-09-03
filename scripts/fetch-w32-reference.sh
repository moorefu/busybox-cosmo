#!/usr/bin/env bash
# ============================================================
# fetch-w32-reference.sh — 拉取 busybox-w32 参考源码 (浅克隆, 只读参考)
#   Windows 适配借鉴源 (fork 状态序列化路线, 其避坑清单全库借鉴;
#   本工程未采用其 vfork≈fork 之外的脆弱部分, 见 docs/ARCHITECTURE.md)
# 产物: refs/busybox-w32/  (gitignored)
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/refs/busybox-w32"
URL="${BUSYBOX_W32_URL:-https://github.com/rmyorston/busybox-w32.git}"

mkdir -p "$ROOT/refs"
if [ ! -d "$DEST/.git" ]; then
  echo "[refs] 浅克隆 $URL → $DEST"
  git clone --depth 1 "$URL" "$DEST"
else
  echo "[refs] 已存在: $DEST"
fi
echo "[refs] 完成"
