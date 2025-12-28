# shellcheck shell=ash
import __termux__
# Allow tests to override KAM_DIR; default to the Android path if not set
KAM_DIR="${KAM_DIR:-/data/adb/kam}"
# Sanity check: avoid accidental operations on an empty or root directory
if [ -z "$KAM_DIR" ] || [ "$KAM_DIR" = "/" ]; then
    echo "Refusing to operate on invalid KAM_DIR: '$KAM_DIR'" >&2
    exit 1
fi
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

# 链接（采用：providers 硬链接 + 全局硬链接，provider-only 简化方案）
# 设计目标：
#  - providers/<kind>/<name>/<modid> 保存 provider 的硬链接（直接指向模块文件）
#  - /data/adb/kam/<kind>/<name> 为指向 provider 的全局硬链接（last-wins）
KAM_DIR="${KAM_DIR:-/data/adb/kam}"
_PROV_BASE="${KAM_DIR}/providers"
# provider-only: no global object pool; operations will link global targets to chosen provider

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

        # Provider-only: create provider entry that points to the module file
        if [ ! -e "${_prov_dir}/${_modid}" ]; then
            if ! ln "$_f" "${_prov_dir}/${_modid}" 2>/dev/null; then
                cp -a "$_f" "${_prov_dir}/${_modid}"
            fi
        else
            # update mtime to mark recent install/update
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
    done
}

# Rebuild provider-only state: pick most-recent provider for each name and make global point to it
provider_rebuild() {
    mkdir -p "${KAM_DIR}/bin" "${KAM_DIR}/lib"
    for _kind in bin lib; do
        _prov_kind_dir="${_PROV_BASE}/${_kind}"
        [ -d "$_prov_kind_dir" ] || continue
        for _pdir in "$_prov_kind_dir"/*; do
            [ -d "$_pdir" ] || continue
            _name=$(basename "$_pdir")
            _target_file="${KAM_DIR}/${_kind}/${_name}"

            # pick winner by mtime
            _winner_rel=$(ls -1t "$_pdir" 2>/dev/null | head -n 1)
            _winner_path="${_pdir}/${_winner_rel}"

            if [ -e "$_winner_path" ]; then
                rm -f "$_target_file"
                if ! ln "$_winner_path" "$_target_file" 2>/dev/null; then
                    if ! ln -s "$_winner_path" "$_target_file" 2>/dev/null; then
                        cp -a "$_winner_path" "$_target_file"
                    fi
                fi
                chmod 0700 "$_target_file" 2>/dev/null || true
            else
                rm -f "$_target_file"
                rmdir "$_pdir" 2>/dev/null || true
            fi
        done
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
        # rebuild provider-only state (pick winners, update global links)
        provider_rebuild || true
        kam_lock_release || true
    else
        # fallback: try to do operations without lock and rebuild at end
        link_files "$MODDIR/.local/bin" "${KAM_DIR}/bin"
        link_files "$MODDIR/.local/lib" "${KAM_DIR}/lib"
        provider_rebuild || true
    fi
else
    # no kam lock helper (unlikely) - behave as before
    link_files "$MODDIR/.local/bin" "${KAM_DIR}/bin"
    link_files "$MODDIR/.local/lib" "${KAM_DIR}/lib"
    provider_rebuild || true
fi
