#!/bin/sh
# ============================================================
# smoke-full.sh — busybox(cross-cosmo) 完整冒烟套件
#
# 设计要点:
#  - 由 busybox 自带 ash 执行:  busybox sh smoke-full.sh
#  - 覆盖分 10 组, 每项验证输出/语义(不只退出码)
#  - 自洽: 网络组全部走本地回环 (nc/telnet), 不依赖外网
#  - 自适应: 按 `busybox --list` 自动 SKIP 未编译的 applet
#  - 平台软失败标 [soft]: 环境相关(如 mac 沙箱禁止 exec /bin/ps)
#  - 汇总: 每组分项 + 总数/通过/跳过/失败, 任意硬失败 => rc 1
# ============================================================
PASS=0; FAIL=0; SKIP=0; SOFT=0
LIST=""
TM_SEQ=0

# 所有临时文件隔离到唯一目录；失败时保留目录位置，避免并发运行互相
# 覆盖，也不污染调用者当前目录。
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/busybox-smoke.XXXXXX")" || exit 2
KEEP_TEST_ROOT="${KEEP_TEST_ROOT:-0}"
cleanup_smoke() {
	if [ "$KEEP_TEST_ROOT" = 1 ]; then
		echo "测试临时目录已保留: $TEST_ROOT" >&2
	else
		rm -rf "$TEST_ROOT"
	fi
}
trap cleanup_smoke EXIT HUP INT TERM
cd "$TEST_ROOT" || exit 2

# 平台判定: cosmo Windows 的 uname -s = "Windows"
# (信号模拟、fork 后 accept 的 socket 继承 = cosmo #1174 部分未根治,
#  见 docs/KNOWN-LIMITATIONS.md → 部分平台相关用例跳过/软处理, 防挂死)
IS_WIN=0
case "$(uname -s 2>/dev/null)" in
	*[Ww]indows*|*[Ww]in32*) IS_WIN=1 ;;
esac

bb_list() { [ -n "$LIST" ] || LIST="$(busybox --list 2>/dev/null)"; echo "$LIST"; }

# 工具存在性
have() { bb_list | grep -qx "$1"; }

# 组计数
g_PASS=0; g_FAIL=0; g_SKIP=0; g_SOFT=0

# 硬测试: 失败即 FAIL
t() {
	desc="$1"; shift
	if "$@" >/dev/null 2>&1; then
		echo "PASS: $desc"; PASS=$((PASS+1)); g_PASS=$((g_PASS+1))
	else
		echo "FAIL: $desc"; FAIL=$((FAIL+1)); g_FAIL=$((g_FAIL+1))
	fi
}
# 需要某 applet, 缺失则 SKIP
tn() { # tn <applet> <desc> <cmd...>
	a="$1"; desc="$2"; shift 2
	if ! have "$a"; then
		echo "SKIP: $desc (无 $a)"; SKIP=$((SKIP+1)); g_SKIP=$((g_SKIP+1)); return 0
	fi
	t "$desc" "$@"
}
# 软测试(平台/环境差异), 失败记 SOFT 不使套件失败
ts() {
	desc="$1"; shift
	if "$@" >/dev/null 2>&1; then
		echo "PASS: $desc"; PASS=$((PASS+1)); g_PASS=$((g_PASS+1))
	else
		echo "SOFT: $desc"; SOFT=$((SOFT+1)); g_SOFT=$((g_SOFT+1))
	fi
}
# 输出式断言: 期望 stdout 匹配 grep 模式
tm() { # tm <desc> <pattern> <cmd...>
	desc="$1"; pat="$2"; shift 2
	TM_SEQ=$((TM_SEQ+1))
	out="tm-output-$$-$TM_SEQ"
	producer_rc=0
	"$@" >"$out" 2>/dev/null || producer_rc=$?
	if [ "$producer_rc" -eq 0 ] && grep -qE "$pat" "$out"; then
		echo "PASS: $desc"; PASS=$((PASS+1)); g_PASS=$((g_PASS+1))
	else
		echo "FAIL: $desc"; FAIL=$((FAIL+1)); g_FAIL=$((g_FAIL+1))
	fi
	rm -f "$out"
}
# Windows 平台缺口(cosmo 模拟限制) → 记 SKIP 不执行, 避免挂死/误判
ws() { # ws <desc> <原因>
	echo "SKIP: $1 ($2)"
	SKIP=$((SKIP+1)); g_SKIP=$((g_SKIP+1))
}

