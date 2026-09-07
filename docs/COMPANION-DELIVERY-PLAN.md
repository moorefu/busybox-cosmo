# 伴生工具交付方案（busybox-archive / busybox-net / bbtty）

状态：方案稿。落笔前先对齐范围、供应线、发布形态与验收标准；实现按 M0–M5 里程碑推进，
每步有明确“完成标准”与可复核证据。本文件是 [COMPANION-TOOLS.md](COMPANION-TOOLS.md)
的工程执行方案，不替代其运行时协议。

## 1. 目标与边界

目标：把 `zip`、`xz`、`curl(+CA)`、`zstd` 变成“固定源码自建 + 可选伴生包 + 行为探测”的
可复现能力；`bbtty` 与其并行完善；`lz4`/`brotli` 只在真实需求出现后启动。

明确不做（对应已确认的产品判断）：

- 不把这些工具的源码揉进 BusyBox 补丁（避免补丁膨胀、升级冲突、单工具安全更新连带重发
  BusyBox、以及 `FEATURE_PREFER_APPLETS` 遮蔽）；
- 不从 `https://cosmo.zip/pub/cosmos/bin/` 滚动目录直接装入正式发布物（该目录已出现
  “此前存在的 `xz` 消失”的情况，不可作为稳定依赖源）；
- 不捆绑外部 `stty` 替代 BusyBox `stty`/底层 termios 任务。

## 2. 供应线（每个伴生工具统一走五步）

1. **取源锁定**：固定版本 tarball/提交 + `*_SHA256` 常量；先校验后解包。镜像源只作为
   备用通道，信任依据仍是 SHA-256（对齐 `scripts/fetch-busybox.sh` 的做法）。
2. **许可归档**：源内 license 文件复制进 `licenses/<tool>/`，NOTICE 汇总；GPL 系工具
   （如 lz4 CLI）单独说明分发条件。
3. **构建配方**：新增 `scripts/build-<tool>.sh`，模板即 `scripts/build-bbtty.sh`
   （双架构 cosmocc → `apelink` 合成 fat APE → `check-ape-64k.sh` 自检）。产物进
   `dist/tools/<tool>.com`。
4. **行为冒烟**：真实往返测试（编码→解码→字节一致），失败必须显式报错而不是静默降级。
5. **SBOM/可复现**：每次构建记录 来源 URL、版本、源码 SHA-256、构建配方提交、产物
   SHA-256；`SOURCE_DATE_EPOCH` 固定时可逐位复现。

CI：从源码复现构建、记录产物哈希，与本地/双工作目录构建对照；上传证据 artifact。

### 候选版本与许可（M1 开工时以实际索引复核，滚动目录不作依据）

| 工具 | 候选基线 | 许可 | 备注 |
|---|---|---|---|
| `zip` | Info-ZIP zip 3.0 + 发行版安全补丁快照 | Info-ZIP（BSD 类） | 只需创建；解码继续用 BusyBox 内建 `unzip` |
| `xz` | 5.4 LTS 线（避 5.6.0/5.6.1 后门事件）或 5.6.2+ | 公有领域/0BSD | 注意 2024-3094 教训，取源与构建脚本必须校验且可复核 |
| `zstd` | 1.5.x 稳定线 | BSD-3-Clause 或 GPLv2 双许可 | BusyBox `tar` 无 `--zstd` 路由，需管道或用 `tar --use-compress-program` |
| `curl` | 8.x 稳定线 | curl（MIT 派生） | CA bundle 单独固定 |
| `cacert.pem` | curl.se/ca 固定版本（Mozilla 源） | 见 CA 更新流程 | 不进默认包、进 net 包 |
| `lz4` | 仅预留 | 库 BSD-2，**CLI GPLv2**（分发条件单独核对） | 需求出现后再锁定版本 |
| `brotli` | 仅预留 | MIT | 数据流格式，无归档元数据/完整性校验 |
| `bbtty` | 自有（本仓库） | 本仓库许可 | 不依赖上游 |

