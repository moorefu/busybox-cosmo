/*
 * bbtty — busybox-cosmo 的跨平台终端状态助手
 *
 * 不复刻 stty 的全部命令行；只提供脚本/TUI 真正需要且能稳定定义的原语。
 * save/raw/restore 的状态令牌只保证在同一台主机、同一终端会话中恢复：
 * Unix 令牌绑定 fstat(0).st_rdev，Windows 令牌要求输入句柄仍指向
 * Console/ConPTY。设备号可能复用，Windows 令牌尚未绑定会话身份，调用者
 * 必须在原终端会话内恢复，不得跨主机或会话保存使用。
 *
 * Windows 后端直接读写 ConsoleMode（参考 wstty 的 Win32 思路，但不引入其
 * raw/cooked 语义与 cp 的早退缺陷）；Unix 后端调用 tcgetattr/cfmakeraw/
 * tcsetattr。VMIN/VTIME 使用 Cosmopolitan 的运行时常量（Linux=6/5，
 * macOS/BSD=16/17），不得改成编译期 Linux 下标。
 */
#define _COSMO_SOURCE
#include "libc/calls/calls.h"
#include "libc/calls/termios.h"
#include "libc/dce.h"
#include "libc/nt/console.h"
#include "libc/nt/enum/consolemodeflags.h"
#include "libc/nt/runtime.h"
#include "libc/stdio/stdio.h"
#include "libc/sysv/consts/termios.h"
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define TOKEN_PREFIX "bbtty-v1"
#define UNIX_DEV_HEX 16 /* st_rdev 的定长十六进制字段 */

/* 配合 cosmo-console-preserve-extra.patch：在 main 前也不得改动终端。
 * 仅 bbtty 定义此符号；BusyBox/curl 等仍使用 Cosmo 默认初始化。 */
const char __cosmo_preserve_console = 1;

static void usage(FILE *f) {
  fputs("用法: bbtty size|save|raw|restore TOKEN|capabilities\n", f);
}

static int cmd_size(void) {
  struct winsize ws;
  int fds[] = {2, 1, 0};
  size_t i;
  for (i = 0; i < sizeof(fds) / sizeof(fds[0]); ++i) {
    memset(&ws, 0, sizeof(ws));
    if (!tcgetwinsize(fds[i], &ws) && ws.ws_row && ws.ws_col) {
      printf("%u %u\n", ws.ws_row, ws.ws_col);
      return 0;
    }
  }
  fputs("bbtty: 无法读取终端尺寸\n", stderr);
  return 1;
}

static void print_hex(const unsigned char *p, size_t n) {
  static const char h[] = "0123456789abcdef";
  size_t i;
  for (i = 0; i < n; ++i) {
    putchar(h[p[i] >> 4]);
    putchar(h[p[i] & 15]);
  }
}

/* 解析恰好 n 字节的定长十六进制，其余一律拒绝。 */
static int parse_hex(const char *s, unsigned char *p, size_t n) {
  size_t i;
  int hi, lo;
  if (strlen(s) != n * 2) return -1;
  for (i = 0; i < n; ++i) {
    hi = s[i * 2];
    lo = s[i * 2 + 1];
    hi = hi >= '0' && hi <= '9' ? hi - '0' :
         hi >= 'a' && hi <= 'f' ? hi - 'a' + 10 :
         hi >= 'A' && hi <= 'F' ? hi - 'A' + 10 : -1;
    lo = lo >= '0' && lo <= '9' ? lo - '0' :
         lo >= 'a' && lo <= 'f' ? lo - 'a' + 10 :
         lo >= 'A' && lo <= 'F' ? lo - 'A' + 10 : -1;
    if (hi < 0 || lo < 0) return -1;
    p[i] = (unsigned char)((hi << 4) | lo);
  }
  return 0;
}

static int is_hex(const char *s, size_t n) {
  size_t i;
  int c;
  for (i = 0; i < n; ++i) {
    c = s[i];
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
          (c >= 'A' && c <= 'F')))
      return 0;
  }
  return 1;
}

/* ---------------- Unix (termios) 后端 ---------------- */

static int unix_tty_dev(unsigned long long *dev) {
  struct stat st;
  if (!isatty(0)) {
    fputs("bbtty: 标准输入不是终端\n", stderr);
    return 1;
  }
  if (fstat(0, &st)) {
    perror("bbtty: fstat");
    return 1;
  }
  *dev = (unsigned long long)st.st_rdev;
  return 0;
}

static int unix_save(struct termios *t) {
  memset(t, 0, sizeof(*t));
  if (tcgetattr(0, t)) {
    perror("bbtty: tcgetattr");
    return 1;
  }
  return 0;
}

