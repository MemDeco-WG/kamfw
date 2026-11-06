# shellcheck shell=ash
import __installer__ || return 1
kamfw_init_paths

set_i18n SET_PERM_BINARIES zh '设置本地可执行文件权限' en 'Setting permissions for local binaries'
set_i18n SET_PERM_LIBRARIES zh '设置本地库文件权限' en 'Setting permissions for local libraries'
for _custom_directory in bin lib; do
    [ -d "$MODDIR/$_custom_directory" ] || continue
    case "$_custom_directory" in bin) info "$(i18n SET_PERM_BINARIES)" ;; lib) info "$(i18n SET_PERM_LIBRARIES)" ;; esac
    command -v set_perm_recursive >/dev/null 2>&1 &&
        set_perm_recursive "$MODDIR/$_custom_directory" 0 0 0700 0700 u:object_r:system_file:s0 || return 1
done
unset _custom_directory
