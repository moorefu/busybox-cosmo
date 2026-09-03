#!/usr/bin/env bash
# ============================================================
# provision.sh — 就绪 cosmopolitan 定制工具链 (toolchain/cosmo)
#
# 三种模式:
#   copy    从已有预编译工具链目录拷贝 (最快, 本工程开发默认)
#           provision.sh copy [/path/to/toolchain]
#   download 下载官方 cosmocc 发行版解压 (无定制 libc 补丁, 仅基础可用)
#           provision.sh download
#   build   从 cosmopolitan master 源码 + 本工程补丁完整构建定制工具链
#           (最完整可复现, 但需数小时; 见 build-custom.sh)
#           provision.sh build
#
# 环境变量:
#   COSMO_SRC    copy 模式的源目录 (默认 /tmp/cosmopolitan-master/.cosmocc/3.9.2)
#   或直接 provision.sh copy /custom/path
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/env.sh"

MODE="${1:-}"
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
    echo "[provision] 拷贝 $SRC → $DEST (APFS clonefile 秒级)..."
    rm -rf "$DEST"; mkdir -p "$DEST"
    cp -c -R "$SRC/." "$DEST/"
    echo "[provision] 完成 ($(du -sh "$DEST" | cut -f1))"
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
  build)
    exec "$TOOLCHAIN_DIR/build-custom.sh"
    ;;
  *)
    echo "用法: $0 {copy [src]|download|build}" >&2
    exit 1
    ;;
esac

# 冒烟验证
if [ -x "$DEST/bin/x86_64-unknown-cosmo-cc" ] && [ -x "$DEST/bin/apelink" ]; then
  echo "[provision] 验证: $DEST 可用"
else
  echo "[provision] 警告: 工具链不完整, 请检查"
fi
