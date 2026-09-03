# busybox-cosmo 工程便捷入口 (底层请直接调用 scripts/*.sh)
.PHONY: help fetch build x86_64 aarch64 fat package smoke clean distclean toolchain-copy

help:
	@echo "make fetch        — 下载并校验 busybox 官方源码 (src/)"
	@echo "make x86_64       — 构建 x86_64 APE (dist/busybox-x86_64.ape)"
	@echo "make aarch64      — 构建 aarch64 APE (dist/busybox-aarch64.ape)"
	@echo "make fat          — 合成双架构 fat (dist/busybox-fat.ape)"
	@echo "make build        — x86_64 + aarch64 + fat 全量"
	@echo "make package      — 生成发布包 (dist/busybox-cosmo-release.zip)"
	@echo "make smoke        — 本地副本冒烟 (mac/linux, busybox.com sh smoke.sh)"
	@echo "make toolchain-copy — 拷入定制工具链 (toolchain/provision.sh copy)"
	@echo "make clean        — 删除可重建产物 (src/work/dist 保留工具链)"

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

clean:
	rm -rf src work dist .tmp log/*.txt

distclean: clean
	@echo "保留 toolchain/cosmo (如需移除: rm -rf toolchain/cosmo)"
