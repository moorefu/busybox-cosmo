#!/bin/sh
# 最小跨平台菜单示例：同一业务逻辑支持非交互和行式交互。
HERE="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
if [ -z "${BBP_BUSYBOX:-}" ] && [ -x "$HERE/busybox" ]; then
	BBP_BUSYBOX="$HERE/busybox"
fi
. "$HERE/lib/portable.sh" || exit 2

if [ "$#" -gt 0 ]; then
	choice=$1
else
	case "$(bbp_ui_mode)" in
		none)
			printf '%s\n' '用法: portable-menu.sh {status|doctor|quit}' >&2
			exit 2
			;;
		*)
			choice=$(bbp_ui_select '请选择操作' 'status' 'doctor' 'quit') || exit $?
			case "$choice" in
				1) choice=status ;; 2) choice=doctor ;; 3) choice=quit ;;
			esac
			;;
	esac
fi

case "$choice" in
	status) printf '%s\n' 'status: ready' ;;
	doctor) "$HERE/scripts/bbcosmo" doctor ;;
	quit) printf '%s\n' '已退出。' ;;
	*) printf '未知操作: %s\n' "$choice" >&2; exit 2 ;;
esac
