# busybox-cosmo 工程便捷入口 (底层请直接调用 scripts/*.sh / toolchain/*.sh)
.PHONY: help fetch build x86_64 aarch64 fat bbtty bbtty-check xz zip zstd curl companion-check cacert https-kat qa-local package archive-package net-package sign-macos smoke smokefull clean distclean \
        toolchain-copy toolchain-fetch toolchain-build toolchain-verify portable-check check test

BUSYBOX ?= $(CURDIR)/dist/release/release/busybox

check:
	bash scripts/check.sh

test:
	"$(BUSYBOX)" ash tests/ash-contract.sh
	"$(BUSYBOX)" ash tests/deep-test.sh
	"$(BUSYBOX)" ash tests/smoke-full.sh
	BBP_BUSYBOX="$(BUSYBOX)" "$(BUSYBOX)" ash tests/portable-contract.sh

help:
	@echo "=== 构建 busybox ==="
	@echo "make fetch            — 下载并校验 busybox 官方源码 (src/)"
	@echo "make x86_64           — 构建 x86_64 APE (dist/busybox-x86_64.ape)"
	@echo "make aarch64          — 构建 aarch64 APE (dist/busybox-aarch64.ape)"
	@echo "make fat              — 合成双架构 fat (dist/busybox-fat.ape)"
	@echo "make bbtty            — 构建跨平台终端助手 (dist/bbtty.com)"
	@echo "make bbtty-check      — 真实 PTY 行为契约 (tests/bbtty-pty.py, 需 python3)"
	@echo "make xz               — 从锁定源码构建伴生 xz (dist/tools/xz.com)"
	@echo "make zip              — 从 Debian 补丁快照构建伴生 zip (dist/tools/zip.com)"
	@echo "make zstd             — 从锁定源码构建伴生 zstd (dist/tools/zstd.com)"
	@echo "make curl             — 从锁定源码构建伴生 curl+mbedtls (dist/tools/curl.com)"
	@echo "make companion-check  — 伴生工具契约 (tests/companion-tools.py, 需产物在 dist/)"
	@echo "make cacert           — 固定 CA bundle 取源 (dist/tools/cacert.pem)"
	@echo "make https-kat        — 本地 TLS KAT (tests/https-kat.py, 需宿主 curl+openssl)"
	@echo "make qa-local          — 本地交付 QA 门禁 (scripts/qa-local.sh, 需全部产物)"
	@echo "make sign-macos        — macOS ad-hoc 签名 dist 下 APE/com 产物"
	@echo "make build            — x86_64 + aarch64 + fat 全量"
	@echo "make package          — 生成发布包 (dist/busybox-cosmo-release.zip)"
	@echo "make archive-package  — 分层 busybox-archive 包 (busybox+xz/zip/zstd)"
	@echo "make net-package      — 分层 busybox-net 包 (busybox+curl.com+cacert)"
	@echo "make smoke            — 本地副本快速离线冒烟"
	@echo "make smokefull        — 完整冒烟(10 组 ~180 项, 自适应 SKIP, 本地回环网络)"
	@echo "make portable-check   — 运行跨平台 Shell 基础库契约测试(需已构建发布包)"
	@echo ""
	@echo "=== 工具链 (toolchain/cosmo) ==="
	@echo "make toolchain-copy   — 从既有已验工具链拷贝 (provision.sh copy, 秒级)"
	@echo "make toolchain-fetch  — 下载官方上游材料 (master@锁定commit + cosmocc-3.9.2)"
	@echo "make toolchain-build  — 从官方源码构建定制工具链 (数小时: fetch+make+assemble+verify)"
	@echo "make toolchain-verify — 校验 toolchain/cosmo vs 参考 .cosmocc/3.9.2"
	@echo ""
	@echo "=== 维护 ==="
	@echo "make check            — 语法、补丁序列、维护脚本回归（不构建、不下载）"
	@echo "make test BUSYBOX=路径 — ash/深度/功能契约（测试已有产物，不重建）"
	@echo "make clean            — 删除可重建产物 (src/work/dist 保留工具链)"
	@echo "make distclean        — clean + 移除工具链"

fetch:
	scripts/fetch-busybox.sh

x86_64:
	scripts/build-ape.sh x86_64

aarch64:
	scripts/build-ape.sh aarch64

fat:
	scripts/build-ape.sh fat

build: x86_64 aarch64 fat

bbtty:
	scripts/build-bbtty.sh

bbtty-check: bbtty
	python3 tests/bbtty-pty.py "$(CURDIR)/dist/bbtty.com"

xz:
	scripts/build-xz.sh

zip:
	scripts/build-zip.sh

zstd:
	scripts/build-zstd.sh

curl:
	scripts/build-curl.sh

companion-check:
	@test -x "$(CURDIR)/dist/tools/xz.com" && test -x "$(CURDIR)/dist/tools/zip.com" || \
	  { echo "先构建伴生工具: make xz && make zip" >&2; exit 1; }
	@args="$(CURDIR)/dist/tools/xz.com $(CURDIR)/dist/tools/zip.com"; \
	if [ -x "$(CURDIR)/dist/busybox-fat.ape" ]; then \
	  args="$$args $(CURDIR)/dist/busybox-fat.ape"; \
	else \
	  echo "提示: 缺 dist/busybox-fat.ape, 精简契约(不含 busybox 解码互操作)" >&2; \
	fi; \
	if [ -x "$(CURDIR)/dist/tools/zstd.com" ]; then \
	  args="$$args --zstd $(CURDIR)/dist/tools/zstd.com"; \
	fi; \
	python3 tests/companion-tools.py $$args; \
	if [ -x "$(CURDIR)/dist/tools/curl.com" ] && command -v openssl >/dev/null 2>&1; then \
	  echo "--- curl.com HTTPS KAT ---"; \
	  python3 tests/https-kat.py "$(CURDIR)/dist/tools/curl.com"; \
	fi

package: build
	scripts/package-release.sh

archive-package:
	scripts/package-archive.sh

net-package:
	scripts/package-net.sh

cacert:
	scripts/fetch-cacert.sh

https-kat:
	python3 tests/https-kat.py "$${CURL:-$$(command -v curl || echo /usr/bin/curl)}"

qa-local:
	scripts/qa-local.sh

sign-macos:
	scripts/sign-macos.sh

smoke:
	"$(BUSYBOX)" ash tests/smoke.sh

smokefull:
	"$(BUSYBOX)" ash tests/smoke-full.sh

portable-check:
	BBP_BUSYBOX="$(BUSYBOX)" "$(BUSYBOX)" ash tests/portable-contract.sh

toolchain-copy:
	toolchain/provision.sh copy

toolchain-fetch:
	toolchain/fetch-sources.sh

toolchain-build:
	toolchain/provision.sh build all

toolchain-verify:
	toolchain/build-custom.sh verify

clean:
	rm -rf src work dist .tmp log/*.txt

distclean: clean
	@echo "移除 toolchain/cosmo 与下载缓存"
	rm -rf toolchain/cosmo toolchain/download
