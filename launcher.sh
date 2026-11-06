# shellcheck shell=ash

_launch_run() (
    busybox=${KAM_LAUNCH_BUSYBOX:-}
    if [ -n "$busybox" ] && [ -x /system/bin/getprop ]; then
        case "$busybox" in
            /data/adb/ap/bin/busybox|/data/adb/ksu/bin/busybox|/data/adb/magisk/busybox|\
            "${MODDIR:-}/bin/busybox"|"${MODDIR:-}/system/bin/busybox") ;;
            *) busybox='' ;;
        esac
    fi
    if [ -n "$busybox" ] && [ -x "$busybox" ]; then "$busybox" timeout 5 "$@"
    elif command -v timeout >/dev/null 2>&1; then timeout 5 "$@"
    else "$@"; fi
)

_launch_url() (
    [ -n "${1:-}" ] || return 2
    command -v am >/dev/null 2>&1 || return 127
    _launch_run am start --user current -a android.intent.action.VIEW -d "$1" >/dev/null 2>&1
)

# ActivityManager may report an error in output while returning status zero.
_launch_browser_start() (
    output=$(_launch_run "$@" 2>&1) || return $?
    case "$output" in
        *Error*|*Exception*|*'Permission Denial'*|*'Background activity'*|*'background activity'*) return 1 ;;
    esac
)

_launch_browser() (
    case "${1:-}" in http://?*|https://?*) ;; *) return 2 ;; esac
    command -v am >/dev/null 2>&1 || return 127
    url=$1
    package=''
    # Role queries require a numeric user on older Android releases.
    user=$(_launch_run am get-current-user 2>/dev/null) || user=''
    case "$user" in ''|*[!0-9]*) user='' ;; esac
    if [ -n "$user" ] && command -v cmd >/dev/null 2>&1; then
        package=$(_launch_run cmd role get-role-holders --user "$user" android.app.role.BROWSER 2>/dev/null) || package=''
    fi
    case "$package" in ''|*[!A-Za-z0-9_.]*) package='' ;; esac
    set -- --user current -a android.intent.action.VIEW -f 0x10000000 -c android.intent.category.BROWSABLE
    if [ -n "$package" ]; then
        _launch_browser_start am start "$@" -p "$package" -d "$url" >/dev/null 2>&1 && return 0
    fi
    _launch_browser_start am start "$@" -d "$url" && return 0
    _launch_browser_start cmd activity start-activity "$@" -d "$url"
)

_launch_app() (
    [ -n "${1:-}" ] || return 2
    case "$1" in
        */*) set -- am start --user current -n "$1" ;;
        *) set -- monkey -p "$1" -c android.intent.category.LAUNCHER 1 ;;
    esac
    command -v "$1" >/dev/null 2>&1 || return 127
    _launch_run "$@" >/dev/null 2>&1
)

launch() {
    case "${1:-}" in
        url|link) _launch_url "${2:-}" ;;
        browser) _launch_browser "${2:-}" ;;
        app|pkg) _launch_app "${2:-}" ;;
        *) _launch_url "${1:-}" ;;
    esac
}
