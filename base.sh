# shellcheck shell=ash
# 判断是否在交互式终端（TTY）中运行
is_tty() {
    # [ -t 0 ] 检查标准输入是否连接到终端
    # [ -t 1 ] 检查标准输出是否连接到终端
    if [ -t 0 ] || [ -t 1 ]; then
        return 0
    else
        return 1
    fi
}

if is_tty; then
    export COL_RED='\033[0;31m'
    export COL_GRN='\033[0;32m'
    export COL_YLW='\033[0;33m'
    export COL_BLU='\033[0;34m'
    export COL_PUR='\033[0;35m'
    export COL_CYN='\033[0;36m'
    export COL_RST='\033[0m'
    export ANSI_CURSOR_UP='\033[%dA'
    export ANSI_CLEAR_LINE='\033[2K\r'
else
    export COL_RED='╳'
    export COL_GRN='▚'
    export COL_YLW='◬'
    export COL_BLU='◈'
    export COL_PUR='║'
    export COL_CYN='┆'
    export COL_RST='❖'
    export ANSI_CURSOR_UP=''
    export ANSI_CLEAR_LINE=''
fi

info () {
    printf '%b\n' "${COL_GRN}$1${COL_RST}"
    # also write to module log (colors are stripped by log())
    log "INFO: $1"
}

green () {
    printf '%b\n' "${COL_GRN}$1${COL_RST}"
}

error () {
    printf '%b\n' "${COL_RED}$1${COL_RST}"
    # also write to module log
    log "ERROR: $1"
}

red() {
    printf '%b\n' "${COL_RED}$1${COL_RST}"
}

warn () {
    printf '%b\n' "${COL_YLW}$1${COL_RST}"
    # also write to module log
    log "WARN: $1"
}

yellow() {
    printf '%b\n' "${COL_YLW}$1${COL_RST}"
}

success () {
    printf '%b\n' "${COL_GRN}$1${COL_RST}"
    # also write to module log
    log "SUCCESS: $1"
}

debug() {
    if [ "${KAM_DEBUG:-0}" = "1" ]; then
        printf '%b\n' "${COL_CYN}[DEBUG] $1${COL_RST}"
        # only log debug messages when debug is enabled
        log "[DEBUG] $1"
    fi
}

cyan() {
    printf '%b\n' "${COL_CYN}$1${COL_RST}"
}


log() {
    # Set sensible defaults using parameter default assignment:
    # - prefer existing MODDIR, otherwise use dirname of $0
    # - default KAM_LOGFILE to "$MODDIR/kam.log" (overridable)
    : "${MODDIR:=${0%/*}}"
    : "${KAM_LOGFILE:=${MODDIR}/kam.log}"
    _logfile="${KAM_LOGFILE}"
    _mode="append"
    _rotate_opt=""
    _rotate_bytes=0

    # simple opts: -w (--overwrite), -f/--file <path>, -r|--rotate <size>
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -w|--overwrite) _mode="overwrite"; shift ;;
            -f|--file) _logfile="$2"; shift 2 ;;
            -r|--rotate|--rotate-size) _rotate_opt="$2"; shift 2 ;;
            *) break ;;
        esac
    done

    # Fallback to env var if not passed via options
    if [ -z "${_rotate_opt:-}" ] && [ -n "${KAM_LOG_ROTATE_SIZE:-}" ]; then
        _rotate_opt="${KAM_LOG_ROTATE_SIZE}"
    fi

    # Parse rotate size (supports K/M/G suffixes). Non-numeric -> disabled.
    if [ -n "${_rotate_opt:-}" ]; then
        case "${_rotate_opt}" in
            *[kK]) _num="${_rotate_opt%[kK]}"; case "${_num}" in ''|*[!0-9]*) _rotate_bytes=0 ;; *) _rotate_bytes=$((_num * 1024)) ;; esac ;;
            *[mM]) _num="${_rotate_opt%[mM]}"; case "${_num}" in ''|*[!0-9]*) _rotate_bytes=0 ;; *) _rotate_bytes=$((_num * 1048576)) ;; esac ;;
            *[gG]) _num="${_rotate_opt%[gG]}"; case "${_num}" in ''|*[!0-9]*) _rotate_bytes=0 ;; *) _rotate_bytes=$((_num * 1073741824)) ;; esac ;;
            *) case "${_rotate_opt}" in ''|*[!0-9]*) _rotate_bytes=0 ;; *) _rotate_bytes=$((_rotate_opt)) ;; esac ;;
        esac
    fi

    if [ "$_mode" = "overwrite" ]; then
        : > "$_logfile" 2>/dev/null || true
    fi

    # helper: rotate if file is too big (AB rotation: keep .b as backup)
    _maybe_rotate() {
        if [ "${_rotate_bytes:-0}" -le 0 ]; then
            return 0
        fi
        if [ -f "$_logfile" ]; then
            _cur_size=$(wc -c < "$_logfile" 2>/dev/null || echo 0)
            if [ "$_cur_size" -ge "$_rotate_bytes" ]; then
                _bak="${_logfile}.b"
                rm -f "$_bak" 2>/dev/null || true
                mv "$_logfile" "$_bak" 2>/dev/null || true
                : > "$_logfile" 2>/dev/null || true
            fi
        fi
    }

    # helper to write one line (strip ANSI colors, prefix timestamp)
    _write_line() {
        _line="$1"
        _clean=$(printf '%s' "$_line" | tr -d '\033' | sed 's/\[[0-9;]*m//g')
        _maybe_rotate
        printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_clean" >> "$_logfile"
    }

    # Prefer explicit args over piped stdin. If no args and stdin has data,
    # read stdin line-by-line and write each line.
    if [ "$#" -gt 0 ]; then
        _msg="$*"
        _write_line "$_msg"
    else
        if [ -t 0 ]; then
            # stdin is a terminal -> no piped input; nothing to write
            :
        else
            while IFS= read -r _ln || [ -n "$_ln" ]; do
                _write_line "$_ln"
            done
        fi
    fi

    # cleanup helper symbols
    unset _maybe_rotate _write_line _line _clean _msg _ln _cur_size _bak _rotate_opt _rotate_bytes _num
}

