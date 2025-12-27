# shellcheck shell=ash
get_stage() {
    # 1. 安装阶段判断 - Magisk/KSU 安装时会注入这些环境变量
    if [ -n "$SKIPUNZIP" ] || [ -n "$ZIPFILE" ]; then
        echo "install"
        return
    fi

    # 2. 卸载阶段判断 - 模块被卸载时的环境
    if [ -n "$MODPATH" ] && [ -z "$ZIPFILE" ] && [ -z "$SKIPUNZIP" ]; then
        echo "uninstall"
        return
    fi

    # 3. 默认为运行时阶段
    echo "runtime"
}

is_installing()   { [ "$(get_stage)" = "install" ] ; }
is_uninstalling()  { [ "$(get_stage)" = "uninstall" ] ; }
is_runtime()       { [ "$(get_stage)" = "runtime" ] ; }