# shellcheck shell=ash
set_i18n LOGLEVEL_SET zh '日志级别已设置为 %s' en 'Log level set to %s' ja 'ログレベルを %s に設定しました' ko '로그 레벨이 %s(으)로 설정되었습니다'

__kam_log_level_normalize() {
    case "$1" in
        0|[Ee][Rr][Rr]|[Ee][Rr][Rr][Oo][Rr]) printf ERROR ;;
        1|[Ww][Aa][Rr][Nn]|[Ww][Aa][Rr][Nn][Ii][Nn][Gg]) printf WARN ;;
        3|[Dd][Bb][Gg]|[Dd][Ee][Bb][Uu][Gg]) printf DEBUG ;;
        *) printf INFO ;;
    esac
}

__kam_log_level_value() {
    case "$1" in
        [Ee][Rr][Rr][Oo][Rr]) printf 0 ;;
        [Ww][Aa][Rr][Nn]) printf 1 ;;
        [Dd][Ee][Bb][Uu][Gg]) printf 3 ;;
        *) printf 2 ;;
    esac
}

__kam_current_loglevel() {
    if [ "${KAM_DEBUG:-0}" = 1 ]; then printf 3; else __kam_log_level_value "${KAM_LOGLEVEL:-${LOGLEVEL:-INFO}}"; fi
}

__kam_should_emit() {
    [ "${KAM_DEBUG:-0}" != 1 ] || return 0
    case "${KAM_LOGLEVEL:-${LOGLEVEL:-INFO}}" in
        [Ee][Rr][Rr][Oo][Rr]) [ "$1" = ERROR ] ;;
        [Ww][Aa][Rr][Nn]) [ "$1" = ERROR ] || [ "$1" = WARN ] ;;
        [Dd][Ee][Bb][Uu][Gg]) return 0 ;;
        *) [ "$1" != DEBUG ] ;;
    esac
}

set_loglevel() {
    [ $# -gt 0 ] || return 0
    KAM_LOGLEVEL=$(__kam_log_level_normalize "$1")
    export KAM_LOGLEVEL
    [ ! -t 1 ] || print "$(i18n LOGLEVEL_SET | t "$KAM_LOGLEVEL")"
}

green() { print "${COL_GRN}$1${COL_RST}"; }
red() { print "${COL_RED}$1${COL_RST}"; }
yellow() { print "${COL_YLW}$1${COL_RST}"; }
cyan() { print "${COL_CYN}$1${COL_RST}"; }

info() { if __kam_should_emit INFO; then green "[info] $1"; log "INFO: $1"; fi; }
warn() { if __kam_should_emit WARN; then yellow "[warn] $1"; log "WARN: $1"; fi; }
error() { red "[error] $1"; log "ERROR: $1"; }
success() { if __kam_should_emit INFO; then green "[done] $1"; log "SUCCESS: $1"; fi; }
debug() { if __kam_should_emit DEBUG; then cyan "[DEBUG] $1"; log "[DEBUG] $1"; fi; }

log() (
    file=${KAM_LOGFILE:-${MODDIR:-${0%/*}}/.log/kam.log}
    mode=append
    size=${KAM_LOG_ROTATE_SIZE:-}
    keep=${KAM_LOG_ROTATE_KEEP:-1}
    while [ $# -gt 0 ]; do
        case "$1" in
            -w|--overwrite) mode=overwrite; shift ;;
            -f|--file) [ $# -ge 2 ] || return 2; file=$2; shift 2 ;;
            -r|--rotate|--rotate-size) [ $# -ge 2 ] || return 2; size=$2; shift 2 ;;
            -k|--rotate-keep) [ $# -ge 2 ] || return 2; keep=$2; shift 2 ;;
            *) break ;;
        esac
    done
    [ "$mode" != overwrite ] || : >"$file" || return 1
    if [ -n "$size" ] && ! command -v logrotate_file >/dev/null 2>&1; then import logrotate || return 1; fi
    _kam_log_write() {
        [ -z "$size" ] || logrotate_file --size "$size" --keep "$keep" "$file" >/dev/null 2>&1 || true
        clean=$(printf '%s' "$1" | sed 's/\x1b//g;s/\[[0-9;]*m//g')
        printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$clean" >>"$file"
    }
    if [ $# -gt 0 ]; then
        _kam_log_write "$*"
    elif [ ! -t 0 ]; then
        while IFS= read -r line || [ -n "$line" ]; do _kam_log_write "$line" || return 1; done
    fi
)
