# NOTICE / 许可说明

本工程代码与产物的许可构成：

| 组件 | 许可 | 说明 |
|---|---|---|
| busybox (源码/产物逻辑) | GPL-2.0 | `busybox.net` 官方源码 + 本工程适配补丁 |
| Cosmopolitan Libc / 工具链 | ISC (cosmopolitan) + 各编译部件自带许可 | 静态链接入 APE; 工具链 GPL3/GPL2/LGPL 部件为编译期工具 |
| busybox-w32 (参考) | GPL-2.0 | 仅参考, 不入产物 (见 scripts/fetch-w32-reference.sh) |
| ape loader / m1 loader | cosmopolitan 同源 | assets/loaders/ 部署件 |

分发注意：
- busybox 产物 (APE/ELF) 静态链接含 GPL-2.0 busybox 代码 → 遵守 GPL 义务 (提供源码/对应许可文本)。
- Cosmopolitan 为静态链接许可友好的 ISC; 工具链本身不随 APE 分发。
- 各补丁归属: 历史适配工作 (2026) + 上游补丁来源见 `patches/cosmo/README.md` 与 `docs/ARCHITECTURE.md`。

许可文本参考: `toolchain/cosmo/LICENSE.*` (工具链自带); busybox `LICENSE` (源码树内)。
