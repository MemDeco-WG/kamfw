# shellcheck shell=ash
import app

setup_termux_env() {
    if [ -f "/data/data/com.termux/files/usr/etc/termux/termux.env" ]; then
        _t_PATH=$PATH
        . /data/data/com.termux/files/usr/etc/termux/termux.env
        export PATH=$_t_PATH:/data/data/com.termux/files/usr/bin
    fi
}
