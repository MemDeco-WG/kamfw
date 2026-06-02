# shellcheck shell=ash
#
# kamfw watchdog helper
#
# Explicit API only. Importing this file must not start background work.

set_i18n "WATCHDOG_NAME_REQUIRED" \
	"zh" "watchdog: 名称不能为空" \
	"en" "watchdog: name is required" \
	"ja" "watchdog: 名前が必要です" \
	"ko" "watchdog: 이름이 필요합니다"

set_i18n "WATCHDOG_COMMAND_REQUIRED" \
	"zh" "watchdog: 命令不能为空" \
	"en" "watchdog: command is required" \
	"ja" "watchdog: コマンドが必要です" \
	"ko" "watchdog: 명령이 필요합니다"

set_i18n "WATCHDOG_INTERVAL_INVALID" \
	"zh" "watchdog: 间隔必须是正整数秒" \
	"en" "watchdog: interval must be a positive number of seconds" \
	"ja" "watchdog: 間隔は正の秒数である必要があります" \
	"ko" "watchdog: 간격은 양의 초 단위여야 합니다"

set_i18n "WATCHDOG_STARTED" \
	"zh" "watchdog 已启动: \$_1 (pid=\$_2)" \
	"en" "watchdog started: \$_1 (pid=\$_2)" \
	"ja" "watchdog を開始しました: \$_1 (pid=\$_2)" \
	"ko" "watchdog 시작됨: \$_1 (pid=\$_2)"

set_i18n "WATCHDOG_STOPPED" \
	"zh" "watchdog 已停止: \$_1" \
	"en" "watchdog stopped: \$_1" \
	"ja" "watchdog を停止しました: \$_1" \
	"ko" "watchdog 중지됨: \$_1"

set_i18n "WATCHDOG_NOT_RUNNING" \
	"zh" "watchdog 未运行: \$_1" \
	"en" "watchdog is not running: \$_1" \
	"ja" "watchdog は実行されていません: \$_1" \
	"ko" "watchdog 실행 중 아님: \$_1"

set_i18n "WATCHDOG_COMMAND_FAILED" \
	"zh" "watchdog \$_1: 命令失败" \
	"en" "watchdog \$_1: command failed" \
	"ja" "watchdog \$_1: コマンドが失敗しました" \
	"ko" "watchdog \$_1: 명령 실패"

watchdog_state_dir() {
	: "${KAM_HOME:=${MODDIR:-${0%/*}}}"
	_wd_dir="${KAM_WATCHDOG_STATE_DIR:-$KAM_HOME/.state/watchdog}"
	mkdir -p "$_wd_dir" 2>/dev/null || return 1
	print "$_wd_dir"
	unset _wd_dir
}

watchdog_pid_file() {
	_wd_name="$1"
	[ -z "$_wd_name" ] && return 1
	_wd_dir="$(watchdog_state_dir)" || return 1
	print "$_wd_dir/$_wd_name.pid"
	unset _wd_name _wd_dir
}

watchdog_valid_interval() {
	case "$1" in
	"" | *[!0-9]* | 0) return 1 ;;
	*) return 0 ;;
	esac
}

watchdog_is_pid_alive() {
	_wd_pid="$1"
	[ -n "$_wd_pid" ] || return 1
	kill -0 "$_wd_pid" 2>/dev/null
}

watchdog_status() {
	_wd_name="$1"
	[ -z "$_wd_name" ] && {
		error "$(i18n WATCHDOG_NAME_REQUIRED)"
		return 2
	}

	_wd_pid_file="$(watchdog_pid_file "$_wd_name")" || return 1
	if [ -f "$_wd_pid_file" ]; then
		_wd_pid="$(sed -n '1p' "$_wd_pid_file" 2>/dev/null)"
		if watchdog_is_pid_alive "$_wd_pid"; then
			print "$_wd_pid"
			unset _wd_name _wd_pid_file _wd_pid
			return 0
		fi
	fi

	unset _wd_name _wd_pid_file _wd_pid
	return 1
}

