# shellcheck shell=ash
import __termux__

setup_termux_env

export PATH="$MODDIR/.local/bin:$PATH"

export LD_LIBRARY_PATH="$MODDIR/.local/lib:$LD_LIBRARY_PATH"
