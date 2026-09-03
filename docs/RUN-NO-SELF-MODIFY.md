# RUN-NO-SELF-MODIFY — APE 自修改问题与"母本不修改"方案论证

## 一、现象(实测, 2026-09-03, macOS x86_64)

| 运行方式 | 母本是否被改 | 功能 |
|---|---|---|
| 直接 exec APE (mac/Linux 首跑) | ✅ **会被改**(平台"同化": 原地重写为纯本机格式) | 首次后为原生格式, 全功能 |
| 经 ape loader 显式运行 (`ape-loader-x86_64 ./busybox.com ...`) | ❌ 不改(md5/cksum 不变) | 顶层命令全功能; **ash 内 STANDALONE 嵌套 exec 受限**(取到 loader 自身路径) |
| Linux + binfmt_misc (`/usr/bin/ape` + `FP`) | ❌ 不改(内核把文件交 loader, 保留真实 argv0) | **嵌套 exec 全功能**(实测矩阵 45/46+31/31) |
| Windows (`.com`/`.exe`) | ❌ 不改(PE 原生加载, 无同化概念) | 全功能 |
| **cache 同化副本**(安装器默认) | ❌ 不改(改的是副本) | **全功能**(含 ash 嵌套 exec) |

为什么直接 exec 会改自身:APE 是"一个文件多种格式"。在 Linux/mac 上内核按其中一种格式
(ELF/Mach-O)加载;cosmopolitan 运行时检测到"直接从盘执行"时,会把文件**原地重写成只含
当前平台格式的纯本机文件**(assimilate),之后每次启动都走内核原生加载,省去再次解析。
这保证"拿到 zip 就能跑",代价是首个执行者会改写文件 —— 所以**发布/安装的母本绝不能直接跑**。

## 二、安装器策略 (`install.sh` + launcher)

按平台自动选择运行方式,母本(`$prefix/libexec/busybox`)永远是 pristine 副本源:

```
Linux + binfmt 已注册  → exec 母本          (内核 loader, 不改母本, 嵌套 exec 全功能)
其它(含 mac、无 binfmt Linux):
   默认 → cache 同化副本:
          首次: cp 母本 → ~/.cache/busybox-cosmo/busybox-<平台-校验和>
                跑一次副本让它"同化"成原生格式
          之后: exec 已同化的原生副本 (快, 全功能)
   BB_USE_LOADER=1 → 显式 ape loader (免拷贝; 顶层命令可用, 嵌套 exec 受限)
Windows             → busybox.exe (PE 原生, 无同化)
```

cache 键 = 平台-架构-母本 cksum:母本升级后自动生成新副本;旧副本可手动清
(`rm -rf ~/.cache/busybox-cosmo`)。可用 `BUSYBOX_COSMO_CACHE`/`XDG_CACHE_HOME` 改位置。

**首跑成本**:一次 `cp`(≈1.9MB)+ 一次同化运行(数十~百 ms);此后直接跑原生副本,与
系统命令同速。Linux+binfmt 则零拷贝零首跑(最快)。

## 三、局限性(如实)

1. **直接 exec 的母本必然会被改** —— 这是 cosmopolitan 设计;任何"禁止改写"方案都必须
   走 loader 或副本,安装器两者都提供。如果文件系统只读(挂载 ro/打包进 squashfs),直接
   exec 会失败而不是改写(cosmo 检测到不可写会报错或回退 loader) —— 需 loader 或 cache。
2. **loader 下嵌套 exec 受限**(mac; 无 binfmt Linux 同理):busybox ash 启动子 applet 时按
   STANDALONE 取"自身可执行路径",loader 场景下拿到的是 loader 而非 busybox,导致部分子
   命令不可用。**要完整 shell 请用默认 cache 副本路径,或 Linux binfmt。**
3. **mac arm64** 需 loader 参与 arm APE 首启(自举到 ~/.ape);安装器已携带
   `ape-loader-macos-arm64`,并以 cache 副本保证完整功能。
4. **64KB 页 Linux aarch64**: 用 `busybox-arm64-linux-elf`(纯 ELF, 无同化问题),
   安装器在 PAGESIZE=65536 时自动选择它。
5. Windows: 文件名必须含 `busybox`(busybox.exe/com) 才启用子命令模式。

## 四、自校验

```sh
a=$(cksum <prefix>/libexec/busybox)
<prefix>/bin/busybox echo hi >/dev/null
b=$(cksum <prefix>/libexec/busybox)
[ "$a" = "$b" ] && echo "母本未被修改 ✓"
```
install.sh 安装成功后会打印同样提示;release 内 smoke-full.sh 可整组回归
(默认路径下 173 PASS / 0 FAIL, 2026-09-03 mac 实测)。
