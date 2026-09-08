# 定制工具链

工具链 = cosmocc 4.0.2 编译驱动 + 锁定的 Cosmopolitan 源码 + [补丁序列](../patches/cosmo/series)。具体哈希由 `fetch-sources.sh` 锁定。

| 命令 | 用途 |
|---|---|
| `provision.sh build all` | 下载校验、构建两架构、组装、验证 |
| `provision.sh copy /绝对路径` | 复用已经验证的定制工具链 |
| `provision.sh download` | 下载官方驱动作诊断；不具备本项目 libc 定制 |
| `build-custom.sh assemble` | 使用已有源码产物重新组装 |
| `build-custom.sh verify` | 校验与参考工具链的关键内容 |

源码锁定 `3293fad0a9eac7865c019be98fb993eeb933405e`。源码树内 `.cosmocc/3.9.2` 是上游固定目录名，实际驱动内容默认为 4.0.2。

## 构建顺序

1. 校验并解压官方驱动基座。
2. 在暂存树应用 `patches/cosmo/series`，记录序列/源码/驱动指纹。
3. 用基座 GNU make 构建两架构 libc、crt、APE loader，以及定制 apelink。
4. 整体安装头文件、库和链接件；组装驱动的 64K 页参数。
5. 验证入口与关键产物，再构建 BusyBox 并运行平台测试。

`work/` 保存源码和中间产物，`toolchain/download/` 缓存下载，`toolchain/cosmo/` 是最终工具链。旧源码树的空标志不再被自动接受：先将旧树移至备份路径，再重建。不要用过时 snapshot 覆盖源码，或混用不同版本的头、库、loader。

环境变量与详细命令见 `build-custom.sh` 文件头。首次构建需要较长时间；CI 按补丁、脚本指纹缓存最终工具链，但缓存命中不代表功能已验证。
