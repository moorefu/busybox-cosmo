# DEPLOYMENT — 部署指南

> 铁律: APE 首次在某平台运行会**同化**(改写为纯本机格式)。zip 母本分发, 每平台各拷原件首跑; 测试用副本。

## Windows (x86_64)

- 文件名须含 `busybox` (如 `busybox.exe` / `busybox.com`) 才能用 `busybox <applet>` 子命令模式;
  多命令部署可复制多个命名副本 (或 NTFS 硬链接)。
- 推荐 **Windows Terminal**: 中文/选择/粘贴体验最佳; cmd 下 `chcp 65001`。
- 冒烟: 三件套 (busybox.com + smoke.sh + smoke-test.bat) 同目录运行 `smoke-test.bat`。

## Linux

### 常规 (binfmt 可用)

```sh
sudo ./assets/loaders/install-linux.sh   # 装 /usr/bin/ape + 注册 binfmt (FP flag)
# 此后 busybox.com / *.ape 直接运行: 免同化/嵌套 exec 全功能/文件保持 pristine
```

### 无 binfmt (容器/临时)

顶层命令可用; ash 嵌套 exec 建议 ELF 版或旧同化行为。容器内先拷副本再跑。

### 64KB 页内核 (aarch64, UOS/麒麟鲲鹏)

```sh
# ① 直接跑裸 ELF (最简, 无需 loader)
./busybox-arm64-linux-elf <applet>

# ② 或 loader + binfmt (APE/fat 也可用)
cp assets/loaders/ape-loader-aarch64 /usr/bin/ape && chmod +x /usr/bin/ape
echo -1 > /proc/sys/fs/binfmt_misc/APE 2>/dev/null
echo ':APE:M::MZqFpD::/usr/bin/ape:FP' > /proc/sys/fs/binfmt_misc/register
# 重启后需重注册 (见 install-linux.sh 提示)
```

> 注意: 64K 页内核**勿用**普通 APE 同化路径 (历史缺陷); 用 ELF 版或 64K loader。

## macOS

- **Intel**: `busybox-x86_64.ape` 副本首跑同化 (Mach-O) → 全功能。
- **Apple Silicon 原生 arm64**: `busybox-arm64.ape` (首跑自动 dd 提取内嵌 loader 到 ~/.ape-1.10 缓存并 exec, 免 cc)。
  - 完整 sh (嵌套 exec) 当前受限 (cosmo 上游级, ash ENOEXEC fallback 与 APE 前缀 argv 语义冲突);
    日常建议 x86 版经 Rosetta: `arch -x86_64 ./busybox-x86_64.ape`。
  - 备选: `cp assets/loaders/ape-loader-macos-arm64 /usr/local/bin/ape`; Xcode CLT: `xcode-select --install`。
- mac 上 `/bin/ps` 透传依赖沙箱允许 exec 外部程序 (受限环境会报 Operation not permitted — 非缺陷)。

## 从 zip 发布包重建单个平台文件

zip 内 `release/` 顶层目录; 解压后取对应平台文件, **不要**在原目录直接运行 zip 内文件 (同化会改源)。
