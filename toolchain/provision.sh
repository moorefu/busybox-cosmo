#!/usr/bin/env bash
# ============================================================
# provision.sh — 就绪 cosmopolitan 定制工具链 (toolchain/cosmo)
#
# 三种模式:
#   copy    从已有预编译定制工具链目录拷贝 (最快, 本工程开发默认)
#           provision.sh copy [/path/to/toolchain]
#   build   从"官方源码"完整构建定制工具链 (可复现, 数小时级)
#           = fetch-sources.sh (官方 master@锁定commit + cosmocc-4.0.2, sha 校验)
#             + build-custom.sh (打补丁→make→组装→verify)
#           provision.sh build [x86_64|aarch64|all]
#   download 下载官方 cosmocc 发行版解压到 toolchain/cosmo
#           (⚠️ 无本工程定制 libc 补丁; 仅作快速可用基座/诊断)
#           provision.sh download
#
# 环境变量:
#   COSMO_SRC    copy 模式的源目录 (默认 /tmp/cosmopolitan-master/.cosmocc/3.9.2)
#   或直接 provision.sh copy /custom/path
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/env.sh"

MODE="${1:-}"
ARCH="${2:-all}"
DEST="$TOOLCHAIN_DIR/cosmo"
COSMO_URL="${COSMO_URL:-https://cosmo.zip/pub/cosmocc/cosmocc.zip}"
mkdir -p "$TOOLCHAIN_DIR"

case "$MODE" in
  copy)
    SRC="${2:-${COSMO_SRC:-/tmp/cosmopolitan-master/.cosmocc/3.9.2}}"
    [ -d "$SRC/bin" ] || die "源工具链无效: $SRC"
    if [ -x "$DEST/bin/x86_64-unknown-cosmo-cc" ] && [ -z "${FORCE:-}" ]; then
      echo "[provision] 工具链已就绪: $DEST (FORCE=1 可重拷)"
      exit 0
    fi
    echo "[provision] 拷贝 $SRC → $DEST ..."
    rm -rf "$DEST"; mkdir -p "$DEST"
    cp -R "$SRC/." "$DEST/"
    echo "[provision] 完成 ($(du -sh "$DEST" | cut -f1))"
    ;;
  build)
    echo "[provision] 从官方源码构建定制工具链 (arch=$ARCH)"
    "$TOOLCHAIN_DIR/fetch-sources.sh"
    exec "$TOOLCHAIN_DIR/build-custom.sh" "$ARCH"
    ;;
  download)
    TMP="$TOOLCHAIN_DIR/download/cosmocc.zip"
    mkdir -p "$TOOLCHAIN_DIR/download"
    echo "[provision] 下载官方 cosmocc ..."
    curl -fL --retry 3 -o "$TMP" "$COSMO_URL"
    rm -rf "$DEST"; mkdir -p "$DEST"
    ( cd "$DEST" && unzip -q "$TMP" )
    echo "[provision] 完成 (官方发行版, 无本工程定制 libc 补丁)"
    ;;
  *)
    echo "用法: $0 {copy [src] | build [x86_64|aarch64|all] | download}" >&2
    exit 1
    ;;
esac

# 冒烟验证
if [ -x "$DEST/bin/x86_64-unknown-cosmo-cc" ] && [ -x "$DEST/bin/apelink" ]; then
  echo "[provision] 验证: $DEST 可用"
else
  echo "[provision] 警告: 工具链不完整, 请检查"
fi
