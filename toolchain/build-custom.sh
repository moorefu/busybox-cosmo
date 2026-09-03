#!/usr/bin/env bash
# ============================================================
# build-custom.sh — 从官方 cosmopolitan 源码构建"定制工具链"
#
# 原则 (与 2026-09-03 已验证工具链逐字节一致):
#   [基座] 官方 cosmocc-3.9.2.zip        (编译驱动/GCC14, 驱动不自行构建)
#   [源码] 官方 cosmopolitan @3293fad    (jart/cosmopolitan master)
#   [补丁] patches/cosmo/cosmo-custom-full.patch (17 文件)
#   [构建] master 树内 make → o/<arch>/cosmopolitan.a + crt/ape 部件
#          (用基座 bin/make 4.4.1 自举; make 版本 3.81 会被拒)
#   [组装] 基座 + 替换 libcosmo.a/crt/ape.* + 重装 include/ (master 头)
#          + 补 4 个驱动包装脚本的 64K 页参数
#
# 用法:
#   toolchain/fetch-sources.sh             # 先下载官方材料 (已 sha 锁定)
#   toolchain/build-custom.sh [arch]       # x86_64|aarch64|all(默认)
#   toolchain/build-custom.sh assemble     # 只重组装 (源码已构建过)
#   toolchain/build-custom.sh verify       # 组装结果 vs 参考 .cosmocc/3.9.2
#
# 环境:
#   JOBS=N            并行度
#   KEEP_SRC=1        保留解压源码树 (加速重试)
#   FORCE=1           覆盖已存在产物
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DL="$ROOT/toolchain/download"
PATCH="$ROOT/patches/cosmo/cosmo-custom-full.patch"
LOG_DIR="$ROOT/log"
mkdir -p "$LOG_DIR"

COSMO_COMMIT="3293fad0a9eac7865c019be98fb993eeb933405e"
COSMO_TARBALL="$DL/cosmopolitan-$COSMO_COMMIT.tar.gz"
COSMOCC_ZIP="$DL/cosmocc-3.9.2.zip"

SRC_DIR="$ROOT/work/cosmopolitan-$COSMO_COMMIT"     # 解压+打补丁源码
OUT_TC="$ROOT/toolchain/cosmo"                       # 最终工具链
STAGE="$ROOT/work/cosmo-stage"                       # 组装暂存
JOBS="${JOBS:-8}"
TC_BASE="$ROOT/work/cosmocc-392-base"                # 官方基座解压处

log() { echo "[build] $*"; }
die() { echo "[build][错误] $*" >&2; exit 1; }

[ -f "$COSMO_TARBALL" ] || die "缺官方源码包, 先跑 toolchain/fetch-sources.sh"
[ -f "$COSMOCC_ZIP" ]   || die "缺官方 cosmocc zip, 先跑 toolchain/fetch-sources.sh"
[ -f "$PATCH" ]         || die "缺定制补丁: $PATCH"

# ---------- 0. 准备基座 (官方 cosmocc 3.9.2) ----------
prep_base() {
  if [ -x "$TC_BASE/bin/x86_64-unknown-cosmo-cc" ]; then
    log "复用官方基座 $TC_BASE"
    return
  fi
  log "解压官方 cosmocc 3.9.2 基座 → $TC_BASE"
  rm -rf "$TC_BASE" "$TC_BASE.tmp"
  mkdir -p "$(dirname "$TC_BASE")"
  ( cd "$(dirname "$TC_BASE")" && unzip -q "$COSMOCC_ZIP" -d cosmocc-392-base.tmp && mv cosmocc-392-base.tmp "$TC_BASE" )
  log "基座 OK: $(ls "$TC_BASE" | tr '\n' ' ')"
}