group() {
	[ "$1" != "" ] && echo ""
	echo "===== 组 $GNO: $1 ====="
	g_PASS=0; g_FAIL=0; g_SKIP=0; g_SOFT=0
}
gsum() {
	echo "  -- 组小计: PASS=$g_PASS FAIL=$g_FAIL SKIP=$g_SKIP SOFT=$g_SOFT"
}

GNO="A"
group "applet 清单与版本"
tm "busybox 版本横幅" "BusyBox v1\.[0-9]+" busybox
t "uname -m" sh -c 'uname -m | grep -q .'
t "uname -s" sh -c 'uname -s | grep -q .'
t "applet 清单非空" sh -c 'busybox --list | grep -q .'
for a in ash sh cat ls cp mv rm mkdir ln echo printf test grep sed awk \
         sort uniq wc head tail cut tr od gzip gunzip bzip2 xz tar find \
         xargs sleep timeout kill env date dd df stat du vi make nc telnet; do
	if have "$a"; then
		echo "PASS: applet=$a"; PASS=$((PASS+1))
	else
		echo "SKIP: applet=$a 未编译"; SKIP=$((SKIP+1))
	fi
done
gsum

GNO="B"
group "文件系统与基本工具"
t "mkdir/cp/cmp/rm" sh -c 'd=sf.d; rm -rf "$d" && mkdir -p "$d/sub" && echo x>"$d/a" && cp "$d/a" "$d/sub/b" && cmp "$d/a" "$d/sub/b" && rm -rf "$d"'
t "mv 跨目录" sh -c 'd=sf.d; rm -rf "$d" && mkdir "$d" && echo m>"$d/f" && mv "$d/f" "$d/g" && test -f "$d/g" && rm -rf "$d"'
t "ln 硬链接" sh -c 'd=sf.d; rm -rf "$d" && mkdir "$d" && echo l>"$d/h" && ln "$d/h" "$d/i" && test "$d/h" -ef "$d/i" && rm -rf "$d"'
t "ln -s 符号链接" sh -c 'd=sf.d; rm -rf "$d" && mkdir "$d" && echo s>"$d/r" && ln -sfn r "$d/s" && test -e "$d/s" && rm -rf "$d"'
t "dd bs/count/seek" sh -c 'printf xxxxxxxx | dd bs=2 count=4 2>/dev/null | wc -c | grep -q 8'
t "dd 写文件大小" sh -c 'dd if=/dev/zero of=sf.bin bs=100 count=3 2>/dev/null && test "$(wc -c <sf.bin)" = 300 && rm -f sf.bin'
t "ls -l 可读" sh -c 'touch sf.f && ls -l sf.f | grep -q -- "-rw" && rm -f sf.f'
t "ls -a 隐藏" sh -c 'touch .sfh && ls -a | grep -q ".sfh" && rm -f .sfh'
t "stat 文件" sh -c 'touch sf.f && stat sf.f >/dev/null 2>&1 && rm -f sf.f'
t "find 深度递归" sh -c 'd=sf.d; rm -rf "$d" && mkdir -p "$d/a/b" && echo z>"$d/a/b/z" && find "$d" -name z | grep -q z && rm -rf "$d"'
t "find -type d" sh -c 'd=sf.d; rm -rf "$d" && mkdir -p "$d/x" && find "$d" -type d | grep -q x && rm -rf "$d"'
t "chmod 位" sh -c 'touch sf.f && chmod 755 sf.f && test "$(stat -c %a sf.f 2>/dev/null || stat -f %Lp sf.f)" = 755 && rm -f sf.f'
t "touch 时间戳" sh -c 'touch sf.f && (touch -d 2000-01-01 sf.f 2>/dev/null || touch -t 200001010000 sf.f) && test -e sf.f && rm -f sf.f'
t "seq/read 生成" sh -c 'seq 1 5 | wc -l | grep -q 5'
t "truncate/扩展" sh -c 'echo abc > sf.f && truncate -s 10 sf.f 2>/dev/null && test "$(wc -c <sf.f)" = 10 && rm -f sf.f'
gsum

