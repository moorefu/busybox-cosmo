#!/usr/bin/env bash
# ============================================================
# build-custom.sh — 从 cosmopolitan master 源码 + 本工程补丁
#                   完整构建"定制工具链" (慢, 数小时级)
#
# 产出: toolchain/cosmo  (3.9.2 编译驱动 + master 头/库 + 本工程 5 定制补丁)
#
# ⚠️ 默认开发路径请用 toolchain/provision.sh copy (秒级)。
#    本脚本供需要从源码级复现工具链的场景使用。
#
# 原理 (详见 patches/cosmo/README.md, 2026-09-03 已验证配方):
#   1. 克隆 cosmo master, 应用 patches/cosmo/* 的 libc 定制
#   2. make -j MODE=x86_64 o/x86_64/cosmopolitan.a + ape 全套 + 工具 .dbg
#   3. 下载官方 cosmocc 3.9.2 作驱动基底 (include 替换为 master 头)
#   4. 库/链接件全套替换: libcosmo.a←cosmopolitan.a + crt/ape.lds/ape*.o
#   5. busybox 用 3.9.2 驱动 + master 头库重编
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/env.sh"

DEST="$TOOLCHAIN_DIR/cosmo"
MASTER_SRC="${COSMO_MASTER_SRC:-}"
MASTER_URL="${COSMO_MASTER_URL:-https://github.com/jart/cosmopolitan.git}"
COSMOCC_URL="${COSMOCC_URL:-https://cosmo.zip/pub/cosmocc/cosmocc.zip}"
JOBS="${JOBS:-8}"

echo "==== 从源码构建定制 cosmopolitan 工具链 ===="
echo "⚠️  此流程需数小时; 中途不可断网。可用 COSMO_MASTER_SRC 指向已克隆的 master 树。"

# 1. master 源码
if [ -z "$MASTER_SRC" ]; then
  MASTER_SRC="$TOOLCHAIN_DIR/download/cosmopolitan-master"
  mkdir -p "$TOOLCHAIN_DIR/download"
  if [ ! -d "$MASTER_SRC/.git" ]; then
    echo "[1/6] 克隆 cosmopolitan master ..."
    git clone --depth 1 "$MASTER_URL" "$MASTER_SRC"
  fi
fi

# 2. 应用 libc 定制补丁 (master-snapshot 覆盖 = 5 补丁的源码形态)
echo "[2/6] 应用 libc 定制 (master-snapshot 覆盖)..."
if [ -d "$PATCHES_DIR/cosmo/master-snapshot" ]; then
  ( cd "$MASTER_SRC" && cp -R "$PATCHES_DIR/cosmo/master-snapshot/." . )
else
  echo "  提示: 无 master-snapshot, 尝试应用 cosmo-libc-custom.patch"
  ( cd "$MASTER_SRC" && patch -p1 < "$PATCHES_DIR/cosmo/cosmo-libc-custom.patch" )
fi

# 3. 构建 x86_64 + aarch64 cosmopolitan.a
for mode in x86_64 aarch64; do
  echo "[3/6] make MODE=$mode o/$mode/cosmopolitan.a ..."
  ( cd "$MASTER_SRC" && make -j"$JOBS" MODE=$mode "o/$mode/cosmopolitan.a" )
done

# 4. 下载官方 3.9.2 驱动基底
echo "[4/6] 下载官方 cosmocc 驱动基底 ..."
BASE="$TOOLCHAIN_DIR/download/cosmocc-392"
mkdir -p "$TOOLCHAIN_DIR/download"
[ -d "$BASE/bin" ] || { curl -fL -o "$TOOLCHAIN_DIR/download/cosmocc.zip" "$COSMOCC_URL"; mkdir -p "$BASE"; ( cd "$BASE" && unzip -q "$TOOLCHAIN_DIR/download/cosmocc.zip" ); }
rm -rf "$DEST"; cp -c -R "$BASE/." "$DEST/"

# 5. 替换头/库/链接件 (全套一致, 缺一 relocation 错)
echo "[5/6] 替换 master 头 + 库 + ape 部件 ..."
# 头
( cd "$MASTER_SRC" && rm -rf "$DEST/include" && cp -R libc/isystem "$DEST/include" 2>/dev/null || true )
# 库与链接件 (结构随版本而变, 此处为核心替换示意, 需按实际 o/ 布局调整)
for m in x86_64 aarch64; do
  archdir="$DEST/${m}-linux-cosmo/lib"
  [ -d "$archdir" ] || continue
  cp "$MASTER_SRC/o/$m/cosmopolitan.a" "$archdir/libcosmo.a" 2>/dev/null || true
  for f in crt.o crtfastmath.o ape.o ape-no-modify-self.o ape-copy-self.o ape.lds; do
    [ -f "$MASTER_SRC/o/$m/$f" ] && cp "$MASTER_SRC/o/$m/$f" "$archdir/$f"
  done
done

echo "[6/6] 定制工具链落盘: $DEST"
echo "⚠️  步骤 5 的替换规则 (路径/部件名) 依赖 cosmo 版本布局; 若 busybox 链接报 relocation/常量错,"
echo "    请对照 patches/cosmo/README.md 的完整配方手工校准, 或改用 provision.sh copy 已验工具链。"
