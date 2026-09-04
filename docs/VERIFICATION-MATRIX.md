# VERIFICATION-MATRIX — 验证矩阵与可复现性记录

## 一、本工程重建验证 (2026-09-03, macOS x86_64 主机)

| 步骤 | 方法 | 结果 |
|---|---|---|
| 取源 | `scripts/fetch-busybox.sh` 从 busybox.net 下载 tarball, sha256 校验 | ✅ `34f9ea6ff863…` 一致 |
| 补丁 | `busybox-cosmo-full.patch` 对官方原版 dry-run/实打 | ✅ 82 文件 0 FAILED |
| x86_64 构建 | 官方源码 + 补丁 + 统一 config + 定制工具链, make → apelink | ✅ 产物 ELF x86_64 |
| aarch64 构建 | 同上 aarch64 交叉 | ✅ 产物 ELF aarch64 |
| fat 合成 | `scripts/build-ape.sh fat` (apelink 双 ELF) | ✅ |
| 发布打包 | `scripts/package-release.sh` | ✅ zip 布局与历史基线一致 |
| 本地冒烟 | 新产物 `busybox.com` 副本跑 `smoke.sh` (mac) | 44/46 (`ps` 环境项 + `[win]` 平台项) — 与历史基线同机行为一致 |

### 逐字节对照结论

- 新构建 x86_64 `busybox_unstripped` 与历史已验证树对比: **全部采样 .o 逐字节相同**; 唯一差异为
  版本横幅 `AUTOCONF_TIMESTAMP` (编译时刻)。
- 固定 `SOURCE_DATE_EPOCH` 后两次独立构建 → md5 一致 (见下节实测)。

## 二、可复现性实测

```
SOURCE_DATE_EPOCH=1788431874 构建 repro1 / repro2 (独立树, 同源同补丁同配置同工具链)
busybox_unstripped md5: repro1 == repro2 == c6a1cd9dbc56db3b99fb41f72f8c2a98  ✅ 逐位可复现
```

## 二·五、定制工具链"从官方源码构建"实测 (2026-09-03 第二期)

在工程内以官方材料 + 本工程补丁完整重建定制工具链 (`toolchain/build-custom.sh all`):

| 阶段 | 结果 |
|---|---|
| fetch: cosmopolitan@3293fad + cosmocc-3.9.2 | sha256 双校验通过 (`cde29083…` / `f4ff13af…`) |
| 补丁: cosmo-custom-full.patch (17 文件) | 官方树 dry-run + 实打 0 FAILED; 结果树与原定制树逐字节一致 |
| make MODE=x86_64 (基座 make 4.4.1 自举) | ✅ cosmopolitan.a 59M + crt/ape 全套 |
| make MODE=aarch64 | ✅ cosmopolitan.a 57M + crt.o + **ape/ape.elf (64K loader, 2026-09-04)** |
| assemble: 官方基座 + master 产物/头 + 64K 包装脚本 | ✅ 结构与已验证 .cosmocc/3.9.2 一致; **3b' 装入 64K ape-aarch64.elf** |
| verify vs 参考 .cosmocc/3.9.2 | x86_64 libcosmo.a **5250/5250 成员**、aarch64 **5252/5252 成员** strip-debug 后代码一致; crt/ape/头/包装脚本一致; **3f' loader 64K 对齐校验** ✓ |
| 用新工具链重建 busybox all | ✅ make 0 错误 (x86_64+aarch64+fat) |
| 本地冒烟 | 44/46, 与基线同机行为一致 (`ps` 沙箱项 + `[win]` 平台项) |

说明: 对象 strip-debug 前逐字节不同, 源于 DWARF 内嵌**构建路径**不同(参考树在 /tmp, 新树在工程内)——
代码节与成员集合完全一致, 功能等价。

## 三、历史验证基线 (2026-09-03, 实机, 记录于 baseline/)

| 平台 | 用法 | smoke | deep | 备注 |
|---|---|---|---|---|
| Windows x86_64 | busybox.com | **46/46** | 待 CI | ps/dev/zero/Unicode/鼠标全绿; deep-test 的 awk 引号用例经 heredoc/-f, smoke-full 网络服务端/信号项按平台缺口 SKIP (见 KNOWN-LIMITATIONS) |
| Linux x86_64 | APE 直跑 (podman) | 45/46 | 31/31 | `[win]` 项除外 |
| Linux aarch64 64K 页 | ELF 直跑 / APE+loader+FP | 45/46 | 31/31 | 鲲鹏 UOS 实机, 双路径同功能 |
| macOS (Intel) | APE | 45/46 | — | 嵌套 exec 修复 |

