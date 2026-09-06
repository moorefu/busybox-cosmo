# 分发母本与运行副本

发布目录中的 APE 应视为只读母本。默认入口是同目录的 `busybox` launcher；它按平台和架构选择载荷，并在需要时把副本放入缓存后再转换或交给 loader。测试、同化和安装均不应直接改写归档中的唯一母本。

| 平台路径 | 母本写入 | 说明 |
|---|---|---|
| Windows `busybox.com` | 否 | PE 原生启动；名称保留 busybox |
| Linux binfmt + loader | 否 | 系统级配置，可支持嵌套 exec |
| Linux ARM64 裸 ELF | 否 | 64K 页场景的直接路径 |
| macOS/无 binfmt Linux launcher | 否 | 缓存副本、原生转换或显式 loader |
| 手工 `--assimilate` | 可能 | 只对临时副本操作；内置路径不跨平台等价 |

缓存优先级：

```text
BUSYBOX_COSMO_CACHE
XDG_CACHE_HOME/busybox-cosmo
用户默认缓存目录/busybox-cosmo
```

缓存键包含平台、架构和母本 SHA256；母本变化会生成新副本。launcher 使用目录锁和临时文件发布副本，但异常断电、陈旧锁、只读用户目录和并发冷启动仍需持续测试。macOS ARM64 还可能准备 `~/.ape-1.10`，因此“母本不改”不等于“零用户目录写入”。

Linux 的 `sudo ./busybox --setup-linux` 会安装 `/usr/bin/ape` 并注册 binfmt，属于明确的系统修改。普通运行不会自动执行这一步。

自检时先复制发布目录，并比较运行前后哈希：

```sh
before=$(sha256sum busybox.com)
BUSYBOX_COSMO_CACHE="$PWD/cache" ./busybox echo ok
after=$(sha256sum busybox.com)
test "$before" = "$after"
```

macOS 用 `shasum -a 256`。启动路径、loader argv 和自身定位仍属于 [ABI 契约](COSMO-ABI-CONTRACTS.md)；平台状态见[部署指南](DEPLOYMENT.md)与[测试指南](TESTING.md)。
