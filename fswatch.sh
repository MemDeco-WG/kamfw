# shellcheck shell=ash
#
# kamfw async file change monitor
#
# Polling-based and dependency-light. Importing this file must not start
# background work. Use `fswatch start ...` explicitly from a runtime phase.

set_i18n "FSWATCH_NAME_REQUIRED" \
	"zh" "fswatch: 名称不能为空" \
	"en" "fswatch: name is required" \
	"ja" "fswatch: 名前が必要です" \
	"ko" "fswatch: 이름이 필요합니다"

set_i18n "FSWATCH_PATH_REQUIRED" \
	"zh" "fswatch: 监控路径不能为空" \
	"en" "fswatch: path is required" \
	"ja" "fswatch: パスが必要です" \
	"ko" "fswatch: 경로가 필요합니다"

set_i18n "FSWATCH_PATH_MISSING" \
	"zh" "fswatch: 路径不存在: \$_1" \
	"en" "fswatch: path does not exist: \$_1" \
	"ja" "fswatch: パスが存在しません: \$_1" \
	"ko" "fswatch: 경로가 없습니다: \$_1"

set_i18n "FSWATCH_COMMAND_REQUIRED" \
	"zh" "fswatch: 命令不能为空" \
	"en" "fswatch: command is required" \
	"ja" "fswatch: コマンドが必要です" \
	"ko" "fswatch: 명령이 필요합니다"

set_i18n "FSWATCH_INTERVAL_INVALID" \
	"zh" "fswatch: 间隔必须是正整数秒" \
	"en" "fswatch: interval must be a positive number of seconds" \
	"ja" "fswatch: 間隔は正の秒数である必要があります" \
	"ko" "fswatch: 간격은 양의 초 단위여야 합니다"

set_i18n "FSWATCH_TOOL_MISSING" \
	"zh" "fswatch: 缺少必需工具: \$_1" \
	"en" "fswatch: required command not found: \$_1" \
	"ja" "fswatch: 必要なコマンドがありません: \$_1" \
	"ko" "fswatch: 필수 명령이 없습니다: \$_1"

set_i18n "FSWATCH_STARTED" \
	"zh" "fswatch 已启动: \$_1 (pid=\$_2)" \
	"en" "fswatch started: \$_1 (pid=\$_2)" \
	"ja" "fswatch を開始しました: \$_1 (pid=\$_2)" \
	"ko" "fswatch 시작됨: \$_1 (pid=\$_2)"

set_i18n "FSWATCH_STOPPED" \
	"zh" "fswatch 已停止: \$_1" \
	"en" "fswatch stopped: \$_1" \
	"ja" "fswatch を停止しました: \$_1" \
	"ko" "fswatch 중지됨: \$_1"

set_i18n "FSWATCH_NOT_RUNNING" \
	"zh" "fswatch 未运行: \$_1" \
	"en" "fswatch is not running: \$_1" \
	"ja" "fswatch は実行されていません: \$_1" \
	"ko" "fswatch 실행 중 아님: \$_1"

set_i18n "FSWATCH_CHANGED" \
	"zh" "fswatch 检测到变化: \$_1" \
	"en" "fswatch change detected: \$_1" \
	"ja" "fswatch が変更を検出しました: \$_1" \
	"ko" "fswatch 변경 감지됨: \$_1"

fswatch_state_dir() {
	: "${KAM_HOME:=${MODDIR:-${0%/*}}}"
	_fw_dir="${KAM_FSWATCH_STATE_DIR:-$KAM_HOME/.state/fswatch}"
	mkdir -p "$_fw_dir" 2>/dev/null || return 1
	print "$_fw_dir"
	unset _fw_dir
}

fswatch_pid_file() {
	_fw_name="$1"
	[ -z "$_fw_name" ] && return 1
	_fw_dir="$(fswatch_state_dir)" || return 1
	print "$_fw_dir/$_fw_name.pid"
	unset _fw_name _fw_dir
}

fswatch_snapshot_file() {
	_fw_name="$1"
	[ -z "$_fw_name" ] && return 1
	_fw_dir="$(fswatch_state_dir)" || return 1
	print "$_fw_dir/$_fw_name.snapshot"
	unset _fw_name _fw_dir
}