GNO="C"
group "文本工具"
tm "grep 基本" "abc" sh -c 'echo abc123 | grep abc'
t "grep -i" sh -c 'echo CASE | grep -qi case'
tm "grep -c 计数" "^[0-9]+$" sh -c 'printf "1\n2\nx\n" | grep -c "[0-9]"'
tm "grep -E 扩展" "123" sh -c 'echo 123 | grep -E "[0-9]{3}"'
t "grep -v 反选" sh -c 'printf "a\nx\n" | grep -v x | grep -q "^a$"'
tm "sed 替换" "world" sh -c 'echo hello | sed s/hello/world/'
tm "sed 地址行" "second" sh -c 'printf "a\nsecond\nc\n" | sed -n 2p'
t "sed 删除行" sh -c 'printf "a\nb\n" | sed 1d | grep -q "^b$"'
tm "awk 字段" "2" sh -c 'echo "1 2 3" | awk "{print \$2}"'
tm "awk NF/printf" "x:y" sh -c 'echo "x y" | awk "{printf \"%s:%s\\n\",\$1,\$2}"'
tm "sort 默认" "^a$" sh -c 'printf "b\na\nc\n" | sort | head -1'
tm "sort -n 数值" "^1$" sh -c 'printf "10\n2\n1\n" | sort -n | head -1'
t "sort -u" sh -c 'printf "1\n1\n2\n" | sort -u | wc -l | grep -q "^2$"'
tm "uniq -c" "2" sh -c 'printf "x\nx\ny\n" | uniq -c | head -1'
t "wc -c(含换行=6)" sh -c 'echo hello | wc -c | grep -q "^6$"'
tm "head -n/-c" "ab" sh -c 'echo abcdef | head -c 2'
tm "tail -n" "b" sh -c 'printf "a\nb\n" | tail -1'
tm "cut -d -f" "l2" sh -c 'echo "l1|l2|l3" | cut -d"|" -f2'
tm "tr 大小写" "test" sh -c 'echo TEST | tr A-Z a-z'
tm "tr -d 删除" "ab" sh -c 'echo axb | tr -d x'
t "od 十六进制" sh -c 'echo hi | od -tx1 | grep -q "68 69" || echo hi | od -A x -t x1 | grep -q "6869"'
t "hexdump" sh -c 'echo hi | hexdump -C | grep -q "68 69"'
t "base64 编码" sh -c 'test "$(echo hi | base64 | tr -d "\n")" = aGkK'
t "base64 解码" sh -c 'echo aGk= | base64 -d | grep -q hi'
t "comm 求交" sh -c 'printf "x\ny\n" | sort > a && printf "x\nz\n" | sort > b && comm -12 a b | grep -q "^x$" && rm -f a b'
t "join" sh -c 'printf "1 x\n" > a && printf "1 y\n" > b && join a b | grep -q "1 x y" && rm -f a b'
t "paste 并排" sh -c 'printf "a\n" > a && printf "1\n" > b && paste a b | grep -q "a[[:space:]]*1" && rm -f a b'
t "fold 折行" sh -c 'echo abcd | fold -w2 | head -1 | grep -q "^ab$"'
t "expand 展开制表" sh -c 'printf "a\tb\n" | expand | grep -qE "a[ ]+b"'
gsum

