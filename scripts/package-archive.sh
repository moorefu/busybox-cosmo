#!/usr/bin/env bash
# ============================================================
# package-archive.sh — busybox-archive 分层伴生包 (M5 部分, 可复现)
#   组成: 最小运行层 (busybox.com fat + busybox 入口 + bbcosmo/lib) +
#         归档工具 tools/{xz,zip,zstd}.com + 各自 SBOM/许可 + MANIFEST
#   前置: make build (busybox-fat.ape) + make xz zip zstd
#   产出: dist/busybox-archive.zip (+ .sha256)
#   说明: net 包(需 curl.com+cacert)与 codec-extra 包(lz4/brotli)在对应
#        工具落地前不产出; 本脚本只负责"已具备工具"的可复现分层打包。
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/env.sh"

OUT_DIR="$DIST_DIR/archive"
OUT_ZIP="$DIST_DIR/busybox-archive.zip"
FAT="$DIST_DIR/busybox-fat.ape"
TOOLS=(xz zip zstd)

[ -f "$FAT" ] || die "缺 dist/busybox-fat.ape, 先 make build"
for t in "${TOOLS[@]}"; do
  [ -f "$DIST_DIR/tools/$t.com" ] || die "缺 dist/tools/$t.com, 先 make $t"
done

rm -rf "$OUT_DIR" && mkdir -p "$OUT_DIR/tools" "$OUT_DIR/lib" "$OUT_DIR/examples" "$OUT_DIR/licenses"

# ---- 运行层 (对齐 --min 包形态) ----
cp "$ROOT/scripts/bb.sh" "$OUT_DIR/busybox" && chmod 755 "$OUT_DIR/busybox"
cp "$FAT" "$OUT_DIR/busybox.com" && chmod 755 "$OUT_DIR/busybox.com"
cp "$ROOT/scripts/bbcosmo" "$OUT_DIR/bbcosmo" && chmod 755 "$OUT_DIR/bbcosmo"
cp "$ROOT/lib/portable.sh" "$OUT_DIR/lib/portable.sh"
cp "$ROOT/examples/portable-menu.sh" "$OUT_DIR/examples/" && chmod 755 "$OUT_DIR/examples/portable-menu.sh"

# ---- 伴生工具 + SBOM + 许可 ----
for t in "${TOOLS[@]}"; do
  cp "$DIST_DIR/tools/$t.com" "$OUT_DIR/tools/$t.com" && chmod 755 "$OUT_DIR/tools/$t.com"
  [ -f "$DIST_DIR/tools/SBOM-$t.txt" ] && cp "$DIST_DIR/tools/SBOM-$t.txt" "$OUT_DIR/tools/"
done
cp "$ROOT/NOTICE.md" "$OUT_DIR/NOTICE.md"
for lic in BUSYBOX-GPL-2.0.txt XZ-COPYING.txt ZIP-INFOZIP-LICENSE.txt ZSTD-LICENSE.txt; do
  [ -f "$ROOT/licenses/$lic" ] && cp "$ROOT/licenses/$lic" "$OUT_DIR/licenses/"
done
cp "$ROOT/docs/COMPANION-TOOLS.md" "$OUT_DIR/COMPANION-TOOLS.md"
cp "$ROOT/docs/COMPANION-DELIVERY-PLAN.md" "$OUT_DIR/COMPANION-DELIVERY-PLAN.md"

# ---- README ----
cat > "$OUT_DIR/README.txt" <<EOF
busybox-archive 伴生包 (busybox + zip/xz/zstd)

Linux/macOS: ./busybox ash script.sh    Windows: busybox.com ash script.sh
诊断: ./busybox ash bbcosmo doctor
归档创建: tools/xz.com tools/zip.com tools/zstd.com
发现与能力: bbcosmo capabilities (tools/ 自动优先于宿主 PATH)

本包不包含可信下载(net 包)与 lz4/brotli(codec-extra); 见 COMPANION-TOOLS.md。
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
  # 可移植 epoch→[[CC]YY]MMDDhhmm[.SS] (GNU date -d / BSD date -r)
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

# ---- 校验: 解压后入口与工具可执行 ----
CHECK="$(mktemp -d "${TMPDIR:-/tmp}/archive-check.XXXXXX")"
trap 'rm -rf "$CHECK"' EXIT HUP INT TERM
unzip -q "$OUT_ZIP" -d "$CHECK"
(
  cd "$CHECK"
  HOME="$CHECK" BUSYBOX_COSMO_CACHE="$CHECK/cache" ./busybox uname -m >/dev/null || die "入口不可执行"
  ./tools/xz.com --version >/dev/null || die "xz.com 不可执行"
  printf 'check' | ./tools/zstd.com -q -c | ./tools/zstd.com -q -d | grep -q '^check$' || die "zstd.com 往返失败"
  echo "[package-archive] 校验通过"
)
echo "archive 包完成: $OUT_ZIP ($(wc -c < "$OUT_ZIP") 字节)"
cat "$OUT_ZIP.sha256"
