#!/usr/bin/env bash
# ============================================================
# build-curl.sh — 从锁定源码构建跨平台 curl (fat APE 伴生工具, M2)
#   依赖链: mbedtls (TLS 后端, 无 autotools, 自带静态库)
#   流程: fetch-curl.sh → 每架构: mbedtls 静态库 → stage → curl 交叉
#         configure (--host 关运行期探测) + make → apelink 合成 → 64K
#         自检 → 本地 TLS KAT (tests/https-kat.py 同参数集) → 许可/SBOM
#   产物: dist/tools/curl.com
#   配方要点: AR/RANLIB 必须用 cosmo 归档器 (macOS Xcode ar 空壳问题);
#             --with-mbedtls 与 --without-ssl 冲突, 只能二者选一。
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/env.sh"

OUT="${CURL_OUT:-$DIST_DIR/tools/curl.com}"
CURL_TARBALL_PATH="$COMPANION_REF_DIR/$CURL_TARBALL"
MBEDTLS_TARBALL_PATH="$COMPANION_REF_DIR/$MBEDTLS_TARBALL"
SBOM="$DIST_DIR/tools/SBOM-curl.txt"
LICENSE_CURL="$ROOT/licenses/CURL-LICENSE.txt"
LICENSE_MBEDTLS="$ROOT/licenses/MBEDTLS-APACHE-2.0.txt"

export PATH="$TC/bin:$PATH"

[ -x "$TC_X86_CC" ] || die "缺 x86_64 编译器"
[ -x "$TC_A64_CC" ] || die "缺 aarch64 编译器"
[ -x "$TC_APELINK" ] || die "缺 apelink"

"$ROOT/scripts/fetch-curl.sh"

# build_mbedtls: $1=源码树 $2=CC $3=cosmo-ar 前缀 $4=输出 stage
build_mbedtls() {
  local src="$1" cc="$2" arp="$3" stage="$4"
  rm -rf "$src" "$stage"
  mkdir -p "$src"
  tar xjf "$MBEDTLS_TARBALL_PATH" -C "$src" --strip-components=1
  (
    cd "$src"
    make -C library libmbedcrypto.a libmbedx509.a libmbedtls.a \
      CC="$cc" AR="${arp}-ar" RL="${arp}-ranlib" CFLAGS="-Os" \
      -j"${JOBS:-8}" > mbedtls-make.log 2>&1 || {
      echo "[build-curl][错误] mbedtls 构建失败: $src" >&2
      tail -20 mbedtls-make.log >&2
      exit 1
    }
  )
  mkdir -p "$stage/include" "$stage/lib"
  cp -R "$src/include/mbedtls" "$stage/include/"
  cp -R "$src/include/psa" "$stage/include/"
  cp "$src/library/"libmbedcrypto.a "$src/library/"libmbedx509.a \
     "$src/library/"libmbedtls.a "$stage/lib/"
  echo "[build-curl] mbedtls stage: $stage"
}

# build_curl: $1=curl 构建树 $2=CC $3=host 三元组 $4=arp 前缀 $5=mbedtls stage $6=输出 ELF
build_curl() {
  local src="$1" cc="$2" host="$3" arp="$4" stage="$5" out="$6"
  rm -rf "$src"
  mkdir -p "$src"
  tar xzf "$CURL_TARBALL_PATH" -C "$src" --strip-components=1
  (
    cd "$src"
    export AR="${arp}-ar" RANLIB="${arp}-ranlib"
    export MSGFMT=/usr/bin/true MSGMERGE=/usr/bin/true XGETTEXT=/usr/bin/true
    export LC_ALL=C ac_cv_func_pledge=no
    ./configure --host="$host" --disable-shared --enable-static \
      --with-mbedtls="$stage" \
      --without-zlib --without-brotli --without-zstd --without-libpsl \
      --without-libidn2 --without-nghttp2 --without-ngtcp2 --without-quiche \
      --disable-ldap --disable-ldaps --disable-dict --disable-manual \
      --disable-docs \
      CC="$cc" CFLAGS="-Os" > configure.log 2>&1 || {
      echo "[build-curl][错误] configure 失败: $src" >&2
      tail -25 configure.log >&2
      exit 1
    }
    make -j"${JOBS:-8}" > make.log 2>&1 || {
      echo "[build-curl][错误] make 失败: $src" >&2
      tail -30 make.log >&2
      exit 1
    }
  )
  cp "$src/src/curl" "$out"
  echo "[build-curl] $host curl 完成: $out"
}

