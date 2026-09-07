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
case "$MODE" in full|--min) ;; *) die "未知打包模式: $MODE（仅支持 full 或 --min）" ;; esac
[ -f "$TREE_X86/busybox_unstripped" ] || die "缺 x86_64 产物, 先跑 scripts/build-ape.sh x86_64"
[ -f "$TREE_A64/busybox_unstripped" ] || die "缺 aarch64 产物, 先跑 scripts/build-ape.sh aarch64"
for required in ape-loader-aarch64 ape-loader-x86_64 ape-loader-macos-arm64 ape-loader-macos-x86_64; do
  [ -f "$LOADERS/$required" ] || die "缺发布所需 loader: $LOADERS/$required"
done
if [ "$MODE" = full ]; then
  for required in ape-m1-loader-src.c assimilate install-linux.sh; do
    [ -f "$LOADERS/$required" ] || die "缺完整包所需文件: $LOADERS/$required"
  done
fi

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
  cp "$LOADERS/ape-loader-aarch64" "$LOADERS/ape-loader-x86_64" "$MIN_OUT/"
  # mac loader (Apple Silicon 真机免 cc 自举用; x86_64 mac 走内置 --assimilate)
  cp "$LOADERS/ape-loader-macos-arm64" "$LOADERS/ape-loader-macos-x86_64" "$MIN_OUT/"
  cp "$ROOT/NOTICE.md" "$ROOT/licenses/BUSYBOX-GPL-2.0.txt" "$MIN_OUT/"
  cat > "$MIN_OUT/README.txt" <<'EOF'
busybox-cosmo 最小发布包

Linux/macOS: ./busybox ash script.sh
Windows x86_64（含 ARM64 仿真）: busybox.com ash script.sh
诊断: ./busybox ash bbcosmo doctor

busybox.com 是 x86_64+aarch64 fat APE；busybox 是平台选择、缓存和 loader
入口。ape-loader-* 与 macOS loader 必须和入口一起分发。Linux 可选执行
sudo ./busybox --setup-linux 注册系统 binfmt；这会修改系统配置。

最小包不含完整文档和测试。macOS ARM64、Windows ARM64 仿真仍是实验路径；
stty/raw TUI、可信 TLS、外部 xz 编码等不属于一致能力承诺。完整说明和源码见
busybox-cosmo 工程仓库的 docs/KNOWN-LIMITATIONS.md。
EOF
  rm -f "$DIST_DIR/busybox-min.zip"
  ( cd "$MIN_OUT" && zip -X -q -r "$DIST_DIR/busybox-min.zip" busybox.com busybox bbcosmo lib examples \
      ape-loader-aarch64 ape-loader-x86_64 \
      ape-loader-macos-arm64 ape-loader-macos-x86_64 README.txt NOTICE.md BUSYBOX-GPL-2.0.txt )
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
cp "$LOADERS"/ape-loader-* "$LOADERS"/ape-m1-loader-src.c "$LOADERS"/assimilate "$OUT/release/"
cp "$LOADERS/install-linux.sh" "$OUT/release/"

echo "=== 4. 测试/安装器/文档 ==="
cp "$ROOT/tests/smoke.sh" "$ROOT/tests/deep-test.sh" "$ROOT/tests/ash-contract.sh" \
  "$ROOT/tests/testlib.sh" "$ROOT/tests/smoke-test.bat" "$OUT/release/"
