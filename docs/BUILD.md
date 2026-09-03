# BUILD — 构建原理与手工等价命令

## 一、全景

```
busybox-1.38.0 官方源码 (src/, 脚本取源, sha256 锁定)
  + patches/busybox-cosmo-full.patch (82 文件 cosmo 适配)
  + config/busybox-1.38.0.config     (裁剪 ~320 applet, STANDALONE+PREFER_APPLETS)
  + 定制 cosmopolitan 工具链          (toolchain/cosmo, 含 5 个 libc 补丁)
  → make → busybox_unstripped (ELF)
  → apelink → busybox-<arch>.ape / busybox-fat.ape
```

## 二、工具链 (toolchain/cosmo)

本工程依赖"定制工具链": **cosmocc 编译驱动(默认 v4.0.2) + cosmo master 头文件/库 + 定制补丁**。
工具链层补丁清单见 `patches/cosmo/README.md`；历史教训：头+库+链接件必须全套一致。

三种就绪方式 (`toolchain/provision.sh`)：

| 模式 | 速度 | 说明 |
|---|---|---|
| `copy [src]` | 秒级 | 从既有已验工具链目录 APFS-clonefile 拷入 (默认 `/tmp/cosmopolitan-master/.cosmocc/3.9.2`) |
| `download` | 分钟级 | 官方 cosmocc (cosmo.zip) — **无定制补丁**, 仅作链路自测 |
| `build` | 小时级 | `build-custom.sh`: master 源码 + `patches/cosmo/master-snapshot` 覆盖 → make → 组装 |

## 三、关键配置 (config/busybox-1.38.0.config)

```
CONFIG_FEATURE_SH_STANDALONE=y     # ash 内建 applet 查找 (Windows 无符号链接 farm)
CONFIG_FEATURE_PREFER_APPLETS=y    # spawn 兄弟 applet 走 applet (对齐 busybox-w32)
CONFIG_FEATURE_WGET_HTTPS=y        # 内置 TLS (wget https)
CONFIG_FEATURE_WGET_OPENSSL=y      # 保留, cosmo 下编译期跳过 helper (补丁)
CONFIG_LAST_SUPPORTED_WCHAR=40959  # 中文等宽字符正常 (原 767 会变 ?)
CONFIG_UNICODE_WIDE_WCHARS=y       # 宽字符 (中文输入回显)
```

## 四、脚本流程

| 脚本 | 作用 |
|---|---|
| `scripts/fetch-busybox.sh` | 取 busybox-1.38.0 官方 tarball → `src/`, sha256 校验 (`34f9ea6f…`) |
| `scripts/prepare-worktree.sh <arch>` | 原版 → `work/busybox-1.38.0-<arch>/`, 打补丁(幂等)、放 .config |
| `scripts/build-ape.sh {x86_64,aarch64,fat,all}` | make + apelink → `dist/*.ape` |
| `scripts/package-release.sh` | 组装 `dist/release/` + zip (复刻历史发布包布局) |

手工等价命令 (x86_64)：

```sh
TC=toolchain/cosmo
cd work/busybox-1.38.0-x86_64        # prepare-worktree 产物
make -j10 CC=$TC/bin/x86_64-unknown-cosmo-cc \
          LD=$TC/bin/x86_64-linux-cosmo-gcc \
          AR=$TC/bin/x86_64-linux-cosmo-ar \
          STRIP=$TC/bin/x86_64-linux-cosmo-strip
$TC/bin/apelink -o ../../dist/busybox-x86_64.ape busybox_unstripped
```

## 五、可复现性

busybox 版本横幅含编译时刻 (`AUTOCONF_TIMESTAMP`, 由 kconfig 生成)。两种处理：

```sh
# A. 固定时间戳 (推荐, 逐位可复现)
SOURCE_DATE_EPOCH=$(date +%s) scripts/build-ape.sh x86_64
# 相同 SOURCE_DATE_EPOCH + 相同源/补丁/配置/工具链 → busybox_unstripped md5 一致

# B. 忽略横幅时刻 (产物 md5 每次不同, 功能等价)
```

本工程在 2026-09 已验证: 同 epoch 两次独立构建 `busybox_unstripped` 逐位一致 (见
docs/VERIFICATION-MATRIX.md)。除横幅外, 全量 `.o` 与历史已验证产物逐字节相同。

## 六、验证

```sh
# 本地 (mac/Linux) — 副本先行 (APE 首跑会同化改写)
cp dist/release/release/busybox.com /tmp/t/ && cd /tmp/t
./busybox.com sh smoke.sh          # 期望 44/46 (mac: ps 视环境, [win] 项平台预期)

# Windows — 冒烟分发包
smoke-test.bat                     # 期望 46/46

# Linux 容器 (勿直接挂载产物目录, 先拷入)
podman run --rm -v $PWD/dist/release/release:/work:Z docker.io/library/alpine:latest sh -c \
  'mkdir /t && cp /work/busybox.com /t/ && cp /work/smoke.sh /t/ && cd /t && ./busybox.com sh smoke.sh'
```
