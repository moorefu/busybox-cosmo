#!/usr/bin/env bash
# ============================================================
# package-release.sh — 生成三平台 + fat 发布包 (复刻 build-release.sh)
#   前置: scripts/build-ape.sh all 已产出两架构
#   产出: dist/release/ 目录 + dist/busybox-cosmo-release.zip
#         (zip 顶层目录名 "release/" 与既有基线包一致)
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

OUT="$DIST_DIR/release"
LOADERS="$ROOT/assets/loaders"

# ---- 前置检查 ----
[ -f "$TREE_X86/busybox_unstripped" ] || die "缺 x86_64 产物, 先跑 scripts/build-ape.sh x86_64"
[ -f "$TREE_A64/busybox_unstripped" ] || die "缺 aarch64 产物, 先跑 scripts/build-ape.sh aarch64"

rm -rf "$OUT" && mkdir -p "$OUT/release"

echo "=== 1. busybox 主产物 ==="
# x86_64 APE (Windows/Linux/macOS x86_64 通用; Windows 需改名 .com/.exe)
"$TC_APELINK" -o "$OUT/release/busybox-x86_64.ape" "$TREE_X86/busybox_unstripped"
cp "$OUT/release/busybox-x86_64.ape" "$OUT/release/busybox.com"
# aarch64 APE
"$TC_APELINK" -o "$OUT/release/busybox-arm64.ape" "$TREE_A64/busybox_unstripped"
# aarch64 裸 ELF (64KB 页内核专用, 免 loader)
cp "$TREE_A64/busybox_unstripped" "$OUT/release/busybox-arm64-linux-elf"
# aarch64 stripped 小版
( cd "$TREE_A64" && "$TC_A64_ST" -o "$OUT/release/busybox-arm64-linux" busybox_unstripped ) || cp "$TREE_A64/busybox" "$OUT/release/busybox-arm64-linux"

echo "=== 2. fat 双架构合成 ==="
"$TC_APELINK" -o "$OUT/release/busybox-fat.ape" "$TREE_X86/busybox_unstripped" "$TREE_A64/busybox_unstripped"

echo "=== 3. ape loader (64K 页 / 无 binfmt 场景) ==="
if [ -d "$LOADERS" ]; then
  cp "$LOADERS"/ape-loader-* "$LOADERS"/ape-m1-loader-src.c "$OUT/release/" 2>/dev/null || true
  cp "$LOADERS/install-linux.sh" "$OUT/release/" 2>/dev/null || true
fi

echo "=== 4. 测试与文档 ==="
cp "$ROOT/tests/smoke.sh" "$ROOT/tests/deep-test.sh" "$ROOT/tests/smoke-test.bat" "$OUT/release/"
cp "$ROOT/docs/PROJECT-HISTORY.md" "$OUT/release/PROJECT-HISTORY.md" 2>/dev/null || true
cp "$ROOT/docs/VERIFICATION-MATRIX.md" "$OUT/release/VERIFICATION-MATRIX.md" 2>/dev/null || true

echo "=== 5. 生成 README.txt ==="
BUILD_DATE="$(date '+%Y-%m-%d')"
cat > "$OUT/release/README.txt" <<EOF
busybox-$BB_VER cosmopolitan 发布包 ($BUILD_DATE, 本工程可复现构建)

文件说明:
  busybox-x86_64.ape         x86_64 APE: Windows/Linux/macOS x86_64 通用
  busybox.com                = 同上(Windows 便捷名, 需含 busybox 名才能子命令模式)
  busybox-arm64.ape          aarch64 APE (4K/16K 页; mac arm64 自举 loader)
  busybox-arm64-linux-elf    aarch64 ELF: 4K/16K/64K 页 Linux aarch64 通用
                             ★ 64KB 页内核(UOS/麒麟鲲鹏)必须用此 ELF 版
  busybox-arm64-linux        arm64 stripped(小体积备用)
  busybox-fat.ape            fat 双架构(x86_64 + aarch64)
  ape-loader-*               ape loader (64K 页/无 binfmt 部署, 见 install-linux.sh)
  smoke.sh/deep-test.sh      测试(各平台: busybox sh smoke.sh)
  smoke-test.bat             Windows 冒烟
  md5sums.txt                校验清单

工程: /Users/moore/Projects/busybox-cosmo (补丁/config/脚本/doc 均入库, 可复现)
复现: SOURCE_DATE_EPOCH=<epoch> make build   (固定后逐位可复现, 见 VERIFICATION-MATRIX.md)

重要规则:
  1. APE 首次在某平台运行会"同化"改写成纯本机格式——分发请 zip 母本; 每平台各拷原件首跑。
  2. Windows: 文件名须含 "busybox"(如 busybox.exe/busybox.com) 才能用子命令模式;
     建议 Windows Terminal 运行; cmd 下 chcp 65001。
  3. 64KB 页 Linux aarch64 用 busybox-arm64-linux-elf(勿用 APE)。
  4. 测试副本先行, 勿直接运行发布原件(会触发同化)。
EOF
echo "=== 6. 校验清单与打包 zip ==="
( cd "$OUT/release" && md5 * > md5sums.txt 2>/dev/null || md5sum * > md5sums.txt )
( cd "$OUT" && zip -qr "$DIST_DIR/busybox-cosmo-release.zip" release )

echo ""
echo "=== 发布包完成 ==="
ls -la "$OUT/release"
echo "zip: $DIST_DIR/busybox-cosmo-release.zip"
