#!/bin/sh
# ============================================================
# busybox — 零安装 launcher (随 release 分发, 与 busybox-*.ape 同目录)
#
# 直接 ./busybox <参数> 即可:
#   1) 按当前平台自动挑选同目录发行件 (mac x86→busybox-x86_64.ape,
#      mac arm→busybox-arm64.ape, linux→对应 APE/ELF, 找不到则 busybox-fat.ape)
#   2) 首跑把母本拷到 cache, 转成当前平台原生格式后运行
#      mac Intel: fat 内置 --assimilate → Mach-O (全功能, 免外部工具)
#      Linux     : 已注册 binfmt 则直跑; 否则 loader 形态 (顶层可用)
#      mac arm64 : loader 形态 (顶层可用) — 全功能请用 Rosetta:
#                  arch -x86_64 ./busybox   (见 docs/APPLE-SILICON-TEST.md)
#   3) 母本 (busybox-*.ape) 永远 pristine
#
# 子命令 (Linux):
#   ./busybox --setup-linux   装 /usr/bin/ape + 注册 binfmt (需 root/sudo);
#                             之后 APE 直跑即全功能 shell (含 64K 页内核)
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

# ---------- Linux 部署: loader + binfmt 注册 (原 install-linux.sh, 内联) ----------
setup_linux() {
  [ "$OS" = linux ] || { echo "仅 Linux 需要 binfmt 注册 (mac 走自同化, Windows 走 PE)" >&2; exit 2; }
  if [ "$(id -u)" != 0 ]; then
    echo "需要 root: 请用 sudo $0 --setup-linux" >&2
    exit 1
  fi
  # 选本架构 loader (发布包预编译: x86_64 与 aarch64)
  case "$ARCH" in
    x86_64)  LOADER="$HERE/ape-loader-x86_64" ;;
    aarch64) LOADER="$HERE/ape-loader-aarch64" ;;
    *) echo "不支持的架构: $MACH" >&2; exit 1 ;;
  esac
  [ -f "$LOADER" ] || { echo "缺 loader 文件: $LOADER (在 release/busybox-min 目录运行)" >&2; exit 1; }

  # 1. 安装 loader (必须 /usr/bin/ape —— cosmo OldApeLoader 检测路径)
  echo "==> 安装 loader 到 /usr/bin/ape"
  cp -f "$LOADER" /usr/bin/ape
  chmod 755 /usr/bin/ape

  # 2. binfmt_misc 挂载
  if [ ! -e /proc/sys/fs/binfmt_misc/register ]; then
    echo "==> 挂载 binfmt_misc"
    modprobe binfmt_misc 2>/dev/null || true
    mount -t binfmt_misc none /proc/sys/fs/binfmt_misc 2>/dev/null || true
    [ -e /proc/sys/fs/binfmt_misc/register ] || {
      echo "无法挂载 binfmt_misc (内核无 CONFIG_BINFMT_MISC?)" >&2; exit 1; }
  fi

  # 3. 注册 (FP: F=fix-binary 语义, P=preserve-argv0 —— 4.19 实测必需)
  if [ -e /proc/sys/fs/binfmt_misc/APE ]; then
    echo "==> 已注册, 更新 flags"
    echo -1 > /proc/sys/fs/binfmt_misc/APE
  fi
  echo "==> 注册 APE binfmt (flags=FP)"
  echo ':APE:M::MZqFpD::/usr/bin/ape:FP' > /proc/sys/fs/binfmt_misc/register

  echo ""
  echo "部署完成:"
  cat /proc/sys/fs/binfmt_misc/APE
  echo ""
  echo "验证: ./busybox.com sh -c 'echo ok'"
  echo "持久化提示: binfmt 注册在重启后失效——建议写入开机脚本"
  echo "(如 /etc/rc.local 或 systemd 单元, 内容即 loader+注册两步)"
  exit 0
}

case "${1:-}" in
  --setup-linux|--install-linux|--setup) setup_linux ;;
esac

# ---------- Windows: 直接 exec 对应原生 PE ----------
if [ "$PLAT" = windows ] || [ "$PLAT" = mingw32 ] || [ "$PLAT" = msys ] || [ "$PLAT" = cygwin ]; then
  [ -f "$HERE/busybox.exe" ] && exec "$HERE/busybox.exe" "$@"
  [ -f "$HERE/busybox.com" ] && exec "$HERE/busybox.com" "$@"
  echo "Windows: 请直接运行 busybox.exe/busybox.com" >&2; exit 1
fi

# ---------- 选母本 ----------
pick_master() {
  # 64K 页 Linux aarch64: 裸 ELF 优先 (免 loader 最简, 仅完整包有)
  [ "$OS" = linux ] && [ "$ARCH" = aarch64 ] && \
    [ "$(getconf PAGESIZE 2>/dev/null)" = 65536 ] && \
    [ -f "$HERE/busybox-arm64-linux-elf" ] && { echo "$HERE/busybox-arm64-linux-elf"; return 0; }
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
  # 兜底: 同目录任一发行母本 (最小包常名为 busybox.com / busybox-fat.ape)
  for f in busybox.com busybox.exe busybox-fat.ape busybox-*.ape; do
    [ -f "$HERE/$f" ] && { echo "$HERE/$f"; return 0; }
  done
  echo ""
}

MASTER="$(pick_master)"
[ -n "$MASTER" ] && [ -f "$MASTER" ] || { echo "同目录缺 busybox-*.ape (请在 release 目录运行)" >&2; exit 1; }

