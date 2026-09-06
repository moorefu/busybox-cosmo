#!/bin/sh
# 最小跨平台菜单示例：同一业务逻辑支持非交互和行式交互。
HERE="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
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

if [ "$#" -gt 0 ]; then
	choice=$1
else
	mode=$(bbp_ui_mode) || exit $?
	case "$mode" in
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
	doctor)
		if [ -f "$HERE/bbcosmo" ]; then doctor_script="$HERE/bbcosmo"; else doctor_script="$HERE/scripts/bbcosmo"; fi
		bbp ash "$doctor_script" doctor
		;;
	quit) printf '%s\n' '已退出。' ;;
	*) printf '未知操作: %s\n' "$choice" >&2; exit 2 ;;
esac
