busybox-1.38.0 cosmopolitan 发布包 (2026-09-03, master 定制工具链 + 5 补丁)

文件说明:
  busybox-x86_64.ape         x86_64 APE: Windows/Linux/macOS x86_64 通用
  busybox.com                = 同上(Windows 便捷名, 需含 busybox 名才能子命令模式)
  busybox-arm64-linux-elf    aarch64 ELF: 4K/16K/64K 页 Linux aarch64 通用
                             ★ 64KB 页内核(UOS/麒麟鲲鹏)必须用此 ELF 版(APE 同化缺陷)
  busybox-fat.ape            fat 双架构(x86_64 + aarch64): 4K/16K 页系统通用
  busybox-arm64-linux        arm64 stripped(小体积备用)
  smoke.sh/deep-test.sh      测试(各平台: busybox sh smoke.sh)
  smoke-test.bat             Windows 冒烟
  md5sums.txt                校验清单

验证成绩(2026-09-03):
  Windows: smoke 46/46 全绿(含 ps/dev/zero/Unicode/鼠标选择)
  Linux x86_64(podman): 45/46([win] 项除外)
  Linux aarch64 64K页(鲲鹏 UOS): ELF 直跑 45/46+31/31;
                                  APE/fat + loader 45/46+31/31(全功能)
  macOS: 45/46 + 嵌套 exec 修复

macOS Apple Silicon(arm64):
  busybox-arm64.ape / busybox-fat.ape 已内嵌预编译 arm64 loader(Mach-O, adhoc签名)
  —— 首跑自动 dd 提取到 ~/.ape-1.10 缓存并 exec, 免 cc 免手动安装(完全自举)
  备选:
  1) 预装 loader(可省首跑提取): cp ape-loader-macos-arm64 /usr/local/bin/ape
  2) Xcode CLT: xcode-select --install(若需现场重编)
  3) Rosetta: arch -x86_64 ./busybox-x86_64.ape
  待 AS 实机验证

Linux 部署(推荐, 一键全功能): sudo ./install-linux.sh
  - 装本架构 loader 到 /usr/bin/ape + 注册 binfmt(FP flag)
  - 此后 APE/fat 直接跑: 免同化/免 cc/嵌套 exec 全功能/文件保持 pristine
  - 重启后 binfmt 需重注册(见脚本提示)
  - 64K 页内核(UOS/麒麟鲲鹏)同此流程(aarch64 loader 已含)

无 binfmt 的容器/临时环境: 顶层命令可用; ash 嵌套 exec 需 ELF 版
(busybox-arm64-linux-elf)或旧同化行为。
Apple Silicon 原生 arm64 的完整 sh(嵌套 exec)当前受限——日常建议 x86 版
经 Rosetta(busybox.com, 同化后与 mac Intel 同路径全功能); arm64 原生
顶层/单命令可用。

64KB 页内核(UOS/麒麟鲲鹏)部署(ape-loader-aarch64):
  # loader 必须装 /usr/bin/ape(cosmo OldApeLoader 检测路径)
  cp ape-loader-aarch64 /usr/bin/ape && chmod +x /usr/bin/ape
  # binfmt 注册必须带 P flag(preserve-argv0, <5.12 内核同样需要,
  # 否则 shell 嵌套 exec 丢 argv0 全挂——见 issue 草稿)
  echo -1 > /proc/sys/fs/binfmt_misc/APE 2>/dev/null
  echo ':APE:M::MZqFpD::/usr/bin/ape:FP' > /proc/sys/fs/binfmt_misc/register
  # 此后 busybox-fat.ape/busybox-arm64.ape 可直接运行(免同化,免 ELF 版)
  # 备选: 直接跑 busybox-arm64-linux-elf(无需 loader)

重要规则:
  1. APE 首次在某平台运行会"同化"改写成纯本机格式——此后该文件平台专属。
     分发请 zip 母本; 每平台各拷原件首跑。
  2. Windows: 文件名须含 "busybox"(如 busybox.exe/busybox.com) 才能用子命令模式;
     建议 Windows Terminal 运行(中文/选择/粘贴最佳体验); cmd 下 chcp 65001。
  3. 64KB 页 Linux aarch64 用 busybox-arm64-linux-elf(勿用 APE)。
  4. 测试副本先行, 勿直接运行发布原件(会触发同化)。
