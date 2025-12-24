# shellcheck shell=ash
# 等待系统开机完成
# 用法: wait_boot [延迟秒数]
wait_boot() {
    # resetprop -w 是最优雅的方案，它会阻塞直到属性变为 1
    if command -v resetprop >/dev/null 2>&1; then
        resetprop -w sys.boot_completed 1 >/dev/null 2>&1
    fi

    # 如果属性不可用或resetprop不存在，回退到循环检测
    while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
        sleep 1
    done

    # 可选的额外缓冲时间
    [ -n "$1" ] && sleep "$1"
}

wait_boot_if_magisk() {
    if is_magisk; then
        wait_boot
    fi
}

# 等待用户解锁 / SDCard 挂载
# 用法: wait_unlock [延迟秒数]
wait_unlock() {
    # 必须先确保开机完成
    wait_boot
    
    # 循环检测 /sdcard 目录是否真正可用（Android 解锁后才会挂载）
    # 使用多种方法检测以确保可靠性
    while true; do
        # 方法1: 检查常见的Android目录
        if [ -d "/sdcard/Android" ] || [ -d "/sdcard/DCIM" ] || [ -d "/sdcard/Download" ]; then
            break
        fi
        
        # 方法2: 检查/storage/emulated/0是否可访问
        if [ -d "/storage/emulated/0" ] && [ -r "/storage/emulated/0" ]; then
            break
        fi
        
        # 方法3: 尝试创建临时文件来测试可写性
        if touch "/sdcard/.kamfw_test" 2>/dev/null; then
            rm -f "/sdcard/.kamfw_test" 2>/dev/null
            break
        fi
        
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
        # 方法1: 使用ping检测（如果可用）
        if command -v ping >/dev/null 2>&1; then
            if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1 || \
               ping -c 1 -W 1 223.5.5.5 >/dev/null 2>&1; then
                unset _wn_timeout _wn_count
                return 0
            fi
        else
            # 方法2: 使用网络接口状态检测（ping不可用时）
            # 检查是否有网络接口处于up状态且有IP地址
            if [ -f /proc/net/route ] && grep -q "^.*\t00000000" /proc/net/route 2>/dev/null; then
                # 检查默认网关是否存在
                if [ -n "$(ip route show default 2>/dev/null | head -n1)" ]; then
                    unset _wn_timeout _wn_count
                    return 0
                fi
            fi
            
            # 方法3: 尝试连接到常见端口
            if command -v nc >/dev/null 2>&1; then
                if nc -z -w1 8.8.8.8 53 >/dev/null 2>&1 || \
                   nc -z -w1 223.5.5.5 53 >/dev/null 2>&1; then
                    unset _wn_timeout _wn_count
                    return 0
                fi
            fi
        fi
        
        _wn_count=$((_wn_count + 1))
        sleep 1
    done

    unset _wn_timeout _wn_count
    return 1 # 超时
}
