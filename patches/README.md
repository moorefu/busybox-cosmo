# 补丁维护

构建只读取两个权威入口：[BusyBox series](busybox/series)、[Cosmopolitan series](cosmo/series)。顺序显式列出；未列入的补丁、重复项、缺失文件会让 `make check` 失败。

## BusyBox 的职责划分

| 补丁 | 内容 |
|---|---|
| 0001-build | 编译参数和构建入口 |
| 0002-runtime-shell | libbb、自身路径、ash/hush 的 fork/exec |
| 0003-terminal-signals | 终端及信号常量适配；不代表 termios 问题已解决 |
| 0004-applets | 归档、网络、进程等 applet 适配 |
| 0005-platform-selection | Linux 专属 applet 的构建选择及相关编译适配 |
| 0006-make-import | 独立 make 实现导入，保留源码版权和许可证头 |

本次把旧 full + restore 合并为最终差异，从 12,381 行降至 5,397 行（包含随后加入的 4 行编译告警修正）；原版与新旧序列均已从同一 tarball 提取/应用对比，除生成物外迁移时的最终源码逐字节一致。`include/usage.h` 不再入补丁，标准 `gen_build_files.sh` 从源码生成。

make 导入约 3,573 行，因其是完整第三方实现而保留一份独立补丁；其他五个补丁均不足 700 行。不以机械碎片化替代职责边界。原始审计参考点为 Git 提交 `b1c678a`，退役 full/restore、旧 helper 补丁和不等价 snapshot 可从该提交追溯。

## 修改流程

1. 从锁定 tarball 创建隔离工作树；用 `scripts/patch-series.py apply` 应用序列，绝不在 `src/` 或已有用户构建树试打。
2. 修改所属职责的补丁；涉及同一文件的后续补丁必须按最终顺序验证。不要把生成头文件、`.config` 或 `.orig/.rej` 入补丁。
3. 在全新原版上应用全部序列，审查最终源码差异。确认变化正是预期，再更新 `busybox/result.sha256` 中受影响文件的 SHA256；新增文件要加入清单。
4. 执行 `make fetch && make check`，使用新 `BUSYBOX_WORK_DIR` 编译并运行 `make test`；最后跑平台 CI。

结果清单是重构/修改的审查护栏，不是上游来源认证，不能不审查就自动刷新来消除失败。序列标志只证明曾完整应用对应补丁，不检测用户在生成树中的后续手工修改。

补丁应用要求 Python 3 和 GNU 兼容的 `patch --batch --forward --fuzz=0`。失败只清理自己的暂存目录，已有无标志/过期工作树保持原样并报错。同一目标不支持并发 prepare。
