# shellcheck shell=ash

import launcher

# --- 功能函数 ---

# 参数: $1 = 包名
is_app_installed() {
    [ -z "$1" ] && return 1
    pm list packages "$1" 2>/dev/null | grep -qx "package:$1"
}

# 用法: require_app <包名> <错误提示信息> [<launch 参数...>]
# - 如果应用已安装，返回 0
# - 否则：
#   - 如果存在 `app` 函数，调用 `app "<错误提示信息>"`，若返回 0 则返回 0，否则终止并显示 <错误提示信息>
#   - 否则，如果提供了额外参数并存在 `launch`，则调用 `launch` 传入这些参数，若返回 0 则返回 0，否则终止并显示 <错误提示信息>
#   - 否则调用 `abort "<错误提示信息>"` 退出
require_app() {
    _pkg="$1"
    _msg="${2:-Missing app: $1}"

    if [ -z "$_pkg" ]; then
        abort "Missing package name"
    fi

    if is_app_installed "$_pkg"; then
        return 0
    fi

    # If a helper `app` function exists, invoke it with the error message and honor its return code.
    if command -v app >/dev/null 2>&1; then
        app "$_msg"
        if [ $? -eq 0 ]; then
            return 0
        fi
        abort "$_msg"
    fi

    # If extra args were provided and `launch` exists, delegate to it and honor its return code.
    if [ $# -gt 2 ]; then
        shift 2
        launch "$@"
        if [ $? -eq 0 ]; then
            return 0
        fi
        abort "$_msg"
    fi

    abort "$_msg"
}
