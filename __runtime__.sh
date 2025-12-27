# shellcheck shell=ash
import __termux__

mkdir -p /data/adb/kam/bin /data/adb/kam/lib

setup_termux_env

export PATH="$MODDIR/.local/bin:/data/adb/kam/bin:$PATH"

export LD_LIBRARY_PATH="$MODDIR/.local/lib:/data/adb/kam/lib:$LD_LIBRARY_PATH"
