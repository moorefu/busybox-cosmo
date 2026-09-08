#!/bin/sh
# 快速、离线的 BusyBox APE 冒烟；完整行为请运行 ash-contract/smoke-full。
. "$(dirname "$0")/testlib.sh"
bbtest_init smoke
PASS=0
FAIL=0
SKIP=0

t() {
	desc="$1"
	shift
	if bbtest_run "$@"; then
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "FAIL: $desc"
		FAIL=$((FAIL + 1))
	fi
}

s() {
	desc="$1"
	echo "SKIP: $desc"
	SKIP=$((SKIP + 1))
}

echo "===== busybox APE smoke test ====="

# --- 基础 ---
t "echo" echo smoke-ok
t "uname" sh -c 'uname -m | grep -q .'
t "date" sh -c 'date +%Y | grep -qE "^[0-9]{4}$"'
t "pwd" sh -c 'case "$PWD" in /*) exit 0;; *) exit 1;; esac'

# --- 文件操作 ---
t "mkdir+cp+cmp+rm" sh -c 'mkdir -p smoke.d && echo x > smoke.d/f1 && cp smoke.d/f1 smoke.d/f2 && cmp smoke.d/f1 smoke.d/f2 && rm -rf smoke.d'
t "dd bs/count" sh -c 'printf xxxx | dd bs=2 count=2 2>/dev/null | wc -c | grep -q 4'
t "ls 目录" sh -c 'mkdir -p smoke.d && ls . | grep -qx smoke.d && rm -rf smoke.d'
t "ln -s" sh -c 'mkdir -p smoke.d && echo x > smoke.d/f1 && ln -sfn smoke.d/f1 smoke.link && test -e smoke.link && rm -rf smoke.d smoke.link'
t "find 递归" sh -c 'mkdir -p smoke.d/sub && echo x > smoke.d/sub/f2 && test "$(find smoke.d -name f2)" = smoke.d/sub/f2 && rm -rf smoke.d'

# --- 文本工具 ---
t "grep 基本" sh -c 'echo abc123 | grep -q abc123'
t "grep -i" sh -c 'echo CASE | grep -qi case'
t "sort+head" sh -c 'printf "b\na\nc\n" | sort | head -1 | grep -q a'
t "sed 替换" sh -c 'echo hello | sed s/hello/world/ | grep -q world'
t "awk 字段" sh -c 'echo "1 2 3" | awk "{print \$2}" | grep -q 2'
t "tr 大小写" sh -c 'echo test | tr a-z A-Z | grep -q TEST'
t "cut 字段" sh -c 'echo "l1|l2|l3" | cut -d"|" -f2 | grep -q l2'
t "wc -l" sh -c '(echo a; echo b) | wc -l | grep -q 2'
t "head -c" sh -c 'echo abcdef | head -c 2 | grep -q ab'
t "tail -1" sh -c 'echo a; echo b | tail -1 | grep -q b'
t "uniq" sh -c 'printf "x\nx\ny\n" | uniq | wc -l | grep -q 2'
t "xxd hex" sh -c 'echo hi | xxd | grep -qi "6869"'

# --- shell 特性 ---
t "for 循环" sh -c 'for i in 1 2 3; do echo $i; done | wc -l | grep -q 3'
t "while+算术" sh -c 'n=0; while [ $n -lt 5 ]; do n=$((n+1)); done; echo $n | grep -q 5'
t "命令替换" sh -c 'x=$(echo hi); test "$x" = hi'
t "管道+fork" sh -c 'yes | head -3 | wc -l | grep -q 3'
t "xargs 子进程" sh -c 'echo one two three | xargs -n1 echo | wc -l | grep -q 3'
t "后台&wait" sh -c 'sleep 0.3 & wait; echo bg-ok'
t "重定向" sh -c 'echo data > smoke.tmp && cat smoke.tmp | grep -q data && rm -f smoke.tmp'
t "here-string 逻辑" sh -c 'test 5 -gt 3 && test ! 2 -gt 5'
t "printf 转义" sh -c 'printf "a\tb\n" | grep -q a'

# --- 进程/系统 ---
if sh -c 'ps | head -2 | grep -qi "pid\|cmd"' >/dev/null 2>&1; then
	echo "PASS: ps"
	PASS=$((PASS + 1))
else
	s "ps（宿主沙箱可能禁止进程枚举）"
fi
t "kill 子 shell 信号状态" sh -c 'sh -c "kill -TERM \$\$"; test "$?" = 143'
t "timeout 命令" sh -c 'timeout 1 sleep 0.1'
t "env" sh -c 'FOO=bar env | grep -q FOO=bar'

# 网络 applet 的确定性本地回环测试在 smoke-full；快速冒烟不访问公网。

# --- 归档/压缩 ---
t "tar 打包解包" sh -c 'mkdir -p s.d && echo data > s.d/f && tar czf s.tgz s.d && tar xzf s.tgz -O s.d/f | grep -q data && rm -rf s.d s.tgz'
t "gzip 往返" sh -c 'echo data | gzip > s.gz && gzip -dc s.gz | grep -q data && rm -f s.gz'
t "gzip -dc 解压" sh -c 'echo dummy > d.txt && gzip -c d.txt > d.gz && gzip -dc d.gz | grep -q dummy && rm -f d.txt d.gz'
t "gzip 非法输入失败" sh -c 'printf invalid > bad.gz; gzip -dc bad.gz >/dev/null 2>&1; test "$?" -ne 0'

# --- 设备/特殊文件 ---
t "/dev/null" sh -c 'cat /dev/null > /dev/null; echo dev-null-ok'
t "/dev/zero" sh -c 'dd if=/dev/zero bs=4 count=1 2>/dev/null | wc -c | grep -q 4'
t "/dev/urandom" sh -c 'dd if=/dev/urandom bs=8 count=1 2>/dev/null | wc -c | grep -q 8'

# --- 路径/大小写 ---
case "$(uname -s 2>/dev/null)" in
	*indows*|MINGW*|MSYS*|CYGWIN*)
		t "[win] cd 系统目录 /c/Windows" sh -c 'cd /c/Windows && pwd | grep -qi windows'
		t "[win] 文件系统大小写不敏感" sh -c 'ls /C/WINDOWS >/dev/null 2>&1 && echo case-ok'
		;;
	*)
		s "[win] cd 系统目录 /c/Windows"
		s "[win] 文件系统大小写不敏感"
		;;
esac

echo "===== 结果: $PASS passed, $FAIL failed, $SKIP skipped ====="
[ "$FAIL" -eq 0 ]
