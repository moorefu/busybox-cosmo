# DEPLOYMENT — 部署指南

> 铁律: APE 首次在某平台运行会**同化**(改写为纯本机格式)。zip 母本分发, 每平台各拷原件首跑; 测试用副本。

> **同化平台差异 (2026-09-04 实测)**: APE 内置 `--assimilate` **仅 mac 有效**
> (把 fat 就地改写为 Mach-O, 免外部工具)。Linux 上内置 `--assimilate` 产物不可加载
> (cosmopolitan 布局局限) → Linux 转原生 ELF 必须用外部 `assimilate` 工具
> (完整包有) 或 binfmt (`install-linux.sh`)。最小包已按此设计 (见 README 发布包)。

## Windows (x86_64)

- 文件名须含 `busybox` (如 `busybox.exe` / `busybox.com`) 才能用 `busybox <applet>` 子命令模式;
  多命令部署可复制多个命名副本 (或 NTFS 硬链接)。
- 推荐 **Windows Terminal**: 中文/选择/粘贴体验最佳; cmd 下 `chcp 65001`。
- 冒烟: 三件套 (busybox.com + smoke.sh + smoke-test.bat) 同目录运行 `smoke-test.bat`。

## Linux

### 常规 (binfmt 可用)

```sh
sudo ./install-linux.sh        # 最小包/完整包同目录均有; 装 /usr/bin/ape + 注册 binfmt (FP)
# 此后 busybox.com / *.ape 直接运行: 免同化/嵌套 exec 全功能/文件保持 pristine
# (qemu arm64 容器实测: 注册后 smoke 45/46, 2026-09-04)
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

#### 为什么 fat.ape 不能"直接"跑在 64K 页 aarch64 (机制 FAQ)

**一层: fat.ape 不是 ELF。** 它首字节是 `MZqFpD` (APE 多格式壳), 而 Linux 内核
`execve()` 只直接加载纯 ELF。所以 fat/ape 在**任何** Linux 上都不能被内核直载,
必须先经一个"加载者": binfmt_misc 的 `/usr/bin/ape`、提取内嵌 loader, 或同化成纯 ELF。
这跟页大小无关。

**二层: 64K 页内核额外要求加载链路 64K 对齐。** 配了 `CONFIG_ARM64_64K_PAGES`
(鲲鹏 UOS/麒麟) 的内核, 装载 ELF 时按 **PAGE_SIZE=64K** 检查每个 `PT_LOAD` 段
`p_vaddr ≡ p_offset (mod 64K)` 且 `p_align` 为页倍数; 不符即拒绝加载。官方
cosmopolitan 对 aarch64 的链接布局与 loader 都硬编码 **16K** 粒度
(ape 链接 `max-page-size=0x4000`, ape loader/apelink `pagesz=16384`), 因此官方产物
(含 fat) 在 64K 内核上: loader 按 16K mmap 对不上 64K 页、ELF 段对齐被内核拒 —
**整条链都起不来**, 而非仅 fat。

**三层: 本项目如何修 (见 `patches/cosmo/cosmo-custom-full.patch`)。** 三处定制让整条
链 64K 对齐: ① 链接 `max-page-size → 0x10000`; ② apelink.c aarch64 `pagesz
16384 → 65536` (64K 是 4K/16K 的公倍数, 64K 对齐在普通内核同样合法); ③ ape loader
按 64K 对齐编译 (**2026-09-04 补全**: 之前只有单独分发的 `ape-loader-aarch64` 是
64K 版, fat/arm64.ape 内嵌的仍是官方 16K 版 — 现由 `toolchain/build-custom.sh 3b'`
从 master 重建 `o/aarch64/ape/ape.elf` 并替换 `bin/ape-aarch64.elf`, 使 fat 内嵌
loader 也 64K 对齐)。**④ apelink 二进制重建 (2026-09-04 qemu 真 64K 内核模拟
发现)**: 官方 zip 的 apelink 未含 64K 补丁 (源码改了但二进制没重编译), 把 aarch64
载荷放 0x4000 (16K 对齐), 真 64K 内核上 loader 按 AT_PAGESZ=64K 校验不同余拒绝
("ELF p_vaddr incongruent w/ p_offset modulo AT_PAGESZ")。build-custom.sh 3b''
现从 master 重建 apelink 并替换 `bin/apelink`。实测当前产物: aarch64 载荷落
0x10000 (单架构) / 0x1b0000 (fat), phdr 全 64K 同余 —— ELF 版可被 64K 内核直载;
APE/fat 经其**内嵌 64K loader** (直接 exec 前端 boot 自动提取到 `~/.ape-1.10`)、
或 binfmt (`/usr/bin/ape` + `FP`)、或 `./busybox` 均可运行。
自检: `scripts/check-ape-64k.sh <file.ape>`; 真 64K 内核模拟: `tests/qemu-64k-test.sh`。

> 结论: "fat 不支持 64K" 的准确说法是 —— fat 从不是 ELF, 需要 loader; 而官方 loader
> 是 16K 粒度的, 在 64K 内核上不能加载。本项目已把 loader、载荷、**apelink 组装**都
> 做成 64K 对齐并内嵌进 fat (2026-09-04), 于是 64K aarch64 上 `busybox-fat.ape`
> 单文件即满足"经 loader 运行"的全部前置; qemu 真 64K 内核 (Ubuntu 6.8.0-31
> generic-64k) 模拟直接 exec 通过 (A-ELF / B-FAT / C-A64 / D-NESTED 全 OK)。
> 免 loader 的最简形态仍是 `busybox-arm64-linux-elf` 直跑。

## macOS

- **推荐**: 包内 `./busybox` (launcher) 按架构自动选最优路径。
- **Intel (x86_64)**: fat 内置 `--assimilate` 自同化 → Mach-O (免外部工具,
  2026-09-04 实测 44/46), 之后全功能 shell。
- **Apple Silicon (arm64)**: 全功能路径有 cosmo 上游限制 (APE 无 Mach-O arm64
  布局, assimilate 只能转 ELF 而 mac 不跑 ELF) — **推荐 Rosetta**:
  `arch -x86_64 ./busybox` (与 mac Intel 等价 ~44/46)。
  原生 arm64 顶层命令: bb.sh 用 loader `-` 模式显式 exec `ape-loader-macos-arm64`
  (免 cc / Xcode CLT; 直接 exec 会被 boot 的 cc 检查卡住)。loader 形态嵌套 exec
  受限 (cosmo 上游级)。**待真机验证**: 见 `docs/APPLE-SILICON-TEST.md`。
- mac 上 `/bin/ps` 透传依赖沙箱允许 exec 外部程序 (受限环境会报 Operation not permitted — 非缺陷)。

## 从 zip 发布包重建单个平台文件

zip 内 `release/` 顶层目录; 解压后取对应平台文件, **不要**在原目录直接运行 zip 内文件 (同化会改源)。
