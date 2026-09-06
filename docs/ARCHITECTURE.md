# 架构与职责

| 层 | 权威入口 | 职责 |
|---|---|---|
| 上游与配置 | `src/` 下载材料、`config/` | 固定 BusyBox 版本及 applet 集合 |
| BusyBox 适配 | `patches/busybox/series` | 编译适配、自身定位、ash exec/fork、平台 applet |
| Cosmopolitan 适配 | `patches/cosmo/series` | Windows 命令行、mac loader 路径、64K 布局等 libc/loader 行为 |
| 构建发布 | `scripts/`、`toolchain/` | 校验来源、原子应用补丁、编译、链接、打包 |
| 启动部署 | `scripts/bb.sh`、`install.sh` | 选择平台载荷、loader、缓存副本或 binfmt |
| 脚本体验 | `lib/portable.sh`、`scripts/bbcosmo` | 能力查询、临时目录、行式交互；实验 API |
| 验证 | `tests/`、GitHub Actions | 行为断言与平台证据，不用 applet 存在性代替功能测试 |

## 为什么 BusyBox 需要特别适配

BusyBox 的 applet 会再调用自身；ash 优先内部 applet 并使用子进程、信号和终端状态。传统实现依赖 Linux 编译期常量、vfork 共享状态、`/proc/self/exe` 和 POSIX 进程模型。Cosmopolitan 的跨平台抽象并不自动满足这些假设。

因此，应用层修正属于 BusyBox 补丁；Windows argv 编码、loader 载荷定位与 ELF 页布局属于工具链。不能把所有问题都塞进 launcher，也不能假设把 vfork 换成 fork 后所有 socket/终端问题都已解决。

## 保持明确的边界

- `include/usage.h` 等生成物由 BusyBox 的标准规则生成，不作为补丁维护。
- make 的外来实现单独保留为导入补丁；平台选择改动不与 ash 运行时混在一起。
- 宿主能力要行为探测：mac `ps` 依赖系统程序，xz 编码依赖外部工具，TLS 校验不能靠 HTTPS 请求成功来证明。
- 脚本层能统一接口、错误和降级，不能模拟完整 POSIX 权限、可靠 PTY 或 Windows socket 继承。

私有符号与布局依赖见 [Cosmopolitan ABI 契约](COSMO-ABI-CONTRACTS.md)；未完成工作见[路线图](ROADMAP.md)。
