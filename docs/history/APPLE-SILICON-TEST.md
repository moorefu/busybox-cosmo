# APPLE-SILICON-TEST — Apple Silicon 真机验证清单 (待真机)

> 状态: 2026-09-04 所有非 Apple Silicon 平台已实测 (mac Intel / Linux x86 / Linux
> arm64 4K / Linux aarch64 真 64K 页内核 qemu 全系统)。Apple Silicon 原生 arm64 是
> 唯一未上真机的维度。本文档 = 上真机后照此执行、照此回报。

## 〇、重要结论 (2026-09-04 静态分析 + mac Intel 实测外推)

**"全功能是否必须 assimilate" — 分平台答案:**

| 平台 | 全功能路径 | 需要外部 assimilate? |
|---|---|---|
| Linux (任意) | binfmt (`--setup-linux`) 或原生 ELF (`busybox-arm64-linux-elf`) | ❌ 不需要 |
| mac Intel | busybox.com 内置 `--assimilate` → 原生 Mach-O (实测 44/46) | ❌ 不需要 |
| mac Apple Silicon | **目前无免 loader 原生路径**: APE 无 Mach-O arm64 布局 (assimilate 源码明言 arm64 只能转 ELF, mac 不跑 ELF); loader 形态嵌套 exec 受限 | ⚠️ assimilate 也救不了 (转不出 mac 原生); **务实 = Rosetta 跑 x86_64** |

**为什么 loader 形态不够 — 两层独立问题 (2026-09-04 深挖):**
1. **`__program_executable_name` 错误 (已修复)**: cosmo libc mac 分支用
   KERN_PROCARGS2 取 exec 链首进程路径, loader 场景返回 loader (~/.ape-1.10)
   而非 busybox。补丁增加 OldApeLoader 检测后回退 argv[0] (与 Linux/BSD 同逻辑)。
   已验证: 修复后 loader 形态顶层 + 路径解析正确 (peprobe 实测 PEN=程序路径)。
2. **ash STANDALONE 子命令 argv 错乱 (未修复, cosmo/busybox 深层)**: 即使
   __program_executable_name 正确, ash 内 exec cat/grep 等 applet 时 argv 仍错位
   (报 "x.txt: applet not found" 而非执行 cat)。涉及 ash 的 applet 分发与 loader
   argv 语义交互, 需 Apple Silicon 真机专项调试。
3. **结论**: mac 上全功能 = 原生 Mach-O 副本; Apple Silicon 造不出 arm64 Mach-O
   原生 (cosmo 不产), 走 Rosetta x86_64。PEN 修复是净改进 (loader 形态更健壮),
   但不足以单独解锁 loader 嵌套全功能。

## 一、先决条件

- Apple Silicon Mac (M1/M2/M3/M4), macOS 14+; **无需 Xcode CLT** (发行件带预编译
  loader; 顶层命令可用)。
- 拷贝 `dist/busybox-min.zip` 与 `dist/busybox-cosmo-release.zip` 到真机解压。

## 二、验证矩阵 (照抄结果回报)

```sh
uname -m   # 期望 arm64
```

| # | 步骤 | 期望 | 实测 |
|---|---|---|---|
| 1 | `./busybox echo hi` (min 包, 顶层) | `hi` | |
| 2 | `./busybox uname -m` | `arm64` | |
| 3 | `./busybox sh -c 'echo nested'` (嵌套) | `nested` (可能受限, 见下) | |
| 4 | `./busybox mkdir -p /tmp/bbT && echo x > /tmp/bbT/f && cp /tmp/bbT/f /tmp/bbT/g && cmp /tmp/bbT/f /tmp/bbT/g && rm -rf /tmp/bbT` | 静默成功 (rc=0) | |
| 5 | 文件系统是否被改: 记录 `busybox.com` md5, 跑几步后再 md5 | **不变** (母本 pristine) | |
| 6 | min 包同目录 `./busybox sh smoke.sh` (若拷入) | 见 smoke 基线 | |
| 7 | `~/.ape-1.10` 是否生成 (loader 缓存) | 存在且为 Mach-O arm64 | |

## 三、预期行为 (来自 boot 静态分析 + 其他平台外推)

### min 包 (fat = busybox.com)

