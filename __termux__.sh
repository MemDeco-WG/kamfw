# shellcheck shell=ash
import app
import env

require_termux() { require_app "com.termux" "Termux Not Installed!" }

set_termux_home() {
    export HOME="/data/data/com.termux/files/home"
}

active_termux_env() {
    # 1. 备份所有可能被 Termux 修改的关键变量
    _bak_PATH="$PATH"
    _bak_HOME="$HOME"
    _bak_PRELOAD="$LD_PRELOAD"
    _bak_PREFIX="$PREFIX"

    _env_file="/data/data/com.termux/files/usr/etc/termux/termux.env"
    if [ -f "$_env_file" ]; then
        # 加载 Termux 官方环境
        . "$_env_file"

        _T_HOME="/data/data/com.termux/files/home"
        _T_BIN="/data/data/com.termux/files/usr/bin"

        # 2. 智能拼接 PATH
        # 优先级：Termux Bin > 常用语言包 Bin > Android 原生 Bin
        _new_PATH="$_T_BIN"
        for _extra in ".local/bin" ".cargo/bin" "go/bin" ".node_modules/bin"; do
            [ -d "$_T_HOME/$_extra" ] && _new_PATH="$_new_PATH:$_T_HOME/$_extra"
        done

        # 保持 Android 原生命令可用，并导出
        export PATH="$_new_PATH:$_bak_PATH"
        export HOME="$_bak_HOME" # 保持当前 Shell 的 HOME 不变，或根据需要切到 $_T_HOME

        # 3. 清理临时变量
        unset _env_file _T_HOME _T_BIN _new_PATH _extra
        info "[*] Termux environment activated."
    fi
    [ -n "$(type dedup_path 2>/dev/null)" ] && dedup_path
}

deactivate_termux_env() {
    # 1. 还原备份的变量
    if [ -n "$_bak_PATH" ]; then
        export PATH="$_bak_PATH"
        export HOME="$_bak_HOME"
        export LD_PRELOAD="$_bak_PRELOAD"
        export PREFIX="$_bak_PREFIX"

        # 2. 彻底清理 Termux 特有变量，防止干扰原生环境
        unset _bak_PATH _bak_HOME _bak_PRELOAD _bak_PREFIX
        unset TERMUX_VERSION TERMUX_APP_PACKAGE_MANAGER TERMUX_MAIN_PACKAGE_FORMAT

        # 3. 处理 LD_PRELOAD 特殊情况
        # 如果备份为空，必须显式 unset，否则为空字符串也会影响部分系统命令
        [ -z "$LD_PRELOAD" ] && unset LD_PRELOAD

        info "[!] Termux environment deactivated."
    else
        warn "[?] No active Termux environment found to deactivate."
    fi
}