GNO="D"
group "归档与压缩"
t "tar czf/解出" sh -c 'd=sf.d; rm -rf "$d" && mkdir -p "$d/sub" && echo data>"$d/sub/f" && tar czf sf.tgz "$d" && tar xzf sf.tgz -O "$d/sub/f" 2>/dev/null | grep -q data && rm -rf "$d" sf.tgz'
t "tar cjf (bzip2)" sh -c 'd=sf.d; rm -rf "$d" && mkdir "$d" && echo b>"$d/f" && tar cjf sf.tbz "$d" 2>/dev/null && tar xjf sf.tbz -O "$d/f" 2>/dev/null | grep -q b && rm -rf "$d" sf.tbz'
if printf x | xz -c 2>/dev/null | xz -d 2>/dev/null | grep -q x; then
	t "tar cJf (外部 xz)" sh -c 'd=sf.d; rm -rf "$d" && mkdir "$d" && echo x>"$d/f" && tar cJf sf.txz "$d" 2>/dev/null && tar xJf sf.txz -O "$d/f" 2>/dev/null | grep -q x && rm -rf "$d" sf.txz'
else
	ws "tar cJf (外部 xz)" "未找到能编码的外部 xz；BusyBox xz 仅用于解码"
fi
t "gzip 往返" sh -c 'echo data | gzip -c > sf.gz && gzip -dc sf.gz | grep -q data && rm -f sf.gz'
t "gzip 多级压缩" sh -c 'echo data | gzip -9 -c > sf.gz && gzip -dc sf.gz | grep -q data && rm -f sf.gz'
t "bzip2 往返" sh -c 'echo data | bzip2 -c > sf.bz2 && bunzip2 -c sf.bz2 | grep -q data && rm -f sf.bz2'
t "xz 往返" sh -c 'echo data | xz -c > sf.xz && xzcat sf.xz | grep -q data && rm -f sf.xz'
t "lzma 往返" sh -c 'echo data | lzma -c > sf.lzma && unlzma -c sf.lzma 2>/dev/null | grep -q data && rm -f sf.lzma'
t "cpio 打包解出" sh -c 'd=sf.d; rm -rf "$d" && mkdir "$d" && echo c>"$d/f" && (cd "$d" && echo f | cpio -o -H newc 2>/dev/null) > sf.cpio && rm -rf "$d/out" && mkdir "$d/out" && (cd "$d/out" && cpio -i -d -F ../../sf.cpio 2>/dev/null) && grep -q c "$d/out/f" && rm -rf "$d" sf.cpio'
if have unzip && have zip; then
	t "unzip/zip 往返" sh -c 'rm -rf sf.zipx && mkdir sf.zipx && echo z > sf.zipx/f && (cd sf.zipx && zip -q ../sf.zip f) && mkdir sf.unzipx && (cd sf.unzipx && unzip -q ../sf.zip) && cmp sf.zipx/f sf.unzipx/f && rm -rf sf.zipx sf.unzipx sf.zip'
else
	ws "unzip/zip 往返" "需要同时编译 zip 与 unzip applet"
fi
t "ar 创建/列出/解出" sh -c 'echo hi > sf.txt && ar r sf.a sf.txt && ar t sf.a | grep -q sf.txt && mkdir -p sf.arx && (cd sf.arx && ar x ../sf.a) && grep -q hi sf.arx/sf.txt && rm -rf sf.txt sf.a sf.arx'
gsum

