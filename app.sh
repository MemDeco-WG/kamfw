# shellcheck shell=ash

_pm_path_safe() {
    pm path "$1" 2>/dev/null | sed -n '1{s/^package://;s/base.apk$//;p;}'
}

is_app_installed() {
    [ -n "${1:-}" ] && [ -d "$(_pm_path_safe "$1")" ]
}

require_app() {
    is_app_installed "${1:-}" && return 0
    error '!'
    error "! ${2:-}"
    error '!'
    return 1
}