## 三·五、fat 内嵌 64K loader (2026-09-04)

| 验证 | 结果 |
|---|---|
| master 重建 `o/aarch64/ape/ape.elf` vs `assets/loaders/ape-loader-aarch64` | 逐字节一致 (md5 `bed8d977…`) |
| 新 `busybox-fat.ape` 内嵌 aarch64 loader | LOAD Align `0x10000` 且 off≡vaddr (mod 64K) ✓ (`check-ape-64k.sh`) |
| 新 `busybox-arm64.ape` 内嵌 aarch64 loader | 同上 ✓ |
| 旧产物 (16K loader) 对照 | 精确报 ✗ Align 0x4000 / 不同余 (脚本判别力验证) |
| mac x86_64 直接 exec 母本 md5 | 恒定 (母本不改) ✓ |
| `./busybox` cache+assimilate 冒烟 | 44/46, 与基线一致 |
| release / min 打包 | 自检通过, zip 内 fat/arm64.ape 均为 64K 就绪产物 |

## 三·六、arm64 Linux 模拟实测 + 最小包重构 (2026-09-04, podman+qemu)

环境: mac x86_64 宿主 → podman machine (applehv) → `--arch arm64` 容器
(qemu 用户态模拟, PAGESIZE 4096)。真 64K 页内核未模拟 (qemu-user 不支持), 64K
就绪性由 phdr 静态校验 + 鲲鹏 UOS 历史实机基线 (45/46, 31/31) 覆盖。

| 验证 (arm64 容器内) | 结果 |
|---|---|
| `busybox-arm64-linux-elf` (裸 ELF) 直跑 | ✅ uname/echo/嵌套 exec; smoke 45/46 + deep 31/31 |
| fat/busybox.com 直接 exec (无 binfmt) | ✅ 顶层命令 (boot 提取内嵌 64K loader); smoke 1/46 (嵌套 exec 受限) |
| fat/busybox.com 内置 `--assimilate` | ❌ 产物头变 ELF 但 phdr 错乱不可加载 (cosmo 布局局限, x86_64 容器同验) |
| 外部 `assimilate` 工具 (cp 到可写区自举后) 处理 fat | ✅ 产物标准 ELF, LOAD Align `0x10000` 且同余 64K; smoke 45/46 + deep 31/31 |
| `sudo ./install-linux.sh` (特权容器) | ✅ 装 loader + binfmt FP enabled; 之后 busybox.com 直 exec smoke 45/46 |
| mac: fat 内置 `--assimilate` | ✅ 自同化 → Mach-O, smoke 44/46 (与 Linux 不同, mac dd 分支完整) |

结论 (最小包依据):
1. **assimilate 工具在 Linux 不可省** (APE 内置 --assimilate 仅 mac 有效)。
2. Linux 全功能两途: 外部 assimilate 工具 或 **binfmt (install-linux.sh, 2KB)** —
   故 min 包移出 656KB assimilate, 改用 install-linux.sh + ape-loader (~18KB)。
3. 新 min 包 (2026-09-04): busybox.com + busybox + install-linux.sh +
   ape-loader-{aarch64,x86_64} + README ≈ 3.7MB (原 4.37MB)。

历史产物 md5: `baseline/busybox-cosmo-release.zip` 内 `release/md5sums.txt`。

## 三·七、qemu 真 64K 内核模拟 + apelink 疏漏修复 (2026-09-04)

**环境**: macOS 本地 `qemu-system-aarch64` 11.1.1 全系统模拟, Ubuntu
`6.8.0-31-generic-64k` 内核 (真 64K 页: MemTotal 524288K / 8184 pages = 65536 B/页),
initramfs 以 busybox-arm64-linux-elf 为 init。**首次真 64K 页内核实测。**

**发现重大疏漏**: 工具链 `bin/apelink` 是官方 zip 预编译二进制, **未含 64K 补丁**
(patches 只改了 master 源码 tool/build/apelink.c ThirdPass pagesz=65536)。
结果: apelink 把 aarch64 载荷放 0x4000 (16K 对齐, 旧) → 真 64K 内核上 ape loader
按 AT_PAGESZ=64K 校验 `p_vaddr ≡ p_offset (mod 64K)` 失败, 报
"ELF p_vaddr incongruent w/ p_offset modulo AT_PAGESZ"。ELF 直跑 (offset 0) 不受影响。

