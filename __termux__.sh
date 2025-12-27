# shellcheck shell=ash
import app

setup_termux_env() {
    _env_file="/data/data/com.termux/files/usr/etc/termux/termux.env"
    if [ -f "$_env_file" ]; then
        _bak_PATH=$PATH
        _bak_HOME=$HOME
        
        . "$_env_file"
        
        _T_HOME="${TERMUX__HOME:-/data/data/com.termux/files/home}"
        _T_BIN="/data/data/com.termux/files/usr/bin"
        
        _ext_PATH="$_bak_PATH:$_T_BIN"
        _ext_PATH="$_ext_PATH:$_T_HOME/.local/bin"
        _ext_PATH="$_ext_PATH:$_T_HOME/.cargo/bin"
        _ext_PATH="$_ext_PATH:$_T_HOME/go/bin"
        _ext_PATH="$_ext_PATH:$_T_HOME/.node_modules/bin"
        
        export PATH="$_ext_PATH"
        export HOME="$_bak_HOME"
        
        unset _bak_PATH _bak_HOME _T_HOME _T_BIN _ext_PATH _env_file
    fi
}