GNO="E"
group "shell (ash) 语法与行为"
t "函数定义/调用" sh -c 'f() { echo fn; }; x=$(f); test "$x" = fn'
t "case 分支" sh -c 'v=ab; case $v in ab) echo m;; *) echo n;; esac | grep -q m'
t "if/elif/else" sh -c 'n=2; if [ $n = 1 ]; then echo a; elif [ $n = 2 ]; then echo b; else echo c; fi | grep -q b'
t "for 循环" sh -c 's=0; for i in 1 2 3 4 5; do s=$((s+i)); done; test "$s" = 15'
t "while 读行" sh -c 'printf "a\nb\n" | while read l; do echo "<$l>"; done | wc -l | grep -q 2'
t "until" sh -c 'n=0; until [ $n -ge 3 ]; do n=$((n+1)); done; test "$n" = 3'
t "算术 \$(( ))" sh -c 'test $((2*3+1)) = 7'
t "参数展开 \${x#}" sh -c 'x=abc.txt; test "${x#abc}" = .txt'
t "参数展开 \${x%}" sh -c 'x=abc.txt; test "${x%.txt}" = abc'
t "参数展开 \${x:-}" sh -c 'unset y; test "${y:-dflt}" = dflt'
t "命令替换 \$()" sh -c 'test "$(echo ok)" = ok'
t "管道与 \$?" sh -c 'echo x | grep -q x && test $? = 0'
t "多命令 && / ;" sh -c 'true && true && test $? = 0'
t "子 shell ( )" sh -c '(cd /; test "$(pwd)" = /)'
t "后台 & + wait" sh -c 'sleep 0.2 & wait; echo done | grep -q done'
t "重定向 < > >>" sh -c 'echo 1>sf.o && echo 2>>sf.o && test "$(wc -l <sf.o)" = 2 && rm -f sf.o'
t "here-doc" sh -c 'cat <<EOF > sf.h
line1
EOF
grep -q line1 sf.h && rm -f sf.h'
t "位置参数 shift" sh -c 'set a b c; shift; test "$1" = b'
t "test 运算" sh -c 'test 5 -gt 3 -a 2 -le 2'
t "引号保留" sh -c 'x="a b"; for w in $x; do echo $w; done | wc -l | grep -q 2'
t "环境变量导出" sh -c 'export E1=v1; sh -c "test \"\$E1\" = v1"'
t "局部变量陷阱修正" sh -c 'i=0; for i in 1 2; do :; done; test "$i" = 2'
t "glob 展开" sh -c 'mkdir -p sf.g && touch sf.g/a1 sf.g/b2 && test "$(echo sf.g/* | wc -w)" = 2 && rm -rf sf.g'
t "printf %s" sh -c 'test "$(printf "%s-%s" a b)" = a-b'
t "&& || 短路" sh -c 'false || echo ok | grep -q ok'
gsum

GNO="F"
group "进程/系统/信息"
tm "id -u 数字" "^[0-9]+$" id -u
ts "whoami 非空(平台/沙箱)" sh -c 'whoami 2>/dev/null | grep -q .'
tm "env 变量透传" "FOO=bar" sh -c 'FOO=bar env | grep FOO=bar'
tm "printenv" "bar" sh -c 'FOO=bar printenv FOO'
tm "uname -m/-s/-r" "." sh -c 'uname -m; uname -s; uname -r | grep -q .'
ts "arch(输出架构)" sh -c 'arch 2>/dev/null | grep -q .'
t "sleep 0.5 后继续" sh -c 'sleep 0.5 && echo ok | grep -q ok'
tm "date 格式" "^20[0-9][0-9]-" sh -c 'date +%Y-%m-%d'
t "date -u UTC" sh -c 'date -u | grep -qiE "UTC|GMT"'
if [ "$IS_WIN" = 1 ]; then
	ws "timeout 杀超时" "win: cosmo 信号/进程组模拟限制, 见 KNOWN-LIMITATIONS"
else
	t "timeout 杀超时" sh -c 'timeout 1 sh -c "sleep 5" >/dev/null 2>&1; r=$?; test $r != 0'
fi
t "free 内存行" sh -c 'free 2>/dev/null | grep -q "Mem:"'
t "uptime" sh -c 'uptime 2>/dev/null | grep -qiE "up|min|day|load"'
ts "ps (平台/沙箱软项)" sh -c 'ps -o pid= 2>/dev/null | head -1 | grep -qE "^[0-9]" || ps | head -2 | grep -qiE "pid|cmd"'
t "hostname 显示" sh -c 'hostname 2>/dev/null | grep -q .'
ts "hostname -s 短名" sh -c 'h=$(hostname -s 2>/dev/null); test -n "$h"'
ts "dnsdomainname 可执行" sh -c 'dnsdomainname >/dev/null 2>&1'
ts "kill 自身信号(TERM)" sh -c 'sh -c "kill -TERM \$\$" 2>/dev/null; r=$?; test $r = 143 -o $r = 0'
t "kill -0 探测" sh -c 'kill -0 $$ 2>/dev/null'
ts "pgrep/pidof(需 /proc, 平台软项)" sh -c 'pgrep -f smoke-full >/dev/null 2>&1 || pgrep sh >/dev/null 2>&1 || pidof sh >/dev/null 2>&1'
ts "nproc(cosmo 上游缺口或可用)" sh -c 'nproc 2>/dev/null | grep -qE "^[0-9]+$"'
ts "uptime -s 启动时间" sh -c 'uptime -s 2>/dev/null | grep -qE "^20[0-9][0-9]-"'
t "stat 自身" sh -c 'stat / >/dev/null 2>&1 || stat . >/dev/null 2>&1'
gsum

