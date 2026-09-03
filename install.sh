#!/bin/sh
# ============================================================
# busybox-cosmo 统一安装器 (跨平台: Linux / macOS / Windows*)
#
#   * Windows 建议在 git-bash / WSL / MSYS 下运行; 纯 cmd 场景见
#     --win-only 输出或 release/README.txt。
#
# 设计目标 (对应 APE 自修改问题, 详见 docs/RUN-NO-SELF-MODIFY.md):
#   1) Linux + binfmt (内核 /usr/bin/ape): 母本零写入且嵌套 exec 全功能 —— 最佳。
#   2) 其余 mac/无 binfmt Linux: 默认 cache 同化副本 —— 首次把母本拷到
#      ~/.cache 运行(副本完成平台"同化"), 母本永远 pristine; 之后直接跑
#      已同化的原生副本(快)。BB_USE_LOADER=1 可改用显式 loader(免拷贝,
#      但 loader 下 ash 嵌套 exec 受限, 见文档)。
#   3) Windows 为 PE 原生加载, 无同化问题, 直接运行 .com/.exe。
#
# 用法:
#   ./install.sh [--prefix DIR] [--linux-binfmt] [--win-only] [--uninstall]
#     --prefix DIR      安装根 (默认 $HOME/.local/share/busybox-cosmo)
#     --linux-binfmt    同时注册 binfmt_misc + /usr/bin/ape (需 root,
#                       之后 Linux 上所有 APE 内核级直跑且不改母本)
#     --win-only        仅准备 Windows 文件 (busybox.exe + loaders)
#     --uninstall       移除本安装器装的东西
# ============================================================
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local/share/busybox-cosmo}"
BINFMT=0
WINONLY=0
UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --linux-binfmt) BINFMT=1; shift ;;
    --win-only) WINONLY=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    *) echo "未知参数: $1 (见头部用法)" >&2; exit 1 ;;
  esac
done

# ---------- 平台/架构探测 ----------
OS="$(uname -s 2>/dev/null | tr A-Z a-z)"
MACH="$(uname -m 2>/dev/null | tr A-Z a-z)"
case "$OS" in
  linux)   PLAT=linux ;;
  darwin)  PLAT=macos ;;
  mingw*|msys*|cygwin*) PLAT=windows ;;
  *) echo "不支持的系统: $OS" >&2; exit 1 ;;
esac
case "$MACH" in
  x86_64|amd64) ARCH=x86_64 ;;
  aarch64|arm64) ARCH=aarch64 ;;
  *) echo "不支持的架构: $MACH" >&2; exit 1 ;;
esac

echo "平台: $PLAT / $ARCH    安装根: $PREFIX"

# ---------- 待安装资产探测 (兼容: release 同目录 / 工程内 dist 布局) ----------
find_asset() { # $1=名 输出路径; 找不到返回 1
  for d in "$HERE" "$HERE/dist" "$HERE/dist/release" "$HERE/dist/release/release" "$HERE/assets/loaders"; do
    if [ -f "$d/$1" ]; then echo "$d/$1"; return 0; fi
  done
  return 1
}

# 选择本平台主二进制
case "$PLAT-$ARCH" in
  linux-x86_64)  MASTER_SRC=busybox-x86_64.ape ;;
  linux-aarch64)
    # 64KB 页内核无法跑 APE 同化路径 → 用裸 ELF
    if [ "$(getconf PAGESIZE 2>/dev/null)" = "65536" ]; then MASTER_SRC=busybox-arm64-linux-elf
    else MASTER_SRC=busybox-arm64.ape; fi ;;
  macos-x86_64)  MASTER_SRC=busybox-x86_64.ape ;;
  macos-aarch64) MASTER_SRC=busybox-arm64.ape ;;
  windows-*)     MASTER_SRC=busybox.com ;;
esac
LOADER_SRC=
case "$PLAT-$ARCH" in
  linux-x86_64)  LOADER_SRC=ape-loader-x86_64 ;;
  linux-aarch64) LOADER_SRC=ape-loader-aarch64 ;;
  macos-x86_64)  LOADER_SRC=ape-loader-macos-x86_64 ;;
  macos-aarch64) LOADER_SRC=ape-loader-macos-arm64 ;;
