#!/usr/bin/env bash
# ============================================================
# notarize-macos.sh — Developer ID 签名 + Apple 公证封装 (对外分发用)
#
#   macOS 对外分发若希望免除 "无法验证开发者/来自互联网" 警告, 需要:
#     1) Developer ID 签名 (需你的开发者证书在钥匙串)
#     2) notarytool 公证 + stapler 附票
#   CI 不做也不持有你的凭据; 本脚本在你本机执行, 凭据走环境变量。
#
#   用法:
#     scripts/notarize-macos.sh [--identity "Developer ID Application: 名字"]
#                              [--file 文件] [--file 文件] ... [--check]
#   环境 (公证必需):
#     APPLE_ID             Apple 账号邮箱
#     APPLE_TEAM_ID        团队 ID (可空, 账号单团队时可省)
#     APPLE_APP_PASSWORD   Apple ID 专用 App 密码 (非登录密码)
#   --check: 只做前置检查 (身份/环境/工具), 不签名不上传
#
#   流程: 对每个文件做 Developer ID 签名 -> 打成 zip -> notarytool submit
#         --wait -> stapler staple -> stapler validate 校验
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[ "$(uname -s)" = Darwin ] || { echo "[notarize][错误] 公证仅能在 macOS 上执行" >&2; exit 1; }

IDENTITY="${DEV_ID_IDENTITY:-Developer ID Application}"
CHECK_ONLY=0
FILES=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --identity) IDENTITY="$2"; shift 2 ;;
    --check) CHECK_ONLY=1; shift ;;
    --file) FILES+=("$2"); shift 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

fail() { echo "[notarize][错误] $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "缺少 $1 (Xcode 命令行工具)"; }
need codesign; need xcrun; need ditto; need spctl

if [ "${#FILES[@]}" -eq 0 ]; then
  while IFS= read -r -d '' f; do FILES+=("$f"); done < <(
    find "$ROOT/dist" -maxdepth 4 -type f \( -name '*.com' -o -name '*.ape' -o -name '*.zip' \) -print0
  )
fi
[ "${#FILES[@]}" -gt 0 ] || { echo "[notarize] 没有文件"; exit 0; }

echo "[notarize] 前置检查 ..."
identity_ok=$(security find-identity -v -p codesigning 2>/dev/null | grep -c "$IDENTITY" || true)
[ "$identity_ok" -ge 1 ] || fail "钥匙串中找不到 Developer ID 身份: $IDENTITY (security find-identity -p codesigning)"
if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "[notarize] --check 通过: 身份存在, 工具齐全"
  echo "[notarize] 公证凭据: APPLE_ID=${APPLE_ID:+已设置} APPLE_TEAM_ID=${APPLE_TEAM_ID:+已设置} APPLE_APP_PASSWORD=${APPLE_APP_PASSWORD:+已设置}"
  exit 0
fi
[ -n "${APPLE_APP_PASSWORD:-}" ] || fail "缺 APPLE_APP_PASSWORD (Apple ID 专用密码); 另需 APPLE_ID/APPLE_TEAM_ID"
[ -n "${APPLE_ID:-}" ] || fail "缺 APPLE_ID"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/notarize.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

echo "[notarize] 1/4 Developer ID 签名 ..."
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "[notarize][跳过] 不存在: $f"; continue; }
  codesign --force --sign "$IDENTITY" --timestamp "$f"
  codesign --verify "$f" || fail "签名校验失败: $f"
  echo "[notarize]   已签名: $f"
done

echo "[notarize] 2/4 聚合打包 zip (公证扫描用) ..."
STAGE="$WORK/stage"
mkdir -p "$STAGE"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  cp "$f" "$STAGE/$(basename "$f")"
done
ZIP="$WORK/notarize-$(date +%s).zip"
ditto -c -k --keepParent "$STAGE" "$ZIP" || fail "打包失败"

echo "[notarize] 3/4 notarytool submit --wait (可能数分钟) ..."
notary_args=(xcrun notarytool submit "$ZIP" --wait --apple-id "$APPLE_ID")
[ -n "${APPLE_TEAM_ID:-}" ] && notary_args+=(--team-id "$APPLE_TEAM_ID")
notary_args+=(--password "$APPLE_APP_PASSWORD")
"${notary_args[@]}"

echo "[notarize] 4/4 stapler staple + validate ..."
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  xcrun stapler staple "$f" 2>/dev/null || true
  xcrun stapler validate "$f" || { echo "[notarize][警告] staple 校验未过: $f" >&2; }
  spctl -a -vv --type open "$f" 2>&1 | grep -q accepted || \
    { echo "[notarize][警告] spctl 未认可: $f (公测前请人工确认)" >&2; }
done
echo "[notarize] 完成。分发前请对每个文件跑 spctl -a -vv --type open <file> 确认 accepted"
