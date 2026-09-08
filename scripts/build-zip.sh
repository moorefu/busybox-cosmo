#!/usr/bin/env bash
# ============================================================
# build-zip.sh — 从锁定源码构建跨平台 zip (fat APE 伴生工具)
#   供应线: fetch-zip.sh (原包+Debian 补丁集 sha256) → 每次全新解包、按
#           series 打补丁 → 双架构编译 (无 configure, 直接 make) →
#           apelink 合成 → 64K 自检 → 创建/解压往返冒烟 → 许可/SBOM
#   产物:   dist/tools/zip.com
#   用法:   scripts/build-zip.sh (ZIP_OUT 可覆盖产物路径)
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/env.sh"

OUT="${ZIP_OUT:-$DIST_DIR/tools/zip.com}"
ZIP_TARBALL_PATH="$COMPANION_REF_DIR/$ZIP_TARBALL"
ZIP_DEB_TARBALL_PATH="$COMPANION_REF_DIR/$ZIP_DEB_TARBALL"
SBOM="$DIST_DIR/tools/SBOM-zip.txt"
LICENSE_OUT="$ROOT/licenses/ZIP-INFOZIP-LICENSE.txt"

export PATH="$TC/bin:$PATH"

[ -x "$TC_X86_CC" ] || die "缺 Cosmopolitan x86_64 编译器: $TC_X86_CC"
[ -x "$TC_A64_CC" ] || die "缺 Cosmopolitan aarch64 编译器: $TC_A64_CC"
[ -x "$TC_APELINK" ] || die "缺 apelink: $TC_APELINK"

"$ROOT/scripts/fetch-zip.sh"

# 把 Debian 补丁集解到临时目录, 返回补丁目录 (含 series)
DEB_PATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zip-deb.XXXXXX")"
trap 'rm -rf "$DEB_PATCH_DIR"' EXIT HUP INT TERM
tar xJf "$ZIP_DEB_TARBALL_PATH" -C "$DEB_PATCH_DIR"

# build_one: 每次全新解包原包并按 series 顺序打补丁后编译
#   $1=构建树 $2=CC $3=输出 ELF
build_one() {
  local src="$1" cc="$2" out="$3"
  rm -rf "$src"
  tar xzf "$ZIP_TARBALL_PATH" -C "$WORK_DIR/companions"
  if [ "$(basename "$src")" != "zip30" ]; then
    mv "$WORK_DIR/companions/zip30" "$src"
  fi
  (
    cd "$src"
    local p
    for p in $(cat "$DEB_PATCH_DIR/debian/patches/series"); do
      patch -s -p1 < "$DEB_PATCH_DIR/debian/patches/$p" || {
        echo "[build-zip][错误] 补丁 $p 应用失败: $src" >&2
        exit 1
      }
    done
    make -f unix/Makefile zip \
      CC="$cc" CFLAGS="-Os -I. -DUNIX" LFLAGS2="" > make.log 2>&1 || {
      echo "[build-zip][错误] make 失败: $src" >&2
      tail -30 make.log >&2
      exit 1
    }
  )
  cp "$src/zip" "$out"
  echo "[build-zip] 单架构完成: $out ($cc)"
}

mkdir -p "$(dirname "$OUT")"
TMP_X86="$DIST_DIR/tools/.zip-x86_64"
TMP_A64="$DIST_DIR/tools/.zip-aarch64"
rm -f "$TMP_X86" "$TMP_A64"

build_one "$WORK_DIR/companions/zip-$ZIP_VER" "$TC_X86_CC" "$TMP_X86"
build_one "$WORK_DIR/companions/zip-$ZIP_VER-aarch64" "$TC_A64_CC" "$TMP_A64"

"$TC_APELINK" -l "$APE_LDR_X86" -l "$APE_LDR_A64" -M "$APE_M1_SRC" \
  -o "$OUT" "$TMP_X86" "$TMP_A64"
