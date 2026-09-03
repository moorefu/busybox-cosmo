#!/bin/sh
# ============================================================
# install-linux.sh — Linux APE 部署(loader + binfmt 注册)
# 用法: sudo ./install-linux.sh
# 效果: 1) 安装本架构 ape loader 到 /usr/bin/ape
#       2) 注册 binfmt_misc(FP flag: preserve-argv0, <5.12 同样需要)
#       此后所有 APE/fat 文件可直接运行(免同化/免 cc/嵌套 exec 全功能)
# ============================================================
set -e

# 需要 root
if [ "$(id -u)" != 0 ]; then
  echo "需要 root: 请用 sudo ./install-linux.sh" >&2
  exit 1
fi

# 选本架构 loader(发布包预编译: x86_64 与 aarch64)
HERE="$(cd "$(dirname "$0")" && pwd)"
case "$(uname -m)" in
  x86_64|amd64)  LOADER="$HERE/ape-loader-x86_64" ;;
  aarch64|arm64) LOADER="$HERE/ape-loader-aarch64" ;;
  *) echo "不支持的架构: $(uname -m)" >&2; exit 1 ;;
esac
[ -f "$LOADER" ] || { echo "缺 loader 文件: $LOADER" >&2; exit 1; }

# 1. 安装 loader(必须 /usr/bin/ape——cosmo OldApeLoader 检测路径)
echo "==> 安装 loader 到 /usr/bin/ape"
cp -f "$LOADER" /usr/bin/ape
chmod 755 /usr/bin/ape

# 2. binfmt_misc 挂载
if [ ! -e /proc/sys/fs/binfmt_misc/register ]; then
  echo "==> 挂载 binfmt_misc"
  modprobe binfmt_misc 2>/dev/null || true
  mount -t binfmt_misc none /proc/sys/fs/binfmt_misc 2>/dev/null || true
  [ -e /proc/sys/fs/binfmt_misc/register ] || {
    echo "无法挂载 binfmt_misc(内核无 CONFIG_BINFMT_MISC?)" >&2; exit 1; }
fi

# 3. 注册(FP: F=fix-binary 语义, P=preserve-argv0 —— 4.19 实测必需)
if [ -e /proc/sys/fs/binfmt_misc/APE ]; then
  echo "==> 已注册, 更新 flags"
  echo -1 > /proc/sys/fs/binfmt_misc/APE
fi
echo "==> 注册 APE binfmt(flags=FP)"
echo ':APE:M::MZqFpD::/usr/bin/ape:FP' > /proc/sys/fs/binfmt_misc/register

echo ""
echo "部署完成:"
cat /proc/sys/fs/binfmt_misc/APE
echo ""
echo "验证: 直接运行 APE 文件, 如: ./busybox-fat.ape sh smoke.sh"
echo "持久化提示: binfmt 注册在重启后失效——建议写入开机脚本"
echo "(如 /etc/rc.local 或 systemd 单元, 内容即本脚本的 loader+注册两步)"
