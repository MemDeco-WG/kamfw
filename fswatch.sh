# shellcheck shell=ash
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

fswatch_state_dir() (
    directory=${KAM_FSWATCH_STATE_DIR:-${KAM_HOME:-${MODDIR:-${0%/*}}}/.state/fswatch}
    mkdir -p "$directory" || return 1
    print "$directory"
)
fswatch_valid_name() { case "${1:-}" in ''|.|..|*[!A-Za-z0-9._-]*) return 1 ;; esac; }
fswatch_valid_interval() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -gt 0 ] 2>/dev/null; }
_fswatch_state_path() (
    fswatch_valid_name "${1:-}" || return 1
    directory=$(fswatch_state_dir) || return 1
    printf '%s/%s.%s\n' "$directory" "$1" "$2"
)
fswatch_pid_file() { _fswatch_state_path "${1:-}" pid; }
fswatch_snapshot_file() { _fswatch_state_path "${1:-}" snapshot; }
fswatch_loop_script_file() { _fswatch_state_path "${1:-}" loop.sh; }
fswatch_lifecycle_lock_file() { _fswatch_state_path "${1:-}" lifecycle.lock; }
fswatch_shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

fswatch_is_pid_alive() {
    case "${1:-}" in ''|0*|*[!0-9]*) return 1 ;; esac
    [ "${#1}" -le 10 ] && [ "$1" -le 2147483647 ] || return 1
    kill -0 "$1" 2>/dev/null && return 0
    [ ! -d "/proc/$1" ] || return 2
    return 1
}
fswatch_proc_cmdline_lines() {
    if command -v magicnet_proc_cmdline_lines >/dev/null 2>&1; then magicnet_proc_cmdline_lines "$1" /proc
    elif [ -x "${MODDIR:-${KAM_HOME:-}}/cli" ]; then "${MODDIR:-${KAM_HOME:-}}/cli" __proc-cmdline /proc "$1"
    else return 2; fi
}
fswatch_proc_stat_identity() {
    if command -v magicnet_proc_stat_identity >/dev/null 2>&1; then magicnet_proc_stat_identity "$1" /proc
    elif [ -x "${MODDIR:-${KAM_HOME:-}}/cli" ]; then "${MODDIR:-${KAM_HOME:-}}/cli" __proc-stat /proc "$1"
    else return 2; fi
}

fswatch_pid_matches_script() (
    fswatch_is_pid_alive "$1" || return $?
    argv=$(fswatch_proc_cmdline_lines "$1") || return $?
    newline='
'
    shell=${argv%%"$newline"*}
    case "${shell##*/}" in sh|ash|dash|bash|ksh|mksh) ;; *) return 1 ;; esac
    [ "$argv" != "$shell" ] && [ "${argv#*"$newline"}" = "$2" ]
)

fswatch_script_pids() (
    snapshot=$(ps -A -o pid=,args= 2>/dev/null) || return 2
    candidates=$(printf '%s\n' "$snapshot" | awk -v expected="$1" 'index($0, expected) { print $1 }')
    pids=''
    count=0
    for pid in $candidates; do
        count=$((count + 1))
        [ "$count" -le 256 ] || return 2
        if fswatch_pid_matches_script "$pid" "$1"; then pids="${pids}${pids:+
}$pid"
        else [ "$?" -ne 2 ] || return 2; fi
    done
    [ -n "$pids" ] || return 1
    printf '%s\n' "$pids"
)

fswatch_stop_pid_for_script() (
    if fswatch_pid_matches_script "$1" "$2"; then :
    else [ "$?" -ne 2 ] || return 2; return 0; fi
    kill "$1" 2>/dev/null || true
    sleep 1
    if fswatch_pid_matches_script "$1" "$2"; then
        kill -9 "$1" 2>/dev/null || true
        sleep 1
        if fswatch_pid_matches_script "$1" "$2"; then return 1; else [ "$?" -ne 2 ] || return 2; fi
    else [ "$?" -ne 2 ] || return 2; fi
)
fswatch_stop_script_processes() (
    pids=$(fswatch_script_pids "$1") || return $?
    for pid in $pids; do fswatch_stop_pid_for_script "$pid" "$1" || return $?; done
)

fswatch_process_start_time() (
    identity=$(fswatch_proc_stat_identity "$1") || return $?
    start=${identity#* }
    case "$start" in ''|*[!0-9]*) return 1 ;; esac
    print "$start"
)
fswatch_pid_has_start_time() (
    actual=$(fswatch_process_start_time "$1") || return $?
    [ "$actual" = "$2" ]
)
fswatch_stop_pid_identity() (
    fswatch_pid_has_start_time "$1" "$2" || return 1
    kill "$1" 2>/dev/null || true
    sleep 1
    fswatch_pid_has_start_time "$1" "$2" && kill -9 "$1" 2>/dev/null || true
)

fswatch_inherited_lock_fds() (
    [ -n "${1:-}" ] || return 0
    for descriptor in /proc/$$/fd/[0-9]*; do
        [ -e "$descriptor" ] || continue
        target=$(readlink "$descriptor") || continue
        [ "$target" != "$1" ] || print "${descriptor##*/}"
    done
)
fswatch_close_inherited_lock_fds() {
    for _fw_descriptor in $(fswatch_inherited_lock_fds "${1:-}"); do
        case "$_fw_descriptor" in ''|*[!0-9]*) continue ;; esac
        eval "exec ${_fw_descriptor}>&-"
    done
    unset _fw_descriptor
}

fswatch_run_locked() (
    [ $# -ge 2 ] || return 2
    action=$1 name=$2
    shift 2
    KAM_FSWATCH_LOCK_FILE=$(fswatch_lifecycle_lock_file "$name") || return 1
    KAM_FSWATCH_LOCK_HELD=1
    KAM_HOME=${KAM_HOME:-${MODDIR:-}}
    MODPATH=${MODPATH:-${MODDIR:-}}
    export KAM_HOME MODDIR MODPATH KAMFW_DIR KAM_FSWATCH_LOCK_HELD KAM_FSWATCH_LOCK_FILE
    export KAM_FSWATCH_STATE_DIR KAM_FSWATCH_LOG_FILE KAM_FSWATCH_PRUNE_NAMES
    runner='
KAM_MODULES=""
export KAM_MODULES
. "$KAMFW_DIR/.kamfwrc" || exit 1
import fswatch || exit 1
case "$1" in
    start) shift; fswatch_start_unlocked "$@" ;;
    stop) shift; fswatch_stop_unlocked "$@" ;;
    *) exit 2 ;;
