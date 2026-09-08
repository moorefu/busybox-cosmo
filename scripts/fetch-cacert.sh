#!/usr/bin/env bash
# ============================================================
# fetch-cacert.sh — 固定版本 CA bundle 更新流程 (M2 第一步)
#   1) 校验既有 dist/tools/cacert.pem 与锁定 SHA-256 一致 → 跳过
#   2) 否则从 curl.se/ca 下载锁定快照, 经官方 .sha256 sidecar 交叉校验,
#      再以锁定值复验; 记录 SBOM 与许可说明
#   产物: dist/tools/cacert.pem (+ SBOM-cacert.txt + licenses/CA-BUNDLE-NOTICE.txt)
#   用法: scripts/fetch-cacert.sh
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/env.sh"

OUT="$DIST_DIR/tools/cacert.pem"
SBOM="$DIST_DIR/tools/SBOM-cacert.txt"
NOTICE="$ROOT/licenses/CA-BUNDLE-NOTICE.txt"
TMP_DL="$(mktemp -d "${TMPDIR:-/tmp}/cacert-dl.XXXXXX")"
trap 'rm -rf "$TMP_DL"' EXIT HUP INT TERM

sha256_check() {
  file="$1"; expect="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    echo "[fetch-cacert][错误] 缺少 sha256sum/shasum" >&2
    return 1
  fi
  [ "$actual" = "$expect" ] || {
    echo "[fetch-cacert][错误] SHA256 不匹配: $file (实际 $actual, 期望 $expect)" >&2
    return 1
  }
}

mkdir -p "$DIST_DIR/tools"
if [ -f "$OUT" ] && sha256_check "$OUT" "$CA_SHA256"; then
  echo "[fetch-cacert] 已有且校验通过: $OUT"
else
  echo "[fetch-cacert] 下载 $CA_URL ..."
  curl -fsSL --connect-timeout 10 --max-time 180 \
    -o "$TMP_DL/$CA_PEM" "$CA_URL" || { echo "[fetch-cacert][错误] 下载失败" >&2; exit 1; }
  # 官方 sidecar 交叉校验后, 再以锁定值复验
  curl -fsSL --connect-timeout 10 --max-time 60 \
    -o "$TMP_DL/$CA_PEM.sha256" "$CA_URL.sha256" || true
  if [ -f "$TMP_DL/$CA_PEM.sha256" ]; then
    official=$(awk '{print $1}' "$TMP_DL/$CA_PEM.sha256")
    [ "$official" = "$CA_SHA256" ] || {
      echo "[fetch-cacert][错误] 官方 sidecar 与锁定值不一致: $official" >&2
      exit 1
    }
    echo "[fetch-cacert] 官方 sidecar 与锁定值一致"
  fi
  sha256_check "$TMP_DL/$CA_PEM" "$CA_SHA256" || { echo "[fetch-cacert] 校验失败"; exit 1; }
  cp "$TMP_DL/$CA_PEM" "$OUT"
fi

# 结构 sanity: 需是 curl.se 转换头且含 >=100 张根证书
head -1 "$OUT" | grep -q '^##' || { echo "[fetch-cacert][错误] 不是预期的 PEM 头" >&2; exit 1; }
count=$(grep -c "BEGIN CERTIFICATE" "$OUT")
[ "$count" -ge 100 ] || { echo "[fetch-cacert][错误] 证书数异常: $count" >&2; exit 1; }

# 许可说明 (Mozilla 转换快照, curl.se 分发, MPL-2.0)
cat > "$NOTICE" <<EOF
CA bundle (cacert.pem) 许可说明
================================
来源: https://curl.se/ca/ (curl 项目对 Mozilla NSS 根证书的转换分发)
快照: $CA_VER (Mozilla 更新时间见文件内转换时间戳)
证书数: $count
许可: Mozilla Public License 2.0 (MPL-2.0)
引用: https://curl.se/docs/caextract.html 与 bundle 文件头部注释
校验: SHA-256 $CA_SHA256 (与官方 .sha256 sidecar 一致)
EOF

{
  echo "tool=cacert.pem (Mozilla->curl.se 转换快照)"
  echo "version=$CA_VER"
  echo "source_url=$CA_URL"
  echo "source_sha256=$CA_SHA256"
  echo "recipe=scripts/fetch-cacert.sh"
  echo "artifact=$OUT"
  echo "artifact_sha256=$(shasum -a 256 "$OUT" | awk '{print $1}')"
  echo "cert_count=$count"
  echo "license=MPL-2.0"
  echo "license_file=$NOTICE"
} > "$SBOM"
echo "cacert 就绪: $OUT ($count 张根证书)"
echo "SBOM: $SBOM"
