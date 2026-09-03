# cosmo 工具链定制补丁（2026-09-03）

对 cosmo master 源码的两处定制。**已打入 /tmp/cosmopolitan-master 并编译出对象，未发布**（工具链打包未完成——master 与 4.0.2/3.9.2 内部 API 不兼容，需 package.sh 全套打包）。

## 补丁 1：/dev/zero 在 Windows 的虚拟（kFdDevZero=11）

cosmo Windows 只虚拟了 /dev/null、/dev/urandom、/dev/tty——加 /dev/zero：

| 文件 | 改动 |
|---|---|
| `libc/intrin/fds.h` | `#define kFdDevZero 11` |
| `libc/calls/open-nt.c` | dispatch 加 `zero` → `sys_open_nt_no_handle(kFdDevZero)` |
| `libc/calls/fstatat-nt.c` | 路径匹配加 zero → `sys_fstat_nt_char(kFdDevZero)` |
| `libc/calls/read-nt.c` | `kFdDevZero` → `memset(data,0,size); return size;` |
| `writev/readv-nt.c` | case 组并入 kFdDevZero |
| `write-nt.c` | case 并入（与 DevRandom 同返回 eperm） |
| `fstat-nt.c` | case 并入（字符设备 stat） |
| `readwrite-nt.c`/`pread.c` | seekable 条件加 kFdDevZero |
| `printfds.c` | 调试名 "kFdZero" |
| `ioctl.c` | 并入 einval 分支 |
| `lseek-nt.c` | 并入（lseek 返回 offset） |

## 补丁 2：mac 自身路径根治（KERN_PROCARGS2）

`libc/calls/getprogramexecutablename.greg.c`：IsXnu 分支（IsMetal 之后）——
sysctl `{CTL_KERN=1, KERN_PROCARGS2=49, getpid()}` 拿 argv 区，首串为 exec 绝对路径。
不依赖 argv[0]/`$_` 推断（mac 上 cosmo 无 GetModuleFileName//proc 分支时的 fallback 缺陷）。
启动早期无 malloc，用 `static char xnu_buf[1<<18]`。

## 应用方法（未来）

```sh
# 到 master 树, 用 master-snapshot/ 下对应文件覆盖即可(或手工按表改)
```

## ✅ 2026-09-03: 定制工具链构建成功

配方（已验证，busybox mac 45/46 + 嵌套 exec 修复）：
1. master 源码全量构建：`make -j8 MODE=x86_64 o/x86_64/cosmopolitan.a`（含 5 补丁，61MB）+ ape 全套 + 工具 .dbg
2. 头文件重建（关键）：3.9.2 工具链 include 整体替换为 master 头
   （`libc/isystem/*` + `libc/integral/*` + `o/cosmocc.h.txt` 列表——package.sh 的打包规则）
3. 库/链接部件替换 3.9.2 工具链：libcosmo.a←cosmopolitan.a、crt.o、crtfastmath.o、
   ape.lds、ape.o、ape-no-modify-self.o、ape-copy-self.o（必须全套一致，缺一 relocation 错）
4. busybox 用 3.9.2 驱动 + master 头库重编 → 0 错误

**教训**：单文件/单库替换必失败（头库常量语义不匹配 EEXIST 等）；必须"头+库+ape 全套"一致替换。
产物：master 树 `o/x86_64/cosmopolitan.a`（61MB，MODE=x86_64 即 package.sh 的 m=x86_64 默认 MODE）。

