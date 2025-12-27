# shellcheck shell=ash

mkdir -p /data/adb/kam/bin /data/adb/kam/lib

export PATH="/data/adb/kam/bin:$MODDIR/.local/bin:$PATH":/data/data/com.termux/files/usr/bin

export LD_LIBRARY_PATH="/data/adb/kam/lib:$MODDIR/.local/lib:$LD_LIBRARY_PATH":/data/data/com.termux/files/usr/lib