# ---------- 1. 官方源码 + 打补丁 ----------
prep_src() {
  local MARK="$SRC_DIR/.bb-cosmo-prepared"
  if [ -f "$MARK" ]; then
    log "复用已备源码树 $SRC_DIR (已打补丁, .cosmocc 就绪)"
    return
  fi
  log "解压官方 cosmopolitan master 源码 ..."
  rm -rf "$SRC_DIR"; mkdir -p "$ROOT/work"
  tar xzf "$COSMO_TARBALL" -C "$ROOT/work"
  # tarball 顶层目录 = cosmopolitan-<sha> 恰为 SRC_DIR; 若不同名则改过来
  if [ ! -d "$SRC_DIR" ]; then
    mv "$ROOT/work/cosmopolitan-$COSMO_COMMIT" "$SRC_DIR"
  fi

  log "打定制补丁 (17 文件) ..."
  ( cd "$SRC_DIR" && patch -p1 -s < "$PATCH" ) || die "补丁应用失败"

  # 追加定制(如 sethostname 跨平台实现): 按需逐个应用 patches/cosmo/cosmo-*-extra.patch
  for extra in "$ROOT/patches/cosmo"/cosmo-*-extra.patch; do
    [ -f "$extra" ] || continue
    log "打附加定制补丁 $(basename "$extra") ..."
    ( cd "$SRC_DIR" && patch -p1 -s < "$extra" ) || die "附加补丁失败: $extra"
  done

  log "预置 .cosmocc/3.9.2 (官方基座, make 自举用) ..."
  mkdir -p "$SRC_DIR/.cosmocc"
  ( cd "$SRC_DIR/.cosmocc" && unzip -q "$COSMOCC_ZIP" -d 3.9.2 && ln -sfn 3.9.2 current )
  touch "$MARK"
  log "源码树就绪: $SRC_DIR"
}

# ---------- 2. make 构建单架构产物 ----------
build_one() { # $1=arch(x86_64|aarch64)
  local arch="$1" mode="$1"
  local targets=()
  local LOG="$LOG_DIR/toolchain-build-$arch.log"
  local objs=()

  case "$arch" in
    x86_64)
      # 已验工具链 x86_64: 替换 libcosmo.a/crt.o + 新增 crtfastmath.o + ape 全套(ape.lds/ape.o/copy-self/no-modify-self)
      targets=( cosmopolitan.a libc/crt/crt.o libc/crt/crtfastmath.o \
                ape/ape.lds ape/ape.o ape/ape-copy-self.o ape/ape-no-modify-self.o )
      ;;
    aarch64)
      # 已验工具链仅替换 aarch64 的 libcosmo.a + crt.o (aarch64.lds 与官方一致, 不动)
      targets=( cosmopolitan.a libc/crt/crt.o )
      ;;
  esac

  for t in "${targets[@]}"; do objs+=( "o/$arch/$t" ); done
  # 头清单 o/cosmocc.h.txt 与 mode 无关 (package.sh 规则里两种 mode 都建它)
  objs+=( "o/cosmocc.h.txt" )

  if [ -f "$SRC_DIR/o/$arch/cosmopolitan.a" ] && [ "${FORCE:-0}" != "1" ]; then
    log "$arch cosmopolitan.a 已存在, 跳过 (FORCE=1 重建)"
    return
  fi

  log "=== make MODE=$arch (JOBS=$JOBS) → ${objs[*]} ==="
  # 注意: 系统 make 3.81 会被 cosmo Makefile 拒绝 → 用基座自带 GNU make 4.4.1
  ( cd "$SRC_DIR" \
    && .cosmocc/3.9.2/bin/make -j"$JOBS" MODE="$mode" "${objs[@]}" >"$LOG" 2>&1 ) \
    || { echo "  构建失败, 看尾部日志:"; tail -30 "$LOG"; die "make $arch 失败 (完整日志 $LOG)"; }

  for t in "${targets[@]}"; do
    [ -f "$SRC_DIR/o/$arch/$t" ] || die "缺产物 o/$arch/$t"
  done
  [ -f "$SRC_DIR/o/cosmocc.h.txt" ] || die "缺头清单 o/cosmocc.h.txt"
  log "$arch 产物 OK: $(du -sh "$SRC_DIR/o/$arch/cosmopolitan.a" | cut -f1)"
}

