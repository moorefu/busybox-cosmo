# toolchain — cosmopolitan 定制工具链

本目录负责工程所需的 **定制 cosmopolitan 工具链**:

```
toolchain/
├── provision.sh        # 就绪入口: copy | build | download
├── fetch-sources.sh    # 下载官方上游材料 (master@commit + cosmocc-3.9.2, sha 锁定)
├── build-custom.sh     # 从官方源码构建定制工具链 (x86_64/aarch64/all/assemble/verify)
├── cosmo/              # 就绪后的工具链 (gitignored, ~1.3G)
└── download/           # 官方材料缓存 (gitignored)
```

## 为什么是"定制"工具链

官方 cosmocc 在 Windows 上不虚拟 `/dev/zero`、mac 自身路径推断不可靠、aarch64 按 16K
对齐(64KB 页内核无法加载)等。历史工程 (2026-09) 针对 cosmo master 打入定制补丁并重编,
得到本工程依赖的工具链。定制内容见 `patches/cosmo/`(cosmo-custom-full.patch 17 文件 +
master-snapshot 覆盖形态 + README)。

工具链本质 = **cosmocc 3.9.2 编译驱动 + cosmo master 头文件/库 + 定制补丁**。
替换铁律: 头+库+链接件(ape.lds/ape*.o/crt)必须全套一致。

## 两种就绪方式

| 命令 | 速度 | 场景 |
|---|---|---|
| `toolchain/provision.sh copy [src]` | 秒级 | **开发默认**: 从既有已验工具链 APFS-clonefile 拷入 (默认 `/tmp/cosmopolitan-master/.cosmocc/3.9.2`) |
| `toolchain/provision.sh build [all]` | 数小时级 | **从官方源码可复现构建**: 下载→打补丁→make→组装→verify |
| `toolchain/provision.sh download` | 分钟级 | 官方 cosmocc 发行版直接落 toolchain/cosmo (⚠️ 无定制补丁, 仅诊断/基座) |

## 从官方源码构建 (fetch + build)

构建对象 = **官方 cosmopolitan 源码** + 本工程定制补丁; 编译驱动/GCC14 取官方
cosmocc-3.9.2 发行(驱动为 GCC/LLVM 发行物, 不与 libc 一起从源码自举; 与上游
`tool/cosmocc/package.sh` 同思路)。锁定:

| 材料 | 来源 | 校验 |
|---|---|---|
| cosmopolitan 源码 | github.com/jart/cosmopolitan @ `3293fad0` | sha256 `cde29083…` |
| cosmocc 3.9.2 | cosmo.zip | sha256 `f4ff13af…` (与 master Makefile pin 一致) |

流水线 (`build-custom.sh all`):

```
1. fetch-sources.sh        下载并 sha 校验两份官方材料
2. 解压基座 cosmocc-3.9.2 → work/cosmocc-392-base     (驱动)
3. 解压 master 源码 → work/cosmopolitan-<commit>
4. 打补丁 patches/cosmo/cosmo-custom-full.patch (17 文件) + 自动应用
   patches/cosmo/cosmo-*-extra.patch 附加定制(如 sethostname 三平台实现)
5. 源码树内自举: .cosmocc/3.9.2/bin/make MODE=x86_64|aarch64
   → o/<arch>/cosmopolitan.a + crt/ape 部件 + o/cosmocc.h.txt
   (系统 make 3.81 会被上游 Makefile 拒绝, 故用基座自带 make 4.4.1)
6. assemble: 基座 + 替换两架构 libcosmo.a/crt(+ x86_64 另加 crtfastmath/ape 全套)
   + include/ 整体重装为 master 头 (package.sh 规则, 已逐字节校验)
   + 驱动包装脚本 64K 页参数 → toolchain/cosmo
7. verify: 与参考 .cosmocc/3.9.2 关键文件逐字节比对
```

断点续跑: `KEEP_SRC=1` 保留源码/产物树, 重跑时自动跳过已完成 make;
`toolchain/build-custom.sh assemble` 只重组装; `verify` 只做对照。

## 验证工具链可用

```sh
toolchain/cosmo/bin/x86_64-unknown-cosmo-cc --version
# 然后 make build (busybox) + make smoke
```
