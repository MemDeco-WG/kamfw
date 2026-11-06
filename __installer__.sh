# shellcheck shell=ash
import __at_exit__
import __install_core__

set_i18n INSTALL_NO_FILES zh '没有需要安装的文件' en 'No files to install'
set_i18n INSTALL_WILL_ON_EXIT zh '将在退出时自动安装 $_1 个文件' en 'Will install $_1 files on exit'
set_i18n INSTALL_RUNNING_NOW zh '正在立即安装 $_1 个文件' en 'Installing $_1 files now'
set_i18n INSTALL_DONE zh '自动安装完成' en 'Install completed'

__install_exclude_patterns=''
__install_include_patterns=''

__inst__invoke_install() (
    if [ -d "${1:-}" ]; then KAM_MODULE_ROOT=$1
    elif [ -f "${1:-}" ]; then ZIPFILE=$1; unset KAM_MODULE_ROOT; fi
    __installer_install_from_filters "${2:-}"
)

__inst__register_hook() {
    at_exit_register_trap
    if [ -n "${1:-}" ]; then
        at_exit_add "__inst__invoke_install $(__inst__quote "$1")"
    else
        at_exit_add '__installer_install_from_filters'
    fi
}

__inst__show_patterns() {
    print "$2"
    eval "_ip_values=\${$1:-}"
    [ -n "$_ip_values" ] || { print '  <none>'; return 0; }
    while IFS= read -r _ip_value; do print "  $_ip_value"; done <<PATTERNS
$_ip_values
PATTERNS
}

install_reset_filters() { unset __install_exclude_patterns __install_include_patterns; }
install_show_filters() {
    __inst__show_patterns __install_exclude_patterns 'Exclude patterns:'
    __inst__show_patterns __install_include_patterns 'Include patterns:'
}
install_exclude() {
    for _ip_pattern in "$@"; do
        _ip_pattern=${_ip_pattern#./}
        __inst__add_unique __install_exclude_patterns "${_ip_pattern#/}"
    done
}
install_include() {
    for _ip_pattern in "$@"; do
        _ip_pattern=${_ip_pattern#./}
        __inst__add_unique __install_include_patterns "${_ip_pattern#/}"
    done
}

install_check() (
    source=${1:-}
    if [ -z "$source" ]; then
        if [ -d "${KAM_MODULE_ROOT:-}" ]; then source=$KAM_MODULE_ROOT
        elif [ -f "${ZIPFILE:-}" ]; then source=$ZIPFILE
        else source=.; fi
    fi
    if [ -f "$source" ]; then files=$(__list_files_from_zip "$source") || return 1
    elif [ -d "$source" ]; then files=$(__list_files_from_dir "$source") || return 1
    else files=$(__list_files_from_dir .) || return 1; fi
    selected=''
    for mode in exclude include; do
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            if [ "$mode" = exclude ]; then
                __inst__matches_any "$file" __install_exclude_patterns && continue
            else
                __inst__matches_any "$file" __install_include_patterns || continue
            fi
            __inst__add_unique selected "$file"
        done <<FILES
$files
FILES
    done
    [ -z "$selected" ] || print "$selected"
)

import __installer_cmd__
