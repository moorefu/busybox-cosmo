# 已知限制

本页只列当前使用边界；修复过程及过往 CI 数字放在[历史记录](history/README.md)。“已编译”“测试通过”“所有场景可用”是不同结论。

| 能力 | 边界与建议 |
|---|---|
| ash 基础脚本 | 优先包内 ash、明确参数引号和退出码。新增契约覆盖引用、管道、exec、argv、wait 等，但不是 POSIX 完整认证 |
| stty / raw TUI | 当前 termios 编译期索引仍有跨平台布局风险。mac/Windows 的真实 PTY 验证与运行时索引改造未完成；不要依赖 raw 模式做一致性承诺 |
| HTTPS wget | 内置 TLS 不等于证书可信校验。当前路径不能作为可信下载后端；需要经验证的校验证书后端或离线签名校验 |
| xz / lzma 压缩 | BusyBox applet 主要提供解码；`tar cJf` 创建归档需要独立外部 xz 编码器。缺少编码器必须视为错误 |
| Unicode | 配置支持部分宽字符，但不是完整 Unicode 字形/宽度引擎；组合字符、emoji 和超过 U+9FFF 的清洗/宽度路径不能承诺一致。原始字节输出与终端排版是两回事 |
| mac ps | 透传系统 `/bin/ps`，选项、输出及沙箱权限不同；脚本不要解析它作为跨平台进程协议 |
| Windows 进程/网络 | fork 成本高，fork 后 socket 继承、服务器 accept 路径仍需验证；不能由客户端 connect 成功推断服务器可用 |
| 权限/信号/特殊文件 | Windows 用户、权限与信号模型不是 POSIX；mkfifo/mknod、nproc 等受锁定 libc 实现限制，不属于可移植基线 |
| 单调时钟 | 锁定 Cosmopolitan 的 `clock_gettime(CLOCK_MONOTONIC)` 在当前 macOS x86_64 会触发 SIGILL，并影响 dd、shuf 等 applet；BusyBox 配置使用 `gettimeofday` 后备。系统时间跳变可能影响长时间测量，升级 libc 后应恢复单调时钟并重测 |
| 启动与缓存 | loader 的名字、argv 布局及用户目录约定属于 ABI 依赖；只复制二进制、不带匹配 loader 可能改变行为 |
| ARM64 | Linux/macOS 有 ARM64 载荷；Windows ARM64 是 x86_64 仿真。macOS ARM64 与 Windows ARM64 CI 仍非阻塞 |
| 64K 页 | 本项目定制产物覆盖 64K 对齐链路，不代表任意官方 cosmocc 产物也支持；仍需目标内核实测 |
| 脚本兼容库 | `portable.sh` / `bbcosmo` 是实验 API，行式交互为当前基础；临时目录所有权、trap 隔离、JSON 控制字符转义和能力探测仍需强化 |

## 使用原则

- 自动化先选非交互模式；交互先保证行式模式，再逐项验证 TUI。
- 不把 SKIP、SOFT 或非阻塞平台的失败计算为“全功能一致”。
- 涉及系统配置、权限修改、网络服务和可信下载，必须做目标环境专测。

下一步优先级见[路线图](ROADMAP.md)，可运行的测试见[测试指南](TESTING.md)。
