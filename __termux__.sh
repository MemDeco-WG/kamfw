# shellcheck shell=ash
import app

setup_termux_env() {
    if [ -f "/data/data/com.termux/files/usr/etc/termux/termux.env" ]; then
        _t_PATH=$PATH
        _t_HOME=$HOME
        . /data/data/com.termux/files/usr/etc/termux/termux.env
        export PATH=$_t_PATH:/data/data/com.termux/files/usr/bin
        export HOME=$_t_HOME
        unset _t_PATH _t_HOME
    fi
}
