# shellcheck shell=ash

# 清理.local
if [ -d "$MODDIR/.local/" ]; then
  rm -rf "$MODDIR/.local/"
fi

# 定义需要清理的基准目录（可由环境变量 KAM_DIR 覆盖）
_KAM_DIR="${KAM_DIR:-/data/adb/kam}"

# 尝试使用 kam.lock 来保证并发一致性：
# - source helpers（如果存在）
# - 尝试获取锁；若成功则在持锁下执行清理并在结束时运行 kam_lock_rebuild_locked；
#   若获取失败则退回到无锁模式并在最后尝试运行 kam_lock_rebuild
_KAMFW_DIR="${KAMFW_DIR:-$MODDIR/lib/kamfw}"
if [ -f "${_KAMFW_DIR}/lock.sh" ]; then
    . "${_KAMFW_DIR}/lock.sh"
fi

# 记录是否在持锁模式下执行
_run_under_lock=0
if command -v kam_lock_acquire >/dev/null 2>&1 && kam_lock_acquire 30 "$MODDIR"; then
    _run_under_lock=1
fi

# providers 基准目录与模块 id
_PROV_BASE="$_KAM_DIR/providers"
_modid="${KAM_MODULE_ID:-$(basename \"$MODDIR\")}"

for _dir_name in bin lib; do
    _target_path="$_KAM_DIR/$_dir_name"
    _prov_kind_dir="${_PROV_BASE}/${_dir_name}"

    # 如果目标目录不存在则跳过
    [ -d "$_target_path" ] || continue

    # 若尚无 providers 结构，退回到原来的简单 nlink 清理以兼容旧数据
    if [ ! -d "$_prov_kind_dir" ]; then
        for _f in "$_target_path"/*; do
            [ -e "$_f" ] || continue
            _nlink=$(ls -ld "$_f" | awk '{print $2}')
            if [ "$_nlink" -eq 1 ]; then
                rm -f "$_f"
            fi
        done
    else
        # provider-aware 清理：遍历每个 providers/<kind>/<name>/ 目录
        for _pdir in "$_prov_kind_dir"/*; do
            [ -d "$_pdir" ] || continue
            _name=$(basename "$_pdir")
            _target_file="$_target_path/$_name"
            _prov_entry="${_pdir}/${_modid}"

            # 移除当前模块在 providers 中的条目（若存在）
            if [ -e "$_prov_entry" ]; then
                rm -f "$_prov_entry"
            fi

            # 如果还有其它 provider，则选一个（按最近时间优先）并把全局目标指向它
            if [ -n "$(ls -A "$_pdir" 2>/dev/null)" ]; then
                _winner_rel=$(ls -1t "$_pdir" 2>/dev/null | head -n 1)
                _winner_path="${_pdir}/${_winner_rel}"
                if [ -e "$_winner_path" ]; then
                    rm -f "$_target_file"
                    # Prefer a hardlink to the winner provider (keeps nlink accurate).
                    # If hardlinking fails (e.g., cross-FS), fall back to symlink, then copy.
                    if ! ln "$_winner_path" "$_target_file" 2>/dev/null; then
                        if ! ln -s "$_winner_path" "$_target_file" 2>/dev/null; then
                            cp -a "$_winner_path" "$_target_file"
                        fi
                    fi
                else
                    # 若 winner 不存在（异常），删除它并让下一轮处理胜出者
                    rm -f "$_winner_path" 2>/dev/null || true
                fi
            else
                # 没有剩余 provider，移除全局符号链接和空 provider 目录
                rm -f "$_target_file"
                rmdir "$_pdir" 2>/dev/null || true
            fi
        done
    fi

    # 如果子目录执行完清理后空了，删掉该子目录
    [ -z "$(ls -A "$_target_path" 2>/dev/null)" ] && rm -rf "$_target_path"
done

# 如果我们在持锁模式下执行，则在锁内进行一次 rebuild 并释放锁；
# 否则尝试进行全局重建（会自行 acquire/release），忽略失败以避免阻塞卸载流程
if [ "${_run_under_lock:-0}" -eq 1 ]; then
    if command -v kam_lock_rebuild_locked >/dev/null 2>&1; then
        kam_lock_rebuild_locked || true
    else
        kam_lock_rebuild || true
    fi
    kam_lock_release || true
else
    kam_lock_rebuild || true
fi

# 最后检查：如果整个 kam 目录都空了（或者只剩下空目录），彻底移除
# 使用 -d 检查确保目录存在，ls -A 检查是否有任何残留（包括隐藏文件）
if [ -d "$_KAM_DIR" ]; then
    _remains=$(ls -A "$_KAM_DIR" 2>/dev/null)
    if [ -z "$_remains" ]; then
        rm -rf "$_KAM_DIR"
    fi
fi
