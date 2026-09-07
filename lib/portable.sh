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

# 兼容层公开退出码。底层 applet 的退出码保持原样；这些值只用于 bbp_* API。
BBP_E_USAGE=2
BBP_E_UNSUPPORTED=3
BBP_E_UNAVAILABLE=127
BBP_E_CANCELLED=130

bbp() {
	"$BBP_BUSYBOX" "$@"
}

bbp_list() {
	bbp --list 2>/dev/null
}

bbp_have() {
	[ "$#" -eq 1 ] || return 2
	bbp_have_name=$1
	bbp_have_list=$(bbp_list) || return 1
	case "
$bbp_have_list
" in
		*"
$bbp_have_name
"*) return 0 ;;
		*) return 1 ;;
	esac
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

bbp_os_family() {
	case "$(bbp_os)" in
		Linux*) printf '%s\n' linux ;;
		Darwin*) printf '%s\n' macos ;;
		*[Ww]indows*|*[Ww]in32*|MINGW*|MSYS*|CYGWIN*) printf '%s\n' windows ;;
		FreeBSD*) printf '%s\n' freebsd ;;
		OpenBSD*) printf '%s\n' openbsd ;;
		NetBSD*) printf '%s\n' netbsd ;;
		*) printf '%s\n' unknown ;;
	esac
}

bbp_arch_family() {
	case "$(bbp_arch)" in
		x86_64|amd64|AMD64) printf '%s\n' x86_64 ;;
		aarch64|arm64|ARM64) printf '%s\n' aarch64 ;;
		*) printf '%s\n' unknown ;;
	esac
}

bbp_is_windows() {
	[ "$(bbp_os_family)" = windows ]
}

# 只查找 PATH 中的独立程序，不使用 command -v。BusyBox ash 启用
# FEATURE_PREFER_APPLETS 后，command -v/xz 可能指向仅支持解码的内置 applet。
bbp_external_command() (
	[ "$#" -eq 1 ] || return "$BBP_E_USAGE"
	case "$1" in
		''|*/*|*[!A-Za-z0-9_.+-]*) return "$BBP_E_USAGE" ;;
	esac
	# PATH 分段仍需关闭 pathname expansion；目录名中的 []*? 只能按字面解释。
	set -f
	bbp_cmd_name=$1
	bbp_cmd_old_ifs=$IFS
	IFS=:
	for bbp_cmd_dir in ${PATH:-}; do
		[ -n "$bbp_cmd_dir" ] || continue
		for bbp_cmd_candidate in \
			"$bbp_cmd_dir/$bbp_cmd_name" \
			"$bbp_cmd_dir/$bbp_cmd_name.exe" \
			"$bbp_cmd_dir/$bbp_cmd_name.com"; do
			if [ -f "$bbp_cmd_candidate" ] && [ -x "$bbp_cmd_candidate" ]; then
				IFS=$bbp_cmd_old_ifs
				bbp_cmd_parent=${bbp_cmd_candidate%/*}
				bbp_cmd_leaf=${bbp_cmd_candidate##*/}
				bbp_cmd_parent=$(CDPATH= cd -- "$bbp_cmd_parent" 2>/dev/null && pwd -P) || return 1
				printf '%s/%s\n' "$bbp_cmd_parent" "$bbp_cmd_leaf"
				return 0
			fi
		done
	done
	return 1
)

