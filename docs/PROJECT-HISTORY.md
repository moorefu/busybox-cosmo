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
