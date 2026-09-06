#!/bin/sh
# 兼容库契约；测试公共 API 的成功与拒绝路径，不把“有 applet”当作功能可用。
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../lib/portable.sh" ]; then
	HERE="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
else
	HERE="$SCRIPT_DIR"
fi
if [ -z "${BBP_BUSYBOX:-}" ]; then
	case "$(uname -s 2>/dev/null)" in
		*[Ww]indows*|*[Ww]in32*) first="$HERE/busybox.com"; second="$HERE/busybox" ;;
		*) first="$HERE/busybox"; second="$HERE/busybox.com" ;;
	esac
	for candidate in "$first" "$second"; do
		if [ -x "$candidate" ]; then BBP_BUSYBOX=$candidate; break; fi
	done
fi
. "$HERE/lib/portable.sh" || exit 2
. "$SCRIPT_DIR/testlib.sh" || exit 2
if [ -f "$HERE/bbcosmo" ]; then BBCOSMO="$HERE/bbcosmo"; else BBCOSMO="$HERE/scripts/bbcosmo"; fi
bbtest_init portable
PASS=0
FAIL=0
t() {
	desc=$1; shift
	if bbtest_run "$@"; then
		printf 'PASS: %s\n' "$desc"; PASS=$((PASS + 1))
	else
		printf 'FAIL: %s\n' "$desc"; FAIL=$((FAIL + 1))
	fi
}
te() {
	desc=$1; script=$2
	t "$desc" eval "$script"
}

te '精确识别 sh 与特殊名字 applet' 'bbp_have sh && bbp_have ash && bbp_have "[" && ! bbp_have applet-that-does-not-exist'
te 'require 缺失返回 127' 'bbp_require applet-that-does-not-exist >/dev/null 2>&1; test "$?" -eq 127'
te '临时目录为绝对路径且含本进程所有权标志' '
	tmp=$(bbp_tmpdir) || exit
	case "$tmp" in /*) ;; *) exit 1 ;; esac
	grep -qx "bbp-tmp-v1:$$" "$tmp/.bbp-owned" && printf data >"$tmp/data" &&
	test "$(bbp cat "$tmp/data")" = data && bbp_cleanup_dir "$tmp" && test ! -e "$tmp"
'
te '拒绝清理无所有权目录' '
	mkdir not-owned
	bbp_cleanup_dir "$PWD/not-owned"; rc=$?
	test "$rc" -eq 2 && test -d not-owned
'
te '拒绝相对路径和当前目录' '
	bbp_cleanup_dir .; a=$?
	bbp_cleanup_dir bbp-fake; b=$?
	test "$a" -eq 2 && test "$b" -eq 2
'
te '显式无效 xz 编码器不回退 PATH' '
	BBP_XZ_ENCODER="$PWD/missing-xz"; export BBP_XZ_ENCODER
	! bbp_external_xz && ! bbp_xz_encode_available
'
te 'xz 探测不覆盖调用者 trap' '
	trap "printf retained > trap-result" 0
	bbp_xz_encode_available >/dev/null 2>&1 || :
	exit 0
'
te '上一个用例的 EXIT trap 已执行' 'test "$(cat trap-result)" = retained'
te 'timeout 参数不足返回 2' 'bbp_run_timeout 1 >/dev/null 2>&1; test "$?" -eq 2'
te 'auto 在非 TTY 降级 none' 'test "$(BBP_UI_MODE=auto bbp_ui_mode)" = none'
te '非法 UI 模式明确失败' 'BBP_UI_MODE=invalid bbp_ui_mode >/dev/null 2>&1; test "$?" -eq 2'
te '未实现 TUI 明确失败' 'BBP_UI_MODE=tui bbp_ui_mode >/dev/null 2>&1; test "$?" -eq 3'
te 'line 菜单选择写 stdout、提示写 stderr' '
	printf "2\n" | BBP_UI_MODE=line bbp_ui_select "选择" one two > selected 2> prompt
	test "$(cat selected)" = 2 && grep -q "选择" prompt
'
te 'line 菜单 EOF 返回 130' '
	BBP_UI_MODE=line bbp_ui_select "选择" one </dev/null >/dev/null 2>&1
	test "$?" -eq 130
'
te 'none 模式不读取输入' '
	BBP_UI_MODE=none bbp_ui_select "不可交互" one </dev/null >/dev/null 2>&1
	test "$?" -eq 2
'
te 'confirm 参数不足返回 2' 'bbp_ui_confirm >/dev/null 2>&1; test "$?" -eq 2'
te '菜单示例非交互路径' 'test "$(bbp ash "$HERE/examples/portable-menu.sh" status)" = "status: ready"'
te '菜单示例未知操作返回 2' 'bbp ash "$HERE/examples/portable-menu.sh" unknown >/dev/null 2>&1; test "$?" -eq 2'
te '能力报告缺少 format 值返回 2' 'bbp ash "$BBCOSMO" capabilities --format >/dev/null 2>&1; test "$?" -eq 2'

echo "===== 兼容库契约: $PASS passed, $FAIL failed ====="
test "$FAIL" -eq 0
