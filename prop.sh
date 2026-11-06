# shellcheck shell=ash
set_i18n "UNINSTALL_CMD_ADDED" \
	"zh" "已加入卸载命令：\$_1" \
	"en" "Added uninstall command: \$_1"

set_i18n "UNINSTALL_SCRIPT_CREATED" \
	"zh" "已创建卸载脚本：\$_1" \
	"en" "Created uninstall script: \$_1"

set_i18n "DELPROP_REMOVED" \
	"zh" "已删除属性：\$_1" \
	"en" "Deleted property: \$_1"

set_i18n "PERSISTPROP_ADDED" \
	"zh" "已记录属性回滚到卸载脚本：\$_1" \
	"en" "Recorded property rollback in uninstall script: \$_1"

set_i18n "PERSISTPROP_SET" \
	"zh" "已设置属性：\$_1" \
	"en" "Set property: \$_1"

set_i18n "PERSISTPROP_NO_MODPATH" \
	"zh" "未提供 MODPATH，无法记录卸载回滚" \
	"en" "MODPATH not provided; cannot record uninstall rollback"

set_i18n "RESETPROP_HEXPATCH_TOOLS_MISSING" \
	"zh" "缺少实现 hexpatch 所需工具（strings/dd），无法执行" \
	"en" "Required tools for hexpatch missing (strings/dd); cannot execute"

set_i18n "RESETPROP_HEXPATCH_FAILED" \
	"zh" "hexpatch 失败：\$_1" \
	"en" "Hexpatch failed: \$_1"

set_i18n "RESETPROP_HEXPATCH_OK" \
	"zh" "hexpatch 成功应用于属性：\$_1" \
	"en" "Hexpatch successfully applied for property: \$_1"

kamfw_uninstall_script_path() {
    [ -n "${1:-${MODPATH:-}}" ] || return 1
    printf '%s/uninstall.sh\n' "${1:-$MODPATH}"
}

kamfw_ensure_uninstall_script() (
    script=$(kamfw_uninstall_script_path "${1:-}") || {
        warn "$(i18n PERSISTPROP_NO_MODPATH)"
        return 1
    }
    if [ ! -f "$script" ]; then
        printf '%s\n' '#!/system/bin/sh' >"$script" || return 1
        chmod 755 "$script" 2>/dev/null || true
        info "$(i18n UNINSTALL_SCRIPT_CREATED | t "$script")"
    fi
)

register_uninstall_cmd() (
    [ -n "${1:-}" ] || return 0
    kamfw_ensure_uninstall_script "${2:-}" || return 1
    script=$(kamfw_uninstall_script_path "${2:-}") || return 1
    grep -Fx -- "$1" "$script" >/dev/null 2>&1 && return 0
    printf '%s\n' "$1" >>"$script" || return 1
    info "$(i18n UNINSTALL_CMD_ADDED | t "$1")"
)

_kamfw_prop_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

delprop_if_exist() (
    [ -n "${1:-}" ] || return 0
    [ -n "$(resetprop "$1" 2>/dev/null)" ] || return 0
    resetprop --delete "$1" 2>/dev/null || return 1
    info "$(i18n DELPROP_REMOVED | t "$1")"
)

persistprop() (
    [ -n "${1:-}" ] && [ $# -ge 2 ] || return 1
    module=${3:-${MODPATH:-}}
    kamfw_ensure_uninstall_script "$module" || return 1
    script=$(kamfw_uninstall_script_path "$module") || return 1
    name=$(_kamfw_prop_quote "$1")
    # Preserve the first value across repeated updates to the same property.
    if ! grep -F -- "resetprop -n -p $name " "$script" >/dev/null 2>&1 &&
       ! grep -Fx -- "resetprop -p --delete $name" "$script" >/dev/null 2>&1 &&
       ! grep -F -- "resetprop -n -p \"$1\" " "$script" >/dev/null 2>&1 &&
       ! grep -Fx -- "resetprop -p --delete \"$1\"" "$script" >/dev/null 2>&1; then
        previous=$(resetprop "$1" 2>/dev/null) || previous=''
        if [ -n "$previous" ]; then rollback="resetprop -n -p $name $(_kamfw_prop_quote "$previous")"
        else rollback="resetprop -p --delete $name"; fi
        register_uninstall_cmd "$rollback" "$module" || return 1
        info "$(i18n PERSISTPROP_ADDED | t "$1")"
    fi
    resetprop -n -p "$1" "$2" 2>/dev/null || return 1
    info "$(i18n PERSISTPROP_SET | t "$1")"
)

resetprop_if_diff() (
    [ -n "${1:-}" ] && [ $# -ge 2 ] || return 1
    current=$(resetprop "$1" 2>/dev/null) || current=''
    [ -n "$current" ] && [ "$current" = "$2" ] && return 0
    resetprop -n "$1" "$2" 2>/dev/null
)

resetprop_if_match() (
    [ -n "${1:-}" ] && [ $# -ge 3 ] || return 1
    current=$(resetprop "$1" 2>/dev/null) || current=''
    case "$current" in *"$2"*) resetprop -n "$1" "$3" 2>/dev/null ;; esac
)

# Legacy device fallback: keep the original property-area offsets and limits.
resetprop_hexpatch() (
    force=0
    case "${1:-}" in -f|--force) force=1; shift ;; esac
    [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
    for tool in strings dd; do
        command -v "$tool" >/dev/null 2>&1 || {
            abort "$(i18n RESETPROP_HEXPATCH_TOOLS_MISSING)"
            return 1
        }
    done
    property_file=/dev/__properties__
    if [ ! -f "$property_file" ]; then
        context=$(resetprop -Z "$1" 2>/dev/null) || context=''
        [ -n "$context" ] || return 2
        property_file=$property_file/$context
    fi
    [ -f "$property_file" ] || return 3
    offset=$(strings -t d "$property_file" 2>/dev/null | awk -v name="$1" 'index($0, name) { print $1; exit }')
    [ -n "$offset" ] || [ "$force" = 1 ] || return 4
    case "$offset" in ''|*[!0-9]*) return 5 ;; esac
    LC_ALL=C
    export LC_ALL
    length=${#2}
    [ "$length" -le 92 ] || return 6
    position=$((offset - 96))
    [ "$position" -ge 0 ] || return 7
    printf '\000\000' | dd of="$property_file" bs=1 count=2 seek="$position" conv=notrunc 2>/dev/null || return 8
    {
        printf '%b' "$(printf '\\%03o' "$length")"
        printf '%s' "$2"
        dd if=/dev/zero bs=1 count="$((92 - length))" 2>/dev/null
    } | dd of="$property_file" bs=1 count=93 seek="$((position + 3))" conv=notrunc 2>/dev/null || {
        warn "$(i18n RESETPROP_HEXPATCH_FAILED | t "$1")"
        return 9
    }
    info "$(i18n RESETPROP_HEXPATCH_OK | t "$1")"
)