wait_key() {
    _wkr_match_list="$*"
    _wkr_event=""
    _wkr_res=""

    while :; do
        _wkr_event=$(getevent -qlc 1 2>/dev/null | awk '$2~/0001|EV_KEY/ && $4~/00000001|DOWN/ {print $3; exit}')
        [ -z "$_wkr_event" ] && continue
        case "$_wkr_event" in
            KEY_VOLUMEUP|0073)   _wkr_res="up"    ;;
            KEY_VOLUMEDOWN|0072) _wkr_res="down"  ;;
            KEY_POWER|0074)      _wkr_res="power" ;;
            KEY_MUTE|0071)       _wkr_res="mute"  ;;
            KEY_F*)              _wkr_res="f${_wkr_event#KEY_F}" ;;
            *)                   _wkr_res=""      ;;
        esac

        if [ -n "$_wkr_res" ]; then
            if [ "$_wkr_match_list" = "any" ]; then
                printf '%s' "$_wkr_res"
                break
            else
                case " ${_wkr_match_list} " in
                    *" ${_wkr_res} "*)
                        printf '%s' "$_wkr_res"
                        break
                        ;;
                esac
            fi
        fi
    done
    unset _wkr_match_list _wkr_event _wkr_res
}

wait_key_up() {
    wait_key "up"
}

wait_key_down() {
    wait_key "down"
}

wait_key_up_down() {
    wait_key "up" "down"
}

wait_key_power() {
    wait_key "power"
}

wait_key_mute() {
    wait_key "mute"
}

wait_key_f() {
    wait_key "f1" "f2" "f3" "f4" "f5" "f6" "f7" "f8" "f9" "f10" "f11" "f12"
}

# 用于“按任意键继续”
wait_key_any() {
    wait_key "any"
}

# 分支不计入
get_manager() {
    if [ -n "$_GM_CACHE" ]; then
        printf '%s' "$_GM_CACHE"
        return 0
    fi

    _gm_type="unknown"
    if command -v magisk >/dev/null 2>&1; then
        _gm_type="magisk"
    elif [ -f "/data/adb/ksud" ] || command -v ksud >/dev/null 2>&1; then
        _gm_type="ksud"
    elif [ -f "/data/adb/apd" ] || command -v apd >/dev/null 2>&1; then
        _gm_type="ap"
    fi

    _GM_CACHE="$_gm_type"
    printf '%s' "$_gm_type"
    unset _gm_type
}

is_magisk() {
    _im_mgr=$(get_manager)
    [ "$_im_mgr" = "magisk" ]
}

is_ksu() {
    _ik_mgr=$(get_manager)
    [ "$_ik_mgr" = "ksud" ]
}

is_ap() {
    _ia_mgr=$(get_manager)
    [ "$_ia_mgr" = "ap" ]
}

