# RUN-NO-SELF-MODIFY — APE 自修改问题与"母本不修改"方案论证

## 一、现象(实测, 2026-09-03, macOS x86_64)

| 运行方式 | 母本是否被改 | 功能 |
|---|---|---|
| **本发行物直接 exec**(内嵌 ape loader: `apelink -l x86.elf -l arm64.elf -M m1.c`) | ❌ **不改**(loader 进程读母本) | 顶层命令全功能; **ash 内 STANDALONE 嵌套 exec 受限**(见局限 2) |
| 旧式 APE(未内嵌 loader)直接 exec 首跑 | ✅ 会被改(平台"同化"原地重写) | 首次后原生格式 |
| Linux + binfmt_misc (`/usr/bin/ape` + `FP`) | ❌ 不改(内核把文件交 loader, 保留真实 argv0) | **嵌套 exec 全功能**(实测矩阵 45/46+31/31) |
| Windows (`.com`/`.exe`) | ❌ 不改(PE 原生加载) | 全功能 |
| **install.sh cache 副本**(默认) | ❌ 不改(改的是副本) | **全功能**(assimilate 生成原生副本) |

> 2026-09-03 发行物已改为**内嵌 loader 的官方形态**(package.sh 同款
> `apelink -l … -M …`),因此 release 里的 `busybox-x86_64.ape` / `busybox-fat.ape`
> **直接运行也不会再改写自身**(实测 md5/cksum 恒定)。旧文"发布件绝不能直接跑"
> 仅适用于未内嵌 loader 的旧产物;新发行物母本安全, 但完整 shell 请走 cache/install。

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
副本用随 release 分发的 `assimilate` 就地转成**当前平台原生格式**(Linux ELF / mac Mach-O),
得到全功能且不再自改的原生二进制。

**首跑成本**:一次 `cp`(≈1.9MB)+ 一次 assimilate 转换(几十 ms);此后直接跑原生副本,
与系统命令同速。Linux+binfmt 则零拷贝零首跑(最快)。

## 三、局限性(如实)

1. **直接 exec 的母本必然会被改** —— 这是 cosmopolitan 设计;任何"禁止改写"方案都必须
   走 loader 或副本,安装器两者都提供。如果文件系统只读(挂载 ro/打包进 squashfs),直接
   exec 会失败而不是改写(cosmo 检测到不可写会报错或回退 loader) —— 需 loader 或 cache。
2. **loader 下嵌套 exec 受限**(mac; 无 binfmt Linux 同理):busybox ash 启动子 applet 时按
   STANDALONE 取"自身可执行路径",loader 场景下拿到的是 loader 而非 busybox,导致部分子
   命令不可用。**要完整 shell 请用默认 cache 副本路径,或 Linux binfmt。**
3. **mac arm64** 需 loader 参与 arm APE 首启(自举到 ~/.ape);安装器已携带
   `ape-loader-macos-arm64`,并以 cache 副本保证完整功能。
4. **64KB 页 Linux aarch64**: 首选 `busybox-arm64-linux-elf`(纯 ELF, 无同化问题,
   免 loader; 安装器在 PAGESIZE=65536 时自动选它)。fat/arm64.ape 自 2026-09-04 起
   **内嵌 64K 对齐 loader** (见 toolchain/build-custom.sh 3b' + check-ape-64k.sh),
   经 `./busybox`(cache+assimilate)或 binfmt+loader 路径同样可用。
5. Windows: 文件名必须含 `busybox`(busybox.exe/com) 才启用子命令模式。

## 三·五、"直接跑 busybox-fat.ape 就自动 cache" 能做到什么程度

- `./busybox-fat.ape`(发行物, 内嵌 loader): 首次运行 cosmopolitan 会**自动把内嵌
  loader 提取/缓存到 `~/.ape-1.10`(或 `$TMPDIR`)再执行**, 母本零写入、有缓存;
  但缓存的是 loader 而非 busybox 原生副本, 故 ash 嵌套 exec 受限。
- 若要"运行 cache 中的 busybox **原生副本**"(全功能 shell): APE 自身引导无法一步
  生成原生文件(需要 assimilate/cc, 且 APE 首字节执行链不可自定义), 因此由
  同目录的零安装 launcher 承担:
  ```sh
  ./busybox <args>     # 同目录直跑: 自动 cp 母本→cache→assimilate 成原生→exec
  ```
  cache 位于 `$BUSYBOX_COSMO_CACHE` → `$XDG_CACHE_HOME/busybox-cosmo` →
  `~/.cache/busybox-cosmo`, 文件 `busybox-<os>-<arch>-<cksum>`; 母本从不改。

## 四、自校验

```sh
a=$(cksum <prefix>/libexec/busybox)
<prefix>/bin/busybox echo hi >/dev/null
b=$(cksum <prefix>/libexec/busybox)
[ "$a" = "$b" ] && echo "母本未被修改 ✓"
```
install.sh 安装成功后会打印同样提示;release 内 smoke-full.sh 可整组回归
(默认路径下 173 PASS / 0 FAIL, 2026-09-03 mac 实测)。
