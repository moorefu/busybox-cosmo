/* forkdiag.c — 诊断 cosmopolitan Windows fork+socket 继承问题
 * 模拟 busybox wget https 的架构: socketpair(AF_UNIX) + fork + 子进程用父进程的 socket
 * 每个测试独立文件输出,避免并发写交错
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/wait.h>
#include <poll.h>
#include <sys/select.h>

static void out(FILE *f, const char *tag, const char *what, int rc) {
  fprintf(f, "%s | %s | rc=%d | errno=%d (%s)\n", tag, what, rc, errno, strerror(errno));
  fflush(f);
}

/* 有界网络读: poll 超时则返回 -2, 避免永久阻塞拖垮全量测试 */
static int timed_recv(int fd, void *buf, int len, int ms) {
  struct pollfd p = { fd, POLLIN, 0 };
  int rc = poll(&p, 1, ms);
  if (rc <= 0) return -2;
  return (int)recv(fd, buf, len, 0);
}
static int timed_read(int fd, void *buf, int len, int ms) {
  struct pollfd p = { fd, POLLIN, 0 };
  int rc = poll(&p, 1, ms);
  if (rc <= 0) return -2;
  return (int)read(fd, buf, len);
}

static int tcp_connect(void) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) return -1;
  struct hostent *h = gethostbyname("www.baidu.com");
  if (!h) { close(fd); return -2; }
  struct sockaddr_in sa;
  memset(&sa, 0, sizeof(sa));
  sa.sin_family = AF_INET;
  sa.sin_port = htons(80);
  memcpy(&sa.sin_addr, h->h_addr, 4);
  if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) < 0) { close(fd); return -3; }
  return fd;
}

static int do_send(int fd) {
  const char *req = "GET / HTTP/1.0\r\nHost: www.baidu.com\r\n\r\n";
  return (int)send(fd, req, strlen(req), 0);
}
static int do_recv(int fd) {
  char buf[256];
  return timed_recv(fd, buf, sizeof(buf), 3000);
}

/* T1: 无 fork 基线 — connect/send/recv 全在父进程 */
static void t1_no_fork(void) {
  FILE *f = fopen("diag-T1.txt", "w");
  int fd = tcp_connect();
  if (fd < 0) { out(f, "T1", "connect", fd); fclose(f); return; }
  out(f, "T1", "connect", fd);
  int n = do_send(fd);  out(f, "T1", "send", n);
  n = do_recv(fd);      out(f, "T1", "recv", n);
  close(fd);
  fclose(f);
}

/* T2: fork 子进程直接使用父进程的已连接 TCP socket (wget TLS 子进程架构) */
static void t2_fork_use_parent_socket(void) {
  int fd = tcp_connect();
  if (fd < 0) { FILE *f = fopen("diag-T2-parent.txt", "w"); out(f, "T2", "connect", fd); fclose(f); return; }
  pid_t pid = fork();
  if (pid == 0) {
    FILE *f = fopen("diag-T2-child.txt", "w");
    out(f, "T2-child", "fork-child-here", 0);
    out(f, "T2-child", "send-on-inherited", do_send(fd));
    out(f, "T2-child", "recv-on-inherited", do_recv(fd));
    fclose(f);
    _exit(0);
  }
  FILE *f = fopen("diag-T2-parent.txt", "w");
  out(f, "T2-parent", "fork-parent-here", pid);
  int st; waitpid(pid, &st, 0);
  out(f, "T2-parent", "waitpid", st);
  close(fd);
  fclose(f);
}

/* T3: fork 子进程内新建 socket (验证子进程 winsock 是否整体可用) */
static void t3_fork_new_socket(void) {
  pid_t pid = fork();
  if (pid == 0) {
    FILE *f = fopen("diag-T3-child.txt", "w");
    int fd = tcp_connect();
    if (fd < 0) { out(f, "T3-child", "connect-new", fd); fclose(f); _exit(1); }
    out(f, "T3-child", "connect-new", fd);
    out(f, "T3-child", "send-new", do_send(fd));
    out(f, "T3-child", "recv-new", do_recv(fd));
    close(fd);
    fclose(f);
    _exit(0);
  }
  FILE *f = fopen("diag-T3-parent.txt", "w");
  int st; waitpid(pid, &st, 0);
  out(f, "T3-parent", "waitpid", st);
  fclose(f);
}