esac'
    # Android's shell supports the descriptors inherited from BusyBox flock.
    # On hosts, Bash also handles descriptor numbers beyond dash's 0..9 limit.
    runner_shell=sh
    if [ -x /system/bin/sh ]; then runner_shell=/system/bin/sh
    elif command -v bash >/dev/null 2>&1; then runner_shell=$(command -v bash); fi
    busybox=${KAM_FSWATCH_BUSYBOX_BIN:-}
    [ -n "$busybox" ] || busybox=$(command -v busybox 2>/dev/null) || true
    if [ -n "$busybox" ] && [ -x "$busybox" ] && "$busybox" flock --help >/dev/null 2>&1; then
        "$busybox" start-stop-daemon --help >/dev/null 2>&1 || { error "$(i18n FSWATCH_TOOL_MISSING | t start-stop-daemon)"; return 1; }
        export KAM_FSWATCH_RUNNER_KIND=busybox KAM_FSWATCH_BUSYBOX_BIN="$busybox"
        "$busybox" flock "$KAM_FSWATCH_LOCK_FILE" "$runner_shell" -c "$runner" fswatch-runner "$action" "$name" "$@"
    elif command -v flock >/dev/null 2>&1 && flock -n -o /dev/null true >/dev/null 2>&1; then
        export KAM_FSWATCH_RUNNER_KIND=util-linux
        flock -o "$KAM_FSWATCH_LOCK_FILE" "$runner_shell" -c "$runner" fswatch-runner "$action" "$name" "$@"
    else error "$(i18n FSWATCH_TOOL_MISSING | t flock)"; return 1; fi
)

fswatch_require_tools() {
    for _fw_tool in find cksum sort readlink; do
        command -v "$_fw_tool" >/dev/null 2>&1 || { error "$(i18n FSWATCH_TOOL_MISSING | t "$_fw_tool")"; return 1; }
    done
}
fswatch_path_is_pruned() {
    for _fw_prune in ${KAM_FSWATCH_PRUNE_NAMES:-}; do
        case "$1" in */"$_fw_prune"|*/"$_fw_prune"/*) return 0 ;; esac
    done
    return 1
}

fswatch_snapshot() (
    [ -n "${1:-}" ] || { error "$(i18n FSWATCH_PATH_REQUIRED)"; return 2; }
    [ -e "$1" ] || { error "$(i18n FSWATCH_PATH_MISSING | t "$1")"; return 1; }
    fswatch_require_tools || return 1
    if [ -d "$1" ]; then
        set -f
        fswatch_path_is_pruned "$1" && return 0
        set -- "$1"
        for name in ${KAM_FSWATCH_PRUNE_NAMES:-}; do
            case "$name" in *'['*|*']'*|*'*'*|*'?'*|*'\'*) name=$(printf '%s' "$name" | sed 's/[][\\*?]/\\&/g') ;; esac
            set -- "$@" -path "*/$name" -prune -o
        done
        {
            find "$@" -type d -print | sed 's/^/D /'
            find "$@" -type f -exec cksum '{}' + | sed 's/^/F /'
        } | LC_ALL=C sort
    else cksum "$1" | sed 's/^/F /'; fi
)

