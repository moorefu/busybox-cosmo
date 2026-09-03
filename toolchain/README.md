# toolchain — cosmopolitan 定制工具链

本目录负责工程所需的 **定制 cosmopolitan 工具链**:

```
toolchain/
├── provision.sh      # 就绪入口: copy | download | build
├── build-custom.sh   # 从 cosmo master 源码完整构建 (数小时)
├── cosmo/            # 就绪后的工具链 (gitignored, ~1.3G)
└── download/         # 下载缓存 (gitignored)
```

## 为什么是"定制"工具链

官方 cosmocc 在 Windows 上不虚拟 `/dev/zero`、mac 自身路径推断不可靠等。
历史工程 (2026-09) 针对 cosmo master 打入 5 个 libc 补丁并重编, 得到本工程依赖的工具链:

- `/dev/zero` Windows 虚拟 (kFdDevZero)
- mac 自身路径根治 (KERN_PROCARGS2)
- QuickEdit 鼠标保留 (tcsetattr)
- 64K 页链接/loader 对齐
- (详见 `patches/cosmo/README.md`)

工具链本质 = **cosmocc 3.9.2 编译驱动 + cosmo master 头文件/库 + 5 补丁**。
替换铁律: 头+库+链接件(ape.lds/ape*.o/crt)必须全套一致。

## 就绪方式

| 命令 | 速度 | 场景 |
|---|---|---|
| `toolchain/provision.sh copy [src]` | 秒级 | **默认推荐**: 从既有已验工具链 APFS-clonefile 拷入 (默认 `/tmp/cosmopolitan-master/.cosmocc/3.9.2`) |
| `toolchain/provision.sh download` | 分钟级 | 官方 cosmocc 发行版 (无定制补丁, 仅链路自测/降级) |
| `toolchain/provision.sh build` | 小时级 | 从 master 源码 + `patches/cosmo` 完整重建 (最大可复现性) |

构建/打包脚本通过 `scripts/env.sh` 定位工具链: 默认 `toolchain/cosmo`, 可用环境变量 `COSMO=/path` 覆盖。

## 验证工具链可用

```sh
toolchain/cosmo/bin/x86_64-unknown-cosmo-cc --version
toolchain/cosmo/bin/apelink -o /tmp/h.com <(echo 'int main(){return 42;}')  # 见 BUILD.md
```