/* T4: socketpair + fork, 子进程用父进程创建的一对 (busybox TLS 通道结构) */
static void t4_fork_socketpair(void) {
  int sp[2];
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, sp) != 0) {
    FILE *f = fopen("diag-T4-parent.txt", "w");
    out(f, "T4", "socketpair", -1);
    fclose(f);
    return;
  }
  pid_t pid = fork();
  if (pid == 0) {
    close(sp[0]);
    FILE *f = fopen("diag-T4-child.txt", "w");
    out(f, "T4-child", "fork-child-here", 0);
    out(f, "T4-child", "send-pair", (int)send(sp[1], "ping", 4, 0));
    /* 父进程不会发数据: poll 等 1s, 超时即放弃, 避免死锁 */
    struct pollfd p4 = { sp[1], POLLIN, 0 };
    int p4rc = poll(&p4, 1, 1000);
    out(f, "T4-child", "poll-pair-1s", p4rc);
    if (p4rc > 0) out(f, "T4-child", "recv-pair", (int)recv(sp[1], (char[8]){0}, 8, 0));
    fclose(f);
    _exit(0);
  }
  close(sp[1]);
  FILE *f = fopen("diag-T4-parent.txt", "w");
  char buf[8];
  out(f, "T4-parent", "recv-pair", (int)recv(sp[0], buf, sizeof(buf), 0));
  int st; waitpid(pid, &st, 0);
  out(f, "T4-parent", "waitpid", st);
  close(sp[0]);
  fclose(f);
}

/* T5: 精确复刻 busybox wget https 的 TLS 子进程操作序列
 * 子进程: socketpair 端移到 fd0/1 + 对继承的 TCP socket 做 write/read/poll/select/getsockopt/urandom
 */
