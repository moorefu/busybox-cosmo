#!/bin/sh
# ============================================================
# busybox — 零安装 launcher (随 release 分发, 与 busybox-*.ape 同目录)
#
# 直接 ./busybox <参数> 即可:
#   1) 按当前平台自动挑选同目录发行件 (mac x86→busybox-x86_64.ape,
#      mac arm→busybox-arm64.ape, linux→对应 APE/ELF, 找不到则 busybox-fat.ape)
#   2) 首跑把母本拷到 cache, 用同目录 assimilate 就地转成当前平台原生格式
#      (Linux ELF / mac Mach-O), 之后直接运行原生副本 —— 全功能 shell
#   3) 母本 (busybox-*.ape) 永远 pristine
#
# cache 位置: $BUSYBOX_COSMO_CACHE → $XDG_CACHE_HOME/busybox-cosmo
#             → ~/.cache/busybox-cosmo (默认)
# 清理: rm -rf ~/.cache/busybox-cosmo
# ============================================================
HERE="$(cd "$(dirname "$0")" && pwd)"
PLAT="$(uname -s 2>/dev/null | tr A-Z a-z)"
MACH="$(uname -m 2>/dev/null | tr A-Z a-z)"
case "$MACH" in x86_64|amd64) ARCH=x86_64;; aarch64|arm64) ARCH=aarch64;; esac
case "$PLAT" in linux) OS=linux;; darwin) OS=macos;; *) OS=$PLAT;; esac

pick_master() {
  # 同目录优先精确平台件; 退回 fat (发行命名: busybox-x86_64.ape / busybox-arm64.ape)
  case "$ARCH" in
    x86_64)
      for f in "busybox-$OS-x86_64.ape" "busybox-x86_64.ape" "busybox-fat.ape"; do
        [ -f "$HERE/$f" ] && { echo "$HERE/$f"; return 0; }
      done ;;
    aarch64)
      for f in "busybox-$OS-arm64.ape" "busybox-arm64.ape" "busybox-fat.ape"; do
        [ -f "$HERE/$f" ] && { echo "$HERE/$f"; return 0; }
      done ;;
  esac
  # 64K 页 Linux: ELF 优先
  [ "$OS" = linux ] && [ "$(getconf PAGESIZE 2>/dev/null)" = 65536 ] && \
    [ -f "$HERE/busybox-arm64-linux-elf" ] && { echo "$HERE/busybox-arm64-linux-elf"; return 0; }
  # 兜底: 同目录任一发行母本 (最小包常名为 busybox.com / busybox-fat.ape)
  for f in busybox.com busybox.exe busybox-fat.ape busybox-*.ape; do
    [ -f "$HERE/$f" ] && { echo "$HERE/$f"; return 0; }
  done
  echo ""
}

# 本平台已同化(原生)的副本直接用 —— 不支持 Windows 双跑此脚本
if [ "$PLAT" = windows ] || [ "$PLAT" = mingw32 ] || [ "$PLAT" = msys ] || [ "$PLAT" = cygwin ]; then
  [ -f "$HERE/busybox.exe" ] && exec "$HERE/busybox.exe" "$@"
  [ -f "$HERE/busybox.com" ] && exec "$HERE/busybox.com" "$@"
  echo "Windows: 请直接运行 busybox.exe/busybox.com" >&2; exit 1
fi

MASTER="$(pick_master)"
[ -n "$MASTER" ] && [ -f "$MASTER" ] || { echo "同目录缺 busybox-*.ape (请在 release 目录运行)" >&2; exit 1; }

CACHE="${BUSYBOX_COSMO_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/busybox-cosmo}"
mkdir -p "$CACHE"
KEY="$OS-$ARCH-$( (cksum < "$MASTER") 2>/dev/null | cut -d' ' -f1 )"
RUN="$CACHE/busybox-$KEY"

if [ ! -x "$RUN" ]; then
  cp -f "$MASTER" "$RUN.tmp" && chmod +x "$RUN.tmp" || exit 1
  # 优先: 同目录/loaders 的 assimilate 把副本转成原生 (全功能)
  AS=""
  for a in "$HERE/assimilate" "$HERE/loaders/assimilate" "$HERE/dist/release/release/assimilate"; do
    [ -x "$a" ] && { AS="$a"; break; }
  done
  if [ -n "$AS" ]; then "$AS" -c "$RUN.tmp" >/dev/null 2>&1 || true
  else "$RUN.tmp" true >/dev/null 2>&1 || true; fi  # 自同化型 APE 的兜底
  mv -f "$RUN.tmp" "$RUN" || { rm -f "$RUN.tmp"; exit 1; }
fi
exec "$RUN" "$@"
