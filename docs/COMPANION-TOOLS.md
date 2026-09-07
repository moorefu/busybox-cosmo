# 伴生工具与 bbtty

核心 BusyBox 保持单文件、离线和较小体积；格式编码、可信 HTTPS 与终端原始模式由
`tools/` 中的可选 APE 补齐。`bbcosmo capabilities --format kv` 是脚本判断能力的
唯一入口，不要根据操作系统名称或 applet 名称猜测。

## 发布顺序

| 阶段 | 组件 | 承诺 | 状态 |
|---|---|---|---|
| P0 | `zip`、`xz` | 创建与解压往返一致 | 供应线已落地：`xz` 5.4.7、`zip`(Info-ZIP 3.0 + Debian 3.0-16 安全补丁)，产物 `dist/tools/xz.com`/`zip.com`；深度契约 `tests/companion-tools.py` 覆盖 deflate/目录/权限/时间戳/Zip Slip(解码端剥离 `../` 不逃逸)/符号链接/错误路径，本机全绿；CI 复现与契约步骤已接入，待实跑 |
| P1 | `curl`、`cacert.pem` | HTTPS 强制证书校验 | 已闭环：CA 固定流程（`fetch-cacert.sh`，2026-08-13 快照）；curl.com 供应线落地（`fetch-curl.sh`+`build-curl.sh`，curl 8.13.0 + **mbedTLS 3.6.2** TLS 后端 → `dist/tools/curl.com`）；本地 TLS KAT `tests/https-kat.py` 六组全绿 + 实网拉取验证；`bbp_https_get` 带 `--proto-redir '=https'`；CI 用交付 curl.com 跑 KAT |
| P1 | `zstd` | 创建与解压往返一致，推荐新归档使用 | 供应线已落地（`scripts/fetch-zstd.sh`+`build-zstd.sh`，v1.5.7 → `dist/tools/zstd.com` + SBOM/license），往返/损坏输入契约入 `tests/companion-tools.py`（`--zstd`），能力上报 `archive.zstd.roundtrip=bundled`；本机全绿 |
| 按需 | `lz4`、`brotli` | 仅真实项目需要时发布 | 只预留发现接口，不进入默认包 |
| 自有 | `bbtty` | `size/save/raw/restore` | Unix PTY 与 Windows Console 驱动已接入 CI；Windows 实机结果及 ConPTY 验收待完成 |

不从 `https://cosmo.zip/pub/cosmos/bin/` 的滚动目录直接装入正式发布物。正式工具必须
能追溯到固定版本或提交、记录 SHA-256 和许可证，并在 CI 中从源码复现。Cosmos
4.0.2 的版本目录可作为交叉测试基线，但其中没有 `xz`，不能独立满足 P0。

## macOS 签名

macOS（尤其 Apple Silicon 原生执行与 Gatekeeper）要求可执行文件带代码签名。
交付物默认未签名；本机/契约前用 ad-hoc 签名即可运行：

```sh
make sign-macos            # 或 scripts/sign-macos.sh [--identity ID] [文件...]
```

- ad-hoc（`-`）免费、无需开发者账号，`codesign --force --sign - --timestamp=none`；
- CI：unix-matrix 的 macOS runner 会在跑契约前对 `release/` 与 `companion-tools/` 下的
  `*.com/*.ape/assimilate` 做 ad-hoc 签名；
- 对外分发若要免「右键打开」警告，需证书持有者做 Developer ID 签名并公证
  （`scripts/sign-macos.sh --identity "Developer ID Application: …"` 后再
  `xcrun notarytool submit --wait`，需 Apple 开发者凭据，CI 不做公证）；
- 分层包 zip 保持未签名以维持逐位可复现，解压后先跑 `make sign-macos`（或对解压目录
  执行 `scripts/sign-macos.sh`）再运行。

## 运行时规则

默认查找顺序是：显式 `BBP_*` 绝对路径、发行包 `tools/`、宿主 `PATH`。显式路径
无效时立即失败，避免在不同机器上静默使用另一实现。

```sh
BBP_BUSYBOX=./busybox
. ./lib/portable.sh

bbp_xz_encode_available || exit 3
bbp_zip_encode_available || exit 3
bbp_zstd_available || printf '%s\n' 'zstd 未安装' >&2
bbp_https_get https://example.com/data.json data.json
```

可信下载只接受 `https://`，强制 `--proto '=https'`、TLS 1.2 及以上、CA 校验，且
没有 `-k` 逃生口。CA 文件通过 `BBP_CA_BUNDLE` 或 `tools/cacert.pem` 提供。
`configured` 仅表示 curl/CA 本地配置完整；正式发布还必须通过联网 KAT，包括有效
证书成功、无效证书失败和重定向不降级到 HTTP。

## bbtty 协议

```sh
token=$(./tools/bbtty.com raw) || exit
trap './tools/bbtty.com restore "$token"' 0 1 2 3 15
# TUI 主循环
```

Windows 后端直接读写 ConsoleMode，并启用虚拟终端输入/输出（不触碰 Quick Edit/
鼠标等扩展位，改动留待 restore 逐位还原；代码页两个方向都恢复，避免 wstty `cp`
输入代码页早退的同类缺陷）；Unix 后端调用 `tcgetattr`、`cfmakeraw`、`tcsetattr`，
`VMIN/VTIME` 取 Cosmopolitan 运行时常量（Linux=6/5，macOS/BSD=16/17）。

状态令牌包含版本、后端和终端身份：Unix 令牌绑定 `fstat(0).st_rdev`，restore 时
标准输入不是终端（rc=1）或设备与令牌不一致（rc=2）都拒绝且不改动任何状态；
Windows 令牌要求输入仍是 Console/ConPTY 才恢复。令牌只保证同一台主机、同一终端
会话内有效，不是 POSIX `stty` 的替代品，也不会接受 `stty -g` 的令牌。

Unix 真实 PTY 契约见 `tests/bbtty-pty.py`（`make bbtty-check`，CI unix-matrix
执行）：尺寸非零、save→restore 逐位还原、raw 关闭 echo/canonical 且同终端
restore 还原、跨终端 restore 拒绝且无副作用、管道重定向明确失败。macOS/BSD 的
`PENDIN(0x20000000)` 是内核在模式迁移时置上、用户态无法清除的托管状态位，契约
按掩码比较（不是 bbtty 丢失状态）。Windows 的 ConPTY/传统 Console 行为一致验证
仍待完成；传统 Console 驱动 `tests/bbtty-console.py` 已接入两个 Windows runner，
验证尺寸、模式/代码页往返、无输出令牌恢复与损坏令牌拒绝，待实机结果。
两类终端日志均随 CI artifact 保存。wstty 只作为行为参考，不作为依赖。

令牌不是跨会话身份凭证：Unix 设备号关闭后可能复用，Windows 尚未绑定会话
身份；调用者只能在原终端会话内短期使用。Unix 驱动包含 SIGTERM/EXIT trap
恢复用例；Windows 异常退出恢复与 ConPTY 输入字节流仍需单独验收。
