#!/bin/sh
# 真实 ash 行为契约：从发布物运行，不能使用宿主 /bin/sh 代替。
. "$(dirname "$0")/testlib.sh"
bbtest_init ash
PASS=0
FAIL=0
t() {
  desc=$1; shift
  if bbtest_run "$@"; then
    echo "PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"; FAIL=$((FAIL + 1))
  fi
}

t '引号、空参数与字面通配符' busybox ash -ec '
  set -- "" "a b" "*" "中文"
  test "$#" = 4 && test "$1" = "" && test "$2" = "a b" && test "$3" = "*" && test "$4" = 中文
'
t 'IFS 分割与带引号的参数展开' busybox ash -ec '
  IFS=:; value=a:b; set -- $value; test "$#" = 2
  set -- "$value"; test "$#" = 1 && test "$1" = a:b
'
t '位置参数 shift/getopts' busybox ash -ec '
  set -- -n "a b" tail
  getopts n: opt; test "$opt" = n && test "$OPTARG" = "a b"
  shift "$((OPTIND - 1))"; test "$#" = 1 && test "$1" = tail
'
t '默认值、长度与前后缀删除' busybox ash -ec '
  unset missing; empty=; x=ab.tar.gz
  test "${missing:-default}" = default && test "${empty-default}" = ""
  test "${#x}" = 9 && test "${x%.gz}" = ab.tar && test "${x##*.}" = gz
'
t '命令替换去除尾部换行且保留退出码' busybox ash -c '
  value=$(printf "a\n\n"; exit 7); rc=$?
  test "$value" = a && test "$rc" = 7
'
t '引号 heredoc 不展开变量' busybox ash -ec '
  value=bad
  cat <<"END" > literal
$value
END
  test "$(cat literal)" = '\''$value'\''
'
t 'read -r 保留反斜线与首尾空格' busybox ash -ec '
  printf "%s\n" " a\\b " > read-input
  IFS= read -r value < read-input
  test "$value" = " a\\b "
'
t '子 shell 的 cwd 与变量不影响父 shell' busybox ash -ec '
  original=$PWD; value=parent; mkdir subdir
  (cd subdir; value=child)
  test "$PWD" = "$original" && test "$value" = parent
'
t '临时环境变量只传给指定命令' busybox ash -ec '
  unset CONTRACT_VALUE
  CONTRACT_VALUE="a b" busybox ash -ec '\''test "$CONTRACT_VALUE" = "a b"'\''
  test "${CONTRACT_VALUE-unset}" = unset
'
t '重定向顺序与追加写入' busybox ash -ec '
  busybox ash -c '\''printf out; printf err >&2'\'' > combined 2>&1
  test "$(cat combined)" = outerr
  result=$(busybox ash -c '\''printf out; printf err >&2'\'' 2>&1 > only-out)
  test "$result" = err && test "$(cat only-out)" = out
  printf again >> only-out; test "$(cat only-out)" = outagain
'
t '重定向失败阻止执行命令' busybox ash -c '
  busybox ash -c '\''echo SHOULD_NOT_RUN > missing-dir/output'\''
  rc=$?; test "$rc" -ne 0 && test ! -e missing-dir/output
'
t '默认管道状态来自最后一项' busybox ash -ec 'false | true; test "$?" = 0'
t 'pipefail 捕获上游失败' busybox ash -c 'set -o pipefail; false | true; test "$?" != 0'
t 'set -e 不吞失败' busybox ash -c '
  busybox ash -ec '\''false; printf bad > should-not-exist'\''
  rc=$?; test "$rc" != 0 && test ! -e should-not-exist
'
t 'set -e 下条件失败仍可处理' busybox ash -ec '
  if false; then exit 1; fi
  false || :
  test yes = yes
'
t 'EXIT trap 保留原始退出码' busybox ash -c '
  busybox ash -c '\''on_exit() { printf "%s" "$?" > exit-status; }; trap on_exit EXIT; exit 23'\''
  rc=$?; test "$rc" = 23 && test "$(cat exit-status)" = 23
'
t 'wait 返回指定子进程状态' busybox ash -c '
  (exit 17) & pid=$!
  wait "$pid"; rc=$?; test "$rc" = 17
'
t '后台进程数据与状态都可回收' busybox ash -ec '
  (printf first > child-one) & p1=$!
  (printf second > child-two) & p2=$!
  wait "$p1"; wait "$p2"
  test "$(cat child-one)" = first && test "$(cat child-two)" = second
'
t '命令不存在返回 127' busybox ash -c '
  busybox ash -c command_that_does_not_exist_bbp
  test "$?" = 127
'
t '空 PATH 下 applet 不借用宿主命令' busybox ash -ec '
  PATH=/path-that-does-not-exist
  value=$(printf "b\na\n" | sort | head -n 1)
  test "$value" = a
  busybox ash -ec '\''test "$(printf abc | wc -c)" -eq 3'\''
'
t 'exec 透传退出码' busybox ash -c '
  busybox ash -c '\''exec busybox ash -c "exit 29"'\''
  test "$?" = 29
'
t '递归 exec 十层' busybox ash -ec '
  printf "%s\n" '\''n=$1; if [ "$n" -eq 0 ]; then printf done; else exec busybox ash "$0" "$((n-1))"; fi'\'' > recurse.sh
  test "$(busybox ash recurse.sh 10)" = done
'

# 同时验证数量和逐项字节；覆盖 Windows 命令行转义及旧 argv[64] 边界。
for count in 63 64 65 256; do
  t "argv $count 项逐项完整（空串、引号、反斜线、中文）" busybox ash -ec '
    count=$1; set --; i=0
    while [ "$i" -lt "$count" ]; do
      case $((i % 4)) in
        0) arg="" ;; 1) arg="a b:$i" ;; 2) arg="quote\"slash\\:$i" ;; 3) arg="中文:$i" ;;
      esac
      set -- "$@" "$arg"; i=$((i+1))
    done
    printf "%s\000" "$@" > expected-argv
    busybox ash -ec '\''count=$1; shift; test "$#" -eq "$count"; printf "%s\000" "$@"'\'' ash "$count" "$@" > actual-argv
    cmp expected-argv actual-argv
  ' ash "$count"
done

t 'SHA256 非空已知答案' busybox ash -ec '
  printf abc > sha-input
  sha256sum sha-input > sha-output
  read -r digest rest < sha-output
  test "$digest" = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
'
t '二进制 NUL 数据经过文件、管道和 base64 无损' busybox ash -ec '
  set -o pipefail
  printf "a\000b\377c\n" > binary
  test "$(wc -c < binary)" -eq 6
  base64 binary > encoded
  test "$(cat encoded)" = YQBi/2MK
  base64 -d encoded | cmp - binary
'
t 'gzip 非法输入必须失败' busybox ash -c '
  printf invalid > not-gzip; gzip -dc not-gzip > decoded
  test "$?" -ne 0
'
t 'gzip、bzip2、tar 二进制文件往返' busybox ash -ec '
  set -o pipefail
  printf "payload\000\377\n" > payload
  gzip -c payload > payload.gz; gzip -dc payload.gz | cmp - payload
  bzip2 -c payload > payload.bz2; bzip2 -dc payload.bz2 | cmp - payload
  tar cf payload.tar payload; tar xf payload.tar -O payload | cmp - payload
'
echo "===== ash/功能契约: $PASS passed, $FAIL failed ====="
test "$FAIL" -eq 0
