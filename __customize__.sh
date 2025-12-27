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

link_files() {
    _lf_src="$1"
    _lf_dst="$2"

    [ -d "$_lf_src" ] || return 0    
    # 确保目标目录存在
    mkdir -p "$_lf_dst"

    for _f in "$_lf_src"/*; do
        # 处理空目录匹配通配符的情况
        [ -e "$_f" ] || continue
        
        _f_name=$(basename "$_f")
        _target="$_lf_dst/$_f_name"

        # 强制替换：先删再链
        # -f 确保即使文件不存在或不可写也不会报错
        rm -f "$_target"
        
        ln "$_f" "$_target"
    done
}

# --- 实际调用 ---

# 链接 bin 目录
link_files "$MODDIR/.local/bin" "/data/adb/kam/bin"

# 链接 lib 目录
link_files "$MODDIR/.local/lib" "/data/adb/kam/lib"