## 3. 发布形态与兼容层

目标目录（对齐既有 `bbcosmo`/`portable.sh` 的解析协议，无需新机制）：

```text
release/
├── busybox.com / busybox / bbcosmo / lib/
└── tools/
    ├── bbtty.com      # 终端助手（本轮已入包）
    ├── zip.com  xz.com  zstd.com      # 将来：archive 伴生包
    ├── curl.com                       # 将来：net 伴生包
    └── cacert.pem                     # 将来：net 伴生包
```

- 兼容层已实现「显式绝对路径(无效即失败) → 包内 `tools/` → 宿主 PATH」；
  不依赖 `command -v <tool>`（BusyBox 仅解码 applet 会遮蔽外部编码器）。
- 分层发布包（`busybox-archive`/`busybox-net`/`busybox-codec-extra`）在 M5 引入，
  与现有单包并存，不改变当前 min/full 交付。

## 4. 能力模型扩充（对齐运行时协议，不改 schema=1 键前缀）

在现有键基础上新增/拆分，沿用来源桶 `builtin|bundled|external|unavailable|unsupported`：

| 键 | 语义 | 现状 |
|---|---|---|
| `archive.zstd.encode` / `.decode` | 从合并的 `.roundtrip` 拆出（BusyBox 无 zstd applet → 双向均走伴生/外部） | 待拆 |
| `archive.lz4.encode/decode`、`archive.brotli.encode/decode` | 仅“发现接口”，缺省 unavailable | 待加 |
| `net.http.fetch` | 可执行强制证书校验的 HTTPS 下载 | 待加（`bbp_https_get` 已具备行为） |
| `net.proxy` / `net.resume` | 仅当 curl 伴生包落地后上报 | 待加 |
| `tty.raw` / `tty.restore` | 由 `bbtty` 支撑；`tty.signal`/`tty.conpty` 待 Windows 驱动 | 部分 |
| 每工具元数据 | `.tool`(绝对路径) 已有；补 `.version`、`.source_sha256`、`.roundtrip=ok/fail/na` | 待加 |

门禁同步：`tests/ci-capability-gate.py` 与 `tests/test_ci_capability_gate.py` 是封闭清单，
每加一类键都要同步两处并有对应正/反例（沿用本轮 zstd/https 的改法）。

## 5. 里程碑与验收

| 里程碑 | 内容 | 完成标准（可复核证据） |
|---|---|---|
| M0 | bbtty 收尾 | Unix 同一 PTY 往返 + SIGTERM/EXIT trap 恢复本机通过；独立 Windows Console 驱动（`tests/bbtty-console.py`）已接入 windows-matrix，待实机结果；ConPTY 会话创建待做 |
| M1 | `zip+xz` 锁定自建（P0） | xz 5.4.7 与 zip（Info-ZIP 3.0 + Debian 3.0-16 安全补丁快照）供应线均已落地：`scripts/fetch-xz.sh`/`build-xz.sh`、`fetch-zip.sh`/`build-zip.sh` → `dist/tools/xz.com`/`zip.com`；深度契约 `tests/companion-tools.py`（`make companion-check`）覆盖 deflate/目录/权限/时间戳/Zip Slip/符号链接/错误路径，本机全绿；CI 复现 + unix-matrix 契约步骤已接入，待提交推送后实跑取证 |

zip 决策点已落：采用 Debian 维护的 3.0-16「原包+补丁」快照（含 unicode 溢出/CVE-2018-13410/
符号链接/命令注入修复）；zip 3.0 内置 deflate、无 configure、不依赖 zlib（发行版同样如此），
bzip2 方法不启用。

curl TLS 后端选型（M2 待办决策点，开工前评审）：已核实 cosmo 工具链**无 openssl/zlib**
（`toolchain/cosmo/**/lib` 无 libssl/libcrypto/libz，include 无对应头）。候选：
wolfSSL（autotools 交叉模式，类似 xz 的 `--host` 方案已在本工程验证可行）或 mbedTLS
（自带 Makefile/无 autotools，需 `--with-mbedtls` 接 curl）。curl 以 `--without-zlib`
构建即可满足 HTTPS 身份/内容获取（HTTP 压缩解码非 M2 承诺）。KAT 已按“同一参数集可替换
被测 curl”设计，curl.com 落地后直接以 `python3 tests/https-kat.py dist/tools/curl.com`
复跑即闭环。

