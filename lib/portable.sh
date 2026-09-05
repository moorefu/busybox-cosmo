#!/bin/sh
# busybox-cosmo 可移植脚本基础库
#
# 约定：
#   BBP_BUSYBOX 指向当前发行包的 busybox 可执行文件或 launcher。
#   需要 applet 时优先调用 bbp <applet>，避免宿主 PATH 中的命令遮蔽 BusyBox。
#   UI 函数把界面写到 stderr，把选择结果写到 stdout。

BBP_BUSYBOX=${BBP_BUSYBOX:-busybox}
BBP_UI_MODE=${BBP_UI_MODE:-auto}
BBP_COLOR=${BBP_COLOR:-auto}

bbp() {
	"$BBP_BUSYBOX" "$@"
}

bbp_list() {
	bbp --list 2>/dev/null
}

bbp_have() {
	[ "$#" -eq 1 ] || return 2
	bbp_have_name=$1
	# sh 通常由 CONFIG_SH_IS_ASH 提供，是 ash 的入口别名；能力
	# 清单应报告逻辑接口，而不是要求发行包额外编译一个 sh applet。
	[ "$bbp_have_name" = sh ] && bbp_have_name=ash
	bbp_have_list=$(bbp_list) || return 1
	bbp_have_old_ifs=$IFS
	bbp_have_ifs=$(printf ' \t\nX')
	bbp_have_ifs=${bbp_have_ifs%X}
	IFS=$bbp_have_ifs
	set -- $bbp_have_list
	IFS=$bbp_have_old_ifs
	for bbp_have_item do
		[ "$bbp_have_item" = "$bbp_have_name" ] && return 0
	done
	return 1
}

bbp_require() {
	while [ "$#" -gt 0 ]; do
		bbp_have "$1" || {
			printf '%s\n' "缺少 BusyBox applet: $1" >&2
			return 127
		}
		shift
	done
}

bbp_os() {
	bbp uname -s 2>/dev/null || printf '%s\n' unknown
}

bbp_arch() {
	bbp uname -m 2>/dev/null || printf '%s\n' unknown
}

bbp_is_windows() {
	case "$(bbp_os)" in
		*[Ww]indows*|*[Ww]in32*|MINGW*|MSYS*|CYGWIN*) return 0 ;;
		*) return 1 ;;
	esac
}

bbp_is_tty() {
	[ -t 0 ] && [ -t 1 ]
}

bbp_term_size() {
	bbp_is_tty || return 1
	bbp stty size 2>/dev/null
}

bbp_ansi_available() {
	bbp_is_tty || return 1
	[ "${TERM:-dumb}" != dumb ] || return 1
	[ -z "${NO_COLOR:-}" ] || return 1
	return 0
}

bbp_ui_mode() {
	case "$BBP_UI_MODE" in
		line|tui|none) printf '%s\n' "$BBP_UI_MODE"; return 0 ;;
		auto) ;;
		*) printf '%s\n' "line"; return 0 ;;
	esac
	if bbp_ansi_available && bbp_term_size >/dev/null 2>&1; then
		printf '%s\n' tui
	elif bbp_is_tty; then
		printf '%s\n' line
	else
		printf '%s\n' none
	fi
}

bbp_color_enabled() {
	case "$BBP_COLOR" in
		always) return 0 ;;
		never) return 1 ;;
		auto) bbp_ansi_available ;;
		*) return 1 ;;
	esac
}

bbp_tmpdir() {
	bbp_require mkdir rm rmdir >/dev/null 2>&1 || return 1
	bbp_tmp_base=${TMPDIR:-${TEMP:-${TMP:-.}}}
	[ -d "$bbp_tmp_base" ] && [ -w "$bbp_tmp_base" ] || bbp_tmp_base=.
	if bbp_have mktemp; then
		bbp_tmp_result=$(bbp mktemp -d "$bbp_tmp_base/bbp.XXXXXX" 2>/dev/null) || bbp_tmp_result=
		if [ -n "$bbp_tmp_result" ] && [ -d "$bbp_tmp_result" ]; then
			printf '%s\n' "$bbp_tmp_result"
			return 0
		fi
	fi
	bbp_tmp_i=0
	while [ "$bbp_tmp_i" -lt 20 ]; do
		bbp_tmp_result="$bbp_tmp_base/bbp-$$-$bbp_tmp_i"
		if bbp mkdir "$bbp_tmp_result" 2>/dev/null; then
			printf '%s\n' "$bbp_tmp_result"
			return 0
		fi
		bbp_tmp_i=$((bbp_tmp_i + 1))
	done
	printf '%s\n' '无法创建临时目录（目录不可写或并发冲突）' >&2
	return 1
}

