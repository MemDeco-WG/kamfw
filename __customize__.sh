# shellcheck shell=ash
import __termux__

setup_termux_env

export PATH="$MODDIR/.local/bin:$PATH"
export LD_LIBRARY_PATH="$MODDIR/.local/lib:$LD_LIBRARY_PATH"

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