# ---------- 3. 组装工具链 ----------
assemble() {
  log "组装 toolchain/cosmo ← 官方基座 + master 产物 + master 头"
  rm -rf "$STAGE"
  ( cd "$ROOT/work" && cp -c -R cosmocc-392-base "$STAGE" )   # clonefile 秒级

  # 3a. 替换 x86_64 部件
  local X="$STAGE/x86_64-linux-cosmo/lib"
  cp -f "$SRC_DIR/o/x86_64/cosmopolitan.a"        "$X/libcosmo.a"
  cp -f "$SRC_DIR/o/x86_64/libc/crt/crt.o"        "$X/crt.o"
  cp -f "$SRC_DIR/o/x86_64/libc/crt/crtfastmath.o" "$X/crtfastmath.o"
  cp -f "$SRC_DIR/o/x86_64/ape/ape.lds"           "$X/ape.lds"
  cp -f "$SRC_DIR/o/x86_64/ape/ape.o"             "$X/ape.o"
  cp -f "$SRC_DIR/o/x86_64/ape/ape-copy-self.o"   "$X/ape-copy-self.o"
  cp -f "$SRC_DIR/o/x86_64/ape/ape-no-modify-self.o" "$X/ape-no-modify-self.o"

  # 3b. 替换 aarch64 部件
  local A="$STAGE/aarch64-linux-cosmo/lib"
  cp -f "$SRC_DIR/o/aarch64/cosmopolitan.a"       "$A/libcosmo.a"
  cp -f "$SRC_DIR/o/aarch64/libc/crt/crt.o"       "$A/crt.o"

  # 3c. include/ 整体替换为 master 头 (package.sh 规则)
  log "安装 master 头 → include/ (o/cosmocc.h.txt 规则)"
  local INC="$STAGE/include"
  rm -rf "$INC" && mkdir -p "$INC/libc/integral"
  cp -R "$SRC_DIR/libc/isystem/."   "$INC/"
  cp    "$SRC_DIR/libc/integral/"*  "$INC/libc/integral/"
  local n=0
  for h in $(cat "$SRC_DIR/o/cosmocc.h.txt"); do
    [ -z "$h" ] && continue
    mkdir -p "$INC/$(dirname "$h")"
    cp -f "$SRC_DIR/$h" "$INC/$h"
    n=$((n+1))
  done
  log "  头文件 $n 个 (cosmocc.h.txt) + isystem/integral"

  # 3d. 驱动包装脚本: 64K 页参数 (与已验 .cosmocc/3.9.2 一致)
  #     注意: 官方 zip 里 5 个包装脚本是同一文件的硬链接 — 改一个等于全改, 故幂等
  log "补驱动脚本 64K 页参数 (PAGESZ/max-page-size)"
  for w in x86_64-unknown-cosmo-cc x86_64-unknown-cosmo-c++ \
           aarch64-unknown-cosmo-cc aarch64-unknown-cosmo-c++ cosmocross; do
    local f="$STAGE/bin/$w"
    [ -f "$f" ] || die "缺包装脚本 $f"
    python3 - "$f" <<'PY'
import sys
p=sys.argv[1]
s=open(p).read()
have_old = ("PAGESZ=16384" in s) or ("max-page-size=16384" in s)
have_new = ("PAGESZ=65536" in s) and ("max-page-size=$PAGESZ" in s)
if have_new:
    sys.exit(0)  # 幂等: 已是 64K 形态 (硬链接兄弟文件已改)
if not have_old:
    sys.exit("wrapper 格式不符(既非 64K 亦非 16K): "+p)
s=s.replace("PAGESZ=16384","PAGESZ=65536")
s=s.replace("-Wl,-z,common-page-size=$PAGESZ -Wl,-z,max-page-size=16384",
            "-Wl,-z,common-page-size=$PAGESZ -Wl,-z,max-page-size=$PAGESZ")
open(p,"w").write(s)
PY
  done

  # 3e. 落盘
  log "落盘 → $OUT_TC"
  rm -rf "$OUT_TC"
  ( cd "$ROOT/work" && cp -c -R cosmo-stage "$OUT_TC" )
  rm -rf "$STAGE"
  log "工具链完成: $OUT_TC ($(du -sh "$OUT_TC" | cut -f1))"
}