bbp_cleanup_dir() {
	[ "$#" -eq 1 ] || return 2
	bbp_cleanup_target=$1
	case "$bbp_cleanup_target" in
		""|/|.|..|"$PWD"|"$PWD/"*) return 2 ;;
	esac
	bbp rm -rf -- "$bbp_cleanup_target"
}

bbp_external_xz() {
	if [ -n "${BBP_XZ_ENCODER:-}" ] && [ -x "$BBP_XZ_ENCODER" ]; then
		printf '%s\n' "$BBP_XZ_ENCODER"
		return 0
	fi
	bbp_xz_candidate=$(command -v xz 2>/dev/null || true)
	[ -n "$bbp_xz_candidate" ] && [ -x "$bbp_xz_candidate" ] || return 1
	printf '%s\n' "$bbp_xz_candidate"
}

bbp_xz_encode_available() {
	bbp_xz_encoder=$(bbp_external_xz) || return 1
	bbp_xz_tmp=$(bbp_tmpdir) || return 1
	trap 'bbp_cleanup_dir "$bbp_xz_tmp" >/dev/null 2>&1 || true' 0 1 2 3 15
	printf '%s' x | "$bbp_xz_encoder" -c >"$bbp_xz_tmp/in.xz" 2>/dev/null || return 1
	[ -s "$bbp_xz_tmp/in.xz" ] || return 1
	"$bbp_xz_encoder" -d <"$bbp_xz_tmp/in.xz" >"$bbp_xz_tmp/out" 2>/dev/null || return 1
	[ "$(bbp cat "$bbp_xz_tmp/out" 2>/dev/null)" = x ]
}

bbp_run_timeout() {
	[ "$#" -gt 1 ] || return 2
	if bbp_have timeout; then
		bbp timeout "$@"
		return $?
	fi
	printf '%s\n' '当前 BusyBox 没有 timeout applet；拒绝伪造超时保证' >&2
	return 127
}

bbp_ui_select() {
	bbp_ui_select_prompt=$1
	shift
	[ "$#" -gt 0 ] || return 2
	[ "$(bbp_ui_mode)" != none ] || return 2
	bbp_ui_select_count=$#
	while :; do
		bbp_ui_select_i=1
		for bbp_ui_select_item do
			printf '%s) %s\n' "$bbp_ui_select_i" "$bbp_ui_select_item" >&2
			bbp_ui_select_i=$((bbp_ui_select_i + 1))
		done
		printf '%s [1-%s]: ' "$bbp_ui_select_prompt" "$bbp_ui_select_count" >&2
		IFS= read -r bbp_ui_select_answer || return 130
		case "$bbp_ui_select_answer" in
			*[!0-9]*|'') ;;
			*)
				[ "$bbp_ui_select_answer" -ge 1 ] 2>/dev/null || continue
				[ "$bbp_ui_select_answer" -le "$bbp_ui_select_count" ] 2>/dev/null || continue
				printf '%s\n' "$bbp_ui_select_answer"
				return 0
				;;
		esac
		printf '%s\n' '请输入菜单编号。' >&2
	done
}

bbp_ui_confirm() {
	bbp_ui_confirm_prompt=$1
	[ "$(bbp_ui_mode)" != none ] || return 2
	printf '%s [y/N]: ' "$bbp_ui_confirm_prompt" >&2
	IFS= read -r bbp_ui_confirm_answer || return 130
	case "$bbp_ui_confirm_answer" in
		y|Y|yes|YES) return 0 ;;
		*) return 1 ;;
	esac
}