fswatch_changed() (
    [ -n "${2:-}" ] || return 2
    directory=${TMPDIR:-}
    if [ -z "$directory" ] || [ ! -d "$directory" ] || [ ! -w "$directory" ]; then
        root=${KAM_HOME:-${MODDIR:-}}
        [ -n "$root" ] || return 1
        directory=$root/.tmp
        mkdir -p "$directory" || return 1
    fi
    temporary=$(mktemp "$directory/kamfw.fswatch.XXXXXX") || return 1
    trap 'rm -f "$temporary"' EXIT
    fswatch_snapshot "$1" >"$temporary" || return 1
    if [ -f "$2" ] && cmp -s "$temporary" "$2"; then return 1; fi
    cp "$temporary" "$2"
)

fswatch_status() (
    [ -n "${1:-}" ] || { error "$(i18n FSWATCH_NAME_REQUIRED)"; return 2; }
    owner=$(fswatch_pid_file "$1") || return 1
    script=${owner%.pid}.loop.sh
    [ -f "$owner" ] || return 1
    pid=''
    IFS= read -r pid <"$owner" || true
    if fswatch_pid_matches_script "$pid" "$script"; then print "$pid"; return 0
    else [ "$?" -ne 2 ] || return 2; fi
    rm -f "$owner"
    return 1
)

fswatch_stop_unlocked() (
    [ "${KAM_FSWATCH_LOCK_HELD:-0}" = 1 ] || return 1
    owner=$(fswatch_pid_file "$1") || return 1
    if fswatch_stop_script_processes "${owner%.pid}.loop.sh"; then result=0; else result=$?; fi
    [ "$result" -ne 2 ] || return 2
    rm -f "$owner" || return 1
    if [ "$result" = 0 ]; then success "$(i18n FSWATCH_STOPPED | t "$1")"
    else warn "$(i18n FSWATCH_NOT_RUNNING | t "$1")"; fi
    return "$result"
)
fswatch_stop() {
    [ -n "${1:-}" ] || { error "$(i18n FSWATCH_NAME_REQUIRED)"; return 2; }
    fswatch_run_locked stop "$1"
}

