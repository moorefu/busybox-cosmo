#!/usr/bin/env bash
# ============================================================
# package-release.sh — 生成三平台 + fat 发布包 (复刻 build-release.sh)
#   前置: scripts/build-ape.sh all 已产出两架构
#   产出: dist/release/ 目录 + dist/busybox-cosmo-release.zip
#         (zip 顶层目录名 "release/" 与既有基线包一致)
#   用法:
#     package-release.sh          完整包 (busybox-*.ape + loaders + install + 测试/文档)
#     package-release.sh --min    最小包 (busybox.com=fat + busybox + assimilate + README)
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

MODE="${1:-full}"
OUT="$DIST_DIR/release"
LOADERS="$ROOT/assets/loaders"
MIN_OUT="$DIST_DIR/min"

# ---- 前置检查 ----
[ -f "$TREE_X86/busybox_unstripped" ] || die "缺 x86_64 产物, 先跑 scripts/build-ape.sh x86_64"
[ -f "$TREE_A64/busybox_unstripped" ] || die "缺 aarch64 产物, 先跑 scripts/build-ape.sh aarch64"

if [ "$MODE" = "--min" ]; then
  echo "=== 生成最小发布包 dist/busybox-min.zip ==="
  rm -rf "$MIN_OUT" && mkdir -p "$MIN_OUT"
  # fat 单文件(含 x86_64+aarch64 载荷, 内嵌 loader) → 命名 busybox.com: Windows 直跑, mac/linux 由 busybox 脚本跑
  "$TC_APELINK" -l "$APE_LDR_X86" -l "$APE_LDR_A64" -M "$APE_M1_SRC" \
    -o "$MIN_OUT/busybox.com" "$TREE_X86/busybox_unstripped" "$TREE_A64/busybox_unstripped"
  chmod 755 "$MIN_OUT/busybox.com"
  cp "$ROOT/scripts/bb.sh" "$MIN_OUT/busybox" && chmod 755 "$MIN_OUT/busybox"
  cp "$LOADERS/assimilate" "$MIN_OUT/assimilate" && chmod 755 "$MIN_OUT/assimilate"
  cp "$ROOT/tests/smoke-full.sh" "$MIN_OUT/smoke-full.sh"
  cat > "$MIN_OUT/README.txt" <<'EOF'
busybox-cosmo 最小发布包 (fat 单文件)

文件:
  busybox.com   fat APE (x86_64 + aarch64, 内嵌 loader)
                Windows: 直跑(须含 busybox 名), 覆盖 x86_64; ARM 版 Windows 不支持
                mac/Linux: 交给同目录 busybox 脚本运行(自动生成原生副本)
  busybox       零安装 launcher: 首跑 cp busybox.com→cache 并用 assimilate 转原生
                (mac=Mach-O / Linux=ELF), 之后运行原生副本(全功能 shell); 母本从不改
  assimilate    原生转换工具(launcher 依赖)
  smoke-full.sh 完整回归 (busybox sh smoke-full.sh)

用法:
  mac/Linux : ./busybox <args>          (或 ./busybox sh smoke-full.sh)
  Windows   : busybox.com <args>        (子命令模式; 建议 Windows Terminal)

cache: $BUSYBOX_COSMO_CACHE → $XDG_CACHE_HOME/busybox-cosmo → ~/.cache/busybox-cosmo
说明/局限: 见完整包 RUN-NO-SELF-MODIFY.md; 64K 页 Linux aarch64(鲲鹏/UOS)请用完整包的
busybox-arm64-linux-elf。loader 形态直跑(不经 busybox)时 ash 嵌套 exec 受限。
EOF
  ( cd "$MIN_OUT" && zip -q "$DIST_DIR/busybox-min.zip" busybox.com busybox assimilate smoke-full.sh README.txt )
  echo "最小包完成: $DIST_DIR/busybox-min.zip"
  ls -la "$MIN_OUT"
  exit 0
fi

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
cp "$ROOT/scripts/bb.sh" "$OUT/release/busybox" && chmod 755 "$OUT/release/busybox"
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
  busybox                    零安装 launcher (同目录直跑: 自动 cache+原生副本)
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
