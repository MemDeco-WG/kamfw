# shellcheck shell=ash
# Minimal customize shim: termux env, local perms, and installer helper import
# Keep this file tiny — heavy lifting lives in src/MagicNet/lib/kamfw/__installer__.sh

import __termux__
import __at_exit__     # provides install-on-exit handler
import __installer__   # compact installer API (install/include/exclude/check/run/schedule)

setup_termux_env

export PATH="$MODDIR/.local/bin:$PATH"
export LD_LIBRARY_PATH="$MODDIR/.local/lib:$LD_LIBRARY_PATH"

# i18n for permission messages (user-visible)
set_i18n "SET_PERM_BINARIES" "zh" "设置本地可执行文件权限" "en" "Setting permissions for local binaries"
set_i18n "SET_PERM_LIBRARIES" "zh" "设置本地库文件权限" "en" "Setting permissions for local libraries"

# Apply private-mode permissions (best-effort; do not fail if helper missing)
[ -d "$MODDIR/.local/bin" ] && {
    info "$(i18n 'SET_PERM_BINARIES')"
    type set_perm_recursive >/dev/null 2>&1 && set_perm_recursive "$MODDIR/.local/bin" 0 0 0700 0700 "u:object_r:system_file:s0"
}
[ -d "$MODDIR/.local/lib" ] && {
    info "$(i18n 'SET_PERM_LIBRARIES')"
    type set_perm_recursive >/dev/null 2>&1 && set_perm_recursive "$MODDIR/.local/lib" 0 0 0700 0700 "u:object_r:system_file:s0"
}
