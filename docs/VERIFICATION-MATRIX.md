# VERIFICATION-MATRIX — 验证矩阵与可复现性记录

## 一、本工程重建验证 (2026-09-03, macOS x86_64 主机)

| 步骤 | 方法 | 结果 |
|---|---|---|
| 取源 | `scripts/fetch-busybox.sh` 从 busybox.net 下载 tarball, sha256 校验 | ✅ `34f9ea6ff863…` 一致 |
| 补丁 | `busybox-cosmo-full.patch` 对官方原版 dry-run/实打 | ✅ 82 文件 0 FAILED |
| x86_64 构建 | 官方源码 + 补丁 + 统一 config + 定制工具链, make → apelink | ✅ 产物 ELF x86_64 |
| aarch64 构建 | 同上 aarch64 交叉 | ✅ 产物 ELF aarch64 |
| fat 合成 | `scripts/build-ape.sh fat` (apelink 双 ELF) | ✅ |
| 发布打包 | `scripts/package-release.sh` | ✅ zip 布局与历史基线一致 |
| 本地冒烟 | 新产物 `busybox.com` 副本跑 `smoke.sh` (mac) | 44/46 (`ps` 环境项 + `[win]` 平台项) — 与历史基线同机行为一致 |

### 逐字节对照结论

- 新构建 x86_64 `busybox_unstripped` 与历史已验证树对比: **全部采样 .o 逐字节相同**; 唯一差异为
  版本横幅 `AUTOCONF_TIMESTAMP` (编译时刻)。
- 固定 `SOURCE_DATE_EPOCH` 后两次独立构建 → md5 一致 (见下节实测)。

## 二、可复现性实测

```
SOURCE_DATE_EPOCH=1788431874 构建 repro1 / repro2 (独立树, 同源同补丁同配置同工具链)
busybox_unstripped md5: repro1 == repro2 == c6a1cd9dbc56db3b99fb41f72f8c2a98  ✅ 逐位可复现
```

## 三、历史验证基线 (2026-09-03, 实机, 记录于 baseline/)

| 平台 | 用法 | smoke | deep | 备注 |
|---|---|---|---|---|
| Windows x86_64 | busybox.com | **46/46** | — | ps/dev/zero/Unicode/鼠标全绿 |
| Linux x86_64 | APE 直跑 (podman) | 45/46 | 31/31 | `[win]` 项除外 |
| Linux aarch64 64K 页 | ELF 直跑 / APE+loader+FP | 45/46 | 31/31 | 鲲鹏 UOS 实机, 双路径同功能 |
| macOS (Intel) | APE | 45/46 | — | 嵌套 exec 修复 |

历史产物 md5: `baseline/busybox-cosmo-release.zip` 内 `release/md5sums.txt`。

## 四、重建 vs 历史基线的差异说明

新构建产物 md5 与历史基线**不同属预期**, 原因:
1. 版本横幅含编译时刻 (未固定 epoch 时)。
2. 本工程**统一**两架构配置为最终验证版 (x86 40959/WIDE; 历史 arm64 树残留 767 旧配置)。
   功能超集, 非回退。
3. apelink/工具链同源 (拷入的就是历史最终定制工具链)。

如要与历史基线逐位一致: 对两架构用各自历史 `.config` + 相同 `SOURCE_DATE_EPOCH` 重建 (不推荐, 功能无增益)。
