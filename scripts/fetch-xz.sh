#!/usr/bin/env bash
# ============================================================
# fetch-xz.sh — 获取 xz 锁定源码 (5.4 LTS, 供应线第一步)
#   1) work/companions/xz-5.4.7/ 已存在且校验标志匹配 → 跳过
#   2) 否则下载锁定 tarball (refs/companions/), 校验 sha256 后解压
# 用法: scripts/fetch-xz.sh
# 环境: XZ_URL/XZ_SHA256 可用 env 覆盖 (离线/镜像场景)
# 说明: 锁定值来自官方 tukaani.org→github release v5.4.7 原始 tarball;
#       不依赖任何滚动目录。构建见 scripts/build-xz.sh。
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

XZ_SRC="$WORK_DIR/companions/xz-$XZ_VER"
XZ_TARBALL_PATH="$COMPANION_REF_DIR/$XZ_TARBALL"

mkdir -p "$COMPANION_REF_DIR"

tmp_tar=""
cleanup() {
  [ -z "$tmp_tar" ] || rm -f "$tmp_tar"
}
trap cleanup EXIT

sha256_check() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    echo "[fetch-xz][错误] 缺少 sha256sum/shasum，拒绝无校验提取" >&2
    return 1
  fi
  [ "$actual" = "$XZ_SHA256" ] || {
    echo "[fetch-xz][错误] SHA256 不匹配: $file (实际 $actual, 期望 $XZ_SHA256)" >&2
    return 1
  }
}

# 已存在则校验目录标志 (.xz-src-ok); 构建脚本会按锁定 tarball 全新重建,
# 因此对残留/无标志目录一律清理重来, 不信任既有内容
if [ -d "$XZ_SRC" ]; then
  if [ -f "$XZ_SRC/.xz-src-ok" ] && grep -qx "sha256=$XZ_SHA256" "$XZ_SRC/.xz-src-ok"; then
    echo "[fetch-xz] xz-$XZ_VER 源码已就绪: $XZ_SRC"
    exit 0
  fi
  echo "[fetch-xz][警告] 移除残留/不匹配的构建树, 将从锁定 tarball 重建: $XZ_SRC" >&2
  rm -rf "$XZ_SRC"
fi

if [ -f "$XZ_TARBALL_PATH" ] && sha256_check "$XZ_TARBALL_PATH"; then
  echo "[fetch-xz] 使用已有且校验通过的 tarball: $XZ_TARBALL_PATH"
elif [ -f "$XZ_TARBALL_PATH" ]; then
  echo "[fetch-xz][警告] 删除校验失败的缓存 tarball: $XZ_TARBALL_PATH" >&2
  rm -f "$XZ_TARBALL_PATH"
fi

if [ ! -f "$XZ_TARBALL_PATH" ]; then
  tmp_tar="$(mktemp "$COMPANION_REF_DIR/.xz-download.XXXXXX")"
  echo "[fetch-xz] 下载 $XZ_URL ..."
  if curl -fL --connect-timeout 10 --max-time 180 -o "$tmp_tar" "$XZ_URL" \
      && sha256_check "$tmp_tar"; then
    mv -f "$tmp_tar" "$XZ_TARBALL_PATH"
    tmp_tar=""
  else
    echo "[fetch-xz][错误] 下载或校验失败: $XZ_URL" >&2
    exit 1
  fi
fi

echo "[fetch-xz] sha256 校验 ..."
sha256_check "$XZ_TARBALL_PATH" || { echo "[fetch-xz] 校验失败 (可用 XZ_SHA256= 覆盖)"; exit 1; }

echo "[fetch-xz] 解压 ..."
mkdir -p "$WORK_DIR/companions"
tar xJf "$XZ_TARBALL_PATH" -C "$WORK_DIR/companions"
printf 'sha256=%s\ntarball=%s\n' "$XZ_SHA256" "$XZ_TARBALL" > "$XZ_SRC/.xz-src-ok"
echo "[fetch-xz] 完成: $XZ_SRC"