| 验证 (真 64K 内核) | 结果 |
|---|---|
| master 重建 apelink (o/x86_64/tool/build/apelink) | 载荷落 0x10000/0x1b0000 (64K 对齐), phdr 全 64K 同余 ✓ |
| 新 busybox-fat.ape 直接 exec | ✅ fat-direct-exec-OK + 嵌套 sh OK (boot 提取内嵌 64K loader) |
| 新 busybox-aarch64.ape 直接 exec | ✅ 同上 |
| busybox-arm64-linux-elf 直跑 | ✅ (基线) |
| mac x86_64 回归 (同化 smoke) | 44/46, 与基线一致 |
| 旧产物对照 | ✗ 0x4000 载荷被 64K loader 拒绝 (qemu 实测复现根因) |

**修复**: build-custom.sh x86_64 targets 加 `tool/build/apelink`, 组装 3b'' 覆盖
`bin/apelink`; 全部正式产物用新 apelink 重打 (旧版备份 baseline/pre-apelink-fix/);
min/release 重新打包, check-ape-64k.sh 全绿。

**遗留**: 真 64K 内核上 loader 形态嵌套 exec 仍受限 (binfmt 未启用时, 普适现象);
binfmt_misc 注册需内核 CONFIG_BINFMT_MISC (本测试内核未含, 未在 64K 上验 binfmt 全功能)。

## 三·八、Apple Silicon 真机准备 (2026-09-04, 待真机)

非 arm64-mac 平台全部实测完毕。Apple Silicon (arm64 mac) 唯一未上真机, 本轮做
静态分析与发行准备:

| 项 | 发现/动作 |
|---|---|
| fat boot mac arm64 分支 | **无 `--assimilate` 分支** (仅 x86_64 有, cosmo 布局); 直接 exec 需 `cc` 编译 ape-m1.c |
| fat 内嵌内容 | 仅 Linux ELF loader + ape-m1.c 源码; **无 mac arm64 预编译 Mach-O loader** |
| 发行件 ape-loader-macos-arm64 | 标准 ape loader (Mach-O arm64, 54KB, 与 ape-m1.c 同源) — 放 ~/.ape-1.10 免 cc |
| bb.sh 修复 | mac arm64 不再走无效 --assimilate; 自动放置 ape-loader-macos-arm64 → ~/.ape-1.10; 有 assimilate 工具则优先 (完整 shell) |
| min 包 | 新增 ape-loader-macos-{arm64,x86_64}; 现 7 文件 ≈ 3.8MB |
| mac Intel 回归 | 44/46, 与基线一致 (改动无副作用) |
| **loader dash 模式实测 (mac Intel)** | `loader - RUN RUN args` (argv0=busybox 真实路径): 顶层 OK, smoke 1/46 — 嵌套 exec 二次 exec 仍受限 (cosmo 上游级), 与直接 exec 等价 |
| **PEN 修复 (cosmo libc, mac)** | KERN_PROCARGS2 在 loader 场景返回 loader 路径 → 加 OldApeLoader 检测回退 argv[0]; peprobe 实测 PEN=程序路径 ✓; 补丁权威更新 17 文件 clean apply; busybox 重建 mac Intel 44/46 无回归 |
| **loader 嵌套 exec 剩余问题** | ash STANDALONE 子命令 argv 错乱 (shellexec/ape-fwd 均未触发, 加调试无输出) — cosmo/busybox 深层, 需 Apple Silicon 真机专项 |
| **结论: 全功能必走 assimilate?** | 否: Linux = binfmt 或原生 ELF (免工具); mac Intel = 内置 --assimilate (免工具); mac arm64 = APE 无 Mach-O 布局, assimilate 也转不出 mac 原生 → **Rosetta x86_64 为全功能路径** |
| **待真机** | 按 docs/APPLE-SILICON-TEST.md 执行并回报 |

## 四、重建 vs 历史基线的差异说明

新构建产物 md5 与历史基线**不同属预期**, 原因:
1. 版本横幅含编译时刻 (未固定 epoch 时)。
2. 本工程**统一**两架构配置为最终验证版 (x86 40959/WIDE; 历史 arm64 树残留 767 旧配置)。
   功能超集, 非回退。
3. apelink/工具链同源 (拷入的就是历史最终定制工具链)。

如要与历史基线逐位一致: 对两架构用各自历史 `.config` + 相同 `SOURCE_DATE_EPOCH` 重建 (不推荐, 功能无增益)。