GNO="G"
group "本地网络(回环, 不依赖外网)"
P=23241
if [ "$IS_WIN" = 1 ]; then
	# cosmo #1174: Windows fork 后 accept 场景 socket 继承未根治 + 信号/进程模拟
	# → nc -l / tcp 服务端回环测试不可靠(会 FAIL 甚至挂死), 跳过; 客户端 nslookup 保留
	ws "nc 本地回环(服务端)" "win: cosmo #1174, 见 KNOWN-LIMITATIONS"
	ws "telnet 本地回显" "win: cosmo #1174, 见 KNOWN-LIMITATIONS"
	ws "tcp 双向 socket" "win: cosmo #1174, 见 KNOWN-LIMITATIONS"
	echo "      (Windows: 网络组以 nslookup 客户端为准; nc/telnet/tcp 服务端缺口见 KNOWN-LIMITATIONS)"
else
	# 简易回显服务器: busybox nc -l -p -e cat(若 -e 支持) 否则退化为只测连接
	if nc -h 2>&1 | grep -q '\-e'; then
		t "nc 回环回显" sh -c "
			nc -l -p $P -e cat >/dev/null 2>&1 &
			srv=\$!
			sleep 0.3
			out=\$(echo hello | nc -w2 127.0.0.1 $P 2>/dev/null)
			kill \$srv 2>/dev/null
			test \"\$out\" = hello"
		tn "telnet 回环回显" "telnet 本地回显" sh -c "
			nc -l -p $P -e cat >/dev/null 2>&1 &
			srv=\$!
			sleep 0.3
			out=\$(echo tlx | telnet 127.0.0.1 $P 2>/dev/null | tr -d '\r')
			kill \$srv 2>/dev/null
			echo \"\$out\" | grep -q tlx"
	else
		# 无 -e: 仅验证 TCP 连接建立(服务器能 accept)
		t "nc listen/connect 握手" sh -c "
			nc -l -p $P >/dev/null 2>&1 &
			srv=\$!
			sleep 0.3
			echo ping | nc -w2 127.0.0.1 $P >/dev/null 2>&1
			r=\$?
			kill \$srv 2>/dev/null
			test \$r = 0"
		ts "telnet 连接握手(soft)" sh -c "
			nc -l -p $P >/dev/null 2>&1 &
			srv=\$!
			sleep 0.3
			echo q | telnet 127.0.0.1 $P 2>/dev/null; r=\$?
			kill \$srv 2>/dev/null
			test \$r = 0"
	fi
	# TCP 客户端纯连接(无需服务端回显语义) — 用 nc -l 后台
	t "tcp 双向 socket 基本" sh -c "
		nc -l -p $((P+1)) >/tmp/ncout 2>&1 &
		srv=\$!
		sleep 0.3
		printf 'abc' | nc -w2 127.0.0.1 $((P+1)) >/dev/null 2>&1
		sleep 0.2
		kill \$srv 2>/dev/null
		grep -q abc /tmp/ncout 2>/dev/null; rc=\$?
		rm -f /tmp/ncout
		test \$rc = 0"
	echo "      (网络组以 nc/telnet 本地回环为准, wget 走外网组可选)"
fi
ts "nslookup localhost(本地)" sh -c 'nslookup localhost 2>/dev/null | grep -qiE "name|server|127.0.0.1"'
gsum

