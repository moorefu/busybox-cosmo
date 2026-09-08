# 已知限制

本页只列当前使用边界；修复过程及过往 CI 数字放在[历史记录](history/README.md)。“已编译”“测试通过”“所有场景可用”是不同结论。

| 能力 | 边界与建议 |
|---|---|
| ash 基础脚本 | 优先包内 ash、明确参数引号和退出码。新增契约覆盖引用、管道、exec、argv、wait 等，但不是 POSIX 完整认证 |
| stty / raw TUI | BusyBox `stty` applet 的 termios 编译期索引仍有跨平台布局风险，不作为 TUI 原始模式路径；TUI 原始模式改由专用 `bbtty`（`size/save/raw/restore`，Unix 令牌绑定终端、真实 PTY 契约 + trap 恢复已验）。Windows 传统 Console 驱动已测，**ConPTY 会话创建仍待实机验证** |
| HTTPS wget | 内置 TLS 不等于证书可信校验，wget 路径不作为可信下载后端；可信下载由伴生 `curl.com` + 固定 `cacert.pem` 提供（`bbp_https_get` 以首参数 `--disable` 屏蔽用户 `.curlrc` 隐式配置，强制 `https://`+证书校验+`--proto-redir`，本地 TLS KAT 直接驱动该包装器并覆盖 `.curlrc` 含 `insecure` 的回归，与实网拉取均已验） |
| xz / lzma / zip / zstd 创建 | 内置 xz、lzma、unzip 只承诺解码。编码器现以**可选伴生 APE** 提供：xz/zip/zstd 固定源码自建于 `dist/tools/*.com`（busybox-archive 分层包），兼容层 bundled 优先、宿主 PATH 兜底并做往返验证；不把第三方揉进 BusyBox 单体的边界不变 |
| Unicode | 配置支持部分宽字符，但不是完整 Unicode 字形/宽度引擎；组合字符、emoji 和超过 U+9FFF 的清洗/宽度路径不能承诺一致。原始字节输出与终端排版是两回事 |
| mac ps | 透传系统 `/bin/ps`，选项、输出及沙箱权限不同；脚本不要解析它作为跨平台进程协议 |
| 按名称找进程 | `pgrep -f` 依赖 `/proc`，Linux 经行为探测后可用，macOS/Windows 报告 `unsupported`；`pidof` 的结果还受宿主进程名影响，不纳入通用能力。跨平台脚本应保存 `$!` 并用 `bbp_pid_alive` |
| Windows 进程/网络 | fork 成本高，fork 后 socket 继承、服务器 accept 路径仍需验证；不能由客户端 connect 成功推断服务器可用 |
| 权限/信号/特殊文件 | Windows 权限与信号模型不是 POSIX；mkfifo/mknod 等不属于可移植基线。用户名、CPU 数和 PID 存活只通过兼容层接口使用 |
| 单调时钟 | 锁定 Cosmopolitan 的 `clock_gettime(CLOCK_MONOTONIC)` 在当前 macOS x86_64 会触发 SIGILL，并影响 dd、shuf 等 applet；BusyBox 配置使用 `gettimeofday` 后备。系统时间跳变可能影响长时间测量，升级 libc 后应恢复单调时钟并重测 |
| 启动与缓存 | loader 的名字、argv 布局及用户目录约定属于 ABI 依赖；只复制二进制、不带匹配 loader 可能改变行为 |
| ARM64 | Linux/macOS 有 ARM64 载荷；Windows ARM64 是 x86_64 仿真。macOS ARM64 与 Windows ARM64 CI 仍非阻塞 |
| 64K 页 | 本项目定制产物覆盖 64K 对齐链路，不代表任意官方 cosmocc 产物也支持；仍需目标内核实测 |
| 脚本兼容库 | `portable.sh` / `bbcosmo` 仍是实验 API；已覆盖临时目录所有权、trap 隔离、JSON 转义、稳定菜单 ID、关键能力探测与工具版本上报；raw TUI 经 `bbtty` 在 Unix 上已可用（行式仍为默认降级），Windows ConPTY 待验 |

## 使用原则

- 自动化先选非交互模式；交互先保证行式模式，再逐项验证 TUI。
- 不把 SKIP 或非阻塞平台的失败计算为“全功能一致”；完整冒烟不再接受模糊 SOFT。
- 涉及系统配置、权限修改、网络服务和可信下载，必须做目标环境专测。

下一步优先级见[路线图](ROADMAP.md)，可运行的测试见[测试指南](TESTING.md)。
