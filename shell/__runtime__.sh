# shellcheck shell=ash
import __termux__

active_termux_env

export PATH="$MODDIR/.local/bin:$PATH"

export LD_LIBRARY_PATH="$MODDIR/.local/lib:$LD_LIBRARY_PATH"
