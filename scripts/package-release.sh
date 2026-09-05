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
  # fat 单文件(含 x86_64+aarch64 载荷 + 64K 对齐内嵌 loader) → 命名 busybox.com
  "$TC_APELINK" -l "$APE_LDR_X86" -l "$APE_LDR_A64" -M "$APE_M1_SRC" \
    -o "$MIN_OUT/busybox.com" "$TREE_X86/busybox_unstripped" "$TREE_A64/busybox_unstripped"
  chmod 755 "$MIN_OUT/busybox.com"
  "$ROOT/scripts/check-ape-64k.sh" "$MIN_OUT/busybox.com" >/dev/null || die "min busybox.com 64K 自检失败 (内嵌 loader 非 64K 对齐?)"
  cp "$ROOT/scripts/bb.sh" "$MIN_OUT/busybox" && chmod 755 "$MIN_OUT/busybox"
  mkdir -p "$MIN_OUT/lib" "$MIN_OUT/examples"
  cp "$ROOT/lib/portable.sh" "$MIN_OUT/lib/portable.sh"
  cp "$ROOT/scripts/bbcosmo" "$MIN_OUT/bbcosmo" && chmod 755 "$MIN_OUT/bbcosmo"
  cp "$ROOT/examples/portable-menu.sh" "$MIN_OUT/examples/portable-menu.sh" && chmod 755 "$MIN_OUT/examples/portable-menu.sh"
  cp "$LOADERS/ape-loader-aarch64" "$LOADERS/ape-loader-x86_64" "$MIN_OUT/" 2>/dev/null || true
  # mac loader (Apple Silicon 真机免 cc 自举用; x86_64 mac 走内置 --assimilate)
  cp "$LOADERS/ape-loader-macos-arm64" "$LOADERS/ape-loader-macos-x86_64" "$MIN_OUT/" 2>/dev/null || true
  cat > "$MIN_OUT/README.txt" <<'EOF'
busybox-cosmo 最小发布包 (fat 单文件)

文件:
  busybox.com      fat APE (x86_64 + aarch64 载荷, 内嵌 64K 对齐 loader)
                   Windows: 直跑 (文件名须含 busybox; 覆盖 x86_64)
                   mac/Linux: 由同目录 busybox 脚本运行
  busybox          零安装 launcher (内含 Linux binfmt 部署子命令)
                   mac x86_64: fat 内置 --assimilate 自同化 → Mach-O (免外部工具)
                   mac arm64 : 自动把 ape-loader-macos-arm64 放 ~/.ape-1.10 免 cc;
                               loader 形态已全功能 (2026-09-04 修复: MODERN 标志/
                               载荷路径解析, 嵌套 exec 可用)
                   Linux: 无 binfmt 时退 loader 形态 (自备 ~/.ape-1.10 或
                           --setup-linux 后嵌套 exec 亦全功能)
  ape-loader-*     --setup-linux 用 (aarch64/x86_64) + mac 免 cc (macos-arm64/x86_64)
  bbcosmo/lib/     诊断、能力报告与可移植 Shell 基础库
  examples/        行式/非交互菜单示例
  README.txt       本说明

用法:
  Windows   : busybox.com <args>
  mac/Linux : ./busybox <args>              (零安装; mac x86_64 自动全功能)
  mac arm64 : ./busybox <args> 顶层可用; 完整 shell 用完整包或 Rosetta 跑 x86_64
  Linux 全功能: sudo ./busybox --setup-linux 一次
                   (装 /usr/bin/ape + 注册 binfmt FP; 之后直接 exec
                    busybox.com 即全功能 shell, 64K 页内核同样可用)
  64K 页 Linux aarch64 (鲲鹏/UOS): 同上 --setup-linux (loader 已 64K 对齐)
  验证注册: ./busybox --setup-linux (非 root 会提示用 sudo)

