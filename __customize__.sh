# shellcheck shell=ash
import __termux__
mkdir -p /data/adb/kam/bin /data/adb/kam/lib

setup_termux_env

export PATH="$MODDIR/.local/bin:/data/adb/kam/bin:$PATH"
export LD_LIBRARY_PATH="$MODDIR/.local/lib:/data/adb/kam/lib:$LD_LIBRARY_PATH"

# =============================================================================
# Local Binaries and Libraries Permission Setup (Private Mode: 0700)
# =============================================================================

# 1. Setup Executables (.local/bin)
# Only root can Read, Write, and Execute.
if [ -d "$MODDIR/.local/bin" ]; then
    print "- Setting private permissions for binaries (0700)..."
    # set_perm_recursive <dir> <owner> <group> <dir_perm> <file_perm> [context]
    set_perm_recursive "$MODDIR/.local/bin" 0 0 0700 0700 "u:object_r:system_file:s0"
fi

# 2. Setup Shared Libraries (.local/lib)
# Only root can access and load these libraries.
if [ -d "$MODDIR/.local/lib" ]; then
    print "- Setting private permissions for libraries (0700)..."
    set_perm_recursive "$MODDIR/.local/lib" 0 0 0700 0700 "u:object_r:system_file:s0"
fi

for _f in "$MODDIR"/.local/bin/*; do
    [ -e "$_f" ] || continue
    _f_name=$(basename "$_f")
    _target="/data/adb/kam/bin/$_f_name"

    # 强制替换：先删再链
    rm -f "$_target"
    ln "$_f" "$_target"
done