# ---------- cache 副本 (母本 pristine) ----------
CACHE="${BUSYBOX_COSMO_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/busybox-cosmo}"
mkdir -p "$CACHE"
KEY="$OS-$ARCH-$( (cksum < "$MASTER") 2>/dev/null | cut -d' ' -f1 )"
RUN="$CACHE/busybox-$KEY"

# mac arm64 loader 预置:**每次调用**都校验 (不能只放创建分支)。
# cosmo OldApeLoader 按 basename (~/.ape-1.10) 识别 loader; 若 LDR 回退到
# 发行件原名 (ape-loader-macos-arm64) 则不被识别 → 载荷把 loader 路径当自身
# exec 路径 → STANDALONE 嵌套 exec argv 错乱 (macOS ARM64 deep→smoke 顺序
# smoke 崩坏根因, 2026-09-04 实测定案)。
APELDR="$HOME/.ape-1.10"
if [ "$OS" = macos ] && [ "$ARCH" = aarch64 ]; then
  for src in "$HERE/ape-loader-macos-arm64" "$HERE/loaders/ape-loader-macos-arm64"; do
    [ -f "$src" ] || continue
    if [ ! -x "$APELDR" ] || ! cmp -s "$src" "$APELDR"; then
      mkdir -p "$(dirname "$APELDR")" 2>/dev/null || true
      cp -f "$src" "$APELDR" && chmod +x "$APELDR" 2>/dev/null
    fi
    break
  done
fi

if [ ! -x "$RUN" ]; then
  cp -f "$MASTER" "$RUN.tmp" && chmod +x "$RUN.tmp" || exit 1

  # ===== 副本转原生 (全功能 shell) — 平台×架构策略 (2026-09-04 实测) =====
  #   mac x86_64 : fat 内置 --assimilate 有效 (Mach-O, 免外部工具)
  #   mac arm64  : fat 内置 --assimilate 分支不存在 (cosmo boot 局限!)
  #                → 需外部 assimilate 工具; 无工具则预置预编译 loader
  #                  (ape-loader-macos-arm64 → ~/.ape-1.10) 走 loader 形态
  #   Linux      : --assimilate 无效 (产物坏 ELF); 工具 / binfmt / loader 形态
  ok=0

  # 1) 外部 assimilate 工具 (完整包) → 原生 ELF/Mach-O
  AS=""
  for a in "$HERE/assimilate" "$HERE/loaders/assimilate"; do
    [ -x "$a" ] && { AS="$a"; break; }
  done
  if [ -n "$AS" ]; then
    if "$AS" -c "$RUN.tmp" >/dev/null 2>&1; then ok=1; fi
  elif [ "$OS" = macos ] && [ "$ARCH" = x86_64 ]; then
    "$RUN.tmp" --assimilate >/dev/null 2>&1 && ok=1   # 仅 x86_64 mac 有此分支
  fi

  # 校验产物是有效原生格式 (mac: Mach-O 头; Linux: ELF 头), 失败则丢弃副本
  if [ "$ok" = 1 ]; then
    magic="$(head -c 4 "$RUN.tmp" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "$OS" in
      macos)  [ "$magic" = "cffaedfe" ] || [ "$magic" = "cefaedfe" ] || ok=0 ;;
      linux)  [ "$magic" = "7f454c46" ] || ok=0 ;;
    esac
    [ "$ok" = 0 ] && rm -f "$RUN.tmp"
  fi

  # 无原生副本 → 用 APE 副本 (loader 形态, 母本仍 pristine)
  if [ ! -f "$RUN.tmp" ]; then
    cp -f "$MASTER" "$RUN.tmp" && chmod +x "$RUN.tmp" || exit 1
  fi
  mv -f "$RUN.tmp" "$RUN" || { rm -f "$RUN.tmp"; exit 1; }
fi

# ---------- 执行: 原生副本直跑; loader 形态走 loader '-' 模式 ----------
magic="$(head -c 4 "$RUN" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
if [ "$magic" = "4d5a7146" ]; then
  # APE 副本 → 找 loader 并用 '-' 模式 (argv[0]=busybox 真实路径, 类 binfmt P flag)
  #   让 busybox realpath(argv[0]) 成功 → STANDALONE 嵌套 exec 全功能
  #   这是 mac (含 Apple Silicon) 与 Linux 无 binfmt 时免 assimilate 的路径;
  #   2026-09-04 静态分析, 真机待验证 (见 docs/APPLE-SILICON-TEST.md)
  LDR=""
  case "$OS-$ARCH" in
    macos-aarch64) for c in "$APELDR" "$HERE/ape-loader-macos-arm64" "$HERE/loaders/ape-loader-macos-arm64"; do
                     [ -x "$c" ] && { LDR="$c"; break; }; done ;;
    macos-x86_64)  for c in "$HERE/ape-loader-macos-x86_64" "$HERE/loaders/ape-loader-macos-x86_64"; do
                     [ -x "$c" ] && { LDR="$c"; break; }; done ;;
    linux-*)       for c in "$HERE/ape-loader-$ARCH" "$HERE/loaders/ape-loader-$ARCH"; do
                     [ -x "$c" ] && { LDR="$c"; break; }; done ;;
  esac
  if [ -n "$LDR" ]; then
    # loader - PROG ARGV0 ...: 第 2 参是要加载的 PROG, 第 3 参成为 argv[0]
    exec "$LDR" - "$RUN" "$RUN" "$@"
  fi
  # 无 loader → 直接 exec (boot 自举: 提取内嵌 loader / 需 cc)
  exec "$RUN" "$@"
fi
exec "$RUN" "$@"