esac

[ "$UNINSTALL" = 1 ] && {
  rm -rf "$PREFIX"
  echo "已卸载: $PREFIX"
  exit 0
}

# Windows: 仅准备文件 (cmd 直接拷走即可)
if [ "$PLAT" = windows ]; then
  SRC="$(find_asset busybox.com)" || { echo "缺 busybox.com (请在 release 目录运行)" >&2; exit 1; }
  mkdir -p "$PREFIX"
  cp -f "$SRC" "$PREFIX/busybox.exe"
  for l in ape-loader-x86_64 ape-loader-aarch64 ape-loader-macos-x86_64 ape-loader-macos-arm64 ape-m1-loader-src.c; do
    L="$(find_asset "$l")" && { mkdir -p "$PREFIX/loaders"; cp -f "$L" "$PREFIX/loaders/"; }
  done
  cp -f "$(find_asset busybox-arm64-linux-elf 2>/dev/null || echo /dev/null)" "$PREFIX/busybox-arm64-linux-elf" 2>/dev/null || true
  echo ""
  echo "Windows 就绪: $PREFIX/busybox.exe  (PE 原生加载, 无自修改)"
  echo "把 busybox.exe 复制/改名到 PATH 中名为 busybox.exe 即可(须含 busybox 才能用子命令模式)。"
  exit 0
fi

MASTER="$(find_asset "$MASTER_SRC")" || { echo "缺 $MASTER_SRC (请在 release 目录或 dist/release/release 下运行)" >&2; exit 1; }
[ -n "$LOADER_SRC" ] && LOADER="$(find_asset "$LOADER_SRC")" || LOADER=

# ---------- 安装 ----------
LIBEXEC="$PREFIX/libexec"
BIN="$PREFIX/bin"
mkdir -p "$LIBEXEC" "$BIN" "$PREFIX/loaders"
cp -f "$MASTER" "$LIBEXEC/busybox"          # 母本: 只读运行/拷贝源, 从不直接改写
chmod 755 "$LIBEXEC/busybox"
for l in ape-loader-x86_64 ape-loader-aarch64 ape-loader-macos-x86_64 ape-loader-macos-arm64 ape-m1-loader-src.c; do
  L="$(find_asset "$l")" && cp -f "$L" "$PREFIX/loaders/" 2>/dev/null && chmod 755 "$PREFIX/loaders/$l" 2>/dev/null || true
done
[ -n "$LOADER" ] && cp -f "$LOADER" "$PREFIX/loaders/$(basename "$LOADER")"

# binfmt (Linux 内核级, 需 root)
if [ "$BINFMT" = 1 ] && [ "$PLAT" = linux ]; then
  LO="$PREFIX/loaders/$LOADER_SRC"
  echo "==> 注册 binfmt_misc (loader=$LO)"
  [ "$(id -u)" = 0 ] || { echo "需要 root 注册 binfmt; 跳过(可用 sudo $0 --linux-binfmt 补)" >&2; }
  if [ "$(id -u)" = 0 ]; then
    cp -f "$LO" /usr/bin/ape && chmod 755 /usr/bin/ape
    [ -e /proc/sys/fs/binfmt_misc/register ] || { modprobe binfmt_misc 2>/dev/null || true; mount -t binfmt_misc none /proc/sys/fs/binfmt_misc 2>/dev/null || true; }
    [ -e /proc/sys/fs/binfmt_misc/APE ] && echo -1 > /proc/sys/fs/binfmt_misc/APE
    echo ':APE:M::MZqFpD::/usr/bin/ape:FP' > /proc/sys/fs/binfmt_misc/register
    echo "   binfmt OK: $(cat /proc/sys/fs/binfmt_misc/APE 2>/dev/null | tr '\n' ' ')"
  fi
fi