watchdog_stop() {
	_wd_name="$1"
	[ -z "$_wd_name" ] && {
		error "$(i18n WATCHDOG_NAME_REQUIRED)"
		return 2
	}

	_wd_pid_file="$(watchdog_pid_file "$_wd_name")" || return 1
	if [ -f "$_wd_pid_file" ]; then
		_wd_pid="$(sed -n '1p' "$_wd_pid_file" 2>/dev/null)"
		if watchdog_is_pid_alive "$_wd_pid"; then
			kill "$_wd_pid" 2>/dev/null || true
			rm -f "$_wd_pid_file"
			success "$(i18n WATCHDOG_STOPPED | t "$_wd_name")"
			unset _wd_name _wd_pid_file _wd_pid
			return 0
		fi
		rm -f "$_wd_pid_file"
	fi

	warn "$(i18n WATCHDOG_NOT_RUNNING | t "$_wd_name")"
	unset _wd_name _wd_pid_file _wd_pid
	return 1
}

watchdog_once() {
	_wd_cmd="$*"
	[ -z "$_wd_cmd" ] && {
		error "$(i18n WATCHDOG_COMMAND_REQUIRED)"
		return 2
	}
	sh -c "$_wd_cmd"
	_wd_rc=$?
	unset _wd_cmd
	return "$_wd_rc"
}

watchdog_start() {
	_wd_notify="${KAM_WATCHDOG_NOTIFY:-0}"
	while [ $# -gt 0 ]; do
		case "$1" in
		--notify | --alert)
			_wd_notify=1
			shift
			;;
		--no-notify | --quiet)
			_wd_notify=0
			shift
			;;
		*) break ;;
		esac
	done

	_wd_name="$1"
	_wd_interval="$2"
	shift 2 2>/dev/null || true
	_wd_cmd="$*"

	[ -z "$_wd_name" ] && {
		error "$(i18n WATCHDOG_NAME_REQUIRED)"
		return 2
	}
	[ -z "$_wd_cmd" ] && {
		error "$(i18n WATCHDOG_COMMAND_REQUIRED)"
		unset _wd_name _wd_interval _wd_cmd
		return 2
	}
	if ! watchdog_valid_interval "$_wd_interval"; then
		error "$(i18n WATCHDOG_INTERVAL_INVALID)"
		unset _wd_name _wd_interval _wd_cmd
		return 2
	fi

	_wd_start_name="$_wd_name"
	_wd_start_interval="$_wd_interval"
	_wd_start_cmd="$_wd_cmd"
	_wd_start_notify="$_wd_notify"

	if _wd_existing_pid="$(watchdog_status "$_wd_start_name" 2>/dev/null)"; then
		watchdog_stop "$_wd_start_name" >/dev/null 2>&1 || true
	fi

	_wd_pid_file="$(watchdog_pid_file "$_wd_start_name")" || return 1
	(
		while :; do
			if ! sh -c "$_wd_start_cmd"; then
				_wd_fail_msg="$(i18n WATCHDOG_COMMAND_FAILED | t "$_wd_start_name")"
				warn "$_wd_fail_msg"
				if [ "$_wd_start_notify" = "1" ]; then
					if ! command -v notify >/dev/null 2>&1; then
						import notify >/dev/null 2>&1 || true
					fi
					if command -v notify >/dev/null 2>&1; then
						notify alert "kamfw_watchdog_$_wd_start_name" "${KAM_WATCHDOG_NOTIFY_TITLE:-kamfw watchdog}" "$_wd_fail_msg" >/dev/null 2>&1 || true
					fi
				fi
				unset _wd_fail_msg
			fi
			sleep "$_wd_start_interval"
		done
	) &
	_wd_pid=$!
	print "$_wd_pid" >"$_wd_pid_file"
	success "$(i18n WATCHDOG_STARTED | t "$_wd_start_name" "$_wd_pid")"

	unset _wd_notify _wd_name _wd_interval _wd_cmd _wd_start_name _wd_start_interval _wd_start_cmd _wd_start_notify _wd_pid_file _wd_pid _wd_existing_pid
}

watchdog() {
	_wd_action="$1"
	shift || true
	case "$_wd_action" in
	start) watchdog_start "$@" ;;
	stop) watchdog_stop "$@" ;;
	status) watchdog_status "$@" ;;
	once) watchdog_once "$@" ;;
	*)
		print "Usage: watchdog start [--notify|--alert] <name> <interval_sec> <command...>"
		print "       watchdog stop <name>"
		print "       watchdog status <name>"
		print "       watchdog once <command...>"
		return 2
		;;
	esac
	_wd_rc=$?
	unset _wd_action
	return "$_wd_rc"
}