cache: $BUSYBOX_COSMO_CACHE → $XDG_CACHE_HOME/busybox-cosmo → ~/.cache/busybox-cosmo
局限: 见完整包 RUN-NO-SELF-MODIFY.md。loader 形态 (无 binfmt Linux / mac arm64)
自 2026-09-04 修复后嵌套 exec 已全功能 (launcher 自动置 ~/.ape-1.10);
全功能替代: mac x86_64 自同化, Linux sudo ./busybox --setup-linux。
EOF
  rm -f "$DIST_DIR/busybox-min.zip"
  ( cd "$MIN_OUT" && zip -X -q -r "$DIST_DIR/busybox-min.zip" busybox.com busybox bbcosmo lib examples \
      ape-loader-aarch64 ape-loader-x86_64 \
      ape-loader-macos-arm64 ape-loader-macos-x86_64 README.txt )
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
"$ROOT/scripts/check-ape-64k.sh" "$OUT/release/busybox-fat.ape" >/dev/null || die "fat 64K 自检失败 (内嵌 loader 非 64K 对齐?)"

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
mkdir -p "$OUT/release/lib" "$OUT/release/examples"
cp "$ROOT/lib/portable.sh" "$OUT/release/lib/portable.sh"
cp "$ROOT/scripts/bbcosmo" "$OUT/release/bbcosmo" && chmod 755 "$OUT/release/bbcosmo"
cp "$ROOT/examples/portable-menu.sh" "$OUT/release/examples/portable-menu.sh" && chmod 755 "$OUT/release/examples/portable-menu.sh"
cp "$ROOT/tests/portable-contract.sh" "$OUT/release/portable-contract.sh"
cp "$ROOT/docs/PROJECT-HISTORY.md" "$OUT/release/PROJECT-HISTORY.md" 2>/dev/null || true
cp "$ROOT/docs/VERIFICATION-MATRIX.md" "$OUT/release/VERIFICATION-MATRIX.md" 2>/dev/null || true
cp "$ROOT/docs/RUN-NO-SELF-MODIFY.md" "$OUT/release/RUN-NO-SELF-MODIFY.md" 2>/dev/null || true
cp "$ROOT/docs/KNOWN-LIMITATIONS.md" "$ROOT/docs/REMEDIATION-PLAN.md" "$ROOT/docs/COSMO-ABI-CONTRACTS.md" "$OUT/release/" 2>/dev/null || true
cp "$ROOT/docs/PORTABLE-RUNTIME-PLAN.md" "$OUT/release/" 2>/dev/null || true
cp "$ROOT/NOTICE.md" "$OUT/release/NOTICE.md" 2>/dev/null || true
cp "$ROOT/src/busybox-$BB_VER/LICENSE" "$OUT/release/BUSYBOX-LICENSE" 2>/dev/null || true

echo "=== 5. 生成 README.txt ==="
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  if date -u -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%d' >/dev/null 2>&1; then
    BUILD_DATE="$(date -u -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%d')"
  else
    BUILD_DATE="$(date -u -r "$SOURCE_DATE_EPOCH" '+%Y-%m-%d')"
  fi
else
  BUILD_DATE="$(date -u '+%Y-%m-%d')"
fi
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
  bbcosmo                    运行诊断与能力报告入口
  lib/portable.sh            跨平台 Shell 基础库
  examples/portable-menu.sh 行式/非交互菜单示例
  portable-contract.sh       兼容库契约测试
  smoke.sh/deep-test.sh      测试(各平台: busybox sh smoke.sh)
  smoke-test.bat             Windows 冒烟
  md5sums.txt                校验清单

工程: busybox-cosmo (补丁/config/脚本/doc 均入库, 可复现)
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
( cd "$OUT/release" && {
    if command -v md5 >/dev/null 2>&1; then
      find . -type f ! -name md5sums.txt ! -name SHA256SUMS -exec md5 {} + > md5sums.txt
    else
      find . -type f ! -name md5sums.txt ! -name SHA256SUMS -exec md5sum {} + > md5sums.txt
    fi
  } )
( cd "$OUT/release" && {
    if command -v sha256sum >/dev/null 2>&1; then
      find . -type f ! -name md5sums.txt ! -name SHA256SUMS -exec sha256sum {} + > SHA256SUMS
    else
      find . -type f ! -name md5sums.txt ! -name SHA256SUMS -exec shasum -a 256 {} + > SHA256SUMS
    fi
  } )
rm -f "$DIST_DIR/busybox-cosmo-release.zip"
( cd "$OUT" && zip -X -qr "$DIST_DIR/busybox-cosmo-release.zip" release )

echo ""
echo "=== 发布包完成 ==="
ls -la "$OUT/release"
echo "zip: $DIST_DIR/busybox-cosmo-release.zip"
