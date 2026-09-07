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
te '平台与架构归一化只返回约定值' '
	case "$(bbp_os_family)" in linux|macos|windows|freebsd|openbsd|netbsd|unknown) ;; *) exit 1 ;; esac
	case "$(bbp_arch_family)" in x86_64|aarch64|unknown) ;; *) exit 1 ;; esac
'
te '外部命令发现不被 BusyBox 同名 applet 遮蔽' '
	mkdir external-bin
	printf "#!/bin/sh\nexit 0\n" > external-bin/probe-tool
	chmod 755 external-bin/probe-tool
	path=$(PATH="$PWD/external-bin" bbp_external_command probe-tool) || exit
	test "$path" = "$PWD/external-bin/probe-tool"
'
te '外部命令发现拒绝路径注入' 'bbp_external_command "../xz" >/dev/null 2>&1; test "$?" -eq 2'
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
te '仅返回成功的伪 zip 不会被判为编码能力' '
	printf "#!/bin/sh\nexit 0\n" > fake-zip
	chmod 755 fake-zip
	BBP_ZIP_ENCODER="$PWD/fake-zip"; export BBP_ZIP_ENCODER
	! bbp_zip_encode_available
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
te '稳定 ID 菜单返回 ID 而不是显示文本' '
	printf "2\r\n" | BBP_UI_MODE=line bbp_ui_select_id "操作" inspect "检查归档" extract "解压归档" > selected-id 2> id-prompt
	test "$(cat selected-id)" = extract && grep -q "解压归档" id-prompt
'
te '稳定 ID 菜单拒绝不成对参数' '
	BBP_UI_MODE=line bbp_ui_select_id "操作" one >/dev/null 2>&1
	test "$?" -eq 2
'
te 'none 模式不读取输入' '
	BBP_UI_MODE=none bbp_ui_select "不可交互" one </dev/null >/dev/null 2>&1
	test "$?" -eq 2
'
te 'confirm 参数不足返回 2' 'bbp_ui_confirm >/dev/null 2>&1; test "$?" -eq 2'
te 'confirm 支持明确默认值及 CRLF 输入' '
	printf "\r\n" | BBP_UI_MODE=line bbp_ui_confirm "继续" yes >/dev/null 2>&1
	yes_rc=$?
	printf "n\r\n" | BBP_UI_MODE=line bbp_ui_confirm "继续" yes >/dev/null 2>&1
	no_rc=$?
	test "$yes_rc" -eq 0 && test "$no_rc" -eq 1
'
te '已知 PID 存活探测' 'bbp_pid_alive $$ && ! bbp_pid_alive invalid >/dev/null 2>&1; test "$?" -eq 0'
te '菜单示例非交互路径' 'test "$(bbp ash "$HERE/examples/portable-menu.sh" status)" = "status: ready"'
te '菜单示例未知操作返回 2' 'bbp ash "$HERE/examples/portable-menu.sh" unknown >/dev/null 2>&1; test "$?" -eq 2'
te '能力报告缺少 format 值返回 2' 'bbp ash "$BBCOSMO" capabilities --format >/dev/null 2>&1; test "$?" -eq 2'
te '能力报告区分 applet 与操作来源' '
	bbp ash "$BBCOSMO" capabilities --format kv > capabilities.kv || exit
	grep -q "^capabilities.schema=1$" capabilities.kv &&
	grep -q "^platform.os.family=" capabilities.kv &&
	grep -q "^archive.xz.decode=" capabilities.kv &&
	grep -qE "^archive.xz.encode=(external|unavailable)$" capabilities.kv &&
	grep -qE "^process.name_search=(builtin|unsupported)$" capabilities.kv &&
	grep -q "^network.https.peer_verified=unsupported$" capabilities.kv
'

echo "===== 兼容库契约: $PASS passed, $FAIL failed ====="
test "$FAIL" -eq 0