bbp_is_tty() {
	# 选择从 stdin 读、提示写 stderr；stdout 可能正被命令替换捕获。
	[ -t 0 ] && [ -t 2 ]
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
		line|none) printf '%s\n' "$BBP_UI_MODE"; return 0 ;;
		tui) printf '%s\n' '当前兼容层尚未实现 raw TUI，请使用 line 模式' >&2; return 3 ;;
		auto) ;;
		*) printf '%s\n' "无效的 BBP_UI_MODE: $BBP_UI_MODE" >&2; return 2 ;;
	esac
	if bbp_is_tty; then
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
	bbp_require mkdir rm grep >/dev/null 2>&1 || return 1
	bbp_tmp_base=${TMPDIR:-${TEMP:-${TMP:-.}}}
	[ -d "$bbp_tmp_base" ] && [ -w "$bbp_tmp_base" ] || bbp_tmp_base=.
	bbp_tmp_base=$(CDPATH= cd -- "$bbp_tmp_base" 2>/dev/null && pwd -P) || return 1
	if bbp_have mktemp; then
		bbp_tmp_result=$(bbp mktemp -d "$bbp_tmp_base/bbp.XXXXXX" 2>/dev/null) || bbp_tmp_result=
		if [ -n "$bbp_tmp_result" ] && [ -d "$bbp_tmp_result" ]; then
			printf 'bbp-tmp-v1:%s\n' "$$" >"$bbp_tmp_result/.bbp-owned" || { bbp rm -rf -- "$bbp_tmp_result"; return 1; }
			printf '%s\n' "$bbp_tmp_result"
			return 0
		fi
	fi
	bbp_tmp_i=0
	while [ "$bbp_tmp_i" -lt 20 ]; do
		bbp_tmp_result="$bbp_tmp_base/bbp-$$-$bbp_tmp_i"
		if bbp mkdir "$bbp_tmp_result" 2>/dev/null; then
			printf 'bbp-tmp-v1:%s\n' "$$" >"$bbp_tmp_result/.bbp-owned" || { bbp rm -rf -- "$bbp_tmp_result"; return 1; }
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
		/*/bbp.*|/*/bbp-*) ;;
		*) return 2 ;;
	esac
	[ -d "$bbp_cleanup_target" ] && [ ! -L "$bbp_cleanup_target" ] || return 2
	[ -f "$bbp_cleanup_target/.bbp-owned" ] && [ ! -L "$bbp_cleanup_target/.bbp-owned" ] || return 2
	bbp grep -qx "bbp-tmp-v1:$$" "$bbp_cleanup_target/.bbp-owned" 2>/dev/null || return 2
	bbp_cleanup_parent=${bbp_cleanup_target%/*}
	bbp_cleanup_leaf=${bbp_cleanup_target##*/}
	bbp_cleanup_parent=$(CDPATH= cd -- "$bbp_cleanup_parent" 2>/dev/null && pwd -P) || return 2
	[ "$bbp_cleanup_parent/$bbp_cleanup_leaf" = "$bbp_cleanup_target" ] || return 2
	bbp rm -rf -- "$bbp_cleanup_target"
}