static void unix_print_token(unsigned long long dev, const struct termios *t) {
  printf(TOKEN_PREFIX ":unix:%016llx:", dev);
  print_hex((const unsigned char *)t, sizeof(*t));
  putchar('\n');
}

static int unix_raw(void) {
  struct termios before, after;
  unsigned long long dev;
  if (unix_save(&before)) return 1;
  if (unix_tty_dev(&dev)) return 1;
  after = before;
  cfmakeraw(&after);
  after.c_cc[VMIN] = 1;
  after.c_cc[VTIME] = 0;
  if (tcsetattr(0, TCSANOW, &after)) {
    perror("bbtty: tcsetattr");
    return 1;
  }
  unix_print_token(dev, &before);
  return 0;
}

/*
 * Unix 令牌布局：bbtty-v1:unix:<rdev 定长16hex>:<termios hex>
 * restore 要求标准输入仍是终端且 rdev 与令牌一致；两者任一不满足都不改写
 * 任何终端状态。
 */
static int unix_restore(const char *token) {
  static const char pfx[] = TOKEN_PREFIX ":unix:";
  struct termios state;
  unsigned long long dev, cur;
  const char *hex;
  size_t prefix_len = sizeof(pfx) - 1;

  if (strncmp(token, pfx, prefix_len)) {
    fputs("bbtty: 状态令牌与当前 Unix 后端不匹配\n", stderr);
    return 2;
  }
  if (strlen(token) < prefix_len + UNIX_DEV_HEX + 1 ||
      !is_hex(token + prefix_len, UNIX_DEV_HEX) ||
      token[prefix_len + UNIX_DEV_HEX] != ':') {
    fputs("bbtty: Unix 状态令牌损坏\n", stderr);
    return 2;
  }
  dev = strtoull(token + prefix_len, 0, 16);
  hex = token + prefix_len + UNIX_DEV_HEX + 1;
  if (parse_hex(hex, (unsigned char *)&state, sizeof(state))) {
    fputs("bbtty: Unix 状态令牌损坏\n", stderr);
    return 2;
  }
  if (unix_tty_dev(&cur)) return 1;
  if (cur != dev) {
    fputs("bbtty: 状态令牌不属于当前终端会话，已拒绝恢复\n", stderr);
    return 2;
  }
  if (tcsetattr(0, TCSANOW, &state)) {
    perror("bbtty: tcsetattr");
    return 1;
  }
  return 0;
}

/* ---------------- Windows (ConsoleMode) 后端 ---------------- */

static int64_t nt_output_handle(void) {
  int64_t h = GetStdHandle(kNtStdErrorHandle);
  uint32_t mode;
  if (h != -1 && GetConsoleMode(h, &mode)) return h;
  return GetStdHandle(kNtStdOutputHandle);
}

/* 读取当前输入/输出 ConsoleMode 与代码页；stdin 必须是 Console/ConPTY。 */
static int nt_read(uint32_t *inmode, uint32_t *outmode, int *hasout) {
  int64_t hin = GetStdHandle(kNtStdInputHandle);
  int64_t hout = nt_output_handle();
  if (hin == -1 || !GetConsoleMode(hin, inmode)) {
    fputs("bbtty: 标准输入不是 Windows Console/ConPTY\n", stderr);
    return 1;
  }
  *hasout = hout != -1 && GetConsoleMode(hout, outmode);
  if (!*hasout) *outmode = 0;
  return 0;
}

static void nt_print_token(uint32_t inmode, uint32_t outmode, int hasout,
                           uint32_t incp, uint32_t outcp) {
  printf(TOKEN_PREFIX ":windows:%08x:%08x:%u:%u:%u\n", inmode, outmode,
         hasout ? 1u : 0u, incp, outcp);
}

/*
 * raw 只收紧输入模式并追加 VT 输入；保留 ENABLE_WINDOW_INPUT 与
 * ENABLE_EXTENDED_FLAGS（含 Quick Edit/鼠标等）位，与 wstty 不同：不改动
 * 未要求的状态，改动留给 restore 逐位还原。raw 不修改代码页。
 */
static int nt_save_or_raw(int make_raw) {
  uint32_t inmode, outmode, incp, outcp;
  int hasout;
  int64_t hin, hout;
  if (nt_read(&inmode, &outmode, &hasout)) return 1;
  incp = GetConsoleCP();
  outcp = GetConsoleOutputCP();
  if (make_raw) {
    hin = GetStdHandle(kNtStdInputHandle);
    hout = nt_output_handle();
    if (!SetConsoleMode(hin,
          (inmode & ~(kNtEnableProcessedInput | kNtEnableLineInput |
                      kNtEnableEchoInput)) |
          kNtEnableVirtualTerminalInput)) {
      fputs("bbtty: 无法设置 Windows 输入模式\n", stderr);
      return 1;
    }
    if (hasout && !SetConsoleMode(hout,
          outmode | kNtEnableProcessedOutput |
          kNtEnableVirtualTerminalProcessing)) {
      SetConsoleMode(hin, inmode);
      fputs("bbtty: 无法设置 Windows 输出模式\n", stderr);
      return 1;
    }
  }
  nt_print_token(inmode, outmode, hasout, incp, outcp);
  return 0;
}

