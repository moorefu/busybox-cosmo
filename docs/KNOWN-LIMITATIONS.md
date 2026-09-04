# KNOWN-LIMITATIONS — 已知限制与遗留

## 功能限制

| 项 | 说明 | 状态 |
|---|---|---|
| `ps` 在 mac | 透传 `/bin/ps`; 沙箱禁止 exec 外部程序时报 Operation not permitted | 环境相关, 非缺陷 |
| `mkfifo` / `mknod` | cosmo 未实现 mknodat wrapper (Linux/mac 均 ENOSYS) | cosmo 上游缺口 |
| `sethostname`(hostname 写) | 已由工程补丁实现三平台等价物; mac/win 需 root/管理员 (非 root 得 EPERM, 读不受限) | cosmo-sethostname-extra.patch |
| `nproc` | cosmo 未实现 sched_getaffinity | cosmo 上游缺口 |
| 64KB 页 Linux aarch64 | 三环修复: ①loader 64K 对齐 (master 重建 ape-aarch64.elf) ②apelink 二进制重建 (官方 zip 未含补丁, 载荷曾放 0x4000 被 64K loader 拒) ③fat 内嵌 loader。另有 `busybox-arm64-linux-elf` 免 loader 直跑。qemu 真 64K 内核 (generic-64k) 实测: ELF/fat/单架构直接 exec 全 OK | ✅ 2026-09-04 (qemu 真 64K 内核模拟) |
| APE 内置 `--assimilate` 仅 mac 有效 | Linux 上产物坏 ELF (cosmopolitan 布局局限: 只 printf ELF 头不重定位 phdr); Linux 转原生须外部 `assimilate` 工具或 binfmt (qemu 实测 2026-09-04) | cosmo 上游级, 已文档化 |
| Linux loader 形态嵌套 exec 受限 | 无 binfmt 时直接 exec APE 走内嵌 loader; 顶层命令可用, ash 嵌套 exec 受限 (qemu arm64/x86 实测 smoke 1/46) | 需 binfmt/ELF/工具 |
| mac Apple Silicon 原生 arm64 | 顶层与嵌套 exec 曾 0/155 FAIL: 根因是 **apelink 在 shell ELF 头硬编码 e_flags=0**, mac m1 loader TryElf 视作非 APE-modern 而把 argv[0] 改写为 exe 路径 (applet 名丢失)。**已自建补丁修复**: `patches/cosmo/cosmo-apelink-apeflags-extra.patch` (shell ELF 头保留载荷 e_flags=EF_APE_MODERN), x86_64 mac loader 同源逻辑代理实测 D2/D3 + deep-test/smoke-full 全 OK | ✅ 自建补丁 (2026-09-04); macos-15 arm64 CI 真机复验 |
| Windows fork | CreateProcess+全内存复制, 较慢; cosmo issue #1174 (accept 场景 socket 继承) 部分未根治 | connect 实测无碍 |
| fat.ape 在 4K/16K 页 aarch64 真机 | qemu-system-aarch64 全系统 (4K 与 64K 内核) 已实测直接 exec + 嵌套 exec; 真机 (鲲鹏 UOS 4K/16K) 仍建议最终冒烟 | 模拟已覆盖, 真机待补 |
| QuickEdit 鼠标补丁 | tcsetattr 定制已打入工具链 | 需 Windows 最终确认 |
| APE 同化 | 首跑改写自身为平台格式; 分发必须 zip 母本 | 设计使然, 测试纪律 |
| `zcat` | busybox 本义为 .Z 解压器; 解 gzip 用 `gzip -dc` | 用法说明 |
| Windows exec argv 含 `\`+`"` 序列 | cosmo Windows 由 argv 重建 CreateProcess 命令行时, 参数内「反斜杠紧跟双引号」曾错乱 (`x\"y` → `x"\y`), 使 `awk "{...\"...\"}"` 等传参失败。**已自建补丁修复**: `patches/cosmo/cosmo-mkntcmdline-roundtrip-extra.patch` (mkntcmdline 遇引号前反斜杠先行双写), 真实二进制 round-trip 全组合验证一致 | ✅ 自建补丁 (2026-09-04); 测试用例保留 heredoc/-v 规避写法 (deep-test/smoke-full) 作跨平台基线 |

## 结构约束

- APE 静态链接, 无 dlopen 扩展 — 对 busybox 无影响。
- 信号/权限/用户模型在 Windows 上为模拟 (busybox-w32 同款问题)。
- Windows 设备文件 (/dev/null 等) 不能传给外部 Windows 程序。

## 上游 issue 草稿 (待提交)

- cosmopolitan: Windows fork accept 场景 socket 继承 (#1174 部分修复, 已跟进)。
- cosmopolitan apeinstall: `P` flag 注册应支持 <5.12 内核 (见 `patches/cosmo/issue-apeinstall-P-flag-old-kernel.md`)。
- cosmopolitan: mknodat / sched_getaffinity 缺失。

## 测试差异说明 (2026-09-03 实机记录)

- 冒烟 46 项含 2 项 `[win]` 专属 (路径映射 /c/Windows), 其他平台为预期 FAIL。
- `ps` 项在 mac 依赖 exec 系统 /bin/ps 的沙箱许可; 本次 mac 沙箱内 44/46 与基线行为一致。
