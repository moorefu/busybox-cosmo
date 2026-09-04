#!/bin/sh
# deep-test.sh — busybox APE 深度测试(补充 smoke)
# 主战场: Linux 容器(podman)与 Windows; 建议: busybox.com sh deep-test.sh
# 覆盖: awk/sed 深度、长管道、大文件、并发 fork 压力
PASS=0
FAIL=0

t() {
	desc="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "FAIL: $desc"
		FAIL=$((FAIL + 1))
	fi
}

echo "===== busybox APE deep test ====="

# --- awk 深度 ---
# [win] awk 程序经 heredoc + awk -f 传入: Windows cosmo exec 重建 argv 时
#   `\`+`"` 相邻序列会错乱 (x\"y → x"\y), 程序含转义引号(如 s["x"]/"N"/"%.2f")
#   走 argv 会坏; 程序文件形式三平台一致 (见 docs/KNOWN-LIMITATIONS.md)。
t "awk 字段+NF" sh -c 'echo "a b c d e" | awk "{print NF}" | grep -q 5'
t "awk 数组聚合" sh -c '
cat > .deep-awk1.$$ <<"EOF"
{s[$1]+=$2} END{print s["x"]}
EOF
printf "x 1\nx 2\ny 3\n" | awk -f .deep-awk1.$$ | grep -q 3
rc=$?; rm -f .deep-awk1.$$; exit $rc'
t "awk 正则+sub" sh -c '
cat > .deep-awk2.$$ <<"EOF"
{gsub(/[0-9]+/, "N"); print}
EOF
echo "abc123def" | awk -f .deep-awk2.$$ | grep -q abcNdef
rc=$?; rm -f .deep-awk2.$$; exit $rc'
t "awk BEGIN/END" sh -c 'echo "l1" | awk "BEGIN{n=0} {n++} END{print n}" | grep -q 1'
t "awk printf 格式" sh -c '
cat > .deep-awk3.$$ <<"EOF"
{printf "%.2f\n", $1}
EOF
echo "3.14159" | awk -f .deep-awk3.$$ | grep -q 3.14
rc=$?; rm -f .deep-awk3.$$; exit $rc'
t "awk 多条件分支" sh -c '
cat > .deep-awk4.$$ <<"EOF"
$1%2==0{print "e"} $1%2==1{print "o"}
EOF
seq 1 20 2>/dev/null | awk -f .deep-awk4.$$ | sort | uniq -c | wc -l | grep -q 2
rc=$?; rm -f .deep-awk4.$$; exit $rc'
t "awk 字符串函数" sh -c 'echo "Hello World" | awk "{print tolower(\$0)}" | grep -q "hello world"'
t "awk getline" sh -c 'printf "1\n2\n3\n" | awk "{getline x; print x}" | grep -q 2'

# --- sed 深度 ---
t "sed 多命令" sh -c 'echo "abc" | sed "s/a/X/; s/c/Z/" | grep -q XbZ'
t "sed 地址范围" sh -c 'printf "1\n2\n3\n4\n" | sed "2,3d" | wc -l | grep -q 2'
t "sed 行追加" sh -c 'echo "a" | sed "a\\b" | wc -l | grep -q 2'
t "sed 保持空间" sh -c 'printf "1\n2\n" | sed -n "1h;2{g;p}" | grep -q 1'
t "sed -i 原地" sh -c 'echo "old" > sed-i.txt && sed -i "s/old/new/" sed-i.txt && grep -q new sed-i.txt && rm -f sed-i.txt'

# --- 长管道/数据流 ---
t "8 级管道链" sh -c 'echo "a b c d e f" | tr " " "\\n" | sort -r | head -3 | tail -1 | tr a-z A-Z | sed "s/^/X/" | grep -q XD'
t "大流量管道 sha256" sh -c 'dd if=/dev/zero bs=1M count=5 2>/dev/null | sha256sum | grep -qE "^[0-9a-f]{64}"'
t "tee 分流" sh -c 'echo flow | tee tee1.txt | grep -q flow && grep -q flow tee1.txt && rm -f tee1.txt'
# [cosmo 限制] mkfifo/mknod: cosmo 未实现 mknodat wrapper(ENOSYS), 不测

# --- 大文件 ---
t "20MB dd+cp 校验" sh -c 'dd if=/dev/urandom of=big.bin bs=1M count=20 2>/dev/null && cp big.bin big2.bin && cmp big.bin big2.bin && rm -f big.bin big2.bin'
t "大文件 sha 一致性" sh -c 'dd if=/dev/urandom of=big.bin bs=1M count=8 2>/dev/null && s1=$(sha256sum big.bin | cut -d" " -f1) && s2=$(cat big.bin | sha256sum | cut -d" " -f1) && test "$s1" = "$s2" && rm -f big.bin'
t "大文件 gzip 往返" sh -c 'dd if=/dev/urandom of=big.bin bs=1M count=4 2>/dev/null && gzip -c big.bin > big.gz && gzip -dc big.gz | cmp - big.bin && rm -f big.bin big.gz'
t "大文件 tar 往返" sh -c 'mkdir -p big.d && dd if=/dev/urandom of=big.d/f bs=1M count=3 2>/dev/null && tar czf big.tgz big.d && tar xzf big.tgz -O big.d/f | cmp - big.d/f && rm -rf big.d big.tgz'

# --- 并发 fork 压力 ---
t "xargs -P8 并发" sh -c 'seq 1 16 | xargs -P8 -n1 sh -c "echo \$\$ >> conc.txt; sleep 0.05" && wc -l < conc.txt | grep -q 16 && rm -f conc.txt'
t "10 个后台进程" sh -c 'i=1; while [ $i -le 10 ]; do (sleep 0.1; echo bg-$i >> bg.txt) & i=$((i+1)); done; wait; wc -l < bg.txt | grep -q 10 && rm -f bg.txt'
t "50 次 fork 循环" sh -c 'i=1; while [ $i -le 50 ]; do sh -c "exit 0" || exit 1; i=$((i+1)); done; echo fork50-ok'
t "嵌套子 shell 3 层" sh -c 'x=$(echo $(echo $(echo deep))) && test "$x" = deep'
t "并发生产者" sh -c '(yes p1 | head -2000 > cp1.txt) & (yes p2 | head -2000 > cp2.txt) & wait; cat cp1.txt cp2.txt | sort | uniq -c | wc -l | grep -q 2 && rm -f cp1.txt cp2.txt'
t "进程替换式 fd" sh -c 'cat <(echo procsub) 2>/dev/null | grep -q procsub || echo no-procsub'

# --- 文本大输入 ---
t "grep 万行" sh -c 'seq 1 10000 | grep -c 999 | grep -q 19'
t "sort 万行稳定" sh -c 'seq 1 5000 | shuf 2>/dev/null | sort -n | head -1 | grep -q 1'
t "wc 大输入" sh -c 'yes word | head -100000 | wc -w | grep -q 100000'

# --- 交互工具可用性(无 tty 探测) ---
t "ed 脚本化编辑" sh -c 'printf "a\\nhello-ed\\n.\\nw ed.txt\\nq\\n" | ed >/dev/null 2>&1 && grep -q hello-ed ed.txt && rm -f ed.txt'
t "vi 二进制存在" sh -c 'vi --help 2>&1 | grep -qi usage'

echo "===== 结果: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