mkdir -p "$(dirname "$OUT")" "$WORK_DIR/companions"
TMP_X86="$DIST_DIR/tools/.curl-x86_64"
TMP_A64="$DIST_DIR/tools/.curl-aarch64"
rm -f "$TMP_X86" "$TMP_A64"

MB_X86="$WORK_DIR/companions/mbedtls-$MBEDTLS_VER"
MB_A64="$WORK_DIR/companions/mbedtls-$MBEDTLS_VER-aarch64"
build_mbedtls "$MB_X86" "$TC_X86_CC" "$TC/bin/x86_64-linux-cosmo" \
  "$WORK_DIR/companions/mbedtls-stage-x86"
build_mbedtls "$MB_A64" "$TC_A64_CC" "$TC/bin/aarch64-linux-cosmo" \
  "$WORK_DIR/companions/mbedtls-stage-aarch64"

build_curl "$WORK_DIR/companions/curl-$CURL_VER" "$TC_X86_CC" "x86_64-pc-linux-gnu" \
  "$TC/bin/x86_64-linux-cosmo" "$WORK_DIR/companions/mbedtls-stage-x86" "$TMP_X86"
build_curl "$WORK_DIR/companions/curl-$CURL_VER-aarch64" "$TC_A64_CC" "aarch64-pc-linux-gnu" \
  "$TC/bin/aarch64-linux-cosmo" "$WORK_DIR/companions/mbedtls-stage-aarch64" "$TMP_A64"

"$TC_APELINK" -l "$APE_LDR_X86" -l "$APE_LDR_A64" -M "$APE_M1_SRC" \
  -o "$OUT" "$TMP_X86" "$TMP_A64"
rm -f "$TMP_X86" "$TMP_A64"
chmod 755 "$OUT"
"$ROOT/scripts/check-ape-64k.sh" "$OUT" >/dev/null || die "curl.com 64K 页自检失败"

# ---- 冒烟: 版本含 mbedtls + 本回环 TLS KAT (同一参数集, 见 https-kat.py) ----
"$OUT" --version | head -3 || die "curl.com 不可执行"
python3 "$ROOT/tests/https-kat.py" "$OUT" || {
  echo "[build-curl][错误] 本地 TLS KAT 未通过 (curl.com)" >&2
  exit 1
}

# ---- 许可归档 ----
tar xzf "$CURL_TARBALL_PATH" -O "curl-$CURL_VER/COPYING" > "$LICENSE_CURL"
# mbedtls: Apache-2.0 (3.x 使用 Apache-2.0 与 GPL-2.0 双许可, 选 Apache-2.0 文件)
tar xjf "$MBEDTLS_TARBALL_PATH" -O "mbedtls-$MBEDTLS_VER/LICENSE" > "$LICENSE_MBEDTLS" 2>/dev/null || true

# ---- SBOM ----
{
  echo "tool=curl"
  echo "version=$CURL_VER"
  echo "source_url=$CURL_URL"
  echo "source_sha256=$CURL_SHA256"
  echo "tls_backend=mbedtls $MBEDTLS_VER (url=$MBEDTLS_URL)"
  echo "tls_backend_sha256=$MBEDTLS_SHA256"
  echo "recipe=scripts/build-curl.sh + scripts/fetch-curl.sh"
  echo "artifact=$OUT"
  echo "artifact_sha256=$(shasum -a 256 "$OUT" | awk '{print $1}')"
  echo "license=curl: MIT/ISC 派生; mbedtls: Apache-2.0"
  echo "license_file=$LICENSE_CURL (curl), $LICENSE_MBEDTLS (mbedtls)"
  echo "build_note=交叉 configure --with-mbedtls, --without-zlib; 无 configure 运行期探测"
} > "$SBOM"
echo "curl 完成: $OUT"
echo "SBOM: $SBOM"
