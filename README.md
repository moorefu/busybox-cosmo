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
| `busybox-aarch64.ape` | Linux / macOS aarch64 (4K/16K 页; 64K 页见下) |
| `busybox-fat.ape` | 双架构 fat (x86_64 + aarch64) |
| `busybox-arm64-linux-elf` | aarch64 裸 ELF — **64KB 页内核专用** (APE 同化缺陷规避) |

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
