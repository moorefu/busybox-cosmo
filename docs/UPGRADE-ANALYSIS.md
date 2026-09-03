# UPGRADE-ANALYSIS — Cosmopolitan 版本与功能扩展调研 (2026-09-03 二期)

回答三个问题: (1) 能否基于 Cosmopolitan v4.0.2 / 最新 master; (2) busybox-w32 可移植什么;
(3) 被裁 applet 有哪些可在 cosmo 帮助下恢复。

## 一、版本结论: 我们已在"最新 master"上, v4.0.2 只是历史标签

事实核对 (git 提交日期, 非推测):

| 版本 | 提交 | 日期 |
|---|---|---|
| **master HEAD (我们的 base)** | `3293fad0` | **2026-07-19** |
| cosmocc 4.0.2 (cosmopolitan v4.0.2) | `59073040` | 2025-01-05 |
| cosmocc 3.9.2 | `4a7dd315` | 2024-09-22 |

- `59073040`(v4.0.2 发布提交)**是 master 的祖先** (`git merge-base --is-ancestor` 验证)。
- 即: v4.0.2 修复的 bug **全部已包含在**我们锁定的 master base 里, 且另有 18 个月的新提交
  (直到 2026-07-19)。**"升级到 v4.0.2" 实为降级**, 无收益。
- 我们的定制 = master libc(2026-07)+ 本工程 17 文件补丁(见 patches/cosmo)。工具链驱动层
  (GCC)cosmocc-3.9.2 与 4.0.2 **同为 GCC 14.1.0**(实测 zip 内 libexec/gcc/.../14.1.0),
  换驱动基座收益也极小。→ **维持 master base, 不动作**。

> 若日后要"跟随发布线", 建议定期把补丁 rebase 到新的 master HEAD 并重跑
> `toolchain/fetch-sources.sh + build-custom.sh`(脚本已支持换 commit/sha)。
> 升级 master 的实操: 改 `toolchain/fetch-sources.sh` 的 COSMO_COMMIT/SHA256 →
> 重新 fetch → `provision.sh build`。当前无必要。

## 二、busybox-w32 可移植性盘点

参考: github.com/rmyorston/busybox-w32 @ dc703c7 (2026-08, busybox 1.39.0 系)。

**结论: 其 win32/ 兼容层(shims)对 cosmo 无移植价值** —— 那些是 MinGW 上补 POSIX
(fnmatch/regex/poll/termios/mntent/statfs…), cosmo libc 已原生提供且更强。真正可借鉴的:

1. **配置策略**: w32 的 mingw64_defconfig = "在非 POSIX 平台上哪些 applet 确实可用"的经验集。
   与我们的裁剪对比, w32 保留而我们裁掉且**可在 cosmo 上恢复**的 applet = 本文第三节实测组。
2. **平台可用性证据**: w32 启用 `AR FREE INOTIFYD LZOPCAT UNCOMPRESS UNLZOP UPTIME`,
   证明这些不需要 Linux 内核专属设施(纯用户态/压缩/系统信息 syscall), 与我们实测一致。
3. **行为差异参考**(仅参考, cosmo 与 MinGW 实现不同): 文件系统大小写、路径分隔、
   /dev 映射、控制台等 —— cosmo 层已按自身语义处理, busybox 侧不再需要 w32 的 #ifdef 堆。

**暂不移植**: w32 独有 applet(如 PLATFORM_MINGW32/SUW32/icon/manifest 等 Windows 专属,
CDROP/PDROP/DROP/JN 等为 w32 作者附加功能)与 cosmo 的"单二进制三平台"目标冲突。

## 三、被裁 applet 的 cosmo 可恢复性

裁剪机制(见 ARCHITECTURE): 我们的 full patch 对无价值/内核专属 applet 做了
`//kbuild:` 行注释 + libbb/cosmo_stubs.c 桩 main。恢复 = 去注释 kbuild + 去桩 + 配置=y
+ (必要时)cosmo 守卫。

分档(161 个被裁 applet 中):

### A. 已实测恢复并纳入本工程 (二期, 6 个)

| applet | cosmo 帮助点 | 实测(mac/无 /proc) |
|---|---|---|
| `free` | cosmo 全平台实现 `sysinfo()`(含 Windows sysinfo-nt.c); 补丁使 /proc/meminfo 缺失时回落 | ✅ 打印真实内存 |
| `uptime` | 同上 sysinfo; 恢复真实源码(去 kbuild 注释+去桩) | ✅ |
| `ar` | 纯文件操作, 无特殊依赖 | ✅ create/list/extract |
| `uncompress` / `unlzop` / `lzopcat` | 纯解压代码 | ✅ 可执行 |

落地: `patches/busybox-applet-restore.patch`(增量, 在 full patch 之后应用)+
config 8 行 =y。恢复流程已固化进 `scripts/prepare-worktree.sh`(幂等)。

### B. 判定为"可恢复但需另测/平台受限"(后续候选, 未纳配置)

- 纯网络/用户态: `TELNET`(客户端, TCP), `HOSTNAME`, `LOGGER`(需 syslog 设施, cosmo 缺
  /dev/log, 收益低), `NTPD`(需 adjtimex), `NETCAT`(已开 NC)
- Linux 专属/内核接口, 仅在 Linux-APE 有意义(Windows/mac 运行时无操作):
  `DMESG KLOGD SYSLOGD LOGREAD`(kmsg/syslog)、`IPCS/IPCRM`(SysV IPC)、
  `PING/TRACEROUTE`(raw socket)、`IFCONFIG/IP/ROUTE/ARP/BRCTL`(netlink/ioctl)、
  `MODPROBE/LSMOD/INSMOD`(内核模块)、`FDISK/MKFS_*/HDPARM/BLOCKDEV`(块设备 ioctl)、
  `SWAPON/OFF`、`NSENTER/UNSHARE`(命名空间)、`MDEV/UEVENT`(uevent netlink)
- 硬件/嵌入式专属, 平台无关无意义: FLASH_*/NAND/UBI/MTD、I2C、RFKILL、WATCHDOG、
  SETSERIAL、RAIDAUTORUN、EJECT、FBSPlASH、BOOTCHARTD、ACPID、CONSPY 等
- 安全/登录模型(cosmo 无 root/ACL): SU/SULOGIN/SETPRIV/SELINUX 系/GETENFORCE 系
- 控制台/VT 专属: KBD_MODE/OPENVT/SHOWKEY/SETFONT/LOADFONT/SETLOGCONS
- 缺上游价值或需大改: BBCONFIG(展示配置)、DEVSFSD、IFPLUGD、INOTIFYD 等

### C. 维持裁剪(内核/嵌入/平台冲突) —— 见 A/B 之外的 stub 清单

> 建议: B 档按"是否在你的目标平台(Linux APE vs Windows/mac)真用得上"取舍;
> Linux 上跑 APE 想要 dmesg/ping/syslog 等可逐个启用并照 A 的流程验证。

## 四、操作指引

```sh
# 恢复新 applet(示例): 1) config 置 y  2) 该 .c 的 //xxkbuild: → //kbuild:
# 3) 删 cosmo_stubs.c 对应桩  4) 必要时加 cosmo 守卫  5) 生成增量补丁
# 6) prepare-worktree(已支持增量)重建 → 平台冒烟
make x86_64 && make smoke
```
