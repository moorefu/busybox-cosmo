#!/usr/bin/env bash
# ============================================================
# build-zstd.sh — 从锁定源码构建跨平台 zstd (fat APE 伴生工具, M3)
#   供应线: fetch-zstd.sh → 每次全新解包 + 配方小补丁(占位符号) →
#           双架构 make zstd-release → apelink → 64K 自检 → 往返冒烟 →
#           许可/SBOM
#   产物:   dist/tools/zstd.com
#   配方说明: cosmocc 驱动会拒绝"无符号表"的汇编产物; huf_decompress_amd64.S
#            是空桩, 追加一个占位符号绕过 (见本文件 patch 段)。
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/env.sh"

OUT="${ZSTD_OUT:-$DIST_DIR/tools/zstd.com}"
ZSTD_TARBALL_PATH="$COMPANION_REF_DIR/$ZSTD_TARBALL"
SBOM="$DIST_DIR/tools/SBOM-zstd.txt"
LICENSE_OUT="$ROOT/licenses/ZSTD-LICENSE.txt"

export PATH="$TC/bin:$PATH"

[ -x "$TC_X86_CC" ] || die "缺 Cosmopolitan x86_64 编译器: $TC_X86_CC"
[ -x "$TC_A64_CC" ] || die "缺 Cosmopolitan aarch64 编译器: $TC_A64_CC"
[ -x "$TC_APELINK" ] || die "缺 apelink: $TC_APELINK"

"$ROOT/scripts/fetch-zstd.sh"

# build_one: 每次全新解包 + 占位符号补丁 + 编译
#   $1=构建树 $2=CC $3=输出 ELF
build_one() {
  local src="$1" cc="$2" out="$3"
  rm -rf "$src"
  tar xzf "$ZSTD_TARBALL_PATH" -C "$WORK_DIR/companions"
  if [ "$(basename "$src")" != "zstd-$ZSTD_VER" ]; then
    mv "$WORK_DIR/companions/zstd-$ZSTD_VER" "$src"
  fi
  # 配方补丁: 空桩 .S 加占位符号, 使 cosmocc 汇编驱动不报错
  cat >> "$src/lib/decompress/huf_decompress_amd64.S" <<'PATCH'

/* busybox-cosmo build: give the stub object a symbol so the cosmocc
 * driver's post-assembly step does not reject an empty symbol table. */
.globl zstd_huf_amd64_stub_sym
zstd_huf_amd64_stub_sym:
	.byte 0
.size zstd_huf_amd64_stub_sym, 1
PATCH
  (
    cd "$src"
    make -j"${JOBS:-8}" zstd-release CC="$cc" CFLAGS="-Os" > make.log 2>&1 || {
      echo "[build-zstd][错误] make 失败: $src" >&2
      tail -30 make.log >&2
      exit 1
    }
  )
  cp "$src/zstd" "$out"
  echo "[build-zstd] 单架构完成: $out ($cc)"
}

mkdir -p "$(dirname "$OUT")"
TMP_X86="$DIST_DIR/tools/.zstd-x86_64"
TMP_A64="$DIST_DIR/tools/.zstd-aarch64"
rm -f "$TMP_X86" "$TMP_A64"

build_one "$WORK_DIR/companions/zstd-$ZSTD_VER" "$TC_X86_CC" "$TMP_X86"
build_one "$WORK_DIR/companions/zstd-$ZSTD_VER-aarch64" "$TC_A64_CC" "$TMP_A64"

"$TC_APELINK" -l "$APE_LDR_X86" -l "$APE_LDR_A64" -M "$APE_M1_SRC" \
  -o "$OUT" "$TMP_X86" "$TMP_A64"
rm -f "$TMP_X86" "$TMP_A64"
chmod 755 "$OUT"
"$ROOT/scripts/check-ape-64k.sh" "$OUT" >/dev/null || die "zstd.com 64K 页自检失败"

# ---- 往返冒烟 ----
SMOKE="$(mktemp -d "${TMPDIR:-/tmp}/zstd-smoke.XXXXXX")"
trap 'rm -rf "$SMOKE"' EXIT HUP INT TERM
head -c 262144 /dev/urandom > "$SMOKE/in.bin"
printf 'zstd roundtrip test payload %s\n' "$(seq 1 200 | tr -d '\n')" >> "$SMOKE/in.bin"
"$OUT" -q -c "$SMOKE/in.bin" > "$SMOKE/in.zst"
"$OUT" -q -d -c "$SMOKE/in.zst" > "$SMOKE/out.bin"
cmp "$SMOKE/in.bin" "$SMOKE/out.bin" || die "zstd.com 自往返不一致"
if command -v zstd >/dev/null 2>&1; then
  zstd -q -d -c "$SMOKE/in.zst" > "$SMOKE/out2.bin"
  cmp "$SMOKE/in.bin" "$SMOKE/out2.bin" || die "宿主 zstd 无法解 zstd.com 产物"
fi
printf 'garbage' > "$SMOKE/junk.zst"
if "$OUT" -q -d -c "$SMOKE/junk.zst" >/dev/null 2>&1; then
  die "损坏 .zst 应解码失败"
fi
echo "[build-zstd] 往返冒烟通过 (.zst 编码 $(wc -c < "$SMOKE/in.zst") 字节)"

# ---- 许可归档 (BSD-3-Clause 分发; 文件内同时含 GPLv2 双许可说明) ----
tar xzf "$ZSTD_TARBALL_PATH" -O "zstd-$ZSTD_VER/LICENSE" > "$LICENSE_OUT"

# ---- SBOM ----
{
  echo "tool=zstd"
  echo "version=$ZSTD_VER"
  echo "source_url=$ZSTD_URL"
  echo "source_sha256=$ZSTD_SHA256"
  echo "recipe=scripts/build-zstd.sh + scripts/fetch-zstd.sh"
  echo "recipe_patch=huf_decompress_amd64.S 追加占位符号 (cosmocc 空符号表驱动限制)"
  echo "artifact=$OUT"
  echo "artifact_sha256=$(shasum -a 256 "$OUT" | awk '{print $1}')"
  echo "license=BSD-3-Clause (dual with GPLv2, 选择 BSD-3-Clause 分发)"
  echo "license_file=$LICENSE_OUT"
  echo "build_note=无 configure; make zstd-release"
} > "$SBOM"
echo "zstd 完成: $OUT"
echo "SBOM: $SBOM"
