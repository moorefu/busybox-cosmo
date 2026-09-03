# KNOWN-LIMITATIONS — 已知限制与遗留

## 功能限制

| 项 | 说明 | 状态 |
|---|---|---|
| `ps` 在 mac | 透传 `/bin/ps`; 沙箱禁止 exec 外部程序时报 Operation not permitted | 环境相关, 非缺陷 |
| `mkfifo` / `mknod` | cosmo 未实现 mknodat wrapper (Linux/mac 均 ENOSYS) | cosmo 上游缺口 |
| `sethostname`(hostname 写) | 已由工程补丁实现三平台等价物; mac/win 需 root/管理员 (非 root 得 EPERM, 读不受限) | cosmo-sethostname-extra.patch |
| `nproc` | cosmo 未实现 sched_getaffinity | cosmo 上游缺口 |
| 64KB 页 Linux aarch64 | 需用 `busybox-arm64-linux-elf` 或 64K loader + binfmt `FP`; 普通 APE 同化路径不可用 | 需 loader |
| mac Apple Silicon 原生 arm64 | 顶层命令可用; ash 嵌套 exec 受限 (APE 前缀 argv 语义) | cosmo 上游级 |
| Windows fork | CreateProcess+全内存复制, 较慢; cosmo issue #1174 (accept 场景 socket 继承) 部分未根治 | connect 实测无碍 |
| fat.ape 在 4K/16K 页 aarch64 实机 | 本机 (mac x86_64) 只能验证合成, 无法实测两架构同机 | 待真机 |
| QuickEdit 鼠标补丁 | tcsetattr 定制已打入工具链 | 需 Windows 最终确认 |
| APE 同化 | 首跑改写自身为平台格式; 分发必须 zip 母本 | 设计使然, 测试纪律 |
| `zcat` | busybox 本义为 .Z 解压器; 解 gzip 用 `gzip -dc` | 用法说明 |

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