M1-xz 交叉构建已踩并记录的坑（zip/zstd/curl 复用）：(a) macOS 宿主跑不了 cosmo 的 Linux ELF
探针，configure 必须用 `--host=` 交叉模式关闭运行期探测；(b) cosmo 库内含 `pledge` 符号但头文件
无声明，xz 需 `--enable-sandbox=no`；(c) 静态库必须用 `x86_64|aarch64-linux-cosmo-ar/ranlib`，
Xcode `ar` 会把 ELF 成员建成空壳库。
| M2 | `curl+CA`（P1） | 已闭环：CA 固定流程（`fetch-cacert.sh`，2026-08-13 + 官方 sidecar 交叉校验）；curl.com 供应线 `fetch-curl.sh`+`build-curl.sh`（curl 8.13.0 + **mbedTLS 3.6.2**，`--with-mbedtls` 静态链，`--without-zlib`）；本地 TLS KAT 六组对 **curl.com** 全绿（含 `--proto-redir '=https'` 不降级）；实网 `https://curl.se` + 锁定 CA 端到端取回正确 sha；CI：build job 复现 `make curl`，unix-matrix 用交付 curl.com 跑 KAT |
| M3 | `zstd`（P1） | 供应线已落地（`scripts/fetch-zstd.sh`+`build-zstd.sh`：v1.5.7 → `dist/tools/zstd.com`，SBOM/license/往返冒烟）；契约并入 `tests/companion-tools.py --zstd`；CI 复现与 unix-matrix 契约已接线。顺序说明：因 M2 的 curl.com 依赖 TLS 后端选型（cosmo 无 openssl/zlib），zstd 先行落地，curl 保留为下一块 |
| M4 | `lz4`/`brotli` 预留 | 只保留发现接口与许可核对结论；不建构建配方、不进默认包 |
| M5 | 分层打包与发布矩阵 | `busybox-archive`（`package-archive.sh`：busybox+xz/zip/zstd）与 `busybox-net`（`package-net.sh`：busybox+curl.com+cacert.pem）均已落地并**逐位可复现**（SOURCE_DATE_EPOCH 固定，两次构建哈希一致实测）；net 包包内自检含实网可信拉取；`busybox-codec-extra`（需 lz4/brotli）待对应工具落地；六 runner 契约与产物哈希对照沿用 M1–M3 接线 |

依赖关系：M1 不依赖 M0；M2 的 CA/KAT 可并行于 M1 的 zip 侧；M3 依赖 M1 的供应线模板
成熟；M4/M5 靠后。

## 6. 风险与依赖

- **xz 上游安全历史**：取源、构建、冒烟全链路必须可复核；优先 LTS 线，避免滚动取新。
- **curl 构建**：需验证 cosmocc 下 TLS/CA/代理特性开关与体积预算（约 12 MiB 量级），
  不与 BusyBox 内建 wget 补丁继续扩张混在一起。
- **Info-ZIP zip 维护停滞**：选发行版带安全补丁的快照；若不成立，备选方案为自建 zip
  写入器或重新评估（M1 决策点）。
- **Windows 验证成本最高**：ConPTY 驱动（会话创建、句柄清理、超时防死锁）单列，投入前
  先出“可运行但受控”的最小驱动。
- **体积预算**：全部捆绑会让发布物接近 3–4 倍，因此默认包保持现状，伴生包按需安装。

## 7. 实施原则（沿用项目既有约定）

先写能暴露错误的行为测试，再改对应层；平台“不支持”应是可查询结果而非静默 fallback；
缺 PTY/网络等基础设施只能记为“条件不足”，不能记为 PASS。