fswatch_start_unlocked() (
    [ "${KAM_FSWATCH_LOCK_HELD:-0}" = 1 ] || return 1
    [ -n "${1:-}" ] || { error "$(i18n FSWATCH_NAME_REQUIRED)"; return 2; }
    [ -n "${2:-}" ] || { error "$(i18n FSWATCH_PATH_REQUIRED)"; return 2; }
    name=$1 path=$2 interval=${3:-}
    [ $# -lt 3 ] || shift 3
    [ -n "$*" ] || { error "$(i18n FSWATCH_COMMAND_REQUIRED)"; return 2; }
    fswatch_valid_interval "$interval" || { error "$(i18n FSWATCH_INTERVAL_INVALID)"; return 2; }
    [ -e "$path" ] || { error "$(i18n FSWATCH_PATH_MISSING | t "$path")"; return 1; }
    fswatch_require_tools || return 1
    owner=$(fswatch_pid_file "$name") || return 1
    script=${owner%.pid}.loop.sh
    snapshot=${owner%.pid}.snapshot
    logfile=${KAM_FSWATCH_LOG_FILE:-${KAM_HOME:-$MODDIR}/.log/fswatch.log}
    fswatch_stop_script_processes "$script" >/dev/null 2>&1 || { [ "$?" -ne 2 ] || return 2; }
    rm -f "$owner" || return 1
    mkdir -p "${logfile%/*}" || return 1
    fswatch_snapshot "$path" >"$snapshot" || return 1
    {
        printf '%s\n' '#!/system/bin/sh' 'unset LD_LIBRARY_PATH'
        printf 'MODDIR=%s\nMODPATH=%s\nKAM_HOME=%s\nKAMFW_DIR=%s\n' \
            "$(fswatch_shell_quote "${MODDIR:-}")" "$(fswatch_shell_quote "${MODDIR:-}")" \
            "$(fswatch_shell_quote "${KAM_HOME:-${MODDIR:-}}")" "$(fswatch_shell_quote "${KAMFW_DIR:-}")"
        printf 'KAM_FSWATCH_NAME=%s\nKAM_FSWATCH_PATH=%s\nKAM_FSWATCH_SNAPSHOT=%s\n' \
            "$(fswatch_shell_quote "$name")" "$(fswatch_shell_quote "$path")" "$(fswatch_shell_quote "$snapshot")"
        printf 'KAM_FSWATCH_PRUNE_NAMES=%s\n_watch_interval=%s\n_watch_command=%s\n' \
            "$(fswatch_shell_quote "${KAM_FSWATCH_PRUNE_NAMES:-}")" "$(fswatch_shell_quote "$interval")" "$(fswatch_shell_quote "$*")"
        cat <<'LOOP'
KAM_MODULES=''
export MODDIR MODPATH KAM_HOME KAMFW_DIR KAM_MODULES KAM_FSWATCH_PRUNE_NAMES
export KAM_FSWATCH_NAME KAM_FSWATCH_PATH KAM_FSWATCH_SNAPSHOT
cd "$KAM_HOME" || exit 1
if [ -n "$KAMFW_DIR" ] && [ -f "$KAMFW_DIR/.kamfwrc" ]; then . "$KAMFW_DIR/.kamfwrc"; import fswatch; fi
command -v fswatch_changed >/dev/null 2>&1 || { printf '%s\n' 'fswatch_changed unavailable; exiting' >&2; exit 1; }
trap '' HUP
while [ ! -f "$KAM_HOME/disable" ] && [ ! -f "$KAM_HOME/remove" ]; do
    _watch_previous=$KAM_FSWATCH_SNAPSHOT.previous
    cp "$KAM_FSWATCH_SNAPSHOT" "$_watch_previous" || exit 1
    if fswatch_changed "$KAM_FSWATCH_PATH" "$KAM_FSWATCH_SNAPSHOT"; then
        if command -v info >/dev/null 2>&1; then info "fswatch change detected: $KAM_FSWATCH_NAME"; fi
        if ! sh -c "$_watch_command"; then
            mv -f "$_watch_previous" "$KAM_FSWATCH_SNAPSHOT" || exit 1
        fi
    fi
    rm -f "$_watch_previous"
    sleep "$_watch_interval"
done
LOOP
    } >"$script" || return 1
    chmod 700 "$script" || return 1
    launch=$owner.launch.$$
    publish=$owner.publish.$$
    trap 'rm -f "$launch" "$publish"' EXIT
    unset LD_LIBRARY_PATH
    case "${KAM_FSWATCH_RUNNER_KIND:-}" in
        busybox)
            (
                fswatch_close_inherited_lock_fds "${KAM_FSWATCH_LOCK_FILE:-}"
                "$KAM_FSWATCH_BUSYBOX_BIN" start-stop-daemon -S -b -m -p "$launch" -x /system/bin/sh -- "$script"
            ) </dev/null >>"$logfile" 2>&1 || return 1
            attempt=0
            while [ ! -s "$launch" ] && [ "$attempt" -lt 3 ]; do sleep 1; attempt=$((attempt + 1)); done
            IFS= read -r pid <"$launch" || return 1
            ;;
        util-linux) (nohup sh "$script") </dev/null >>"$logfile" 2>&1 & pid=$! ;;
        *) return 1 ;;
    esac
    start=$(fswatch_process_start_time "$pid") || start=''
    attempt=0
    while [ -n "$start" ] && fswatch_pid_has_start_time "$pid" "$start" && ! fswatch_pid_matches_script "$pid" "$script"; do
        attempt=$((attempt + 1))
        [ "$attempt" -lt "${KAM_FSWATCH_LAUNCH_ATTEMPTS:-10}" ] || break
        sleep 1
    done
    if [ -z "$start" ] || ! fswatch_pid_has_start_time "$pid" "$start" || ! fswatch_pid_matches_script "$pid" "$script"; then
        [ -z "$start" ] || fswatch_stop_pid_identity "$pid" "$start" >/dev/null 2>&1 || true
        fswatch_stop_script_processes "$script" >/dev/null 2>&1 || true
        error "fswatch: watcher failed to enter loop: $name"
        return 1
    fi
    if ! { print "$pid" >"$publish" && mv -f "$publish" "$owner"; }; then
        rm -f "$owner"
        fswatch_stop_pid_identity "$pid" "$start" >/dev/null 2>&1 || true
        fswatch_stop_script_processes "$script" >/dev/null 2>&1 || true
        error "fswatch: failed to publish watcher pid: $name"
        return 1
    fi
    success "$(i18n FSWATCH_STARTED | t "$name" "$pid")"
)

fswatch_start() { fswatch_run_locked start "$@"; }
fswatch() {
    case "${1:-}" in
        snapshot) shift; fswatch_snapshot "$@" ;;
        changed) shift; fswatch_changed "$@" ;;
        start) shift; fswatch_start "$@" ;;
        stop) shift; fswatch_stop "$@" ;;
        status) shift; fswatch_status "$@" ;;
        *)
            print 'Usage: fswatch snapshot <path>'
            print '       fswatch changed <path> <snapshot-file>'
            print '       fswatch start <name> <path> <interval_sec> <command...>'
            print '       fswatch stop <name>'
            print '       fswatch status <name>'
            return 2
            ;;
    esac
}
