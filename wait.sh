# shellcheck shell=ash

wait_boot() (
    count=0
    while [ "$count" -lt 120 ] && [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ]; do
        sleep 1
        count=$((count + 1))
    done
    [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ] ||
        log 'WARN: Boot completion timeout after 120s, proceeding anyway'
    [ -z "${1:-}" ] || sleep "$1"
)

wait_boot_if_magisk() { if is_magisk; then wait_boot "$@"; fi; }

wait_unlock() (
    wait_boot
    count=0
    while [ "$count" -lt 300 ] && [ ! -d /sdcard ]; do
        sleep 1
        count=$((count + 1))
    done
    [ "$count" -lt 300 ] || log 'WARN: Device unlock timeout after 300s, proceeding anyway'
    [ -z "${1:-}" ] || sleep "$1"
)

wait_net() (
    count=0
    while [ "$count" -lt "${1:-30}" ]; do
        ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1 && return 0
        count=$((count + 1))
        sleep 1
    done
    return 1
)
