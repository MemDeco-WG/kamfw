# shellcheck shell=ash

mkdir -p /data/adb/kam/bin /data/adb/kam/lib

export PATH="$MODDIR/.local/bin:/data/adb/kam/bin:$PATH":/data/data/com.termux/files/usr/bin

export LD_LIBRARY_PATH="$MODDIR/.local/lib:/data/adb/kam/lib:$LD_LIBRARY_PATH":/data/data/com.termux/files/usr/lib
