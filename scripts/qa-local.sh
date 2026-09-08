#!/usr/bin/env bash
# ============================================================
# qa-local.sh — 本地交付 QA 门禁 (镜像 CI unix-matrix 的关键步骤)
#   顺序: 1) bbtty 真实 PTY 契约  2) 伴生工具契约 (xz/zip/zstd)
#         3) curl.com HTTPS KAT   4) bbcosmo capabilities + capability gate
#   前置: make build xz zip zstd curl cacert bbtty 已产出 dist/ 对应物
#   用法: scripts/qa-local.sh [--os macos|linux --arch x86_64|aarch64]
#   任一环节失败即退出非零 (证据 = 各节 PASS 汇总)
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OS=macos
ARCH=x86_64
NAME_SEARCH=unsupported
[ "${1:-}" = --os ] && OS=$2
[ "${3:-}" = --arch ] && ARCH=$4

need() { command -v "$1" >/dev/null 2>&1 || { echo "[qa][错误] 缺少 $1"; exit 1; }; }
need python3; need openssl
[ -x dist/bbtty.com ] || { echo "[qa][错误] 缺 dist/bbtty.com (make bbtty)"; exit 1; }
for t in xz zip zstd curl; do
  [ -x "dist/tools/$t.com" ] || { echo "[qa][错误] 缺 dist/tools/$t.com (make $t)"; exit 1; }
done
[ -x dist/busybox-fat.ape ] || { echo "[qa][错误] 缺 dist/busybox-fat.ape (make build)"; exit 1; }
[ -f dist/release/release/busybox ] || { echo "[qa][错误] 缺 release busybox 入口 (make package)"; exit 1; }

echo "=== 1/4 bbtty 真实 PTY 契约 ==="
python3 tests/bbtty-pty.py dist/bbtty.com || exit 1

echo "=== 2/4 伴生工具契约 (xz/zip/zstd) ==="
python3 tests/companion-tools.py \
  dist/tools/xz.com dist/tools/zip.com dist/busybox-fat.ape \
  --zstd dist/tools/zstd.com || exit 1

echo "=== 3/4 curl.com HTTPS KAT ==="
python3 tests/https-kat.py dist/tools/curl.com || exit 1

echo "=== 4/4 capabilities + 门禁 ==="
export BBP_BUSYBOX="$ROOT/dist/release/release/busybox"
export BBP_TOOLS_DIR="$ROOT/dist/tools"
BBP_BUSYBOX="$BBP_BUSYBOX" BBP_TOOLS_DIR="$BBP_TOOLS_DIR" \
  "$BBP_BUSYBOX" ash scripts/bbcosmo capabilities --format json > /tmp/qa-cap.json || exit 1
python3 tests/ci-capability-gate.py /tmp/qa-cap.json \
  --os "$OS" --arch "$ARCH" --name-search "$NAME_SEARCH" || exit 1
rm -f /tmp/qa-cap.json

echo "===== QA 本地门禁: 全部通过 ($OS/$ARCH) ====="