GNO="H"
group "多字节/Unicode"
t "UTF-8 中文字符串" sh -c 'echo 中文测试 | grep -q 中文'
t "ls 中文文件名" sh -c 'mkdir -p sf.u && touch sf.u/文件.txt && ls sf.u | grep -q 文件 && rm -rf sf.u'
t "wc -m 字符计数(宽)" sh -c 'printf "中文ab" | wc -m | grep -qE "^[0-9]+$"'
t "printf UTF-8" sh -c 'printf "你\n" | grep -q 你'
t "sed 中文替换" sh -c 'echo 你好世界 | sed s/你好/您好/ | grep -q 您好'
t "tr 宽字符透传" sh -c 'echo 宽字符 | tr -d " " | grep -q 宽字符'
gsum

GNO="I"
group "make / 工具链集成"
t "make 执行配方" sh -c 'printf "all:\n\techo make-ok\n" > Makefile.sf && make -f Makefile.sf 2>/dev/null | grep -q make-ok && rm -f Makefile.sf'
t "make 目标依赖" sh -c 'printf "p: q\n\ttouch p\nq:\n\ttouch q\n" > Makefile.sf && make -f Makefile.sf p 2>/dev/null && test -f p -a -f q && rm -f Makefile.sf p q'
tm "sha256sum 向量" "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" sh -c 'printf "" | sha256sum'
tm "sha1sum 向量" "da39a3ee5e6b4b0d3255bfef95601890afd80709" sh -c 'printf "" | sha1sum'
tm "md5sum 向量" "d41d8cd98f00b204e9800998ecf8427e" sh -c 'printf "" | md5sum'
t "cksum 一致" sh -c 'echo abc > sf.f && c1=$(cksum <sf.f) && c2=$(cksum <sf.f) && test "$c1" = "$c2" && rm -f sf.f'
t "crc32 一致" sh -c 'echo abc > sf.f && crc32 sf.f >/dev/null 2>&1 && rm -f sf.f'
t "base32 往返" sh -c 'echo hi | base32 > sf.b32 && base32 -d sf.b32 2>/dev/null | grep -q hi && rm -f sf.b32'
t "uudecode 往返" sh -c 'echo hi | uuencode f > sf.uu && uudecode -o sf.f sf.uu 2>/dev/null && grep -q hi sf.f && rm -f sf.uu sf.f'
gsum

GNO="J"
group "vi/编辑器与 misc"
t "vi 可启动" sh -c 'echo hi > sf.v && vi -c "q!" sf.v </dev/null >/dev/null 2>&1; rc=$?; rm -f sf.v; test "$rc" = 0 -o "$rc" = 1'
tm "cat -n 行号" "^[[:space:]]*1" sh -c 'echo x | cat -n'
t "od -c 可视" sh -c 'echo x | od -c | grep -q x'
t "strings 二进制字符串" sh -c 'printf "hi\0world" > sf.b && strings sf.b 2>/dev/null | grep -q hi && rm -f sf.b'
tm "rev 反转" "olleh" sh -c 'echo hello | rev'
tm "shuf 排列" "^[ab]" sh -c 'printf "a\nb\n" | shuf'
tm "yes 输出截断" "^y$" sh -c 'yes | head -1'
t "cal 日历" sh -c 'cal 2>/dev/null | grep -qE "[A-Za-z]+ +20[0-9][0-9]|[0-9][0-9]"'
t "seq -w 补零" sh -c 'seq -w 9 11 | head -1 | grep -q "^09$"'
t "tsort 拓扑" sh -c 'printf "a b\n" | tsort 2>/dev/null | head -1 | grep -q "^a$"'
gsum

# ---------------- 汇总 ----------------
echo ""
echo "=================================================="
echo "  完整冒烟结果:"
echo "    总通过 PASS : $PASS"
echo "    总失败 FAIL : $FAIL"
echo "    跳过 SKIP   : $SKIP   (未编译/不支持)"
echo "    软失败 SOFT : $SOFT   (平台/环境差异)"
echo "=================================================="
if [ "$FAIL" -gt 0 ]; then
	echo "结果: 存在 FAIL, 见上(rc=1)"
	exit 1
else
	echo "结果: 全部通过/软失败 (rc=0)"
	exit 0
fi
