#!/usr/bin/env bash
# ============================================================
# package-net.sh — busybox-net 分层伴生包 (M5 部分, 可复现)
#   组成: 最小运行层 (busybox.com fat + busybox 入口 + bbcosmo/lib) +
#         可信下载 tools/curl.com + tools/cacert.pem + SBOM/许可 + MANIFEST
#   前置: make build + make curl + make cacert
#   产出: dist/busybox-net.zip (+ .sha256)
#   说明: codec-extra 包(lz4/brotli)在对应工具落地前不产出。
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/env.sh"

OUT_DIR="$DIST_DIR/net"
OUT_ZIP="$DIST_DIR/busybox-net.zip"
FAT="$DIST_DIR/busybox-fat.ape"

[ -f "$FAT" ] || die "缺 dist/busybox-fat.ape, 先 make build"
[ -f "$DIST_DIR/tools/curl.com" ] || die "缺 dist/tools/curl.com, 先 make curl"
[ -f "$DIST_DIR/tools/cacert.pem" ] || die "缺 dist/tools/cacert.pem, 先 make cacert"

rm -rf "$OUT_DIR" && mkdir -p "$OUT_DIR/tools" "$OUT_DIR/lib" "$OUT_DIR/examples" "$OUT_DIR/licenses"

# ---- 运行层 (对齐 --min 包形态) ----
cp "$ROOT/scripts/bb.sh" "$OUT_DIR/busybox" && chmod 755 "$OUT_DIR/busybox"
cp "$FAT" "$OUT_DIR/busybox.com" && chmod 755 "$OUT_DIR/busybox.com"
cp "$ROOT/scripts/bbcosmo" "$OUT_DIR/bbcosmo" && chmod 755 "$OUT_DIR/bbcosmo"
cp "$ROOT/lib/portable.sh" "$OUT_DIR/lib/portable.sh"
cp "$ROOT/examples/portable-menu.sh" "$OUT_DIR/examples/" && chmod 755 "$OUT_DIR/examples/portable-menu.sh"

# ---- 可信下载组件 ----
cp "$DIST_DIR/tools/curl.com" "$OUT_DIR/tools/curl.com" && chmod 755 "$OUT_DIR/tools/curl.com"
cp "$DIST_DIR/tools/cacert.pem" "$OUT_DIR/tools/cacert.pem" && chmod 644 "$OUT_DIR/tools/cacert.pem"
for sbom in SBOM-curl.txt SBOM-cacert.txt; do
  [ -f "$DIST_DIR/tools/$sbom" ] && cp "$DIST_DIR/tools/$sbom" "$OUT_DIR/tools/"
done
cp "$ROOT/NOTICE.md" "$OUT_DIR/NOTICE.md"
for lic in BUSYBOX-GPL-2.0.txt CURL-LICENSE.txt MBEDTLS-APACHE-2.0.txt CA-BUNDLE-NOTICE.txt; do
  [ -f "$ROOT/licenses/$lic" ] && cp "$ROOT/licenses/$lic" "$OUT_DIR/licenses/"
done
cp "$ROOT/docs/COMPANION-TOOLS.md" "$OUT_DIR/COMPANION-TOOLS.md"
cp "$ROOT/docs/COMPANION-DELIVERY-PLAN.md" "$OUT_DIR/COMPANION-DELIVERY-PLAN.md"

# ---- README ----
cat > "$OUT_DIR/README.txt" <<EOF
busybox-net 伴生包 (busybox + curl.com + cacert.pem)

Linux/macOS: ./busybox ash script.sh    Windows: busybox.com ash script.sh
可信下载: tools/curl.com + tools/cacert.pem
脚本接口: BBP_BUSYBOX/BBP_CURL/BBP_CA_BUNDLE 指向本包对应文件后,
          bbp_https_get 强制 https + 证书校验 (见 lib/portable.sh)。

本包不含归档工具(archive 包)与 lz4/brotli(codec-extra); 见 COMPANION-TOOLS.md。
EOF

# ---- MANIFEST (sha256) ----
(
  cd "$OUT_DIR"
  find . -type f | sort | while read -r f; do
    case "$f" in ./MANIFEST.txt) continue ;; esac
    shasum -a 256 "$f" | sed "s|  \./|  |"
  done
) > "$OUT_DIR/MANIFEST.txt"

# ---- 打包 (SOURCE_DATE_EPOCH 固定: 归一 mtime + 排序条目 → 逐位可复现) ----
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  export SOURCE_DATE_EPOCH
  if date --version >/dev/null 2>&1; then
    stamp="$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%d%H%M.%S)"
  else
    stamp="$(date -u -r "$SOURCE_DATE_EPOCH" +%Y%m%d%H%M.%S)"
  fi
  find "$OUT_DIR" -type f -exec touch -h -t "$stamp" {} +
fi
rm -f "$OUT_ZIP"
( cd "$OUT_DIR" && find . -type f | sort | zip -X -q "$OUT_ZIP" -@ )
shasum -a 256 "$OUT_ZIP" > "$OUT_ZIP.sha256"

# ---- 校验: 解压后入口与可信下载组件可执行/存在 ----
CHECK="$(mktemp -d "${TMPDIR:-/tmp}/net-check.XXXXXX")"
trap 'rm -rf "$CHECK"' EXIT HUP INT TERM
unzip -q "$OUT_ZIP" -d "$CHECK"
(
  cd "$CHECK"
  HOME="$CHECK" BUSYBOX_COSMO_CACHE="$CHECK/cache" ./busybox uname -m >/dev/null || die "入口不可执行"
  ./tools/curl.com --version | grep -q mbedTLS || die "curl.com 缺 mbedTLS 后端"
  [ -s tools/cacert.pem ] || die "cacert.pem 为空"
  grep -q 'BEGIN CERTIFICATE' tools/cacert.pem || die "cacert.pem 结构异常"
  echo "[package-net] 校验通过"
)
echo "net 包完成: $OUT_ZIP ($(wc -c < "$OUT_ZIP") 字节)"
cat "$OUT_ZIP.sha256"