# ---------- launcher (不修改母本策略) ----------
cat > "$BIN/busybox" <<EOF
#!/bin/sh
# busybox-cosmo launcher — 以不修改母本的方式运行
MASTER="$LIBEXEC/busybox"
PLAT="$PLAT"; ARCH="$ARCH"
LOADERS="$PREFIX/loaders"
CACHE="\${BUSYBOX_COSMO_CACHE:-\${XDG_CACHE_HOME:-\$HOME/.cache}/busybox-cosmo}"

# 1) Linux binfmt 已注册 → 内核经 /usr/bin/ape loader 加载, 母本零写入;
#    loader 保留真实 argv0 → ash STANDALONE 嵌套 exec 全功能 (最快路径)
if [ "\$PLAT" = linux ] && [ -e /proc/sys/fs/binfmt_misc/APE ]; then
  exec "\$MASTER" "\$@"
fi
# 2) 默认: cache 同化副本 —— 首次拷母本到 ~/.cache 运行(副本完成平台同化,
#    之后为原生格式直跑, 快), 母本 pristine 且 ash 嵌套 exec 全功能。
#    BB_USE_LOADER=1: 改用显式 loader(免拷贝, 但 loader 下嵌套 exec 受限,
#    详见 docs/RUN-NO-SELF-MODIFY.md)。
if [ "\${BB_USE_LOADER:-0}" = 1 ]; then
  LOADER=
  case "\$PLAT-\$ARCH" in
    linux-x86_64)  [ -x "\$LOADERS/ape-loader-x86_64" ]        && LOADER="\$LOADERS/ape-loader-x86_64" ;;
    linux-aarch64) [ -x "\$LOADERS/ape-loader-aarch64" ]       && LOADER="\$LOADERS/ape-loader-aarch64" ;;
    macos-x86_64)  [ -x "\$LOADERS/ape-loader-macos-x86_64" ]  && LOADER="\$LOADERS/ape-loader-macos-x86_64" ;;
    macos-aarch64) [ -x "\$LOADERS/ape-loader-macos-arm64" ]   && LOADER="\$LOADERS/ape-loader-macos-arm64" ;;
  esac
  if [ -n "\$LOADER" ]; then exec "\$LOADER" "\$MASTER" "\$@"; fi
fi
mkdir -p "\$CACHE"
KEY="\$PLAT-\$ARCH-\$( (cksum < "\$MASTER") 2>/dev/null | cut -d' ' -f1 )"
if [ ! -x "\$CACHE/busybox-\$KEY" ]; then
  cp -f "\$MASTER" "\$CACHE/busybox-\$KEY.tmp"
  chmod +x "\$CACHE/busybox-\$KEY.tmp"
  # 首跑完成同化 (只发生在副本上)
  "\$CACHE/busybox-\$KEY.tmp" true 2>/dev/null || true
  mv -f "\$CACHE/busybox-\$KEY.tmp" "\$CACHE/busybox-\$KEY"
fi
exec "\$CACHE/busybox-\$KEY" "\$@"
EOF
chmod 755 "$BIN/busybox"

# 便捷 applet 名 (母本亦名 busybox, 子命令模式可用)
ln -sfn busybox "$BIN/busybox.com" 2>/dev/null || cp -f "$LIBEXEC/busybox" "$BIN/busybox.com"

echo ""
echo "=== 安装完成 ==="
echo "  主程序(母本, 只读, 从不直接 exec): $LIBEXEC/busybox"
echo "  launcher:           $BIN/busybox   (binfmt→cache 同化副本→[BB_USE_LOADER=1] loader; 母本不改)"
echo "  loaders:            $PREFIX/loaders/"
echo ""
echo "试运行:"
echo "  $BIN/busybox --help | head"
echo "  $BIN/busybox sh $PREFIX/../smoke.sh   (若同目录有 smoke.sh)"
echo ""
echo "母本自修改校验:"
echo "  a=\$(cksum $LIBEXEC/busybox); $BIN/busybox echo hi >/dev/null; b=\$(cksum $LIBEXEC/busybox); [ \"\$a\" = \"\$b\" ] && echo '母本未被修改 ✓'"
[ "$PLAT" = linux ] && echo "提示: binfmt 注册重启后失效; 用 --linux-binfmt 或写开机脚本重注册。64K 页内核请用 busybox-arm64-linux-elf。"
exit 0
