#!/usr/bin/env bash
# ============================================================
# check-ape-64k.sh — 验证 APE/fat 单文件的 64K 页内核就绪性
#
# 背景: 64K 页 Linux aarch64 (鲲鹏 UOS/麒麟) 要求 APE 内嵌的
#   aarch64 loader ELF 的每个 PT_LOAD 满足:
#     p_align  ≥ 0x10000 (64K 倍数)  且  p_vaddr ≡ p_offset (mod 64K)
#   官方 cosmocc 的 ape-aarch64.elf 是 16K 对齐 (Align 0x4000) → 不可加载。
#   本工程由 master 重建 64K loader (见 toolchain/build-custom.sh 3b'),
#   fat 内嵌后即可"单文件"在 64K 内核经内嵌 loader 路径运行。
#
# 用法: scripts/check-ape-64k.sh <file.ape> [readelf-前缀目录]
#   第二个参数缺省为 ./toolchain/cosmo/bin (内含 x86_64/aarch64 readelf)
#
# 输出: 列出内嵌各架构 loader 的 LOAD 对齐, 校验 64K 同余; 退出码 0=就绪
# ============================================================
set -euo pipefail

FILE="${1:-}"
[ -n "$FILE" ] && [ -f "$FILE" ] || { echo "用法: $0 <file.ape> [toolchain/bin 目录]" >&2; exit 2; }
BIN="${2:-$(cd "$(dirname "$0")/.." && pwd)/toolchain/cosmo/bin}"

# 解出内嵌 gzip loader → stdout: "<arch> <tmp-elf> <size>"
TMPDIR_CHECK="$(mktemp -d "${TMPDIR:-/tmp}/ape64k.XXXXXX")"
trap 'rm -rf "$TMPDIR_CHECK"' EXIT HUP INT TERM

command -v python3 >/dev/null 2>&1 || { echo "缺少 python3，无法解析 APE" >&2; exit 1; }

extract_loaders() { # $1=file
  TMPDIR_CHECK="$TMPDIR_CHECK" python3 - "$1" <<'PY'
import struct, sys, zlib
import os
d = open(sys.argv[1], 'rb').read()
seen = set()
for i in range(len(d) - 4):
    if d[i] != 0x1f or d[i+1] != 0x8b:
        continue
    try:
        # gzip 流后紧跟其它数据 (zip), GzipFile 会因多成员报错 → zlib 解到 eof
        z = zlib.decompressobj(31)
        full = bytearray()
        off = i
        end = min(len(d), i + 262144)
        while not z.eof and off < end:
            full += z.decompress(d[off:min(off + 65536, end)])
            off += 65536
        full = bytes(full)
        if full[:4] != b'\x7fELF':
            continue
        mach = struct.unpack_from('<H', full, 18)[0]
        arch = 'aarch64' if mach == 0xb7 else ('x86_64' if mach == 0x3e else 'arch%#x' % mach)
        if arch in seen:
            continue
        seen.add(arch)
        out = os.path.join(os.environ['TMPDIR_CHECK'], 'loader-%s.elf' % arch)
        open(out, 'wb').write(full)
        print(arch, out, len(full))
    except Exception:
        # APE 中可能还有普通 gzip 数据；只有识别为 ELF 的流才是 loader。
        continue
PY
}

fail=0

check_arch() { # $1=arch  $2=elf  $3=rd
  [ -x "$3" ] || { echo "  ✗ [$1] 缺少 readelf: $3"; fail=1; return; }
  "$3" -l "$2" 2>/dev/null | awk '/^[[:space:]]*LOAD[[:space:]]/{off=$2; va=$3; getline; print off, va, $NF}' > "$TMPDIR_CHECK/phdr-$1"
  local n=0
  while read -r off va al; do
    [ -n "$al" ] || continue
    n=$((n+1))
    okalign=1
    case "$al" in
      0x10000|0x20000|0x40000|0x80000|0x100000) ;;
      *) echo "  ✗ [$1] LOAD$n Align=$al (< 0x10000, 64K 内核不可加载)"; okalign=0; fail=1 ;;
    esac
    d=$(( 16#${va#0x} - 16#${off#0x} ))
    r=$(( d % 65536 )); [ $r -lt 0 ] && r=$(( r + 65536 ))
    if [ "$r" != 0 ]; then
      echo "  ✗ [$1] LOAD$n off=$off vaddr=$va 不同余 64K (Δ=0x$(printf %x $d))"
      fail=1
    elif [ "$okalign" = 1 ]; then
      echo "  ✓ [$1] LOAD$n Align=$al 且 off≡vaddr (mod 64K)"
    fi
  done < "$TMPDIR_CHECK/phdr-$1"
  if [ "$n" -eq 0 ]; then
    echo "  ✗ [$1] 未找到 PT_LOAD，拒绝通过"
    fail=1
  fi
}

echo "== 检查 $FILE (64K 页内核就绪性) =="
TMPL="$TMPDIR_CHECK/loaders.list"
extract_loaders "$FILE" > "$TMPL"
found=0
while read -r arch elfpath size; do
  found=1
  rd=""
  case "$arch" in
    aarch64) rd="$BIN/aarch64-linux-cosmo-readelf" ;;
    x86_64)  rd="$BIN/x86_64-linux-cosmo-readelf" ;;
  esac
  echo "-- 内嵌 $arch loader ($size B)"
  check_arch "$arch" "$elfpath" "$rd"
done < "$TMPL"
if [ "$found" = 0 ]; then
  echo "✗ 未发现内嵌 gzip ELF loader，无法证明 64K 就绪" >&2
  exit 1
fi
[ "$fail" = 0 ] && echo "== ✓ 64K 页内核就绪 ==" || { echo "== ✗ 存在 64K 不兼容 =="; exit 1; }
