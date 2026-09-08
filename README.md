# busybox-cosmo

基于 BusyBox 1.38.0 与定制 Cosmopolitan 的跨平台命令集，提供 ash、常用文件和文本工具，以及实验性的 Shell 兼容库。

同一套源码不等于各平台行为完全一致。Windows 使用 x86_64 PE；Linux/macOS 提供 x86_64 和 ARM64 路径。Windows ARM64 目前测试 x86_64 仿真，**不是原生 ARM64 版本**。功能边界见[已知限制](docs/KNOWN-LIMITATIONS.md)。

## 运行发布包

解压后，在发布目录中运行：

```sh
# Linux / macOS
./busybox ash your-script.sh
./busybox ash bbcosmo doctor
./busybox ash ash-contract.sh    # 完整包附带测试
```

Windows 使用 `busybox.com ash your-script.sh`。优先用包内 launcher 或明确的二进制路径，不依赖宿主 PATH 上同名工具。安装、缓存与 64K 页说明见[部署指南](docs/DEPLOYMENT.md)。

## 从源码构建

宿主需要 Bash、Python 3、make、C 编译器、patch、curl、tar、zip/unzip。完整工具链首次构建较慢。

```sh
toolchain/provision.sh build all
make build
scripts/package-release.sh          # dist/busybox-cosmo-release.zip
scripts/package-release.sh --min    # dist/busybox-min.zip
```

已有工具链可用 `toolchain/provision.sh copy /绝对路径` 导入。官方 cosmocc 下载模式不含本项目定制，不能替代发布工具链。[构建细节](docs/BUILD.md)

## 开发与测试

```sh
make check                         # 语法、补丁及维护脚本测试；无需重建
make fetch && make check           # 追加真实 BusyBox 补丁结果与生成文件验证
make test                          # 已有发布物：ash + deep + full + 兼容库
make test BUSYBOX=/绝对路径/busybox
```

CI 将同一份完整发布物分发到 Linux、macOS、Windows；macOS ARM64 和 Windows ARM64 仿真任务暂为非阻塞实验任务。CI 通过只代表已执行的用例通过，不覆盖所有 applet、终端或权限模型。[测试分层与证据](docs/TESTING.md)

## 文档与源码入口

- [文档索引](docs/README.md)：当前指南与历史记录分离。
- [架构](docs/ARCHITECTURE.md)：运行、工具链和兼容库的职责边界。
- [补丁维护](patches/README.md)：两个显式序列、来源和升级规则。
- [后续工作](docs/ROADMAP.md)：尚未解决的问题，不混入部署说明。
- `config/` 固定功能配置；`scripts/` 构建/发布；`lib/` 脚本库；`tests/` 行为与维护测试。

源码许可证及第三方归属见 [NOTICE.md](NOTICE.md)。发布包包含 BusyBox GPL 许可证；再分发仍需履行相应源码提供义务。
