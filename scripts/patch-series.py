#!/usr/bin/env python3
"""校验、指纹化并原子应用补丁序列；仅依赖 Python 3 和宿主 patch。"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def read_series(series):
    series = Path(series).resolve()
    entries = []
    seen = set()
    for line in series.read_text().splitlines():
        name = line.strip()
        if not name or name.startswith("#"):
            continue
        path = Path(name)
        if path.is_absolute() or ".." in path.parts or path.suffix != ".patch":
            raise ValueError(f"非法补丁路径: {name}")
        if name in seen:
            raise ValueError(f"重复补丁: {name}")
        seen.add(name)
        patch = series.parent / path
        if not patch.is_file() or patch.is_symlink():
            raise ValueError(f"缺失补丁或符号链接: {name}")
        entries.append((name, patch))
    if not entries:
        raise ValueError("补丁序列为空")
    return entries


def fingerprint(series):
    digest = hashlib.sha256()
    for name, patch in read_series(series):
        digest.update(name.encode() + b"\0")
        digest.update(hashlib.sha256(patch.read_bytes()).digest())
    return digest.hexdigest()


def apply(series, source, target):
    source, target = Path(source).resolve(), Path(target).absolute()
    expected = f"series_sha256={fingerprint(series)}\n"
    marker = target / ".bb-series-ok"
    if target.exists() or target.is_symlink():
        if not target.is_symlink() and marker.is_file() and marker.read_text() == expected:
            print(f"[补丁] 复用指纹匹配的工作树: {target}")
            return
        raise ValueError(f"工作树缺少标志或指纹过期，不覆盖现有文件: {target}；请指定新的工作目录")
    if not source.is_dir():
        raise ValueError(f"原版源码目录不存在: {source}")
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".patch-stage-", dir=target.parent) as stage:
        tree = Path(stage) / "tree"
        shutil.copytree(source, tree, symlinks=True)
        for name, patch in read_series(series):
            print(f"[补丁] {name}", flush=True)
            with patch.open("rb") as data:
                subprocess.run(["patch", "--quiet", "--batch", "--forward", "--fuzz=0", "-p1"],
                               cwd=tree, stdin=data, check=True)
        (tree / ".bb-series-ok").write_text(expected)
        # 并发准备不是受支持的工作流；若另一进程已发布，绝不覆盖它。
        if target.exists() or target.is_symlink():
            raise ValueError(f"目标被并发创建: {target}")
        os.rename(tree, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check", "fingerprint", "apply"])
    parser.add_argument("series", type=Path)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--target", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "apply":
            if not args.source or not args.target:
                parser.error("apply 需要 --source 和 --target")
            apply(args.series, args.source, args.target)
        elif args.command == "fingerprint":
            print(fingerprint(args.series))
        else:
            entries = read_series(args.series)
            actual = {p.relative_to(args.series.parent).as_posix()
                      for p in args.series.parent.rglob("*.patch")}
            listed = {name for name, _ in entries}
            if actual != listed:
                raise ValueError(f"存在未列入 series 的补丁: {sorted(actual - listed)}")
            print(f"[补丁] {args.series}: {len(entries)} 项，{fingerprint(args.series)}")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"[补丁错误] {error}\n")


if __name__ == "__main__":
    main()
