# busybox-cosmo 工程便捷入口 (底层请直接调用 scripts/*.sh / toolchain/*.sh)
.PHONY: help fetch build x86_64 aarch64 fat package smoke clean distclean \
        toolchain-copy toolchain-fetch toolchain-build toolchain-verify

help:
	@echo "=== 构建 busybox ==="
	@echo "make fetch            — 下载并校验 busybox 官方源码 (src/)"
	@echo "make x86_64           — 构建 x86_64 APE (dist/busybox-x86_64.ape)"
	@echo "make aarch64          — 构建 aarch64 APE (dist/busybox-aarch64.ape)"
	@echo "make fat              — 合成双架构 fat (dist/busybox-fat.ape)"
	@echo "make build            — x86_64 + aarch64 + fat 全量"
	@echo "make package          — 生成发布包 (dist/busybox-cosmo-release.zip)"
	@echo "make smoke            — 本地副本冒烟 (mac/linux, busybox.com sh smoke.sh)"
	@echo ""
	@echo "=== 工具链 (toolchain/cosmo) ==="
	@echo "make toolchain-copy   — 从既有已验工具链拷贝 (provision.sh copy, 秒级)"
	@echo "make toolchain-fetch  — 下载官方上游材料 (master@锁定commit + cosmocc-3.9.2)"
	@echo "make toolchain-build  — 从官方源码构建定制工具链 (数小时: fetch+make+assemble+verify)"
	@echo "make toolchain-verify — 校验 toolchain/cosmo vs 参考 .cosmocc/3.9.2"
	@echo ""
	@echo "=== 维护 ==="
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

package: build
	scripts/package-release.sh

smoke:
	@rm -rf .tmp/smoke && mkdir -p .tmp/smoke
	@cp dist/release/release/busybox.com .tmp/smoke/ 2>/dev/null || cp dist/busybox-x86_64.ape .tmp/smoke/busybox.com
	@cp tests/smoke.sh .tmp/smoke/
	@cd .tmp/smoke && ./busybox.com sh smoke.sh

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
