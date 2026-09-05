# Cosmopolitan ABI 与布局约定

本文记录 busybox-cosmo 依赖的 Cosmopolitan 行为。这里的“约定”是当前锁定工具链的可验证实现，不等同于 Cosmopolitan 的稳定公共 ABI。升级工具链时必须重新运行对应检查。

| 编号 | 约定与代码位置 | 适用范围 | 失败表现 | 验证方式 |
|---|---|---|---|---|
| TERMIOS-CC | `libc/sysv/consts.sh`、`libc/calls/termios.internal.h` 的 `COPY_TERMIOS` | Linux/Windows/macOS tty | `stty` 控制项写入错误 `c_cc` 槽位 | 各平台独立 PTY 读写 intr/erase/eof/min/time |
| SIGNAL-NUMBER | `libc/intrin/sig2linux.c`、`linux2sig.c` | 向系统调用边界转换信号 | 终端/进程信号编号或可用性不一致 | 逐项发送与 `kill -l` 交叉检查 |
| APE-ARGV | loader 的 `- PROG ARGV0 ...` 协议、`shell/ash.c` | 无 binfmt 的 APE 启动与嵌套 exec | argv0 丢失、参数截断或把 loader 当载荷 | 0/1/63/64/256 参数及空格、中文、引号往返 |
| SELF-PATH | `GetProgramExecutableName`、macOS `KERN_PROCARGS2` | standalone/loader 深层 exec | BusyBox 找不到自身，回落到宿主工具 | 连续 shell/standalone 冷启动与缓存启动 |
| LOADER-DISCOVERY | launcher、ash、libc 对 loader 名称/路径的查找 | macOS/Linux 显式 loader | 载荷路径被识别为 loader，嵌套 exec 失败 | 私有 loader、系统 loader、缺 loader 三种路径 |
| FORK-ERROR | tar 压缩子进程、BusyBox `fork/vfork` | vfork/fork 子进程 | exec 或编码中途失败被父进程误判成功 | 假编码器、无 PATH、非零退出、空归档 |
| WINDOWS-ABI | Toolhelp、`tprecode16to8` 真实头文件原型 | Cosmopolitan Windows | ps 名称乱码或 ABI 调用破坏栈 | Unicode 进程名及系统 `ps` 交叉输出 |
| PAGE-LAYOUT | APE loader 与 payload 的 PT_LOAD、`e_flags`、最终偏移 | 4K/16K/64K 页 Linux | loader 可解压但内核拒绝加载 | `check-ape-64k.sh` 坏样本 + QEMU 64K |
| TOOLCHAIN-SET | 头、库、crt、apelink、loader 的同源摘要 | 自定义工具链构建 | 旧工具链/缓存产生不可复现产物 | manifest、SHA256、干净目录重建 |
| APPLET-CAPABILITY | BusyBox applet 实际编码/解码能力与配置 | tar/gzip/bzip2/xz/lzma | 仅解码 applet 被误当编码器 | 外部工具缺失、独立工具交叉校验 |

## 升级检查清单

1. 锁定新的 Cosmopolitan 提交和工具链版本，重新生成头文件并保存摘要。
2. 先运行静态补丁来源检查，再构建 full/min；不得复用旧工作树标记。
3. 运行 `scripts/check-ape-64k.sh` 的正确样本和坏样本，确认缺工具、解析异常、缺 loader 都返回非零。
4. 在 Linux、macOS、Windows（含仿真路径）分别执行长 argv、嵌套 exec、tar 压缩和 ps/TTY 专项。
5. 只有当结果与上一版本逐项对照后，才更新 `docs/KNOWN-LIMITATIONS.md` 和发布能力清单。