bbp_external_xz() (
	if [ "${BBP_XZ_ENCODER+x}" = x ]; then
		case "$BBP_XZ_ENCODER" in /*) ;; *) return 1 ;; esac
		[ -x "$BBP_XZ_ENCODER" ] || return 1
		printf '%s\n' "$BBP_XZ_ENCODER"
		return 0
	fi
	bbp_external_command xz
)

bbp_external_lzma() (
	if [ "${BBP_LZMA_ENCODER+x}" = x ]; then
		case "$BBP_LZMA_ENCODER" in /*) ;; *) return 1 ;; esac
		[ -x "$BBP_LZMA_ENCODER" ] || return 1
		printf '%s\n' "$BBP_LZMA_ENCODER"
		return 0
	fi
	bbp_external_command lzma
)

bbp_external_zip() (
	if [ "${BBP_ZIP_ENCODER+x}" = x ]; then
		case "$BBP_ZIP_ENCODER" in /*) ;; *) return 1 ;; esac
		[ -x "$BBP_ZIP_ENCODER" ] || return 1
		printf '%s\n' "$BBP_ZIP_ENCODER"
		return 0
	fi
	bbp_external_command zip
)

bbp_xz_encode_available() {
	(
		bbp_xz_encoder=$(bbp_external_xz) || exit 1
		bbp_xz_tmp=$(bbp_tmpdir) || exit 1
		trap 'bbp_cleanup_dir "$bbp_xz_tmp" >/dev/null 2>&1 || true' 0 1 2 3 15
		printf '%s' x >"$bbp_xz_tmp/in"
		bbp timeout 10 "$bbp_xz_encoder" -c "$bbp_xz_tmp/in" >"$bbp_xz_tmp/in.xz" 2>/dev/null || exit 1
		[ -s "$bbp_xz_tmp/in.xz" ] || exit 1
		bbp xz -dc "$bbp_xz_tmp/in.xz" >"$bbp_xz_tmp/out" 2>/dev/null || exit 1
		bbp cmp "$bbp_xz_tmp/in" "$bbp_xz_tmp/out" >/dev/null 2>&1 || exit 1
		bbp_cleanup_dir "$bbp_xz_tmp" || exit 1
		trap - 0 1 2 3 15
	)
}

bbp_lzma_encode_available() {
	(
		bbp_lzma_encoder=$(bbp_external_lzma) || exit 1
		bbp_lzma_tmp=$(bbp_tmpdir) || exit 1
		trap 'bbp_cleanup_dir "$bbp_lzma_tmp" >/dev/null 2>&1 || true' 0 1 2 3 15
		printf '%s' x >"$bbp_lzma_tmp/in"
		bbp timeout 10 "$bbp_lzma_encoder" -c "$bbp_lzma_tmp/in" >"$bbp_lzma_tmp/in.lzma" 2>/dev/null || exit 1
		[ -s "$bbp_lzma_tmp/in.lzma" ] || exit 1
		bbp unlzma -c "$bbp_lzma_tmp/in.lzma" >"$bbp_lzma_tmp/out" 2>/dev/null || exit 1
		bbp cmp "$bbp_lzma_tmp/in" "$bbp_lzma_tmp/out" >/dev/null 2>&1 || exit 1
		bbp_cleanup_dir "$bbp_lzma_tmp" || exit 1
		trap - 0 1 2 3 15
	)
}

bbp_zip_encode_available() {
	(
		bbp_require unzip cmp >/dev/null 2>&1 || exit 1
		bbp_zip_encoder=$(bbp_external_zip) || exit 1
		bbp_zip_tmp=$(bbp_tmpdir) || exit 1
		trap 'bbp_cleanup_dir "$bbp_zip_tmp" >/dev/null 2>&1 || true' 0 1 2 3 15
		printf '%s' x >"$bbp_zip_tmp/in"
		(cd "$bbp_zip_tmp" && bbp timeout 10 "$bbp_zip_encoder" -q archive.zip in) >/dev/null 2>&1 || exit 1
		[ -s "$bbp_zip_tmp/archive.zip" ] || exit 1
		bbp unzip -p "$bbp_zip_tmp/archive.zip" in >"$bbp_zip_tmp/out" 2>/dev/null || exit 1
		bbp cmp "$bbp_zip_tmp/in" "$bbp_zip_tmp/out" >/dev/null 2>&1 || exit 1
		bbp_cleanup_dir "$bbp_zip_tmp" || exit 1
		trap - 0 1 2 3 15
	)
}

bbp_username() {
	[ "$#" -eq 0 ] || return "$BBP_E_USAGE"
	bbp_username_value=$(bbp whoami 2>/dev/null) || return 1
	[ -n "$bbp_username_value" ] || return 1
	printf '%s\n' "$bbp_username_value"
}

bbp_cpu_count() {
	[ "$#" -eq 0 ] || return "$BBP_E_USAGE"
	bbp_cpu_value=$(bbp nproc 2>/dev/null) || return 1
	case "$bbp_cpu_value" in ''|*[!0-9]*) return 1 ;; esac
	[ "$bbp_cpu_value" -gt 0 ] 2>/dev/null || return 1
	printf '%s\n' "$bbp_cpu_value"
}

# 空 DNS 域是有效结果（很多工作站只有短主机名），用退出码区分查询失败。
bbp_dns_domain() {
	[ "$#" -eq 0 ] || return "$BBP_E_USAGE"
	bbp dnsdomainname 2>/dev/null
}

bbp_pid_alive() {
	[ "$#" -eq 1 ] || return "$BBP_E_USAGE"
	case "$1" in ''|*[!0-9]*|0) return "$BBP_E_USAGE" ;; esac
	bbp kill -0 "$1" 2>/dev/null
}

# 名称搜索是可选能力：Linux /proc 通常可用，macOS/Windows 不据 applet
# 清单猜测。探针启动唯一标记的子进程，并要求 pgrep -f 找到其 PID；pidof
# 依赖宿主暴露的进程名，不能代表通用的命令行名称搜索能力。
bbp_process_search_available() {
	(
		[ "$(bbp_os_family)" = linux ] || exit 1
		bbp_require sh sleep kill pgrep >/dev/null 2>&1 || exit 1
		bbp_probe_marker=bbp-process-probe-$$
		# 直接执行外部入口，避免把 shell 函数放入后台后 $! 指向异步函数的
		# 包装进程。末尾的 ':' 防止 ash 直接 exec sleep，确保标记留在 argv。
		"$BBP_BUSYBOX" sh -c 'sleep 10; :' "$bbp_probe_marker" >/dev/null 2>&1 &
		bbp_probe_pid=$!
		trap 'bbp kill "$bbp_probe_pid" >/dev/null 2>&1 || true; wait "$bbp_probe_pid" 2>/dev/null || true' 0 1 2 3 15
		bbp_probe_attempt=0
		while [ "$bbp_probe_attempt" -lt 3 ]; do
			bbp_probe_pgrep=$(bbp pgrep -f "$bbp_probe_marker" 2>/dev/null) || bbp_probe_pgrep=
			for bbp_probe_item in $bbp_probe_pgrep; do
				[ "$bbp_probe_item" = "$bbp_probe_pid" ] && exit 0
			done
			bbp_probe_attempt=$((bbp_probe_attempt + 1))
			[ "$bbp_probe_attempt" -lt 3 ] && bbp sleep 1
		done
		exit 1
	)
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
	[ "$#" -ge 2 ] || return 2
	bbp_ui_select_prompt=$1
	shift
	bbp_ui_select_mode=$(bbp_ui_mode) || return $?
	[ "$bbp_ui_select_mode" != none ] || return 2
	bbp_ui_select_count=$#
	while :; do
		bbp_ui_select_i=1
		for bbp_ui_select_item do
			printf '%s) %s\n' "$bbp_ui_select_i" "$bbp_ui_select_item" >&2
			bbp_ui_select_i=$((bbp_ui_select_i + 1))
		done
		printf '%s [1-%s]: ' "$bbp_ui_select_prompt" "$bbp_ui_select_count" >&2
		IFS= read -r bbp_ui_select_answer || return "$BBP_E_CANCELLED"
		bbp_ui_cr=$(printf '\r')
		bbp_ui_select_answer=${bbp_ui_select_answer%"$bbp_ui_cr"}
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

# 参数为 PROMPT ID LABEL [ID LABEL ...]；显示文本可变化，stdout 只返回稳定 ID。
bbp_ui_select_id() {
	[ "$#" -ge 3 ] || return "$BBP_E_USAGE"
	bbp_ui_id_prompt=$1
	shift
	[ $(( $# % 2 )) -eq 0 ] || return "$BBP_E_USAGE"
	bbp_ui_id_mode=$(bbp_ui_mode) || return $?
	[ "$bbp_ui_id_mode" != none ] || return "$BBP_E_USAGE"
	bbp_ui_id_count=$(($# / 2))
	while :; do
		bbp_ui_id_i=1
		for bbp_ui_id_value do
			if [ $((bbp_ui_id_i % 2)) -eq 0 ]; then
				printf '%s) %s\n' "$((bbp_ui_id_i / 2))" "$bbp_ui_id_value" >&2
			fi
			bbp_ui_id_i=$((bbp_ui_id_i + 1))
		done
		printf '%s [1-%s]: ' "$bbp_ui_id_prompt" "$bbp_ui_id_count" >&2
		IFS= read -r bbp_ui_id_answer || return "$BBP_E_CANCELLED"
		bbp_ui_cr=$(printf '\r')
		bbp_ui_id_answer=${bbp_ui_id_answer%"$bbp_ui_cr"}
		case "$bbp_ui_id_answer" in
			''|*[!0-9]*) ;;
			*)
				if [ "$bbp_ui_id_answer" -ge 1 ] 2>/dev/null && [ "$bbp_ui_id_answer" -le "$bbp_ui_id_count" ] 2>/dev/null; then
					bbp_ui_id_i=1
					for bbp_ui_id_value do
						if [ "$bbp_ui_id_i" -eq $((bbp_ui_id_answer * 2 - 1)) ]; then
							[ -n "$bbp_ui_id_value" ] || return "$BBP_E_USAGE"
							printf '%s\n' "$bbp_ui_id_value"
							return 0
						fi
						bbp_ui_id_i=$((bbp_ui_id_i + 1))
					done
				fi
				;;
		esac
		printf '%s\n' '请输入菜单编号。' >&2
	done
}

bbp_ui_confirm() {
	[ "$#" -ge 1 ] && [ "$#" -le 2 ] || return "$BBP_E_USAGE"
	bbp_ui_confirm_prompt=$1
	bbp_ui_confirm_default=${2:-no}
	case "$bbp_ui_confirm_default" in yes|no) ;; *) return "$BBP_E_USAGE" ;; esac
	bbp_ui_confirm_mode=$(bbp_ui_mode) || return $?
	[ "$bbp_ui_confirm_mode" != none ] || return "$BBP_E_USAGE"
	if [ "$bbp_ui_confirm_default" = yes ]; then
		printf '%s [Y/n]: ' "$bbp_ui_confirm_prompt" >&2
	else
		printf '%s [y/N]: ' "$bbp_ui_confirm_prompt" >&2
	fi
	IFS= read -r bbp_ui_confirm_answer || return "$BBP_E_CANCELLED"
	bbp_ui_cr=$(printf '\r')
	bbp_ui_confirm_answer=${bbp_ui_confirm_answer%"$bbp_ui_cr"}
	case "$bbp_ui_confirm_answer" in
		y|Y|yes|YES) return 0 ;;
		n|N|no|NO) return 1 ;;
		'') [ "$bbp_ui_confirm_default" = yes ] ; return $? ;;
		*) return 1 ;;
	esac
}