cp "$ROOT/scripts/bb.sh" "$OUT/release/busybox" && chmod 755 "$OUT/release/busybox"
cp "$ROOT/tests/smoke-full.sh" "$OUT/release/smoke-full.sh" 2>/dev/null || true
cp "$ROOT/install.sh" "$OUT/release/install.sh" && chmod 755 "$OUT/release/install.sh"
mkdir -p "$OUT/release/lib" "$OUT/release/examples"
cp "$ROOT/lib/portable.sh" "$OUT/release/lib/portable.sh"
cp "$ROOT/scripts/bbcosmo" "$OUT/release/bbcosmo" && chmod 755 "$OUT/release/bbcosmo"
cp "$ROOT/examples/portable-menu.sh" "$OUT/release/examples/portable-menu.sh" && chmod 755 "$OUT/release/examples/portable-menu.sh"
cp "$ROOT/tests/portable-contract.sh" "$OUT/release/portable-contract.sh"
cp "$ROOT/tests/ci-capability-gate.py" "$OUT/release/ci-capability-gate.py"
cp "$ROOT/docs/DEPLOYMENT.md" "$ROOT/docs/KNOWN-LIMITATIONS.md" \
  "$ROOT/docs/TESTING.md" "$ROOT/docs/ROADMAP.md" "$ROOT/docs/COSMO-ABI-CONTRACTS.md" \
  "$ROOT/docs/RUN-NO-SELF-MODIFY.md" "$OUT/release/"
cp "$ROOT/NOTICE.md" "$OUT/release/NOTICE.md"
cp "$ROOT/licenses/BUSYBOX-GPL-2.0.txt" "$OUT/release/BUSYBOX-GPL-2.0.txt"

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
busybox-$BB_VER Cosmopolitan 发布包（${BUILD_DATE}）

Linux/macOS: ./busybox ash script.sh
Windows x86_64（含 ARM64 仿真）: busybox.com ash script.sh
诊断: ./busybox ash bbcosmo doctor

主要文件:
  busybox.com / busybox-x86_64.ape  Windows/Linux/macOS x86_64 APE
  busybox-arm64.ape                 Linux/macOS ARM64 APE
  busybox-fat.ape                   x86_64 + ARM64 fat APE
  busybox-arm64-linux-elf           Linux ARM64 裸 ELF（含 64K 页布局）
  busybox                            平台选择、缓存与 loader 入口
  install.sh / install-linux.sh     用户安装与 Linux binfmt（按需）
  ash-contract.sh                   ash 与核心功能契约
  deep-test.sh / smoke-full.sh      压力与综合功能测试
  BUSYBOX-GPL-2.0.txt / NOTICE.md   源码许可与归属

先读 DEPLOYMENT.md 和 KNOWN-LIMITATIONS.md。macOS ARM64 与 Windows ARM64
仿真仍是实验 CI；stty/raw TUI、可信 TLS、外部 xz 编码等不能由普通冒烟推断。

发布件包含 BusyBox GPL 许可证、NOTICE 和校验清单。构建是否逐位可复现需要对
两份独立构建与打包结果作哈希比较，不能仅由 SOURCE_DATE_EPOCH 推断。
EOF
echo "=== 6. 校验清单与打包 zip ==="
( cd "$OUT/release" && {
    if command -v md5 >/dev/null 2>&1; then
      find . -type f ! -name md5sums.txt ! -name SHA256SUMS -print | LC_ALL=C sort |
        while IFS= read -r file; do md5 -r "$file"; done > md5sums.txt
    else
      find . -type f ! -name md5sums.txt ! -name SHA256SUMS -print | LC_ALL=C sort |
        while IFS= read -r file; do md5sum "$file"; done > md5sums.txt
    fi
  } )
( cd "$OUT/release" && {
    if command -v sha256sum >/dev/null 2>&1; then
      find . -type f ! -name md5sums.txt ! -name SHA256SUMS -print | LC_ALL=C sort |
        while IFS= read -r file; do sha256sum "$file"; done > SHA256SUMS
    else
      find . -type f ! -name md5sums.txt ! -name SHA256SUMS -print | LC_ALL=C sort |
        while IFS= read -r file; do shasum -a 256 "$file"; done > SHA256SUMS
    fi
  } )
rm -f "$DIST_DIR/busybox-cosmo-release.zip"
( cd "$OUT" && zip -X -qr "$DIST_DIR/busybox-cosmo-release.zip" release )

echo ""
echo "=== 发布包完成 ==="
ls -la "$OUT/release"
echo "zip: $DIST_DIR/busybox-cosmo-release.zip"
