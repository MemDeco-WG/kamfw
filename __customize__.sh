# shellcheck shell=ash
import __termux__
# Allow tests to override KAM_DIR; default to the Android path if not set
KAM_DIR="${KAM_DIR:-/data/adb/kam}"
mkdir -p "$KAM_DIR/bin" "$KAM_DIR/lib"

setup_termux_env

export PATH="$MODDIR/.local/bin:${KAM_DIR}/bin:$PATH"
export LD_LIBRARY_PATH="$MODDIR/.local/lib:${KAM_DIR}/lib:$LD_LIBRARY_PATH"

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

# 链接（采用：content-addressable objects + provider 硬链接 + 全局硬链接）
# 设计目标：
#  - 对于内容相同的文件使用 object 池（/data/adb/kam/objects/<sha256>）实现去重
#  - providers/<kind>/<name>/<modid> 保存 provider 的硬链接（方便引用计数清理）
#  - /data/adb/kam/<kind>/<name> 为指向 object 的全局硬链接（last-wins）
KAM_DIR="${KAM_DIR:-/data/adb/kam}"
_PROV_BASE="${KAM_DIR}/providers"
_OBJ_DIR="${KAM_DIR}/objects"

# get_hash is provided by lock.sh; do not redefine here to avoid duplication.
# If a hashing tool isn't available, lock.sh's get_hash will fail and we will
# fall back to provider-only behavior in `link_files`.

link_files() {
    _lf_src="$1"
    _lf_dst="$2"

    [ -d "$_lf_src" ] || return 0
    mkdir -p "$_lf_dst"

    _kind=$(basename "$_lf_dst")  # bin 或 lib

    for _f in "$_lf_src"/*; do
        [ -e "$_f" ] || continue

        _f_name=$(basename "$_f")
        _target="$_lf_dst/$_f_name"
        _prov_dir="${_PROV_BASE}/${_kind}/${_f_name}"
        mkdir -p "$_prov_dir"

        _modid="${KAM_MODULE_ID:-$(basename "$MODDIR")}"

        # 尝试使用内容哈希建立 object（优先去重）
        if _hash=$(get_hash "$_f") 2>/dev/null; then
            mkdir -p "$_OBJ_DIR"
            _obj_path="${_OBJ_DIR}/${_hash}"

            # 首次见到该 hash 时把 data 放到 object 池（优先 ln 零拷贝，失败时 cp）
            if [ ! -e "$_obj_path" ]; then
                if ! ln "$_f" "$_obj_path" 2>/dev/null; then
                    cp -a "$_f" "$_obj_path"
                fi
            fi

            # 在 providers 下为该模块创建一个硬链接（指向 object）
            if [ ! -e "${_prov_dir}/${_modid}" ]; then
                if ! ln "$_obj_path" "${_prov_dir}/${_modid}" 2>/dev/null; then
                    cp -a "$_obj_path" "${_prov_dir}/${_modid}"
                fi
            else
                # 已存在，则更新 mtime 以标记最近安装/更新
                touch "${_prov_dir}/${_modid}" 2>/dev/null || true
            fi

            # 将全局可见文件设置为 object 的硬链接（last-wins）
            rm -f "$_target"
            if ! ln "$_obj_path" "$_target" 2>/dev/null; then
                cp -a "$_obj_path" "$_target"
            fi

            chmod 0700 "$_obj_path" 2>/dev/null || true
            chmod 0700 "${_prov_dir}/${_modid}" 2>/dev/null || true
            chmod 0700 "$_target" 2>/dev/null || true
        else
            # Hash unavailable -> fallback to provider-only install (no dedupe)
            if [ ! -e "${_prov_dir}/${_modid}" ]; then
                if ! ln "$_f" "${_prov_dir}/${_modid}" 2>/dev/null; then
                    cp -a "$_f" "${_prov_dir}/${_modid}"
                fi
            else
                touch "${_prov_dir}/${_modid}" 2>/dev/null || true
            fi

            # Make global target point to the provider entry (prefer hardlink, fall back to symlink or copy)
            rm -f "$_target"
            if ! ln "${_prov_dir}/${_modid}" "$_target" 2>/dev/null; then
                if ! ln -s "${_prov_dir}/${_modid}" "$_target" 2>/dev/null; then
                    cp -a "${_prov_dir}/${_modid}" "$_target"
                fi
            fi

            chmod 0700 "${_prov_dir}/${_modid}" 2>/dev/null || true
            chmod 0700 "$_target" 2>/dev/null || true
        fi
    done
}


# Source kam.lock helpers if available
_KAMFW_DIR="${KAMFW_DIR:-$MODDIR/lib/kamfw}"
if [ -f "${_KAMFW_DIR}/lock.sh" ]; then
    . "${_KAMFW_DIR}/lock.sh"
fi

# Acquire the lock, perform linking, rebuild state, release the lock
# Use configurable KAM_DIR for destination paths
if command -v kam_lock_acquire >/dev/null 2>&1; then
    if kam_lock_acquire 30 "$MODDIR"; then
        link_files "$MODDIR/.local/bin" "${KAM_DIR}/bin"
        link_files "$MODDIR/.local/lib" "${KAM_DIR}/lib"
        # rebuild while holding the lock (efficient)
        if command -v kam_lock_rebuild_locked >/dev/null 2>&1; then
            kam_lock_rebuild_locked || true
        else
            kam_lock_rebuild || true
        fi
        kam_lock_release || true
    else
        # fallback: try to do operations without lock and rebuild at end
        link_files "$MODDIR/.local/bin" "${KAM_DIR}/bin"
        link_files "$MODDIR/.local/lib" "${KAM_DIR}/lib"
        kam_lock_rebuild || true
    fi
else
    # no kam lock helper (unlikely) - behave as before
    link_files "$MODDIR/.local/bin" "${KAM_DIR}/bin"
    link_files "$MODDIR/.local/lib" "${KAM_DIR}/lib"
fi
