# shellcheck shell=ash
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

watchdog_state_dir() (
    directory=${KAM_WATCHDOG_STATE_DIR:-${KAM_HOME:-${MODDIR:-${0%/*}}}/.state/watchdog}
    mkdir -p "$directory" || return 1
    print "$directory"
)
watchdog_pid_file() (
    case "${1:-}" in ''|.|..|*[!A-Za-z0-9._-]*) return 1 ;; esac
    directory=$(watchdog_state_dir) || return 1
    print "$directory/$1.pid"
)
watchdog_shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
watchdog_valid_interval() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -gt 0 ] 2>/dev/null; }
watchdog_is_pid_alive() {
    case "${1:-}" in ''|0*|*[!0-9]*) return 1 ;; esac
    [ "${#1}" -le 10 ] && [ "$1" -le 2147483647 ] || return 1
    kill -0 "$1" 2>/dev/null && return 0
    [ ! -d "/proc/$1" ] || return 2
    return 1
}
watchdog_proc_cmdline_lines() {
    if command -v magicnet_proc_cmdline_lines >/dev/null 2>&1; then magicnet_proc_cmdline_lines "$1" /proc
    elif [ -x "${MODDIR:-${KAM_HOME:-}}/cli" ]; then "${MODDIR:-${KAM_HOME:-}}/cli" __proc-cmdline /proc "$1"
    else return 2; fi
}
watchdog_pid_matches_script() (
    watchdog_is_pid_alive "$1" || return $?
    argv=$(watchdog_proc_cmdline_lines "$1") || return $?
    newline='
'
    shell=${argv%%"$newline"*}
    case "${shell##*/}" in sh|ash|dash|bash|ksh|mksh) ;; *) return 1 ;; esac
    [ "$argv" != "$shell" ] && [ "${argv#*"$newline"}" = "$2" ]
)
watchdog_script_pids() (
    snapshot=$(ps -A -o pid=,args= 2>/dev/null) || return 2
    candidates=$(printf '%s\n' "$snapshot" | awk -v expected="$1" 'index($0, expected) { print $1 }')
    pids=''
    count=0
    for pid in $candidates; do
        count=$((count + 1))
        [ "$count" -le 256 ] || return 2
        if watchdog_pid_matches_script "$pid" "$1"; then pids="${pids}${pids:+
}$pid"
        else [ "$?" -ne 2 ] || return 2; fi
    done
    [ -n "$pids" ] || return 1
    printf '%s\n' "$pids"
)

watchdog_status() (
    [ -n "${1:-}" ] || { error "$(i18n WATCHDOG_NAME_REQUIRED)"; return 2; }
    owner=$(watchdog_pid_file "$1") || return 1
    [ -f "$owner" ] || return 1
    pid=''
    IFS= read -r pid <"$owner" || true
    watchdog_pid_matches_script "$pid" "${owner%.pid}.loop.sh" || return $?
    print "$pid"
)

watchdog_stop() (
    [ -n "${1:-}" ] || { error "$(i18n WATCHDOG_NAME_REQUIRED)"; return 2; }
    owner=$(watchdog_pid_file "$1") || return 1
    script=${owner%.pid}.loop.sh
    if pids=$(watchdog_script_pids "$script"); then result=0; else result=$?; fi
    [ "$result" -ne 2 ] || return 2
    if [ "$result" = 0 ]; then
        for pid in $pids; do
            if watchdog_pid_matches_script "$pid" "$script"; then :
            else [ "$?" -ne 2 ] || return 2; continue; fi
            kill "$pid" 2>/dev/null || true
        done
        sleep 1
        if watchdog_script_pids "$script" >/dev/null; then return 1
        else [ "$?" -ne 2 ] || return 2; fi
        rm -f "$owner" || return 1
        success "$(i18n WATCHDOG_STOPPED | t "$1")"
    else
        rm -f "$owner" || return 1
        warn "$(i18n WATCHDOG_NOT_RUNNING | t "$1")"
        return 1
    fi
)
watchdog_once() {
    [ -n "$*" ] || { error "$(i18n WATCHDOG_COMMAND_REQUIRED)"; return 2; }
    sh -c "$*"
}

watchdog_start() (
    notify=${KAM_WATCHDOG_NOTIFY:-0}
    while [ $# -gt 0 ]; do
        case "$1" in --notify|--alert) notify=1 ;; --no-notify|--quiet) notify=0 ;; *) break ;; esac
        shift
    done
    [ -n "${1:-}" ] || { error "$(i18n WATCHDOG_NAME_REQUIRED)"; return 2; }
    name=$1 interval=${2:-}
    [ $# -lt 2 ] || shift 2
    [ -n "$*" ] || { error "$(i18n WATCHDOG_COMMAND_REQUIRED)"; return 2; }
    watchdog_valid_interval "$interval" || { error "$(i18n WATCHDOG_INTERVAL_INVALID)"; return 2; }
    if watchdog_status "$name" >/dev/null 2>&1; then watchdog_stop "$name" >/dev/null 2>&1 || return $?
    else [ "$?" -ne 2 ] || return 2; fi
    owner=$(watchdog_pid_file "$name") || return 1
    script=${owner%.pid}.loop.sh
    if watchdog_script_pids "$script" >/dev/null; then return 2
    else [ "$?" -ne 2 ] || return 2; fi
    logfile=${KAM_WATCHDOG_LOG_FILE:-${KAM_HOME:-$MODDIR}/.log/watchdog.log}
    mkdir -p "${logfile%/*}" || return 1
    {
        printf '%s\n' '#!/system/bin/sh'
        printf 'MODDIR=%s\nMODPATH=%s\nKAM_HOME=%s\nKAMFW_DIR=%s\n' \
            "$(watchdog_shell_quote "${MODDIR:-}")" "$(watchdog_shell_quote "${MODDIR:-}")" \
            "$(watchdog_shell_quote "${KAM_HOME:-${MODDIR:-}}")" "$(watchdog_shell_quote "${KAMFW_DIR:-}")"
        printf '_watch_name=%s\n_watch_interval=%s\n_watch_command=%s\n_watch_notify=%s\n' \
            "$(watchdog_shell_quote "$name")" "$(watchdog_shell_quote "$interval")" \
            "$(watchdog_shell_quote "$*")" "$(watchdog_shell_quote "$notify")"
        printf 'KAM_WATCHDOG_NOTIFY_TITLE=%s\n' "$(watchdog_shell_quote "${KAM_WATCHDOG_NOTIFY_TITLE:-kamfw watchdog}")"
        cat <<'LOOP'
KAM_MODULES=''
export MODDIR MODPATH KAM_HOME KAMFW_DIR KAM_MODULES KAM_WATCHDOG_NOTIFY_TITLE
cd "$KAM_HOME" || exit 1
if [ -n "$KAMFW_DIR" ] && [ -f "$KAMFW_DIR/.kamfwrc" ]; then . "$KAMFW_DIR/.kamfwrc"; fi
trap '' HUP
[ ! -f "$KAM_HOME/disable" ] && [ ! -f "$KAM_HOME/remove" ] || exit 0
sleep "$_watch_interval"
while [ ! -f "$KAM_HOME/disable" ] && [ ! -f "$KAM_HOME/remove" ]; do
    if ! sh -c "$_watch_command"; then
        _watch_failure="watchdog $_watch_name: command failed"
        if command -v warn >/dev/null 2>&1; then warn "$_watch_failure"
        else printf '%s\n' "$_watch_failure" >&2; fi
        if [ "$_watch_notify" = 1 ]; then
            command -v notify >/dev/null 2>&1 || import notify || true
            if command -v notify >/dev/null 2>&1; then
                notify alert "kamfw_watchdog_$_watch_name" "$KAM_WATCHDOG_NOTIFY_TITLE" "$_watch_failure" >/dev/null 2>&1 || true
            fi
        fi
    fi
    sleep "$_watch_interval"
done
LOOP
    } >"$script" || return 1
    chmod 700 "$script" || return 1
    nohup sh "$script" </dev/null >"$logfile" 2>&1 &
    pid=$!
    publish=$owner.publish.$$
    if ! { print "$pid" >"$publish" && mv -f "$publish" "$owner"; }; then
        kill "$pid" 2>/dev/null || true
        rm -f "$publish"
        return 1
    fi
    attempt=0
    result=1
    while [ "$attempt" -lt 10 ]; do
        if watchdog_pid_matches_script "$pid" "$script"; then result=0; break; else result=$?; fi
        attempt=$((attempt + 1))
        sleep 0.05
    done
    [ "$result" -ne 2 ] || return 2
    if [ "$result" != 0 ]; then
        kill "$pid" 2>/dev/null || true
        rm -f "$owner"
        return 1
    fi
    success "$(i18n WATCHDOG_STARTED | t "$name" "$pid")"
)

watchdog() {
    case "${1:-}" in
        start) shift; watchdog_start "$@" ;;
        stop) shift; watchdog_stop "$@" ;;
        status) shift; watchdog_status "$@" ;;
        once) shift; watchdog_once "$@" ;;
        *)
            print 'Usage: watchdog start [--notify|--alert] <name> <interval_sec> <command...>'
            print '       watchdog stop <name>'
            print '       watchdog status <name>'
            print '       watchdog once <command...>'
            return 2
            ;;
    esac
}
