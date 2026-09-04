# busybox-cosmo

单一 APE 跨平台 **busybox 1.38.0** — 基于 [Cosmopolitan Libc](https://github.com/jart/cosmopolitan) 构建，一个二进制原生运行于 **Windows / Linux / macOS × x86_64 / aarch64**。

> 本工程是把历史研究/适配工作（`/Users/moore/Projects/busybox` 下的 cosmo-dist 迭代）固化为**可复现工程**的结果：补丁、配置、脚本、文档、测试全部入库；源码与工具链按需取用/拷入，全新机器可重建。

---

## 快速开始

```sh
# 1) 就绪工具链 (三选一)
toolchain/provision.sh copy                # 从既有预编译定制工具链拷入(默认 /tmp/cosmopolitan-master/.cosmocc/3.9.2, 秒级)
toolchain/provision.sh build               # 从官方源码完整构建定制工具链(fetch+make+assemble+verify, 数小时, 可复现)
toolchain/provision.sh download            # 官方 cosmocc 发行版(无定制 libc 补丁, 仅诊断/基座)

# 2) 取源 + 构建 (x86_64 + aarch64 + fat) —— 或直接 make build
make fetch && make build

# 3) 打包发布
make package                              # → dist/busybox-cosmo-release.zip

# 4) 测试 (注意: 测试副本先行, APE 首跑会"同化"改写自身)
make smoke
```

### 自动化验证

`.github/workflows/ci.yml` 在每次 push、PR 和手动触发时执行：先从锁定源码构建
定制 Cosmopolitan 工具链与双架构 BusyBox，再把同一份发布物分发到以下原生 runner：

- Linux x86_64 (`ubuntu-24.04`)
- macOS x86_64 (`macos-15-intel`)
- Windows x86_64 (`windows-2022`)
- Linux ARM64 (`ubuntu-24.04-arm`)
- macOS ARM64 (`macos-15`，实验性、非阻塞)
- Windows ARM64 (`windows-11-arm`，实验性、非阻塞；验证 x86_64 PE 仿真路径，
  不代表 Windows ARM64 原生产物)

Unix 与 Windows 均运行 `deep-test.sh` 和 `smoke-full.sh`；任一硬失败都会让对应
稳定平台 CI job 失败。两个 ARM64 实验任务仍执行完整套件并保留失败日志，但在
对应原生路径完成前不阻塞稳定平台。工具链按源码、补丁和构建脚本的内容哈希缓存，
缓存未命中时从锁定上游源码完整重建。

### 安装/部署 (母本不修改)

```sh
./install.sh --prefix ~/.local/share/busybox-cosmo   # 跨平台(win 用 --win-only)
./install.sh --linux-binfmt                          # Linux 内核级直跑(需 root, 需开机重注册)
# 默认: cache 同化副本, 母本 libexec/busybox 永远 pristine; 详见 docs/RUN-NO-SELF-MODIFY.md
```
### 从官方源码构建定制工具链 (可复现)

```sh
make toolchain-fetch     # 下载官方上游: cosmopolitan@3293fad0 + cosmocc-4.0.2 驱动 (sha 锁定)
make toolchain-build     # 打补丁→make 双架构→组装→verify → toolchain/cosmo
make toolchain-verify    # 与已验参考 .cosmocc/3.9.2 代码级比对
```

详见 `toolchain/README.md`(流水线)与 `patches/cosmo/README.md`(17 文件定制内容)。

### 可复现构建

busybox 会把编译时刻写进版本横幅 (`AUTOCONF_TIMESTAMP`)。固定 `SOURCE_DATE_EPOCH` 后两次构建逐位一致：

```sh
SOURCE_DATE_EPOCH=1788431874 scripts/build-ape.sh x86_64
```

## 产物矩阵

| 产物 | 平台 |
|---|---|
| `busybox-x86_64.ape` / `busybox.com` | Windows / Linux / macOS x86_64 |
| `busybox-aarch64.ape` | Linux / macOS aarch64 (内嵌 64K 对齐 loader) |
| `busybox-fat.ape` | 双架构 fat (x86_64 + aarch64, 内嵌 64K 对齐 loader) |
| `busybox-arm64-linux-elf` | aarch64 裸 ELF — **64KB 页内核免 loader 直跑** |

> 64K 页 Linux aarch64 (鲲鹏 UOS/麒麟): `busybox-arm64-linux-elf` 免 loader 直跑;
> `busybox-fat.ape` / `busybox-aarch64.ape` 已内嵌 64K 对齐 loader 且**由重建的
> apelink 组装** (载荷放 64K 对齐偏移; 官方 apelink 未含 64K 补丁会把载荷放 0x4000,
> 真 64K 内核 loader 拒绝 — 2026-09-04 qemu 真 64K 内核模拟实测并修复)。
> 自检: `scripts/check-ape-64k.sh <file.ape>`。

## 运行路径与同化 (2026-09-04 实测)

| 场景 | 路径 | 全功能 shell? |
|---|---|---|
| Windows | `busybox.com` 直跑 (PE 原生) | ✅ |
| mac Intel | `./busybox` → **fat 内置 `--assimilate` 自同化** → Mach-O | ✅ (免外部工具) |
| mac Apple Silicon | `./busybox` → 自动放 ape-loader-macos-arm64 到 ~/.ape-1.10 (免 cc); 完整 shell 用完整包 assimilate | ⚠️ 顶层可用, 完整 shell 需工具 (待真机) |
| Linux | `sudo ./busybox --setup-linux` 一次 → `busybox.com` 直跑 (binfmt) | ✅ |
| Linux (无 binfmt) | `./busybox` → loader 形态 (顶层命令可用) | ⚠️ 嵌套 exec 受限 |
| Linux 64K aarch64 | 同上 --setup-linux; fat 直接 exec 亦可用 (qemu 真 64K 内核实测) | ✅ |
| 任意 Linux | 完整包含 `assimilate` 工具 → 同化产物 ELF (64K 对齐) | ✅ |

> 注: APE 内置 `--assimilate` 仅 mac 有效 (cosmopolitan 布局局限: Linux 分支只
> printf ELF 头不重定位 phdr, 产物不可加载 — 2026-09-04 qemu arm64/x86 实测);
> Linux 转原生 ELF 须外部 `assimilate` 工具或 binfmt。

## 发布包

- `dist/busybox-cosmo-release.zip` 完整包: busybox-{x86_64,arm64,fat}.ape +
  `busybox-arm64-linux-elf` (64K 直跑) + assimilate/loaders + install + 测试/文档
- `dist/busybox-min.zip` **最小包 (7 文件 ≈ 3.8MB)**: busybox.com (fat) +
  busybox (launcher, 内置 `--setup-linux`) + ape-loader-{aarch64,x86_64} +
  ape-loader-macos-{arm64,x86_64} + README
  (assimilate 已移出 min — Linux 全功能走 `./busybox --setup-linux`; mac arm64
  免 cc 自举靠 ape-loader-macos-arm64; 见 docs/APPLE-SILICON-TEST.md)

## 目录结构

```
config/            busybox 裁剪配置 (已验证, ~320 applet)
patches/           busybox-cosmo-full.patch (82 文件完整适配) + cosmo 工具链定制补丁
toolchain/         provision.sh (copy/download/build) + build-custom.sh + cosmo/(拷入工具链, gitignored)
scripts/           fetch-busybox / fetch-w32-reference / prepare-worktree / build-ape / package-release
tests/             smoke.sh(46) deep-test.sh(31) smoke-test.bat forkdiag
assets/loaders/    ape-loader (64K 页 / 无 binfmt 部署)
baseline/          2026-09-03 已验证发布包 (历史基线, md5 可对照)
src/  work/  dist/ 源码/构建树/产物 (可重建, gitignored)
docs/              工程与平台文档
Makefile           便捷入口 (build/package/smoke/clean)
```

## 文档索引

- `docs/BUILD.md` — 构建原理与手工等价命令
- `docs/ARCHITECTURE.md` — 适配全景(补丁分类/根因/修复)
- `docs/DEPLOYMENT.md` — 各平台部署(Windows/Linux/64K 页/mac)
- `docs/KNOWN-LIMITATIONS.md` — 已知限制与上游缺口
- `docs/VERIFICATION-MATRIX.md` — 验证矩阵与可复现性记录

## 许可

busybox 为 GPL-2.0；产物为静态链接的 Cosmopolitan(ISC) + busybox 代码, 分发注意 GPL 义务。
