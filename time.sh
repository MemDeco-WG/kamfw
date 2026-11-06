# shellcheck shell=ash

_kam_get_now() (
    now=$(date +%s%N 2>/dev/null)
    case "$now" in *N*) date +%s ;; *) printf '%s\n' "$((now / 1000000))" ;; esac
)

_kam_timer_key() {
    case "${1:-}" in ''|*[!A-Za-z0-9_]*) return 1 ;; esac
}

timer_start() {
    _kam_timer_key "${1:-}" || return 1
    export "KAM_T_$1=$(_kam_get_now)"
}

timer_get_interval() (
    _kam_timer_key "${1:-}" || return 1
    eval "start=\${KAM_T_$1:-}"
    [ -n "$start" ] || { printf '0\n'; return 1; }
    printf '%s\n' "$(($(_kam_get_now) - start))"
)

timer_stop() {
    _kam_timer_key "${1:-}" || return 1
    timer_get_interval "$1"
    unset "KAM_T_$1"
}

get_time_iso() { date '+%Y-%m-%dT%H:%M:%S'; }
get_time_log() { date '+[%Y-%m-%d %H:%M:%S]'; }
get_time_fixed() { date '+%Y%m%d_%H%M%S'; }
get_time_short() { date '+%b %d, %H:%M'; }
get_time_http() { date -u '+%a, %d %b %Y %H:%M:%S GMT'; }

format_duration() {
    printf '%02d:%02d:%02d\n' "$((${1:-0} / 3600))" "$((${1:-0} % 3600 / 60))" "$((${1:-0} % 60))"
}

timestamp_to_readable() {
    date -d "@$1" "+${2:-%Y-%m-%d %H:%M:%S}" 2>/dev/null || date -r "$1" "+${2:-%Y-%m-%d %H:%M:%S}"
}

get_greeting() (
    hour=$(date +%H)
    hour=${hour#0}
    if [ "$hour" -ge 5 ] && [ "$hour" -lt 12 ]; then printf 'Good Morning\n'
    elif [ "$hour" -ge 12 ] && [ "$hour" -lt 18 ]; then printf 'Good Afternoon\n'
    else printf 'Good Evening\n'; fi
)
