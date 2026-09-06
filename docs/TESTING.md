# 测试指南

## 分层入口

| 层 | 命令/文件 | 验证内容 |
|---|---|---|
| 维护门禁 | `make check` | 逐文件 Shell 语法、序列完整性、补丁失败回滚、测试设施生命周期 |
| 源码门禁 | `make fetch && make check` | 新序列应用到原版、82 个变更文件的结果哈希、usage.h 标准再生成 |
| ash/核心功能 | `tests/ash-contract.sh` | 引号、heredoc、IFS、环境、重定向、管道、退出码、trap、wait、exec、长 argv、哈希/二进制归档 |
| 压力与综合功能 | `tests/deep-test.sh`、`tests/smoke-full.sh` | 大数据流、并发、文本、文件、归档及回环网络 |
| 实验兼容库 | `tests/portable-contract.sh` | 初步能力/临时目录/非交互契约，不是完整 TUI 测试 |
| 平台专测 | `tests/ci-platform-probe.py` | PTY/termios、外部 xz 等待确认假设；当前仅采证 |
| 64K 内核 | `tests/qemu-64k-test.sh` | 全系统模拟，不用普通 ARM64 runner 冒充 64K 内核 |

## 本地运行

`make smoke`、`make smokefull`、`make portable-check` 和 `make test` 都使用已有产物，不会重编译或重新打包。`make test` 汇总 ash、deep、full 和兼容库四套契约。可设置 `BUSYBOX=/绝对路径/busybox`；Windows 使用包内 `busybox.com`。

完整冒烟默认不打开 socket，适合受限沙箱；CI 设置 `BBTEST_NETWORK=1`，将本地回环失败作为硬失败。手工验网络时也显式设置该变量，避免把“没执行”误读为通过。

完整发布包中：

```sh
./busybox ash ash-contract.sh
./busybox ash deep-test.sh
./busybox ash smoke-full.sh
./busybox ash portable-contract.sh
```

新契约使用明确的 `busybox ash` 子进程，包含空 PATH 下的内部 applet 测试。argv 不只数参数，还逐字节比较 63/64/65/256 项，覆盖空串、空格、中文、引号和反斜线。

## 断言与临时目录纪律

- `testlib.sh` 在当前可写目录创建绝对路径的隔离目录；创建最多重试 20 次，禁止只读环境无限循环。
- 命令在子 shell 执行，失败输出和原始退出码写入套件日志；退出/中断清理不会吞退出码。
- `KEEP_TEST_ROOT=1` 保留临时目录用于复现。清理只作用于本次创建的目录。
- 必须断言输出和生产者状态；不要使用 `test $? -ge 0`、末尾 `echo ok` 或无条件清理吞掉失败。
- 上游失败重要时使用 ash 的 `set -o pipefail`。预期 SIGPIPE 的 `yes | head` 需单独解释，不能盲目套用。
- 非空哈希使用独立已知答案；往返测试不能单独证明编码格式正确。

## CI 解释

同一完整发布物在 Linux x86_64/ARM64、macOS x86_64/ARM64、Windows x86_64/ARM64 仿真运行。ash 契约与深度/完整套件的日志分别上传；稳定平台硬失败阻断，两个 ARM64 实验平台仍非阻塞。

min 包增加 Linux x86_64 的同套 ash 契约；其余平台的 min 包端到端矩阵尚待补齐。PTY 探针、SKIP、SOFT 不算通过；测试清单不是全 applet 功能认证。
