#!/usr/bin/env bash
# 从锁定原版生成构建树；补丁失败不留下半成品，不猜测旧树是否已打补丁。
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/env.sh"
ARCH="${1:-x86_64}"
case "$ARCH" in
  x86_64) TREE="$TREE_X86" ;;
  aarch64) TREE="$TREE_A64" ;;
  *) die "未知架构: $ARCH (x86_64|aarch64)" ;;
esac
command -v python3 >/dev/null || die "补丁管理需要 Python 3"
"$ROOT/scripts/fetch-busybox.sh"
python3 "$ROOT/scripts/patch-series.py" check "$BB_PATCH_SERIES"
python3 "$ROOT/scripts/patch-series.py" apply "$BB_PATCH_SERIES" \
  --source "$SRC_DIR/busybox-$BB_VER" --target "$TREE"

cp "$CONFIG_DIR/busybox-$BB_VER.config" "$TREE/.config"
# 新增源码带来的 Kconfig 符号必须在 oldconfig 前写入；oldconfig 会把它们
# 规范化到最终位置。不能在 oldconfig 后用 sed -i 触碰 .config，否则正式
# make 会再次进入无输入配置流程。
for c in $BB_FORCE_APP_LETS; do
  if ! grep -qx "$c=y" "$TREE/.config"; then
    if grep -qx "# $c is not set" "$TREE/.config"; then
      sed -i.bak "s/^# $c is not set$/$c=y/" "$TREE/.config"
      rm -f "$TREE/.config.bak"
    else
      printf '%s=y\n' "$c" >> "$TREE/.config"
    fi
  fi
done
# yes 被 make 关闭输入后收到 SIGPIPE 是正常的，只忽略管道上游，不吞 make 错误。
if ! (
  cd "$TREE"
  set +o pipefail
  yes "" | make -s oldconfig
) >"$TREE/.oldconfig.log" 2>&1; then
  tail -40 "$TREE/.oldconfig.log" >&2
  die "BusyBox oldconfig 失败"
fi
rm -f "$TREE/.oldconfig.log"
for c in $BB_FORCE_APP_LETS; do
  grep -qx "$c=y" "$TREE/.config" || die "无法启用配置: $c"
done
echo "[prepare] $ARCH 构建树就绪: $TREE"