| 路径 | 机制 | 预期 |
|---|---|---|
| 直接 exec busybox.com | boot 找系统 ape → 找 ~/.ape-1.10 → 无则需 cc | **需预置 loader 或 cc** |
| `./busybox` (launcher) | bb.sh 自动把 ape-loader-macos-arm64 → ~/.ape-1.10, 然后 exec 副本 | ✅ 顶层命令可用 |
| ash 嵌套 exec | loader 形态 (cosmopolitan 普适) | ⚠️ 可能受限 (顶层 OK) |

> **已知 (cosmo boot 布局)**: fat 内置 `--assimilate` **无 mac arm64 分支**
> (仅 x86_64 有) — 所以 mac arm64 **不能**像 mac Intel 那样一键自同化;
> bb.sh 已改为自动放置预编译 `ape-loader-macos-arm64` 到 `~/.ape-1.10` 免 cc。

### 完整包 (含 assimilate 工具)

| 路径 | 预期 |
|---|---|
| `./busybox` (bb.sh 找到同目录 assimilate) | assimilate 在 mac 上默认转 Mach-O; **arm64 因 APE 无 Mach-O 布局会报错并提示 -ae (转 ELF, mac 不跑)** → 实际走 loader 形态 |
| 直接 exec busybox-aarch64.ape | boot 找系统 ape → ~/.ape-1.10 → 无则需 cc |
| **Rosetta x86_64 (推荐全功能路径)** | `arch -x86_64 ./busybox` → x86_64 载荷 + 内置 --assimilate → Mach-O x86_64 → **44/46 全功能** (与 mac Intel 同) |

### Rosetta 对照 (推荐必测, 用于区分"arm64 原生问题" vs "cosmo 普适限制")

```sh
arch -x86_64 ./busybox sh smoke.sh   # min 包 busybox.com 的 x86_64 载荷经 Rosetta
```
期望: 与 mac Intel 基线一致 (~44/46, 2 项 [win] 平台项)。

## 四、smoke 基线对照

| 平台 | 期望 smoke | 说明 |
|---|---|---|
| mac Intel (已实测) | 44/46 | 2 FAIL = `[win]` 项 (平台预期) |
| mac arm64 原生 arm64 形态 (待真机) | 顶层多, 嵌套组 FAIL | loader 形态普适限制 (busybox exec_ape_via_loader 转发仍受限, mac Intel 1/46 佐证) |
| mac arm64 via Rosetta x86_64 | 44/46 | **推荐的全功能对照基线** |

> 注意: `ps` 项在 mac 依赖 exec /bin/ps; 受限沙箱/无许可环境会
> "Operation not permitted" (环境相关, 非缺陷 — 见 KNOWN-LIMITATIONS)。

## 五、真机回报格式 (建议)

请回报:
1. `uname -m` 与 macOS 版本;
2. 上表 1-7 逐项结果;
3. `./busybox sh smoke.sh` 的最后汇总行 (若拷入 smoke.sh);
4. `file ~/.ape-1.10` 输出;
5. 若嵌套 exec 受限, 记录 `./busybox sh -c 'echo ok'` 的确切报错;
6. Rosetta 对照结果。

## 六、若发现问题: 预期分支点

- **直接 exec busybox.com 报 "please run: xcode-select --install"** → 属预期
  (boot 无预置 loader 时的提示); 用 `./busybox` 而非直接 exec。
- **./busybox 顶层 OK 但嵌套 exec FAIL** → loader 形态普适限制 (cosmo 上游级),
  非 arm64 特有; mac Intel loader 形态同样 1/46。
- **全功能首选**: Rosetta (`arch -x86_64 ./busybox`), 与 mac Intel 等价 44/46。
- **bb.sh 的 loader '-' 模式尝试**: bb.sh 对 loader 形态会用
  `ape-loader - RUN RUN args` (argv0=busybox 真实路径, 类 binfmt P flag) ——
  mac Intel 实测仍 1/46 (嵌套 exec 链二次 exec 受限), 保留此路径供真机复验;
  若真机 arm64 意外可用则更优, 否则以 Rosetta 为准。
- **回报重点**: 顶层 vs 嵌套的分界、`~/.ape-1.10` 形态、Rosetta 对照、直接 exec
  busybox.com 的报错原文。
