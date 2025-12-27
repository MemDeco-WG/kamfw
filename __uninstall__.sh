# shellcheck shell=ash

# 清理.local
if [ -d "$MODDIR/.local/" ]; then
  rm -rf "$MODDIR/.local/"
fi

# 定义需要清理的基准目录
_KAM_DIR="/data/adb/kam"

# 遍历需要检查硬链接的子目录
for _dir_name in bin lib; do
    _target_path="$_KAM_DIR/$_dir_name"
    
    # 如果目录不存在则跳过
    [ -d "$_target_path" ] || continue
    
    # 遍历目录下的文件
    for _f in "$_target_path"/*; do
        # 处理空目录情况或不存在的文件
        [ -e "$_f" ] || continue
        
        # 获取硬链接数 (nlink)
        # ls -ld 输出的第二列即为硬链接数
        _nlink=$(ls -ld "$_f" | awk '{print $2}')
        
        # 如果链接数为 1，说明磁盘上只剩下当前的这个硬链接
        # 意味着原模块目录（modules/xxx）下的源文件已被删除
        if [ "$_nlink" -eq 1 ]; then
            rm -f "$_f"
        fi
    done
    
    # 如果子目录执行完清理后空了，删掉该子目录
    [ -z "$(ls -A "$_target_path" 2>/dev/null)" ] && rm -rf "$_target_path"
done

# 最后检查：如果整个 kam 目录都空了（或者只剩下空目录），彻底移除
# 使用 -d 检查确保目录存在，ls -A 检查是否有任何残留（包括隐藏文件）
if [ -d "$_KAM_DIR" ]; then
    _remains=$(ls -A "$_KAM_DIR" 2>/dev/null)
    if [ -z "$_remains" ]; then
        rm -rf "$_KAM_DIR"
    fi
fi
