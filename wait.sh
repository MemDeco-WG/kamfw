# shellcheck shell=ash
# 等待系统开机完成
# 用法: wait_boot [延迟秒数]
wait_boot() {
    # resetprop -w 是最优雅的方案，它会阻塞直到属性变为 1
    resetprop -w sys.boot_completed 1 >/dev/null 2>&1

    # 如果属性不可用，回退到循环检测
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 1
    done

    # 可选的额外缓冲时间
    [ -n "$1" ] && sleep "$1"
}

wait_boot_if_magisk() {
    if is_magisk; then
        wait_boot
    fi
    exit 0
}

# 等待用户解锁 / SDCard 挂载
# 用法: wait_unlock [延迟秒数]
wait_unlock() {
    # 必须先确保开机完成
    wait_boot
    # 循环检测 /sdcard 目录是否真正可用（Android 解锁后才会挂载）
    while [ ! -d "/sdcard/Android" ]; do
        sleep 1
    done

    [ -n "$1" ] && sleep "$1"
}

# 等待网络连接可用
# 用法: wait_net [超时秒数]
wait_net() {
    _wn_timeout="${1:-30}"
    _wn_count=0

    while [ $_wn_count -lt $_wn_timeout ]; do
        if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1 || \
           ping -c 1 -W 1 223.5.5.5 >/dev/null 2>&1; then
            unset _wn_timeout _wn_count
            return 0
        fi
        _wn_count=$((_wn_count + 1))
        sleep 1
    done

    unset _wn_timeout _wn_count
    return 1 # 超时
}
