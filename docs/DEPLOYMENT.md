# 部署指南

## 默认入口

完整包和最小包都提供 `busybox` launcher、`busybox.com`、平台 loader、`bbcosmo` 和 `lib/`。完整包另有安装器、各架构产物与测试。

```sh
# Linux / macOS：从解压后的目录运行
./busybox ash script.sh
./busybox ash bbcosmo doctor

# Windows（PowerShell/cmd）
busybox.com ash script.sh
busybox.com ash bbcosmo doctor
```

不要将任意宿主 `sh` 的测试结果当成包内 ash 的结果。Windows 二进制名字保留 `busybox`；Windows ARM64 当前使用 x86_64 仿真。终端可先采用 UTF-8 和行式交互；完整 TUI 仍需专门验证。

脚本在执行可选操作前可运行 `./busybox ash bbcosmo capabilities --format kv`。压缩创建来源只会是 `builtin`、`external` 或 `unavailable`，进程名称搜索只会是 `builtin` 或 `unsupported`；不要从 applet 清单自行推断。

## 缓存与安装

launcher 选择架构并准备缓存副本/loader。缓存优先级为 `BUSYBOX_COSMO_CACHE`、`XDG_CACHE_HOME/busybox-cosmo`、用户默认缓存目录。某些启动路径需要用户目录中的 `~/.ape-1.10`，并非完全无写入。

完整包可运行 `./install.sh --prefix /绝对路径`；前缀会写入 launcher 与卸载清单，因此拒绝引号、反斜杠、变量展开符和换行，Windows Git Bash/MSYS 请使用 `/c/...` 路径。Linux 如需系统级 binfmt，可使用 `sudo ./busybox --setup-linux`。后者会修改系统配置，不是普通脚本运行的必要前置；注册的开机持久化需按安装器提示处理。

发布 APE 内嵌 loader，正常启动与主动同化不同。转换原生格式应作用于副本，不要直接对分发母本运行 `--assimilate`。Linux 原生转换使用完整包的独立 assimilate 工具；不要使用 APE 内置的 mac 同化路径。

## ARM64 与 64K 页 Linux

本项目同时调整 loader、载荷链接与 apelink 组装的 64K 对齐。APE 仍需 loader，裸 `busybox-arm64-linux-elf` 可免 loader 运行。

`scripts/check-ape-64k.sh` 是静态布局检查；`tests/qemu-64k-test.sh` 是真实 64K 内核的全系统模拟，二者不等价。普通 ARM runner 也不能替代 64K 内核测试。

macOS ARM64 走原生 loader 路径，已增加嵌套 exec 适配，CI 仍保留实验级别；不再笼统宣称必须用 Rosetta。生产使用前在目标终端跑[契约测试](TESTING.md)。

遇到问题请提供平台、产物 SHA256、启动命令和失败日志。[已知限制](KNOWN-LIMITATIONS.md)