fswatch_shell_quote() {
	printf "'"
	printf '%s' "$1" | sed "s/'/'\\\\''/g"
	printf "'"
}

fswatch_valid_interval() {
	case "$1" in
	"" | *[!0-9]* | 0) return 1 ;;
	*) return 0 ;;
	esac
}

fswatch_is_pid_alive() {
	_fw_pid="$1"
	[ -n "$_fw_pid" ] || return 1
	kill -0 "$_fw_pid" 2>/dev/null
}

fswatch_require_tools() {
	for _fw_tool in find cksum sort; do
		if ! command -v "$_fw_tool" >/dev/null 2>&1; then
			error "$(i18n FSWATCH_TOOL_MISSING | t "$_fw_tool")"
			unset _fw_tool
			return 1
		fi
	done
	unset _fw_tool
}

fswatch_path_is_pruned() {
	_fw_prune_path="$1"
	for _fw_prune_name in ${KAM_FSWATCH_PRUNE_NAMES:-}; do
		case "$_fw_prune_path" in
		*/"$_fw_prune_name"|*/"$_fw_prune_name"/*)
			unset _fw_prune_path _fw_prune_name
			return 0
			;;
		esac
	done
	unset _fw_prune_path _fw_prune_name
	return 1
}

fswatch_snapshot() {
	_fw_path="$1"
	[ -z "$_fw_path" ] && {
		error "$(i18n FSWATCH_PATH_REQUIRED)"
		return 2
	}
	[ -e "$_fw_path" ] || {
		error "$(i18n FSWATCH_PATH_MISSING | t "$_fw_path")"
		return 1
	}
	fswatch_require_tools || return 1

	if [ -d "$_fw_path" ]; then
		{
			find "$_fw_path" -type d -print 2>/dev/null | while IFS= read -r _fw_item || [ -n "$_fw_item" ]; do
				fswatch_path_is_pruned "$_fw_item" && continue
				printf 'D %s\n' "$_fw_item"
			done
			find "$_fw_path" -type f -print 2>/dev/null | while IFS= read -r _fw_item || [ -n "$_fw_item" ]; do
				fswatch_path_is_pruned "$_fw_item" && continue
				cksum "$_fw_item" 2>/dev/null | sed 's/^/F /'
			done
		} | sort
	else
		cksum "$_fw_path" 2>/dev/null | sed 's/^/F /'
	fi

	unset _fw_path _fw_item
}

fswatch_changed() {
	_fw_path="$1"
	_fw_snapshot="$2"
	[ -n "$_fw_snapshot" ] || return 2

	_fw_tmp_dir="${TMPDIR:-}"
	if [ -z "$_fw_tmp_dir" ] || [ ! -d "$_fw_tmp_dir" ] || [ ! -w "$_fw_tmp_dir" ]; then
		_fw_tmp_dir="${KAM_HOME:-${MODDIR:-/data/local/tmp}}/.tmp"
		mkdir -p "$_fw_tmp_dir" 2>/dev/null || _fw_tmp_dir="/data/local/tmp"
	fi
	_fw_tmp="$_fw_tmp_dir/kamfw.fswatch.$$"
	fswatch_snapshot "$_fw_path" >"$_fw_tmp" || {
		rm -f "$_fw_tmp" 2>/dev/null || true
		unset _fw_path _fw_snapshot _fw_tmp_dir _fw_tmp
		return 1
	}

	if [ ! -f "$_fw_snapshot" ] || ! cmp -s "$_fw_tmp" "$_fw_snapshot" 2>/dev/null; then
		cp "$_fw_tmp" "$_fw_snapshot" 2>/dev/null || {
			rm -f "$_fw_tmp" 2>/dev/null || true
			unset _fw_path _fw_snapshot _fw_tmp_dir _fw_tmp
			return 1
		}
		rm -f "$_fw_tmp" 2>/dev/null || true
		unset _fw_path _fw_snapshot _fw_tmp_dir _fw_tmp
		return 0
	fi

	rm -f "$_fw_tmp" 2>/dev/null || true
	unset _fw_path _fw_snapshot _fw_tmp_dir _fw_tmp
	return 1
}

fswatch_status() {
	_fw_name="$1"
	[ -z "$_fw_name" ] && {
		error "$(i18n FSWATCH_NAME_REQUIRED)"
		return 2
	}

	_fw_pid_file="$(fswatch_pid_file "$_fw_name")" || return 1
	if [ -f "$_fw_pid_file" ]; then
		_fw_pid="$(sed -n '1p' "$_fw_pid_file" 2>/dev/null)"
		if fswatch_is_pid_alive "$_fw_pid"; then
			print "$_fw_pid"
			unset _fw_name _fw_pid_file _fw_pid
			return 0
		fi
	fi

	unset _fw_name _fw_pid_file _fw_pid
	return 1
}

fswatch_stop() {
	_fw_name="$1"
	[ -z "$_fw_name" ] && {
		error "$(i18n FSWATCH_NAME_REQUIRED)"
		return 2
	}

	_fw_pid_file="$(fswatch_pid_file "$_fw_name")" || return 1
	if [ -f "$_fw_pid_file" ]; then
		_fw_pid="$(sed -n '1p' "$_fw_pid_file" 2>/dev/null)"
		if fswatch_is_pid_alive "$_fw_pid"; then
			kill "$_fw_pid" 2>/dev/null || true
			rm -f "$_fw_pid_file"
			success "$(i18n FSWATCH_STOPPED | t "$_fw_name")"
			unset _fw_name _fw_pid_file _fw_pid
			return 0
		fi
		rm -f "$_fw_pid_file"
	fi

	warn "$(i18n FSWATCH_NOT_RUNNING | t "$_fw_name")"
	unset _fw_name _fw_pid_file _fw_pid
	return 1
}

fswatch_start() {
	_fw_name="$1"
	_fw_path="$2"
	_fw_interval="$3"
	shift 3 2>/dev/null || true
	_fw_cmd="$*"

	[ -z "$_fw_name" ] && {
		error "$(i18n FSWATCH_NAME_REQUIRED)"
		return 2
	}
	[ -z "$_fw_path" ] && {
		error "$(i18n FSWATCH_PATH_REQUIRED)"
		unset _fw_name _fw_path _fw_interval _fw_cmd
		return 2
	}
	[ -z "$_fw_cmd" ] && {
		error "$(i18n FSWATCH_COMMAND_REQUIRED)"
		unset _fw_name _fw_path _fw_interval _fw_cmd
		return 2
	}
	if ! fswatch_valid_interval "$_fw_interval"; then
		error "$(i18n FSWATCH_INTERVAL_INVALID)"
		unset _fw_name _fw_path _fw_interval _fw_cmd
		return 2
	fi
	[ -e "$_fw_path" ] || {
		error "$(i18n FSWATCH_PATH_MISSING | t "$_fw_path")"
		unset _fw_name _fw_path _fw_interval _fw_cmd
		return 1
	}
	fswatch_require_tools || {
		unset _fw_name _fw_path _fw_interval _fw_cmd
		return 1
	}

	_fw_start_name="$_fw_name"
	_fw_start_path="$_fw_path"
	_fw_start_interval="$_fw_interval"
	_fw_start_cmd="$_fw_cmd"

	if _fw_existing_pid="$(fswatch_status "$_fw_start_name" 2>/dev/null)"; then
		fswatch_stop "$_fw_start_name" >/dev/null 2>&1 || true
	fi

	_fw_pid_file="$(fswatch_pid_file "$_fw_start_name")" || return 1
	_fw_snapshot_file="$(fswatch_snapshot_file "$_fw_start_name")" || return 1
	_fw_log_file="${KAM_FSWATCH_LOG_FILE:-${KAM_HOME:-$MODDIR}/.log/fswatch.log}"
	_fw_script_file="${_fw_pid_file%.pid}.loop.sh"
	mkdir -p "${_fw_log_file%/*}" 2>/dev/null || true
	_fw_loop_name="$_fw_start_name"
	_fw_loop_path="$_fw_start_path"
	_fw_loop_interval="$_fw_start_interval"
	_fw_loop_cmd="$_fw_start_cmd"
	_fw_loop_snapshot_file="$_fw_snapshot_file"
	fswatch_snapshot "$_fw_loop_path" >"$_fw_loop_snapshot_file" || return 1

	{
		printf '%s\n' '#!/system/bin/sh'
		printf '%s\n' "MODDIR=$(fswatch_shell_quote "${MODDIR:-}")"
		printf '%s\n' "MODPATH=$(fswatch_shell_quote "${MODDIR:-}")"
		printf '%s\n' "KAM_HOME=$(fswatch_shell_quote "${KAM_HOME:-${MODDIR:-}}")"
		printf '%s\n' "KAMFW_DIR=$(fswatch_shell_quote "${KAMFW_DIR:-}")"
		printf '%s\n' "KAM_MODULES=''"
		printf '%s\n' "KAM_FSWATCH_PRUNE_NAMES=$(fswatch_shell_quote "${KAM_FSWATCH_PRUNE_NAMES:-}")"
		printf '%s\n' "export MODDIR MODPATH KAM_HOME KAMFW_DIR KAM_MODULES KAM_FSWATCH_PRUNE_NAMES"
		printf '%s\n' 'cd "$KAM_HOME" || exit 1'
		printf '%s\n' 'if [ -n "$KAMFW_DIR" ] && [ -f "$KAMFW_DIR/.kamfwrc" ]; then . "$KAMFW_DIR/.kamfwrc"; import fswatch; fi'
		printf '%s\n' 'trap "" HUP'
		printf '%s\n' 'while :; do'
		printf '%s\n' "  if fswatch_changed $(fswatch_shell_quote "$_fw_loop_path") $(fswatch_shell_quote "$_fw_loop_snapshot_file"); then"
		printf '%s\n' "    if command -v info >/dev/null 2>&1; then info $(fswatch_shell_quote "fswatch change detected: $_fw_loop_name"); fi"
		printf '%s\n' "    KAM_FSWATCH_NAME=$(fswatch_shell_quote "$_fw_loop_name") KAM_FSWATCH_PATH=$(fswatch_shell_quote "$_fw_loop_path") KAM_FSWATCH_SNAPSHOT=$(fswatch_shell_quote "$_fw_loop_snapshot_file") sh -c $(fswatch_shell_quote "$_fw_loop_cmd")"
		printf '%s\n' '  fi'
		printf '%s\n' "  sleep $(fswatch_shell_quote "$_fw_loop_interval")"
		printf '%s\n' 'done'
	} >"$_fw_script_file" || return 1
	chmod 700 "$_fw_script_file" 2>/dev/null || true
	nohup sh "$_fw_script_file" </dev/null >>"$_fw_log_file" 2>&1 &
	_fw_pid=$!
	print "$_fw_pid" >"$_fw_pid_file"
	success "$(i18n FSWATCH_STARTED | t "$_fw_start_name" "$_fw_pid")"

	unset _fw_name _fw_path _fw_interval _fw_cmd _fw_start_name _fw_start_path _fw_start_interval _fw_start_cmd _fw_pid_file _fw_snapshot_file _fw_log_file _fw_script_file _fw_loop_name _fw_loop_path _fw_loop_interval _fw_loop_cmd _fw_loop_snapshot_file _fw_pid _fw_existing_pid
}

fswatch() {
	_fw_action="$1"
	shift || true
	case "$_fw_action" in
	snapshot) fswatch_snapshot "$@" ;;
	changed) fswatch_changed "$@" ;;
	start) fswatch_start "$@" ;;
	stop) fswatch_stop "$@" ;;
	status) fswatch_status "$@" ;;
	*)
		print "Usage: fswatch snapshot <path>"
		print "       fswatch changed <path> <snapshot-file>"
		print "       fswatch start <name> <path> <interval_sec> <command...>"
		print "       fswatch stop <name>"
		print "       fswatch status <name>"
		return 2
		;;
	esac
	_fw_rc=$?
	unset _fw_action
	return "$_fw_rc"
}
