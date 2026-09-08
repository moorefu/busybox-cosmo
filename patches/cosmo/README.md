# Cosmopolitan 补丁

唯一应用入口是 [series](series)。基座为 Cosmopolitan `3293fad0a9eac7865c019be98fb993eeb933405e`；顺序与迁移前 full + 按字典序 extra 完全一致。

| 补丁 | 职责 |
|---|---|
| cosmo-custom-full | Windows /dev/zero、mac 自身路径、QuickEdit、loader/apelink 64K 对齐 |
| cosmo-apelink-apeflags-extra | APE 标志，避免 loader 的旧 argv 约定 |
| cosmo-mkntcmdline-roundtrip-extra | Windows 参数中的反斜线与双引号往返 |
| cosmo-pen-mac-loader-extra | mac loader 路径下识别真正载荷 |
| cosmo-sethostname-extra | 平台 hostname 写入适配；仍受权限控制 |
| cosmo-console-preserve-extra | bbtty 显式保留启动前 Console 模式/代码页；其他程序行为不变 |

主补丁只有约 233 行，保留其现有边界；不为追求文件数量机械拆分。驱动包装脚本的 64K 参数仍由工具链组装阶段处理。

旧 `master-snapshot/` 和文档式 `cosmo-libc-custom.patch` 不是等价权威来源，已从当前目录移除；需要追溯时查看 Git 历史 `b1c678a`，不要再覆盖构建树。

`toolchain/build-custom.sh` 使用统一补丁管理器，按序列顺序应用，并检查源码完成标志的指纹。维护方法见[补丁指南](../README.md)。涉及私有 ABI 的变更同时更新 [ABI 契约](../../docs/COSMO-ABI-CONTRACTS.md)。
