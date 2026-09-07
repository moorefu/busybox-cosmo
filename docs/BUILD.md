# 构建指南

## 输入与产物

构建输入由四部分组成：SHA256 锁定的 BusyBox 1.38.0、[BusyBox 补丁序列](../patches/busybox/series)、`config/busybox-1.38.0.config`、定制 Cosmopolitan 工具链。取源优先访问 BusyBox 发布站，失败时访问保存同一 tarball 的 Buildroot 源码镜像；无论来自本地缓存还是网络，提取前都必须通过锁定的 SHA256 校验。

工具链为 cosmocc 4.0.2 驱动 + Cosmopolitan `3293fad0a9eac7865c019be98fb993eeb933405e` 源码及[工具链补丁序列](../patches/cosmo/series)。头文件、libc、crt、APE loader 和 apelink 必须配套；不能只替换单个库。[工具链流程](../toolchain/README.md)

## 命令

```sh
toolchain/provision.sh build all       # 首次准备工具链
make fetch                            # 下载并校验上游 BusyBox
make build                            # 两架构 ELF + APE + fat
scripts/package-release.sh            # 完整包
scripts/package-release.sh --min      # 最小包
make check
make test
```

`make x86_64`、`make aarch64` 可单独编译，`make fat` 组合已有的两架构 ELF。打包只组合已有构建结果，不执行编译。

## 工作树与补丁更新

`src/` 保存原版，`work/busybox-1.38.0-<arch>/` 保存构建树，`dist/` 保存输出。

补丁应用在暂存目录内完成，全部成功后才发布工作树；标志记录完整序列的内容和顺序指纹。缺标志、指纹过期或半成品均报错，**不会猜测“已经打过”、跳过失败补丁或删除旧工作树**。

旧 full/restore 工作树不能自动迁移。保留旧树，指定新目录：

```sh
BUSYBOX_WORK_DIR="$PWD/work/series-v1" make build
BUSYBOX_WORK_DIR="$PWD/work/series-v1" scripts/package-release.sh
```

构建与打包必须使用同一个目录变量。不要在生成树修改权威源码；修改对应补丁，并按[补丁维护指南](../patches/README.md)验证。

工具链旧源码标志也不再自动接受。升级序列前先将旧 `work/cosmopolitan-<commit>` 移到备份目录；构建脚本不会覆盖它。同一工作树不支持并发 prepare。

## 可复现性

固定 `SOURCE_DATE_EPOCH` 可固定 BusyBox 横幅时间；同时固定配置、补丁、工具链与构建路径。是否逐位一致应对两次独立构建的哈希做比较，不能仅凭设置时间戳推断。ZIP 文件时间和打包环境也需要单独验证。
