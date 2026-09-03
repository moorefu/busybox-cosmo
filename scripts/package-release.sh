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
"$TC_APELINK" $(apelink_embed_args x86_64) -o "$OUT/release/busybox-x86_64.ape" "$TREE_X86/busybox_unstripped"
cp "$OUT/release/busybox-x86_64.ape" "$OUT/release/busybox.com"
# aarch64 APE
"$TC_APELINK" $(apelink_embed_args aarch64) -o "$OUT/release/busybox-arm64.ape" "$TREE_A64/busybox_unstripped"
# aarch64 裸 ELF (64KB 页内核专用, 免 loader)
cp "$TREE_A64/busybox_unstripped" "$OUT/release/busybox-arm64-linux-elf"
# aarch64 stripped 小版
( cd "$TREE_A64" && "$TC_A64_ST" -o "$OUT/release/busybox-arm64-linux" busybox_unstripped ) || cp "$TREE_A64/busybox" "$OUT/release/busybox-arm64-linux"

echo "=== 2. fat 双架构合成 ==="
"$TC_APELINK" -l "$APE_LDR_X86" -l "$APE_LDR_A64" -M "$APE_M1_SRC" -o "$OUT/release/busybox-fat.ape" "$TREE_X86/busybox_unstripped" "$TREE_A64/busybox_unstripped"

echo "=== 3. ape loader (64K 页 / 无 binfmt 场景) ==="
if [ -d "$LOADERS" ]; then
  cp "$LOADERS"/ape-loader-* "$LOADERS"/ape-m1-loader-src.c "$LOADERS"/assimilate "$OUT/release/" 2>/dev/null || true
  cp "$LOADERS/install-linux.sh" "$OUT/release/" 2>/dev/null || true
fi

echo "=== 4. 测试/安装器/文档 ==="
cp "$ROOT/tests/smoke.sh" "$ROOT/tests/deep-test.sh" "$ROOT/tests/smoke-test.bat" "$OUT/release/"
cp "$ROOT/tests/smoke-full.sh" "$OUT/release/smoke-full.sh" 2>/dev/null || true
cp "$ROOT/install.sh" "$OUT/release/install.sh" && chmod 755 "$OUT/release/install.sh"
cp "$ROOT/docs/PROJECT-HISTORY.md" "$OUT/release/PROJECT-HISTORY.md" 2>/dev/null || true
cp "$ROOT/docs/VERIFICATION-MATRIX.md" "$OUT/release/VERIFICATION-MATRIX.md" 2>/dev/null || true
cp "$ROOT/docs/RUN-NO-SELF-MODIFY.md" "$OUT/release/RUN-NO-SELF-MODIFY.md" 2>/dev/null || true

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
  assimilate                 原生转换工具(install.sh 用其生成全功能原生副本)
  install.sh                 统一跨平台安装器 (loader/binfmt/cache 策略)
  smoke.sh/deep-test.sh      测试(各平台: busybox sh smoke.sh)
  smoke-test.bat             Windows 冒烟
  md5sums.txt                校验清单

工程: /Users/moore/Projects/busybox-cosmo (补丁/config/脚本/doc 均入库, 可复现)
复现: SOURCE_DATE_EPOCH=<epoch> make build   (固定后逐位可复现, 见 VERIFICATION-MATRIX.md)

重要规则:
  1. 本发布件为"内嵌 ape loader"官方形态(apelink -l/-M)——直接运行不再改写自身
     (母本 md5 恒定); 但 loader 形态下 ash 嵌套子命令受限, 完整 shell 请用:
        ./install.sh [--prefix DIR]          # 生成 cache 原生副本(assimilate), 全功能且母本不改
        sudo ./install.sh --linux-binfmt     # Linux 内核级直跑(全功能+不改)
        BB_USE_LOADER=1 亦可(见 RUN-NO-SELF-MODIFY.md)
  2. Windows: 文件名须含 "busybox"(如 busybox.exe/busybox.com) 才能用子命令模式;
     建议 Windows Terminal 运行; cmd 下 chcp 65001。
  3. 64KB 页 Linux aarch64 用 busybox-arm64-linux-elf(勿用 APE)。
  4. 顶层命令/单测可直接 ./busybox-x86_64.ape sh smoke-full.sh(loader 形态可跑多数项)。
EOF
echo "=== 6. 校验清单与打包 zip ==="
( cd "$OUT/release" && md5 * > md5sums.txt 2>/dev/null || md5sum * > md5sums.txt )
( cd "$OUT" && zip -qr "$DIST_DIR/busybox-cosmo-release.zip" release )

echo ""
echo "=== 发布包完成 ==="
ls -la "$OUT/release"
echo "zip: $DIST_DIR/busybox-cosmo-release.zip"
