#!/usr/bin/env bash
# 廉价维护门禁：不编译、不下载，也不依赖已构建的 BusyBox。
set -euo pipefail
cd "$(dirname "$0")/.."
for file in scripts/*.sh toolchain/*.sh install.sh assets/loaders/install-linux.sh; do
  bash -n "$file"
done
for file in tests/*.sh scripts/bbcosmo lib/*.sh examples/*.sh; do
  sh -n "$file"
done
python3 scripts/patch-series.py check patches/busybox/series
python3 scripts/patch-series.py check patches/cosmo/series
python3 -m py_compile tests/ci-platform-probe.py tests/ci-capability-gate.py
python3 -m unittest discover -s tests -p 'test_*.py' -v
