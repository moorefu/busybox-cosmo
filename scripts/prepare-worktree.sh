#!/usr/bin/env bash
# ============================================================
# prepare-worktree.sh — 由原版源码生成某架构的已打补丁构建树
#   用法: scripts/prepare-worktree.sh <x86_64|aarch64>
#   产物: work/busybox-1.38.0-<arch>/  (已打补丁 + .config)
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

ARCH="${1:-x86_64}"
case "$ARCH" in
  x86_64)  TREE="$TREE_X86" ;;
  aarch64) TREE="$TREE_A64" ;;
  *) die "未知架构: $ARCH (x86_64|aarch64)" ;;
esac

# 0. 前置检查
[ -f "$BB_FULL_PATCH" ] || die "缺完整补丁: $BB_FULL_PATCH (先整理 patches/)"
[ -f "$CONFIG_DIR/busybox-$BB_VER.config" ] || die "缺配置: config/busybox-$BB_VER.config"

# 1. 取原版源码
scripts/fetch-busybox.sh
SRC="$SRC_DIR/busybox-$BB_VER"

# 2. 复制原版 → 工作树
if [ ! -d "$TREE" ]; then
  echo "[prepare] 复制原版源码 → $TREE"
  mkdir -p "$WORK_DIR"
  cp -R "$SRC" "$TREE"
fi

# 3. 打补丁 (幂等: 以 .bb-patch-ok 标志为准)
#    注意: 不能用 `patch -R --dry-run` 探测"已打过"——GNU patch 在纯净树反向探测时会
#    自动回答 "Ignore -R? [y]" 并返回 0, 造成误判跳过补丁 (2026-09-03 实测踩坑)。
if [ ! -f "$TREE/.bb-patch-ok" ]; then
  if ( cd "$TREE" && patch -p1 --dry-run -s < "$BB_FULL_PATCH" >/dev/null 2>&1 ); then
    echo "[prepare] 打补丁 busybox-cosmo-full.patch ..."
    ( cd "$TREE" && patch -p1 -s < "$BB_FULL_PATCH" )
  elif ( cd "$TREE" && grep -q "get_busybox_exec_path" include/libbb.h ); then
    echo "[prepare] 树已含补丁(旧工作区拷入), 跳过"
  else
    die "补丁 forward dry-run 失败且树中无补丁痕迹, 请检查"
  fi
  touch "$TREE/.bb-patch-ok"
  echo "[prepare] 补丁完成"
else
  echo "[prepare] 补丁已应用, 跳过"
fi

# 3b. 增量补丁: 恢复部分被裁 applet (free/uptime/ar/uncompress/unlzop/lzopcat)
#     (基于已打 full patch 的树; 幂等以 .bb-restore-ok 标志为准)
if [ -f "$BB_RESTORE_PATCH" ] && [ ! -f "$TREE/.bb-restore-ok" ]; then
  if ( cd "$TREE" && patch -p1 --dry-run -s < "$BB_RESTORE_PATCH" >/dev/null 2>&1 ); then
    echo "[prepare] 打增量补丁 $(basename "$BB_RESTORE_PATCH") ..."
    ( cd "$TREE" && patch -p1 -s < "$BB_RESTORE_PATCH" )
    touch "$TREE/.bb-restore-ok"
  else
    echo "[prepare] 增量补丁不可用(可能已含或版本不符), 跳过: $BB_RESTORE_PATCH"
  fi
fi

# 4. 放配置
cp "$CONFIG_DIR/busybox-$BB_VER.config" "$TREE/.config"
echo "[prepare] $ARCH 构建树就绪: $TREE"
