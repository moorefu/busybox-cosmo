# cosmo 工具链定制补丁（2026-09-03）

对 cosmopolitan master 源码的 **17 文件定制**，是"定制工具链"与官方 cosmocc 的唯一源码差异。
本目录三种形态等价：

| 形态 | 说明 |
|---|---|
| `cosmo-custom-full.patch` | **权威 unified diff**（相对官方 commit `3293fad0`，`patch -p1` 可直接应用）— 工具链构建用它 |
| `master-snapshot/` | 成品文件覆盖形态（文件内容 = 定制后状态；旧配方用 `cp -R master-snapshot/. <master树>/`） |
| `cosmo-libc-custom.patch` | 早期文档式补丁（含注释，供阅读，不以 patch -p1 为保证） |
| `cosmo-sethostname-extra.patch` | **附加定制**：libc/calls/sethostname.c（三平台等价物），build-custom 自动应用所有 `cosmo-*-extra.patch` |

基座：**jart/cosmopolitan @ `3293fad0a9eac7865c019be98fb993eeb933405e`**
（`toolchain/fetch-sources.sh` 按该 commit + sha256 `cde29083…` 取官方源码）。

## 定制内容（4 组，17 文件）

### 1. `/dev/zero` 在 Windows 的虚拟（kFdDevZero=11, 13 文件）

cosmo Windows 只虚拟 /dev/null、/dev/urandom、/dev/tty——加 /dev/zero：

`libc/intrin/fds.h` + `libc/calls/{open,fstatat,fstat,read,write,readv,writev,
readwrite,pread,printfds,ioctl,lseek}-nt.c`（open/fstat 加路径匹配、read 返回零、
lseek 返回 offset、ioctl 并入 einval、printfds 调试名 "kFdZero" 等）。

### 2. mac 自身路径根治（KERN_PROCARGS2, 1 文件）

`libc/calls/getprogramexecutablename.greg.c`：IsXnu 分支用
sysctl `{CTL_KERN, KERN_PROCARGS2, getpid()}` 取 exec 绝对路径，不依赖 argv[0]/`$_` 推断。
启动早期无 malloc，用 `static char xnu_buf[1<<18]`。

### 3. QuickEdit 鼠标保留（1 文件）

`libc/calls/tcsetattr-nt.c`：raw 模式下不再无条件关 QuickEdit（让 busybox sh 里鼠标选择/
粘贴可用）；真正要鼠标的程序会发 XT 序列由上游 InterceptTerminalCommands 让出。

### 4. 64K 页支持（2 文件）

- `ape/BUILD.mk`：loader 链接 `max-page-size=0x4000 → 0x10000`（64K 页内核可加载 loader）
- `tool/build/apelink.c`：aarch64 `pagesz = 16384 → 65536`（绝对化 phdr 64K 对齐，
  64K 页内核不再因不同余被 loader 拒）

> 说明：驱动包装脚本（`bin/*-cosmo-cc` 等）另有一处 64K 参数（PAGESZ/max-page-size），
> 属工具链组装层改动（见 `toolchain/build-custom.sh` assemble 步骤 3d），非源码补丁。

## 应用

```sh
# 权威方式 (toolchain/build-custom.sh 内部即用此)
cd cosmopolitan-3293fad* && patch -p1 < cosmo-custom-full.patch

# 旧式覆盖方式
cp -R master-snapshot/. <cosmo 源码树>/
```

## 历史教训

1. 单文件/单库替换必失败（头库常量语义不匹配 EEXIST 等）；必须"头+库+ape 全套"一致替换。
2. 头文件重建规则 = package.sh 的 `libc/isystem + libc/integral + o/cosmocc.h.txt`。
3. master 与 4.0.2/3.9.2 内部 API 不兼容 → 需如上从 master 源码整体构建 cosmopolitan.a。