/*
 * restore 先校验句柄与当前模式可读，再尽量整体应用，最后才考虑代码页：
 * 两个代码页都要尝试（吸取 wstty cp 设置输入代码页后提前 return 的教训），
 * 任何一步失败都会尝试回滚已应用的模式，避免半恢复状态。
 */
static int nt_restore(const char *token) {
  uint32_t inmode, outmode, hasout, incp, outcp;
  uint32_t curin, curout, curincp, curoutcp;
  int64_t hin, hout;
  char tail;
  int ok = 1, hasout_now = 0;
  if (sscanf(token, TOKEN_PREFIX ":windows:%x:%x:%u:%u:%u%c",
             &inmode, &outmode, &hasout, &incp, &outcp, &tail) != 5) {
    fputs("bbtty: Windows 状态令牌损坏或后端不匹配\n", stderr);
    return 2;
  }
  /* 拒绝 scanf 可接受的符号、空白、溢出和非规范字段。 */
  char canonical[128];
  snprintf(canonical, sizeof(canonical),
           TOKEN_PREFIX ":windows:%08x:%08x:%u:%u:%u",
           inmode, outmode, hasout, incp, outcp);
  if (hasout > 1 || strcmp(token, canonical)) {
    fputs("bbtty: Windows 状态令牌格式无效\n", stderr);
    return 2;
  }
  hin = GetStdHandle(kNtStdInputHandle);
  if (hin == -1 || !GetConsoleMode(hin, &curin)) {
    fputs("bbtty: 标准输入不是 Windows Console/ConPTY\n", stderr);
    return 1;
  }
  hout = nt_output_handle();
  hasout_now = hout != -1 && GetConsoleMode(hout, &curout);
  curincp = GetConsoleCP();
  curoutcp = GetConsoleOutputCP();
  if (hasout && !hasout_now) {
    fputs("bbtty: 标准输出不再是 Console，无法恢复输出模式\n", stderr);
    ok = 0;
  } else if (hasout && hasout_now && !SetConsoleMode(hout, outmode)) {
    fputs("bbtty: 无法恢复 Windows 输出模式\n", stderr);
    ok = 0;
  }
  if (!SetConsoleMode(hin, inmode)) {
    fputs("bbtty: 无法恢复 Windows 输入模式\n", stderr);
    ok = 0;
  }
  /* 输入/输出代码页都要尝试恢复，不能因其中一个失败而跳过另一个。 */
  if (incp && !SetConsoleCP(incp)) {
    fputs("bbtty: 无法恢复 Windows 输入代码页\n", stderr);
    ok = 0;
  }
  if (outcp && !SetConsoleOutputCP(outcp)) {
    fputs("bbtty: 无法恢复 Windows 输出代码页\n", stderr);
    ok = 0;
  }
  if (!ok) {
    /* 尽力回滚到进入 restore 之前的状态，避免半恢复。 */
    SetConsoleMode(hin, curin);
    if (hasout_now) SetConsoleMode(hout, curout);
    SetConsoleCP(curincp);
    SetConsoleOutputCP(curoutcp);
    return 1;
  }
  return 0;
}

static int cmd_capabilities(void) {
  printf("bbtty.schema=1\n");
  printf("bbtty.backend=%s\n", IsWindows() ? "windows-console" : "termios");
  printf("bbtty.size=available\n");
  printf("bbtty.save_restore=available\n");
  printf("bbtty.raw=available\n");
  printf("bbtty.posix_stty_compatible=no\n");
  return 0;
}

int main(int argc, char *argv[]) {
  struct termios state;
  unsigned long long dev;
  if (argc == 2 && !strcmp(argv[1], "size")) return cmd_size();
  if (argc == 2 && !strcmp(argv[1], "capabilities")) return cmd_capabilities();
  if (argc == 2 && !strcmp(argv[1], "save")) {
    if (IsWindows()) return nt_save_or_raw(0);
    if (unix_save(&state)) return 1;
    if (unix_tty_dev(&dev)) return 1;
    unix_print_token(dev, &state);
    return 0;
  }
  if (argc == 2 && !strcmp(argv[1], "raw")) {
    return IsWindows() ? nt_save_or_raw(1) : unix_raw();
  }
  if (argc == 3 && !strcmp(argv[1], "restore")) {
    return IsWindows() ? nt_restore(argv[2]) : unix_restore(argv[2]);
  }
  usage(stderr);
  return 2;
}
