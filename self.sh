# shellcheck shell=ash

config() {
    if is_ksu; then
        _kc_manager=$(command -v ksud 2>/dev/null) || _kc_manager=/data/adb/ksud
        if [ -x "$_kc_manager" ]; then
            [ -n "${KSU_MODULE:-}" ] || [ ! -f "${MODDIR:-}/module.prop" ] ||
                export KSU_MODULE=$(sed -n 's/^id=//p' "$MODDIR/module.prop")
            "$_kc_manager" module config "$@"
            return $?
        fi
    fi
    _kamfw_config "$@"
}

_kamfw_config() (
    action=${1:-help}
    [ $# -eq 0 ] || shift
    case "$action" in ''|help) printf '%s\n' 'Usage: config [get|set|list|delete|clear] [--temp] [--stdin] <key> [value]'; return ;; esac
    id=${KSU_MODULE:-${MODDIR##*/}}
    [ -n "$id" ] || { error 'Module ID unknown'; return 1; }
    base=${KAM_CONFIG_DIR:-${KAM_HOME:-${MODDIR:-${MODPATH:-/tmp}}}/.state/kamfw-config/$id}
    mkdir -p "$base/persist" "$base/tmp" || return 1
    chmod 0700 "$base" "$base/persist" "$base/tmp" || return 1
    directory=$base/persist
    stdin=0
    while [ $# -gt 0 ]; do
        case "$1" in --temp) directory=$base/tmp ;; --stdin) stdin=1 ;; *) break ;; esac
        shift
    done
    case "$action" in
        list) { ls -1 "$base/persist"; ls -1 "$base/tmp"; } | sort -u; return ;;
        clear) rm -rf "$directory" && mkdir -m 0700 -p "$directory"; return ;;
    esac
    case "${1:-}" in ''|.|..|*[!A-Za-z0-9._-]*) return 1 ;; esac
    key=$1
    shift
    case "$action" in
        get)
            if [ -f "$base/tmp/$key" ]; then cat "$base/tmp/$key"
            elif [ -f "$base/persist/$key" ]; then cat "$base/persist/$key"
            else return 1; fi
            ;;
        set)
            temp=$(mktemp "$directory/.$key.XXXXXX") || return 1
            trap 'rm -f "$temp"' EXIT
            if [ "$stdin" = 1 ]; then cat >"$temp"; else printf '%s' "$*" >"$temp"; fi &&
                mv -f "$temp" "$directory/$key"
            ;;
        delete) rm -f "$directory/$key" ;;
        *) return 1 ;;
    esac
)

disable() {
    [ -n "${MODDIR:-}" ] || return 1
    if touch "$MODDIR/disable"; then print '* 模块已禁用 (重启后生效)'
    else print '! 禁用操作失败：权限不足或目录不存在'; return 1; fi
}
enable() {
    [ -n "${MODDIR:-}" ] || return 1
    if rm -f "$MODDIR/disable"; then print '* 模块已启用 (重启后生效)'
    else print '! 启用操作失败'; return 1; fi
}
