#!/bin/sh
# 兼容库契约测试；由当前 BusyBox ash 执行。
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../lib/portable.sh" ]; then
	HERE="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
else
	HERE="$SCRIPT_DIR"
fi
. "$HERE/lib/portable.sh" || exit 2
FAIL=0

ok() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

bbp_have sh && ok 'sh applet' || bad 'sh applet'
bbp_have printf && ok 'printf applet' || bad 'printf applet'
bbp_have test && ok 'test applet' || bad 'test applet'

tmp=$(bbp_tmpdir) || tmp=
if [ -n "$tmp" ] && [ -d "$tmp" ]; then
	printf '%s\n' data >"$tmp/data"
	[ "$(bbp cat "$tmp/data")" = data ] && ok '临时目录读写' || bad '临时目录读写'
	bbp_cleanup_dir "$tmp" && [ ! -e "$tmp" ] && ok '临时目录清理' || bad '临时目录清理'
else
	bad '临时目录创建'
fi

[ "$(BBP_UI_MODE=auto bbp_ui_mode)" = none ] && ok '非 TTY 自动降级' || bad '非 TTY 自动降级'
BBP_UI_MODE=none bbp_ui_select '不可交互' a b >/dev/null 2>&1 && bad 'none 模式误进入菜单' || ok 'none 模式拒绝菜单'

exit "$FAIL"