# ---------- 4. 校验 vs 参考 .cosmocc/3.9.2 ----------
verify() {
  local REF="${COSMO_REF:-/tmp/cosmopolitan-master/.cosmocc/3.9.2}"
  log "校验 $OUT_TC vs 参考 $REF"
  log "  对象(.a/.o): 比对 strip-debug 后代码节 (DWARF 含构建路径, 逐字节不可比)"
  log "  文本/脚本/头: 逐字节比对"
  local ok=1

  # 对象类 — 剥调试信息后比代码节
  local tmpdir="/tmp/bb-verify-$$"
  mkdir -p "$tmpdir"
  for f in \
    x86_64-linux-cosmo/lib/libcosmo.a \
    x86_64-linux-cosmo/lib/crt.o x86_64-linux-cosmo/lib/crtfastmath.o \
    x86_64-linux-cosmo/lib/ape.o x86_64-linux-cosmo/lib/ape-copy-self.o \
    x86_64-linux-cosmo/lib/ape-no-modify-self.o \
    aarch64-linux-cosmo/lib/libcosmo.a aarch64-linux-cosmo/lib/crt.o; do
    # 选本架构的 strip/ar (x86 objcopy 不能处理 aarch64 对象; 用组装产物自带的)
    local arch=; [[ "$f" == aarch64-* ]] && arch=aarch64 || arch=x86_64
    local stripbin="$OUT_TC/bin/$arch-linux-cosmo-objcopy"
    local arbin="$OUT_TC/bin/$arch-linux-cosmo-ar"
    local tag=$(basename "$f" | tr '.' '_')
    if [[ "$f" == *.a ]]; then
      mkdir -p "$tmpdir/${tag}_a" "$tmpdir/${tag}_b"
      ( cd "$tmpdir/${tag}_a" && cp "$OUT_TC/$f" x.a && "$arbin" x x.a ) || { log "  ✗ $f 解包失败"; ok=0; continue; }
      ( cd "$tmpdir/${tag}_b" && cp "$REF/$f" x.a && "$arbin" x x.a ) || { log "  ✗ $f 解包失败"; ok=0; continue; }
      local na nb ndiff=0 extra=0
      na=$(ls "$tmpdir/${tag}_a" | grep -c '\.o$' || true)
      nb=$(ls "$tmpdir/${tag}_b" | grep -c '\.o$' || true)
      # 允许"我方 = 参考 + 本工程附加成员"(如 sethostname.o), 附加清单如下
      local extra_ok=1
      if [ "$na" -lt "$nb" ]; then
        log "  ✗ $f: 我方成员数 $na < 参考 $nb"; ok=0; continue
      fi
      for o in "$tmpdir/${tag}_a"/*.o; do
        [ -e "$o" ] || continue
        local b=$(basename "$o")
        if [ ! -f "$tmpdir/${tag}_b/$b" ]; then
          case "$b" in
            sethostname.o) extra=$((extra+1)) ;;   # 本工程 cosmo-sethostname-extra.patch 附加
            *) extra_ok=0 ;;
          esac
          continue
        fi
        "$stripbin" --strip-debug "$o" "$tmpdir/s1.o" 2>/dev/null || true
        "$stripbin" --strip-debug "$tmpdir/${tag}_b/$b" "$tmpdir/s2.o" 2>/dev/null || true
        cmp -s "$tmpdir/s1.o" "$tmpdir/s2.o" || ndiff=$((ndiff+1))
      done
      if [ "$extra_ok" = "1" ] && [ "$ndiff" = "0" ]; then
        log "  ✓ $f ($nb 参考成员代码一致 + 本工程附加 $extra 成员)"
      else
        log "  ✗ $f: $ndiff 个不一致 / 非法附加成员"; ok=0
      fi
    else
      "$stripbin" --strip-debug "$OUT_TC/$f" "$tmpdir/v1.o" 2>/dev/null || true
      "$stripbin" --strip-debug "$REF/$f" "$tmpdir/v2.o" 2>/dev/null || true
      if cmp -s "$tmpdir/v1.o" "$tmpdir/v2.o"; then log "  ✓ $f (strip-debug 代码一致)"
      else log "  ✗ 差异: $f"; ok=0; fi
    fi
  done

  # 文本/脚本/头 — 逐字节
  for f in \
    include/stdio.h include/libc/intrin/fds.h \
    bin/cosmocross bin/x86_64-unknown-cosmo-cc bin/aarch64-unknown-cosmo-cc; do
    if cmp -s "$OUT_TC/$f" "$REF/$f" 2>/dev/null; then log "  ✓ $f (逐字节)"
    else log "  ✗ 差异: $f"; ok=0; fi
  done

  rm -rf "$tmpdir"
  if [ $ok = 1 ]; then log "=== 校验通过: 与已验证 .cosmocc/3.9.2 代码/内容一致 ==="
  else die "存在差异, 请人工核对"; fi
}

# ---------- main ----------
MODE_MAIN="${1:-all}"
case "$MODE_MAIN" in
  x86_64|aarch64) prep_base; prep_src; ( cd "$SRC_DIR" && build_one "$MODE_MAIN" ) ;;
  all)            prep_base; prep_src
                  ( cd "$SRC_DIR" && build_one x86_64 )
                  ( cd "$SRC_DIR" && build_one aarch64 ) ;;
  assemble)       [ -d "$SRC_DIR/o/x86_64" ] || die "缺源码构建产物, 先跑 build-custom.sh all"
                  [ -d "$TC_BASE" ] || prep_base; assemble ;;
  verify)         verify ;;
  *) die "未知参数: $MODE_MAIN (x86_64|aarch64|all|assemble|verify)" ;;
esac
log "完成"
