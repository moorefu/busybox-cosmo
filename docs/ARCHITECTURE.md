# ARCHITECTURE — 适配全景

> 历史: 2026-09-03 于 `/Users/moore/Projects/busybox`(cosmo-dist) 完成四路线选型与三平台实机验证,
> 本工程承接其全部结论与补丁。选型: **A. busybox + cosmocc** (实证跑通, 有 ash, 补丁可控) 为最终路线。

## 一、busybox 侧适配补丁 (patches/busybox-cosmo-full.patch, 82 文件)

### A. cosmo 平台适配 (核心)

| 文件 | 改动 | 根因 |
|---|---|---|
| `Makefile`、`scripts/Makefile.build`、`scripts/Makefile.IMA` | 移除 `-nostdlib` (3 处) | cosmocc 包装器不支持 |
| `include/libbb.h` | `bb_busybox_exec_path` → `get_busybox_exec_path()` (`__COSMOPOLITAN__`) + `bb_argv0` 声明 | Windows 无符号链接 farm, `/proc/self/exe` 不可 exec |
| `libbb/messages.c` | cosmo 分支实现 `get_busybox_exec_path()` | 运行时解析自身路径 |
| `libbb/appletlib.c` | `main()` 记录 `bb_argv0 = argv[0]` | 同上 |
| `shell/ash.c` | ① vforkexec 在 cosmo 下改 `fork()` ② exec-path 配合 | cosmo vfork-nt 与 ash 交互缺陷 |
| `archival/tar.c` | vfork_compressor 子进程 cosmo 下 `execv(自身, [gzip,-f])` | `execlp("gzip")` PATH 找不到 + vfork errno 共享失效 |
| `networking/wget.c` | `FEATURE_WGET_OPENSSL && !__COSMOPOLITAN__` 跳过 openssl helper | `child_failed` 依赖 vfork 共享内存 → 父进程误判, wget https 必挂 |
| `networking/tls.c` | 修上游 debug 代码 `len24_hi` → `hp->len24_hi` | TLS_DEBUG=1 才能编译 |

### B. 编译期常量修复 (extern const 平台化常量 vs busybox 编译期用法)

`stty/mkfifo/hostid/tune2fs/u_signal_names/hush/tls/bootchartd/beep` 等: 固定常量值 / mknod 替代 mkfifo(3)。

### C. 裁剪摘除 (kbuild 行注释)

被裁剪 applet 的源文件 `//kbuild:` 行注释 (gen_build_files 机制: 须注释源内行, 改 Kbuild.src 会被覆盖)。

### D. 新增

`libbb/cosmo_stubs.c` — 被裁剪 applet 的 stub main (打印 not supported)。

### E. 平台功能 (三平台 ps / unicode)

- **ps**: Windows=Toolhelp 枚举 / Linux=/proc / mac=透传 `/bin/ps`
- **Unicode**: `LAST_SUPPORTED_WCHAR=40959` + `WIDE_WCHARS=y` (ls 中文、输入回显)

## 二、cosmo 工具链侧定制补丁 (patches/cosmo/)

| 补丁 | 效果 | 验证 |
|---|---|---|
| /dev/zero Windows 虚拟 (kFdDevZero=11, 13 文件) | dd/读零可用 | Windows 46/46 |
| mac 自身路径 (KERN_PROCARGS2 sysctl) | mac 嵌套 exec 根治 | mac 清 PATH 全过 |
| QuickEdit 鼠标保留 (tcsetattr) | busybox sh 内鼠标选择/粘贴 | Windows |
| 64K 布局 (链接/ape loader 64K 对齐) | 64K 页内核 ELF 可用 | 鲲鹏 UOS 45/46 |

`patches/cosmo/master-snapshot/` = 5 补丁最终源码形态 (覆盖即应用); `cosmo-libc-custom.patch` = 补丁文件。

## 三、关键经验

1. **vfork 共享内存模式** (`child_failed`/`vfork_exec_errno`) 在 cosmo Windows 全失效 → 全绕 fork 是正确路线。
2. **头+库+链接件全套一致**才能替换工具链; 单件替换必遇符号/常量错。
3. **mac 测试失真**: `__program_executable_name` 退化 argv0/`$_` (已被 KERN_PROCARGS2 补丁根治);
   实机验证以 Windows/Linux 为准。
4. **测试纪律**: APE 首跑同化改写文件; 容器勿直接挂载分发目录; 发布件绝不本机直跑。
5. 64K 页问题全链路: 链接布局 → apelink 嵌入 → loader 加载 → binfmt argv0, 每层独立缺陷。
6. binfmt `P` flag (preserve-argv0) 是 <5.12 内核同样需要的旧特性 (见 patches/cosmo/issue-*.md)。