rm -f "$TMP_X86" "$TMP_A64"
chmod 755 "$OUT"
"$ROOT/scripts/check-ape-64k.sh" "$OUT" >/dev/null || die "zip.com 64K 页自检失败"

# ---- 往返冒烟: zip.com 创建 → 独立解码器解出并逐字节一致 ----
# 解码器候选: 本工程 fat busybox (内建 unzip) > 宿主 unzip (Info-ZIP)
BB_DECODER=""
for cand in "$DIST_DIR/busybox-fat.ape" "$ROOT/dist/release/release/busybox"; do
  if [ -x "$cand" ]; then BB_DECODER="$cand"; break; fi
done
if [ -z "$BB_DECODER" ] && command -v unzip >/dev/null 2>&1; then
  BB_DECODER="unzip"
fi
[ -n "$BB_DECODER" ] || die "缺少解码器(busybox-fat.ape/宿主 unzip), 无法做 zip 往返冒烟"

SMOKE="$(mktemp -d "${TMPDIR:-/tmp}/zip-smoke.XXXXXX")"
mkdir -p "$SMOKE/src/sub"
printf 'hello busybox-cosmo\n' > "$SMOKE/src/a.txt"
head -c 65536 /dev/urandom > "$SMOKE/src/sub/b.bin"
printf 'utf8-content-ok\n' > "$SMOKE/src/sub/u8.txt"
(
  cd "$SMOKE/src"
  "$OUT" -q -r "$SMOKE/out.zip" .
)
# 注: 列目录是 unzip -l; zip 的 -l 表示 LF→CRLF 文本转换(需文件操作数), 勿误用
mkdir -p "$SMOKE/extract"
if [ "$BB_DECODER" = "unzip" ]; then
  ( cd "$SMOKE/extract" && unzip -q -o "$SMOKE/out.zip" )
else
  ( cd "$SMOKE/extract" && "$BB_DECODER" unzip -q -o "$SMOKE/out.zip" )
fi
cmp "$SMOKE/src/a.txt" "$SMOKE/extract/a.txt" || die "zip 文本往返不一致"
cmp "$SMOKE/src/sub/b.bin" "$SMOKE/extract/sub/b.bin" || die "zip 二进制往返不一致"
cmp "$SMOKE/src/sub/u8.txt" "$SMOKE/extract/sub/u8.txt" || die "zip 内容往返不一致"
echo "[build-zip] 往返冒烟通过 ($BB_DECODER 解码 zip.com 产物)"

# ---- 许可归档 (原包 LICENSE) ----
rm -f "$LICENSE_OUT"
tar xzf "$ZIP_TARBALL_PATH" -C "$DEB_PATCH_DIR" zip30/LICENSE 2>/dev/null \
  && cp "$DEB_PATCH_DIR/zip30/LICENSE" "$LICENSE_OUT" \
  || tar xzf "$ZIP_TARBALL_PATH" -O zip30/zip.h | sed -n '1,60p' > "$LICENSE_OUT"
[ -s "$LICENSE_OUT" ] || die "许可文件为空: $LICENSE_OUT"

# ---- SBOM ----
{
  echo "tool=zip"
  echo "version=Info-ZIP ${ZIP_VER} (Debian ${ZIP_VER}-${ZIP_DEB_REV} 补丁快照)"
  echo "source_url=$ZIP_URL"
  echo "source_sha256=$ZIP_SHA256"
  echo "debian_patchset_url=$ZIP_DEB_URL"
  echo "debian_patchset_sha256=$ZIP_DEB_SHA256"
  echo "recipe=scripts/build-zip.sh + scripts/fetch-zip.sh"
  echo "artifact=$OUT"
  echo "artifact_sha256=$(shasum -a 256 "$OUT" | awk '{print $1}')"
  echo "license=Info-ZIP License; 内置 deflate (无需 zlib); bzip2 方法未启用"
  echo "license_file=$LICENSE_OUT"
  echo "build_note=无 configure; 直接 make -f unix/Makefile zip"
} > "$SBOM"
echo "zip 完成: $OUT"
echo "SBOM: $SBOM"
