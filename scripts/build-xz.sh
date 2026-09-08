#!/usr/bin/env bash
# ============================================================
# build-xz.sh — 从锁定源码构建跨平台 xz (fat APE 伴生工具)
#   供应线: fetch-xz.sh (取源+sha256) → 双架构交叉编译 → apelink 合成
#           → 64K 页自检 → 往返冒烟 → 许可/SBOM 归档
#   产物:   dist/tools/xz.com   (x86_64 + aarch64 fat APE, 运行时可自解码)
#   用法:   scripts/build-xz.sh
#   环境:   XZ_OUT 覆盖产物路径; 常量覆盖见 env.sh
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/env.sh"

OUT="${XZ_OUT:-$DIST_DIR/tools/xz.com}"
XZ_TARBALL_PATH="$COMPANION_REF_DIR/$XZ_TARBALL"
SBOM="$DIST_DIR/tools/SBOM-xz.txt"
LICENSE_OUT="$ROOT/licenses/XZ-COPYING.txt"

# 交叉构建运行期探测会误判: cosmo 库内含 pledge 符号但头文件无声明, 若不
# 关闭 xz 会误启用 OpenBSD sandbox 路径。见 docs/COMPANION-DELIVERY-PLAN.md。
export PATH="$TC/bin:$PATH"
export MSGFMT=/usr/bin/true MSGMERGE=/usr/bin/true XGETTEXT=/usr/bin/true
export LC_ALL=C ac_cv_func_pledge=no

[ -x "$TC_X86_CC" ] || die "缺 Cosmopolitan x86_64 编译器: $TC_X86_CC"
[ -x "$TC_A64_CC" ] || die "缺 Cosmopolitan aarch64 编译器: $TC_A64_CC"
[ -x "$TC_APELINK" ] || die "缺 apelink: $TC_APELINK"

"$ROOT/scripts/fetch-xz.sh"

# build_one: 每次从锁定 tarball 全新提取并构建, 保证可复现
#   $1=构建树目录 $2=CC $3=host 三元组 $4=cosmo ar $5=cosmo ranlib $6=输出 ELF
build_one() {
  local src="$1" cc="$2" host="$3" ar="$4" ranlib="$5" out="$6"
  rm -rf "$src"
  tar xJf "$XZ_TARBALL_PATH" -C "$WORK_DIR/companions"
  if [ "$(basename "$src")" != "xz-$XZ_VER" ]; then
    mv "$WORK_DIR/companions/xz-$XZ_VER" "$src"
  fi
  (
    cd "$src"
    # AR/RANLIB 必须用 cosmo 归档器: macOS Xcode ar 会把 Linux ELF 成员建
    # 成空壳静态库 (liblzma.a 96 字节事故的根因)。
    AR="$ar" RANLIB="$ranlib" ./configure --host="$host" --enable-sandbox=no \
      --disable-nls --disable-shared --enable-static \
      --disable-doc --disable-scripts --disable-xzdec --disable-lzmadec \
      CC="$cc" CFLAGS="-Os" > configure.log 2>&1 || {
      echo "[build-xz][错误] configure 失败: $src" >&2
      tail -25 configure.log >&2
      exit 1
    }
    make -j"${JOBS:-8}" > make.log 2>&1 || {
      echo "[build-xz][错误] make 失败: $src" >&2
      tail -30 make.log >&2
      exit 1
    }
  )
  cp "$src/src/xz/xz" "$out"
  echo "[build-xz] $host 构建完成: $out"
}

mkdir -p "$(dirname "$OUT")"
TMP_X86="$DIST_DIR/tools/.xz-x86_64"
TMP_A64="$DIST_DIR/tools/.xz-aarch64"
rm -f "$TMP_X86" "$TMP_A64"

build_one "$WORK_DIR/companions/xz-$XZ_VER" "$TC_X86_CC" "x86_64-pc-linux-gnu" \
  "$TC/bin/x86_64-linux-cosmo-ar" "$TC/bin/x86_64-linux-cosmo-ranlib" "$TMP_X86"
build_one "$WORK_DIR/companions/xz-$XZ_VER-aarch64" "$TC_A64_CC" "aarch64-pc-linux-gnu" \
  "$TC/bin/aarch64-linux-cosmo-ar" "$TC/bin/aarch64-linux-cosmo-ranlib" "$TMP_A64"

"$TC_APELINK" -l "$APE_LDR_X86" -l "$APE_LDR_A64" -M "$APE_M1_SRC" \
  -o "$OUT" "$TMP_X86" "$TMP_A64"
rm -f "$TMP_X86" "$TMP_A64"
chmod 755 "$OUT"
"$ROOT/scripts/check-ape-64k.sh" "$OUT" >/dev/null || die "xz.com 64K 页自检失败"

# ---- 往返冒烟: 自编码/自解码 + 宿主编解码交叉 ----
SMOKE="$(mktemp -d "${TMPDIR:-/tmp}/xz-smoke.XXXXXX")"
trap 'rm -rf "$SMOKE"' EXIT HUP INT TERM
head -c 1048576 /dev/urandom > "$SMOKE/in.bin"
"$OUT" -c "$SMOKE/in.bin" > "$SMOKE/in.xz"
"$OUT" -dc "$SMOKE/in.xz" > "$SMOKE/out.bin"
cmp "$SMOKE/in.bin" "$SMOKE/out.bin" || die "xz.com 自往返不一致"
if command -v xz >/dev/null 2>&1; then
  xz -dc "$SMOKE/in.xz" > "$SMOKE/out2.bin"
  cmp "$SMOKE/in.bin" "$SMOKE/out2.bin" || die "宿主编解码器无法解 xz.com 产物"
fi
echo "[build-xz] 往返冒烟通过 (.xz 编码 $(wc -c < "$SMOKE/in.xz") 字节)"

# ---- 许可归档 (xz CLI 公有领域; cosmo 自带 getopt_long, 不引入 LGPL 组件) ----
tar xJf "$XZ_TARBALL_PATH" -O "xz-$XZ_VER/COPYING" > "$LICENSE_OUT"

# ---- SBOM ----
{
  echo "tool=xz"
  echo "version=$XZ_VER"
  echo "source_url=$XZ_URL"
  echo "source_sha256=$XZ_SHA256"
  echo "recipe=scripts/build-xz.sh + scripts/fetch-xz.sh"
  echo "artifact=$OUT"
  echo "artifact_sha256=$(shasum -a 256 "$OUT" | awk '{print $1}')"
  echo "license=public-domain (CLI); cosmo 自带 getopt_long, 未引入 LGPL 组件"
  echo "license_file=$LICENSE_OUT"
  echo "build_note=交叉 configure --enable-sandbox=no (cosmo 无 pledge 声明), 关闭运行期探测"
} > "$SBOM"
echo "xz 完成: $OUT"
echo "SBOM: $SBOM"
