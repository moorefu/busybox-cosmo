#!/usr/bin/env bash
# ============================================================
# sign-macos.sh — macOS 代码签名 (Gatekeeper / Apple Silicon)
#   默认 ad-hoc 签名 ("-"): 免费、无需开发者账号, 满足 Apple Silicon
#   原生执行与本地运行; 若需对外分发免"右键打开"需 Developer ID +
#   notarization (见下方 --identity/环境变量说明), 那部分必须由证书持有者执行。
#
#   用法: scripts/sign-macos.sh [--identity ID] [文件...]
#   默认文件: dist 下所有 *.com / *.ape / assimilate (含 release/min/分层目录)
#   非 macOS 上运行会提示并退出 1。
#
#   Developer ID + 公证 (可选, 需要 Apple 开发者账号凭据):
#     scripts/sign-macos.sh --identity "Developer ID Application: <你的名字>" \
#       并设置 APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD 后再运行
#       xcrun notarytool submit --wait ...
#   (公证为分发环节, 需要证书私钥, 本项目 CI 不做公证)
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[ "$(uname -s)" = Darwin ] || {
  echo "[sign][错误] 仅 macOS 需要/支持 codesign (当前 $(uname -s)); ad-hoc 签名请到 mac 执行" >&2
  exit 1
}
command -v codesign >/dev/null 2>&1 || { echo "[sign][错误] 缺 codesign" >&2; exit 1; }

IDENTITY="-"   # ad-hoc
PATHS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --identity) IDENTITY="$2"; shift 2 ;;
    *) PATHS+=("$1"); shift ;;
  esac
done

if [ "${#PATHS[@]}" -eq 0 ]; then
  # 默认: dist 下的 APE/com 可执行 (含 dist/release、dist/min、dist/tools 等)
  while IFS= read -r -d '' f; do PATHS+=("$f"); done < <(
    find "$ROOT/dist" -maxdepth 4 -type f \( -name '*.com' -o -name '*.ape' -o -name 'assimilate' \) -print0
  )
fi
[ "${#PATHS[@]}" -gt 0 ] || { echo "[sign] 没有需要签名的文件"; exit 0; }

for f in "${PATHS[@]}"; do
  [ -f "$f" ] || { echo "[sign][跳过] 不存在: $f"; continue; }
  if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - --timestamp=none "$f"
  else
    codesign --force --sign "$IDENTITY" --timestamp "$f"
  fi
  codesign --verify "$f" || { echo "[sign][错误] 校验失败: $f" >&2; exit 1; }
  echo "[sign] ok: $f"
done

echo "[sign] 完成 (identity: $IDENTITY), 共 ${#PATHS[@]} 个文件"
echo "[sign] 分发说明: ad-hoc 仅满足本机/Apple Silicon 运行; 对外免警告分发需"
echo "[sign]           Developer ID + xcrun notarytool submit --wait (证书持有者执行)"