static void t5_tls_child_sequence(void) {
  FILE *f5 = fopen("diag-T5-enter.txt", "w"); /* 探针: 进入 T5 */
  if (f5) { fprintf(f5, "T5-enter | step=start\n"); fflush(f5); }
  int sp[2];
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, sp) != 0) {
    FILE *f = fopen("diag-T5-parent.txt", "w");
    out(f, "T5", "socketpair", -1);
    fclose(f);
    return;
  }
  if (f5) { fprintf(f5, "T5-enter | step=socketpair-ok sp0=%d sp1=%d\n", sp[0], sp[1]); fflush(f5); }
  int sfd = tcp_connect(); /* 父进程创建的已连接 TCP socket */
  if (f5) { fprintf(f5, "T5-enter | step=connect sfd=%d\n", sfd); fflush(f5); }
  if (sfd < 0) {
    FILE *f = fopen("diag-T5-parent.txt", "w");
    out(f, "T5", "connect", sfd);
    fclose(f);
    return;
  }
  if (f5) { fprintf(f5, "T5-enter | step=about-to-fork\n"); fflush(f5); }
  pid_t pid = fork();
  if (f5) { fprintf(f5, "T5-enter | step=fork-returned pid=%d\n", (int)pid); fflush(f5); }
  if (pid == 0) {
    /* —— TLS 子进程侧 (仿 spawn_ssl_client 子分支) —— */
    if (f5) { fprintf(f5, "T5-child | step=child-start\n"); fflush(f5); }
    fclose(f5);
    f5 = NULL;
    FILE *f = fopen("diag-T5-child.txt", "w");
    if (!f) _exit(9);
    close(sp[0]);
    dup2(sp[1], 0);
    dup2(0, 1);
    /* 1. 对继承 socket write (TLS 加密写同款调用) */
    const char *req = "GET / HTTP/1.0\r\nHost: www.baidu.com\r\n\r\n";
    errno = 0;
    out(f, "T5-child", "write-sock", (int)write(sfd, req, strlen(req)));
    /* 2. poll: 混合 stdin(管道) + socket —— TLS copy loop 结构 */
    {
      struct pollfd pfds[2];
      pfds[0].fd = 0; pfds[0].events = POLLIN;
      pfds[1].fd = sfd; pfds[1].events = POLLIN;
      errno = 0;
      int prc = poll(pfds, 2, 5000);
      out(f, "T5-child", "poll-mixed", prc);
      fprintf(f, "T5-child | revents[0]=%d revents[1]=%d\n", pfds[0].revents, pfds[1].revents);
      fflush(f);
    }
    /* 3. read (TLS 解密读同款) */
    {
      char buf[256];
      errno = 0;
      out(f, "T5-child", "read-sock", timed_read(sfd, buf, sizeof(buf), 3000));
    }
    /* 4. select 读集 */
    {
      fd_set rfds; FD_ZERO(&rfds); FD_SET(sfd, &rfds);
      struct timeval tv = { 3, 0 };
      errno = 0;
      out(f, "T5-child", "select-sock", select(sfd + 1, &rfds, NULL, NULL, &tv));
    }
    /* 5. getsockopt */
    {
      int soerr = 999; socklen_t sl = sizeof(soerr);
      errno = 0;
      int grc = getsockopt(sfd, SOL_SOCKET, SO_ERROR, &soerr, &sl);
      fprintf(f, "T5-child | getsockopt rc=%d so_error=%d errno=%d\n", grc, soerr, errno);
      fflush(f);
    }
    /* 6. /dev/urandom —— busybox tls_get_random 同款 */
    {
      unsigned char rb[32];
      int ufd = open("/dev/urandom", O_RDONLY);
      out(f, "T5-child", "open-urandom", ufd);
      if (ufd >= 0) {
        errno = 0;
        out(f, "T5-child", "read-urandom", (int)read(ufd, rb, sizeof(rb)));
        close(ufd);
      }
    }
    /* 7. 向父进程管道写回 (明文通道) */
    out(f, "T5-child", "write-pipe", (int)write(1, "plaintext-ok", 12));
    fclose(f);
    _exit(0);
  }
  close(sp[1]);
  FILE *f = fopen("diag-T5-parent.txt", "w");
  out(f, "T5-parent", "fork", pid);
  {
    char buf[64];
    errno = 0;
    int n = (int)read(sp[0], buf, sizeof(buf));
    buf[n > 0 ? n : 0] = 0;
    fprintf(f, "T5-parent | read-pipe n=%d data=\"%s\" errno=%d\n", n, buf, errno);
    fflush(f);
  }
  {
    int st; waitpid(pid, &st, 0);
    out(f, "T5-parent", "waitpid", st);
  }
  close(sfd);
  close(sp[0]);
  fclose(f);
  if (f5) fclose(f5);
}

int main(int argc, char **argv) {
  printf("forkdiag v4 starting... pid=%d\n", (int)getpid());
  fflush(stdout);
  FILE *f0 = fopen("diag-T0-start.txt", "w");
  if (f0) { fprintf(f0, "T0-start | pid=%d argv=%s\n", (int)getpid(), argc > 1 ? argv[1] : "(all)"); fflush(f0); }
  fclose(f0);
  const char *sel = argc > 1 ? argv[1] : NULL;
  printf("== begin t1 ==\n"); fflush(stdout);
  if (!sel || !strcmp(sel, "t1")) t1_no_fork();
  printf("== begin t2 ==\n"); fflush(stdout);
  if (!sel || !strcmp(sel, "t2")) t2_fork_use_parent_socket();
  printf("== begin t3 ==\n"); fflush(stdout);
  if (!sel || !strcmp(sel, "t3")) t3_fork_new_socket();
  printf("== begin t4 ==\n"); fflush(stdout);
  if (!sel || !strcmp(sel, "t4")) t4_fork_socketpair();
  printf("== begin t5 ==\n"); fflush(stdout);
  if (!sel || !strcmp(sel, "t5")) t5_tls_child_sequence();
  printf("forkdiag %s done.\n", sel ? sel : "(all)");
  fflush(stdout);
  return 0;
}
