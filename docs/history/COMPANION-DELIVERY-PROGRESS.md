# 伴生工具交付进度档案（M0–M5）

本文件记录 docs/COMPANION-DELIVERY-PLAN.md 里程碑的执行状态与本地验证证据，
供交接与后续迭代核对。时间基准：2026-09 一轮多轮迭代后。

## 收尾快照（第 12 轮）

本地验证电池全绿：`make check`（25 单测）OK；`make qa-local` 4 节 21 项 PASS
（bbtty PTY / companion 契约 / curl.com HTTPS KAT / capabilities 门禁）；
分层包 archive/net 固定 `SOURCE_DATE_EPOCH` 下两次构建哈希一致。
后续里程碑推进仅剩外部条件项（见“已知剩余”），本地可复现交付已收口。

## 已完成并本地验证

| 里程碑 | 内容 | 证据 |
|---|---|---|
| M1 | xz 5.4.7、zip（Info-ZIP 3.0 + Debian 3.0-16）供应线 | `dist/tools/xz.com`/`zip.com`；`make companion-check` 契约含 deflate/权限/时间戳/Zip Slip/符号链接/错误路径 |
| M2 | curl 8.13.0 + mbedTLS 3.6.2 + cacert.pem(2026-08-13) | `make curl` rc=0；`tests/https-kat.py` 6/6 对 curl.com；实网 `bbp_https_get` 返回锁定 sha |
| M3 | zstd 1.5.7 供应线 | `dist/tools/zstd.com`；契约含往返与损坏输入 |
| M5 | busybox-archive / busybox-net 分层包 | `package-archive.sh`/`package-net.sh`；SOURCE_DATE_EPOCH 固定时两次构建哈希一致 |
| bbtty(M0 大部分) | Unix PTY 契约 + Windows Console 驱动 | `tests/bbtty-pty.py`（含 trap 恢复）；`tests/bbtty-console.py` 已入 windows-matrix |

## 供应线脚本（同一模式，可复现）

fetch/build 对：`fetch-xz.sh`/`build-xz.sh`、`fetch-zip.sh`/`build-zip.sh`、
`fetch-zstd.sh`/`build-zstd.sh`、`fetch-curl.sh`/`build-curl.sh`、`fetch-cacert.sh`。
统一要点：锁定版本+SHA-256；交叉 configure 用 `--host` 关运行期探测；静态库
`AR/RANLIB` 必须用 cosmo 归档器（macOS Xcode ar 会把 ELF 成员建成空壳库）；
产物 fat APE + `check-ape-64k.sh` + SBOM/license 归档。

## CI 接线（待提交推送后实跑取证）

- build job：复现构建 xz/zip/zstd/curl；上传 `busybox-tools` 与 `busybox-layers`；
- unix-matrix：bbtty PTY 契约、companion 契约（xz/zip/zstd）、HTTPS KAT（交付的
  curl.com）、capability gate；
- windows-matrix：bbtty capabilities 门禁 + 独立 Console 契约（`bbtty-console.py`）。

## 本地交付 QA 门禁（第 10 轮）

`scripts/qa-local.sh`（`make qa-local`）把 CI unix-matrix 关键步骤镜像成本地单命令：
1) bbtty 真实 PTY 契约 → 2) 伴生工具契约 (xz/zip/zstd) → 3) curl.com HTTPS KAT →
4) bbcosmo capabilities + capability gate。任一环节失败即非零退出；
本机整跑 4/4 全绿（macos/x86_64）。

## 已知剩余

- **CI 实跑证据**：build/unix-matrix/windows-matrix 步骤全部接线，需提交推送后由
  runner 产出（本地无法模拟）；`qa-local.sh` 提供可重复的本地镜像作为替代证据；
- M0 残项：Windows **ConPTY 会话创建**驱动（传统 Console 已覆盖）；
- M5 残项：`busybox-codec-extra`（lz4/brotli）按方案仅在真实需求出现后落地。

## 能力模型扩充（已落地，第 9 轮）

- 新增键：`archive.zstd.encode` / `archive.zstd.decode`（与 `.roundtrip` 并存）、
  `network.http.fetch=available|unavailable`；
- 每工具新增 `*.tool.version`（bundled/external 均尽力上报；zip 取 "This is Zip"
  行、xz/zstd/curl 取 `--version` 首行）；
- 契约同步：`tests/portable-contract.sh` 断言 encode/decode/fetch 键；本地 32 项全绿。
