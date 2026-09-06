# PROJECT-HISTORY — 项目来龙去脉 (2026-08 ~ 2026-09)

> 本工程不是从零开始: 它固化了一段真实的跨平台移植研究 (于 `/Users/moore/Projects/busybox`
> 下的 cosmo-dist 迭代完成)。本文还原决策过程, 便于后人理解为何补丁长这样。

## 一、目标

单一可执行文件, 原生运行于 **Windows / Linux / macOS × amd64 / arm64**:
- Windows 也要有可用 shell (ash)、wget https、ps、中文支持;
- 64KB 页内核 (UOS/麒麟鲲鹏 aarch64) 也要能用。

## 二、选型历程 (四路线)

| 路线 | 结论 | 依据 |
|---|---|---|
| A. busybox + cosmocc | ✅ 采用 | 实证跑通; 有 ash; 补丁可控 (本文档基线) |
| B. toybox + superconfigure | 备选 | 配方现成但无 shell, 功能差一档 |
| C. busybox-w32 (MinGW) | 参考 | fork 用 2500 行状态序列化最脆弱 (issue #604); 其避坑清单全库借鉴 |
| D. armybox(Rust)+cargo_cosmo | 观察 | armybox mac 编译失败; cargo_cosmo 过新; 常量 shim 覆盖不全 |

## 三、关键战役时间线 (2026-09-03 实机)

1. **wget https 报 Socket error** — openssl helper `child_failed` 依赖 vfork 共享内存, cosmo
   Windows 上 vfork≈fork 不共享 → 父进程误判。修: cosmo 下跳过 helper 走 internal TLS。
2. **ash 内 applet not found / 管道 exec 错乱** — Windows 无符号链接 farm、`/proc/self/exe`
   不可 exec; vfork-nt 与 ash 交互缺陷。修: STANDALONE+PREFER_APPLETS 配置 +
   `get_busybox_exec_path()` 运行时解析 + cosmo 下 vforkexec→fork。
3. **tar czf 失败** — 压缩子进程 `execlp("gzip")` 找不到。修: execv 自身 gzip applet。
4. **ps 不可用** — cosmo 无 /proc。修: Windows=Toolhelp / Linux=/proc / mac=透传 /bin/ps。
5. **ls 中文变 `?`** — LAST_SUPPORTED_WCHAR=767。修: 40959 + WIDE_WCHARS。
6. **64KB 页内核 aarch64** — 三层缺陷: ape loader 自身 64K 对齐 / apelink 嵌入 16K 假设 /
   binfmt 无 P flag 剥 argv0。逐层修复 (本工程 assets/loaders + patches/cosmo 64K 布局)。
7. **mac 嵌套 exec 不可靠** — `__program_executable_name` 无 mac 分支。修: KERN_PROCARGS2 sysctl
   (工具链定制)。

## 四、验证成绩 (历史, 2026-09-03 实机)

| 平台 | smoke | deep | 说明 |
|---|---|---|---|
| Windows x86_64 | 46/46 | — | 含 ps/dev/zero/Unicode/鼠标 |
| Linux x86_64 (podman) | 45/46 | 31/31 | `[win]` 项平台预期 |
| Linux aarch64 64K 页 (鲲鹏 UOS) | 45/46 | 31/31 | ELF 与 APE+loader 双路径 |
| macOS (Intel) | 45/46 | — | 嵌套 exec 修复 |

## 五、本工程 (busybox-cosmo) 的固化工作

- 把散落的补丁/配置/脚本/文档收拢为**可复现工程**;
- busybox 官方 tarball sha256 锁定 (`34f9ea6f…`), 脚本取源;
- 工具链 provision 化 (copy/download/build 三模式);
- 统一两架构为最终验证配置 (40959/WIDE); 修复 prepare 脚本的 patch 误判坑;
- `SOURCE_DATE_EPOCH` 支持逐位可复现构建;
- 重建产物与历史基线逐对象字节一致 (仅版本横幅时刻不同, 见 VERIFICATION-MATRIX)。

## 六、第二期 (2026-09-03): 定制工具链"从官方源码构建"

一期交付"拷入已验工具链"。二期补上**官方源码构建入口**, 使工具链本身可复现:

- `toolchain/fetch-sources.sh` — 下载官方 cosmopolitan@`3293fad0` 源码与官方 cosmocc-3.9.2
  (sha256 锁定; cosmocc sha 与上游 master Makefile 内 pin 一致)。
- 逆向提取权威源码差异 → `patches/cosmo/cosmo-custom-full.patch` (17 文件, `patch -p1` 直接可用;
  覆盖形态仍保留在 `master-snapshot/`)。
- `toolchain/build-custom.sh` — 官方基座自举 make → 双架构 cosmopolitan.a + crt/ape →
  组装(基座+master 产物/头+64K 包装脚本) → 与已验参考代码级 verify。
- 实测: 双架构从零构建成功; libcosmo.a 5250/5252 成员与参考 strip-debug 后代码全一致;
  用新工具链重建 busybox x86_64+aarch64+fat 0 错误, 冒烟 44/46 与基线一致。


## 七、驱动基座升级 cosmocc 3.9.2 → 4.0.2 (2026-09-03)

工具链的**编译驱动层**换用官方 cosmocc v4.0.2(sha `85b8c37a…`, COSMOCC_VER 参数化)。
master libc 仍从官方源码构建(不受驱动影响——实测双架构 libcosmo.a 与 3.9.2 驱动构建
strip-debug 代码逐成员一致); 驱动脚本/GCC/binutils/apelink 为 4.0.2。
验证: 组装后 cosmocross = 4.0.2 基座 + 64K 变换逐字节一致; busybox 重建 + 双冒烟无回归。

## 八、fat 单文件支持 64K 页内核: 内嵌 loader 换 64K 版 (2026-09-04)

**问题**: fat.ape / busybox-aarch64.ape 直接 exec (无 binfmt) 时, 前端 sh 引导把
**内嵌** loader 提取到 `~/.ape-1.10` 再运行。但此前 apelink `-l` 嵌入的是官方
`ape-aarch64.elf` —— **16K 页对齐** (phdr Align 0x4000, vaddr/offset 不同余 64K),
64K 页内核 (鲲鹏 UOS/麒麟) 拒载。当时 64K 验证能过, 是因为走的是**单独安装**的
`ape-loader-aarch64` (64K 版) + binfmt, fat 自身仍未就绪 —— "fat 单文件 64K" 缺口。

**修复链路** (本阶段):
1. 定位: master 源码树 `ape/BUILD.mk` 的 loader 链接已被补丁改成
   `max-page-size=0x10000`, 但 build-custom.sh 从未重建 loader, 工具链
   `bin/ape-aarch64.elf` 仍是基座官方 16K 版。
2. 增量构建 `o/aarch64/ape/ape.elf` → 与 `assets/loaders/ape-loader-aarch64`
   **逐字节一致** (md5 `bed8d977…`) —— 证明 assets 64K loader 就是补丁后 master 产物。
3. build-custom.sh: aarch64 build_one 目标加 `ape/ape.elf`; assemble 3b' 把它装入
   `bin/ape-aarch64.elf`; verify 新增 3f' 段 (LOAD Align ≥ 0x10000 且同余 64K) 防回归。
4. 重打 `busybox-fat.ape` / `busybox-aarch64.ape`: 内嵌 aarch64 loader 现为 64K 版
   (解内嵌 ELF 实测 phdr Align 0x10000、vaddr≡offset)。
5. 新增 `scripts/check-ape-64k.sh`: 解出 APE 内嵌各架构 loader, 逐 LOAD 校验 64K
   对齐与同余; build-ape.sh / package-release.sh 合成 fat 后自动调用。
6. 回归: mac x86_64 直接 exec + `./busybox` cache+assimilate 冒烟 44/46, 与基线一致;
   x86 loader 保持官方 64K 版未动。

**现在**: `busybox-fat.ape` 单文件即满足 64K aarch64 "经 loader 运行"的全部前置;
免 loader 最简仍是 `busybox-arm64-linux-elf` 直跑。

## 九、最小包 + "不用 assimilate?" 实测结论 (2026-09-04)

**问题**: 最小发行包能否砍掉 656KB 的 assimilate 工具, 让 fat APE 自己同化?
以及 64K/arm64 支持到底需要带什么。

**实测 (podman applehv VM + `--arch arm64` qemu 容器, PAGESIZE 4096)**:
1. fat/busybox.com **直接 exec** (无 binfmt): 前端 boot 提取内嵌 loader → 顶层命令
   可用; 但 loader 形态嵌套 exec 受限 (smoke 1/46) — 与页大小无关的普适现象。
2. fat/busybox.com 内置 **`--assimilate`**: mac 有效 (dd 分支搬完整 Mach-O 头 →
   44/46); **Linux 无效** (printf 分支只写 64B ELF 头不重定位 phdr, 产物坏 ELF,
   x86_64 容器同验) — cosmopolitan 上游布局局限, 非本工程可改。
3. **外部 assimilate 工具** (cp 到可写区自举后) 处理 fat: 产物标准 ELF,
   LOAD Align 0x10000 且同余 64K (64K 内核就绪), smoke 45/46 + deep 31/31。
4. **`install-linux.sh` (特权容器实测)**: 装 64K loader + binfmt FP enabled →
   busybox.com 直接 exec 即全功能, smoke 45/46。
5. `busybox-arm64-linux-elf` 裸 ELF 直跑: smoke 45/46 + deep 31/31 (零依赖)。

**结论 → 最小包重构** (dist/busybox-min.zip, 4→6 文件但总 4.37→3.72MB):
- **assimilate 移出 min** (Linux 全功能改走 binfmt: install-linux.sh 2KB +
  ape-loader ~18KB, 远小于 656KB 工具)。
- min = busybox.com (fat) + busybox (launcher) + install-linux.sh + ape-loader-{aarch64,x86_64} + README。
- launcher 策略: mac 内置 --assimilate (免工具); Linux 有工具用工具、无工具退
  loader 形态并在首跑给提示 (指向 install-linux.sh); 64K Linux 优先 ELF。
- bb.sh 修复: pick_master 的 64K ELF 分支移到循环前 (原在兜底后永不执行);
  同化产物加 magic 校验 (防 Linux 坏 ELF 落 cache)。

**遗留**: 64K 页内核 (真机) 仍建议鲲鹏 UOS 上跑 check-ape-64k.sh + 冒烟收尾;
本机 qemu-user 无法模拟 64K 页 (见 KNOWN-LIMITATIONS)。

## 十、真 64K 内核模拟: apelink 未含补丁的疏漏 (2026-09-04)

**动机**: 用户提示本地 qemu 已装。用 qemu-system-aarch64 + Ubuntu generic-64k 内核
(真 64K 页) 做全系统模拟 — 首次在真 64K 内核验证 fat 单文件。

**发现**: 此前 64K 修复只改了 master 源码 (tool/build/apelink.c ThirdPass
pagesz 16384→65536), 但工具链 bin/apelink 是官方 zip 预编译二进制, 从未重建。
实测: 官方 apelink 组装的 APE, aarch64 载荷放 0x4000 (16K 对齐), 真 64K 内核上
loader 按 AT_PAGESZ 校验不同余 → "ELF p_vaddr incongruent w/ p_offset" 拒绝。
ELF 版 (offset 0) 与单独 64K loader 不受影响 — 此前静态校验查的是"载荷 phdr 对齐"
与"loader 对齐", 漏了"apelink 放置载荷的文件偏移须 64K 对齐"这一环。

**修复**: 从 master 重建 apelink (x86_64 targets 加 tool/build/apelink + 组装 3b''
覆盖 bin/apelink); 重打全部 APE; aarch64 载荷落 0x10000 (单架构) / 0x1b0000
(fat), 64K 同余; qemu 真 64K 内核直接 exec fat 通过。旧产物备份
baseline/pre-apelink-fix/。

**附带**: install-linux.sh 合并进 busybox launcher (`./busybox --setup-linux`),
min 包 5 文件 (busybox.com + busybox + ape-loader×2 + README), arm64 特权容器实测
注册后 smoke 45/46。

## 十一、Apple Silicon 真机准备: bb.sh mac arm64 修复 (2026-09-04)

全部非 arm64-mac 平台实测完毕, Apple Silicon 是最后一块。静态分析 boot 发现:

1. **fat 内置 `--assimilate` 无 mac arm64 分支** (cosmopolitan boot 布局: mac 分支
   只处理 x86_64 dd Mach-O 头; arm64 走"cc 编译 ape-m1.c") — bb.sh 原先把 mac
   当统一路径会让 Apple Silicon 静默失败。
2. fat 内嵌仅 Linux ELF loader + ape-m1.c 源码; 无 mac arm64 预编译 Mach-O loader。
3. 发行件 `ape-loader-macos-arm64` (Mach-O arm64, 与 ape-m1.c 同源) 放 ~/.ape-1.10
   即可让 boot 命中缓存 loader, **免 cc / xcode CLT**。

修复: bb.sh 平台×架构策略 — mac x86_64 走自同化; mac arm64 自动放置
ape-loader-macos-arm64 → ~/.ape-1.10 (有外部 assimilate 工具则优先, 得完整 shell);
mac arm64 loader 形态提示。min 包加 ape-loader-macos-{arm64,x86_64} (7 文件 ≈ 3.8MB)。
mac Intel 回归 44/46 无副作用。真机验证清单见 docs/APPLE-SILICON-TEST.md。


## 十二、"加了 loader 能全功能吗?" — 深挖与 PEN 修复 (2026-09-04)

追问 mac Apple Silicon 加 loader 能否全功能。深挖 + mac Intel 实测, 定位两层问题:

**第一层: `__program_executable_name` 错误 (已修复, cosmo libc)**
- cosmo mac 分支用 KERN_PROCARGS2 取 exec 链首进程路径; 经 ape loader 加载时返回
  loader (~/.ape-1.10) 而非程序路径 → busybox STANDALONE exec 自身 = exec loader → 死结。
- 修复: mac 分支加 OldApeLoader 检测 (与 Linux/FreeBSD 分支同逻辑), 检测到 loader
  回退 argv[0] (loader 保留其为程序路径)。peprobe 实测: PEN 从 loader 路径 →
  正确程序路径。补丁已权威更新 (17 文件全 clean apply, 产物与 master 源码逐字节一致)。
- busybox 重建 + mac Intel 回归 44/46 无副作用。

**第二层: ash STANDALONE 子命令 argv 错乱 (未修复, 深层)**
- 即使 PEN 正确, ash 内 exec cat/grep 等 applet 仍错位 ("x.txt: applet not found"
  而非执行 cat)。shellexec/exec_ape_via_loader 均未触发 (加调试无输出), 指向
  ash 的 applet 分发 (PREFER_APPLETS/NOEXEC/argv 语义) 与 loader argv 交互问题。
- 需 Apple Silicon 真机专项调试; mac Intel loader 形态 smoke 1/46 佐证。

**结论**: mac 全功能 = 原生 Mach-O (Intel 自同化 44/46); Apple Silicon 无 arm64
Mach-O 原生 (cosmo 不产), 务实走 Rosetta x86_64。PEN 修复是净改进但不解锁 loader
嵌套全功能。真机验证清单见 docs/APPLE-SILICON-TEST.md。
