#!/usr/bin/env bash
# 构建自有的跨平台终端助手。产物仍由发布打包脚本决定是否纳入。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/env.sh"
OUT="${BBTTY_OUT:-$ROOT/dist/bbtty.com}"
TMP_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/bbtty-build.XXXXXX")"
trap 'rm -rf "$TMP_BUILD"' EXIT HUP INT TERM

[ -x "$TC_X86_CC" ] || die "缺 Cosmopolitan x86_64 编译器: $TC_X86_CC"
[ -x "$TC_A64_CC" ] || die "缺 Cosmopolitan aarch64 编译器: $TC_A64_CC"
[ -x "$TC_APELINK" ] || die "缺 apelink: $TC_APELINK"
mkdir -p "$(dirname "$OUT")"
"$TC_X86_CC" -Os -Wall -Wextra -o "$TMP_BUILD/bbtty-x86_64.dbg" "$ROOT/tools/bbtty.c"
"$TC_A64_CC" -Os -Wall -Wextra -o "$TMP_BUILD/bbtty-aarch64.dbg" "$ROOT/tools/bbtty.c"
"$TC_APELINK" -l "$APE_LDR_X86" -l "$APE_LDR_A64" -M "$APE_M1_SRC" \
  -o "$OUT" "$TMP_BUILD/bbtty-x86_64.dbg" "$TMP_BUILD/bbtty-aarch64.dbg"
chmod 755 "$OUT"
"$ROOT/scripts/check-ape-64k.sh" "$OUT" >/dev/null || die "bbtty 64K 页自检失败"
echo "bbtty 完成: $OUT"
