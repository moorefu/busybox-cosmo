# CI 真机证据与任务设计

本文把现有 GitHub Actions 矩阵转成可复核的平台证据采集方案。目标不是把一次任务“跑绿”当作兼容性结论，而是为每个待定问题保存宿主、产物、命令和结果，稳定后再把报告项提升为发布门禁。

## 现有 runner 能验证什么

| runner | 可直接取得的信息 | 当前定位 |
|---|---|---|
| `ubuntu-24.04` | x86_64、Linux loader、工具链构建、静态 64K 检查 | 稳定阻断门禁 |
| `ubuntu-24.04-arm` | 原生 aarch64、真实 CPU 指令与页大小 | 稳定阻断门禁；ARM 标签仍需关注预览状态 |
| `macos-15-intel` | macOS x86_64、BSD termios、x86 APE 启动 | 稳定矩阵；需关注托管标签变化 |
| `macos-15` | Apple Silicon arm64、macOS termios、arm64 loader | 先报告，基线稳定后再阻断 |
| `windows-2022` | Windows x86_64 APE、路径/环境变量/进程行为 | 稳定矩阵 |
| `windows-11-arm` | Windows ARM64 仿真路径及环境差异 | 实验矩阵，不等同于原生 ARM BusyBox |

每次任务应保存 `uname`/Windows 版本、CPU 特性、实际架构、产物 `file` 信息和 SHA256。ARM runner 与部分 macOS runner 的服务级别/预览状态可能变化，不能只凭 YAML 标签宣称长期可用。

## 已接入的证据任务

`.github/workflows/ci.yml` 现在会：

1. 脚本检查阶段编译 `tests/ci-platform-probe.py`，避免探针本身语法损坏。
2. 工具链冷构建后执行一次带源码参考树的 `build-custom.sh verify`；缓存命中仍保留入口和产物检查。
3. Unix 真机在深度/完整测试前采集宿主信息，并运行 `tests/ci-platform-probe.py`。探针当前是“报告、不阻断”，输出作为后续 C/D/F/B 的基线。
4. Unix/Windows 无论测试成功还是失败都上传宿主信息、产物摘要和测试日志；测试不再因日志清理而丢失原始返回值。
5. 构建任务上传工具链、提交、固定时间戳和发布物摘要，便于区分旧缓存与新构建。

探针包含四类最小证据：

- `argv-256`：通过 ash 再次 exec 同一 APE，确认 256 个参数没有在 loader 边界被截断。
- `termios erase`：在独立 PTY 上分别由 BusyBox 和宿主 `stty` 写入，再由对方读取，能直接暴露 `c_cc` 槽位错位。
- `tar-xz`：有宿主 xz 时验证非空归档和独立解压；将 PATH 隔离到无 xz 目录时必须返回失败，防止误把 BusyBox 的仅解码 applet 当编码器。
- 宿主/产物摘要：记录 runner 标签、架构、CPU/OS、`file` 和 SHA256，作为 SIGILL、loader、缓存问题的归因材料。

## 待提升为门禁的任务

### P0：每次提交阻断

- full/min 包解压后摘要校验、零安装与安装后各跑一次。
- tar gzip/bzip2 往返、外部 xz 往返、缺 xz 的准确非零返回。
- 静态 APE/loader 64K 检查和坏样本拒绝。
- `bb_argv0` 配置开关（含 `NUM_SCRIPTS=0`）以及 0/1/63/64/65/256 参数。
- 测试框架的负向自检：故意改错断言、让生产者失败、删除 applet 时必须失败或明确 SKIP。

### P1：每次提交采证，基线稳定后阻断

- Linux/macOS PTY 上的 intr/erase/kill/eof/start/stop/min/time 读写和恢复；无 PTY 时标基础设施缺失，不能记 PASS。
- dd/shuf 最小复现，记录 CPU 特性、启动形态、信号/返回值、产物摘要；新鲜构建仍 SIGILL 时阻断对应平台。
- 本地回环 httpd/ftpd/inetd/ssl_server，保存非空响应及系统工具交叉校验；未编译 applet 仅记能力缺项。
- 冷缓存并发启动、损坏缓存、只读发布目录、带空格/中文/引号路径。

### Nightly/手动：昂贵或依赖虚拟化

- `tests/qemu-64k-test.sh --full`：来宾直接断言页大小 65536，宿主等待明确完成标记并设置超时。
- 两个独立目录使用同一 `SOURCE_DATE_EPOCH` 构建，比较 full/min zip SHA256 和文件清单。
- 锁定源码、cosmo 补丁和工具链版本升级演练；缓存命中后仍检查 manifest。

## 证据转门禁的规则

一个平台只有在连续两次新鲜构建中通过同一用例、日志包含真实断言、没有未解释的 SKIP/SOFT，才可从“报告”提升为“阻断”。实验 runner 的失败不能被 `continue-on-error` 伪装成支持结论；应在发布说明中标记为实验或仿真。所有失败工件保留至少 14 天，并以用例 ID、runner、commit、产物 SHA256 关联。

