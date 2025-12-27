# shellcheck shell=ash

mkdir -p /data/adb/kam/bin /data/adb/kam/lib

setup_termux_env

export PATH="$MODDIR/.local/bin:/data/adb/kam/bin:$PATH"
export LD_LIBRARY_PATH="$MODDIR/.local/lib:/data/adb/kam/lib:$LD_LIBRARY_PATH"

if [ -d "$MODDIR/.local/bin"  ]; then
    
fi

for _f in "$MODDIR"/.local/bin/*; do
    [ -e "$_f" ] || continue
    _f_name=$(basename "$_f")
    _target="/data/adb/kam/bin/$_f_name"

    # 强制替换：先删再链
    rm -f "$_target"
    ln "$_f" "$_target"
done
