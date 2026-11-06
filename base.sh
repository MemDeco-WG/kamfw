# shellcheck shell=ash

is_tty() { [ -t 0 ] || [ -t 1 ]; }
if is_tty; then
    export COL_RED='\033[0;31m' COL_GRN='\033[0;32m' COL_YLW='\033[0;33m'
    export COL_BLU='\033[0;34m' COL_PUR='\033[0;35m' COL_CYN='\033[0;36m' COL_RST='\033[0m'
    export ANSI_CURSOR_UP='\033[%dA' ANSI_CLEAR_LINE='\033[2K\r'
else
    export COL_RED='╳' COL_GRN='▚' COL_YLW='◬' COL_BLU='◈' COL_PUR='║' COL_CYN='┆' COL_RST='❖'
    export ANSI_CURSOR_UP='' ANSI_CLEAR_LINE=''
fi

x() (
    [ ! -t 0 ] || return 0
    text=$(cat)
    count=${1:-1}
    while [ "$count" -gt 0 ]; do printf '%s' "$text"; count=$((count - 1)); done
)

wait_key() (
    wanted=" $* "
    while :; do
        event=$(getevent -qlc 1 2>/dev/null | awk '$2~/0001|EV_KEY/ && $4~/00000001|DOWN/ {print $3; exit}')
        case "$event" in
            KEY_VOLUMEUP|0073) key=up ;;
            KEY_VOLUMEDOWN|0072) key=down ;;
            KEY_POWER|0074) key=power ;;
            KEY_MUTE|0071) key=mute ;;
            KEY_F*) key=f${event#KEY_F} ;;
            *) continue ;;
        esac
        case "$wanted" in ' any '|*" $key "*) print "$key"; return ;; esac
    done
)
wait_key_up() { wait_key up; }
wait_key_down() { wait_key down; }
wait_key_up_down() { wait_key up down; }
wait_key_power() { wait_key power; }
wait_key_mute() { wait_key mute; }
wait_key_f() { wait_key f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12; }
wait_key_any() { wait_key any; }

get_manager() {
    if [ -z "${_GM_CACHE:-}" ]; then
        if command -v magisk >/dev/null 2>&1; then _GM_CACHE=magisk
        elif [ -f /data/adb/ksud ] || command -v ksud >/dev/null 2>&1; then _GM_CACHE=ksud
        elif [ -f /data/adb/apd ] || command -v apd >/dev/null 2>&1; then _GM_CACHE=ap
        else _GM_CACHE=unknown; fi
    fi
    print "$_GM_CACHE"
}
is_magisk() { [ "$(get_manager)" = magisk ]; }
is_ksu() { [ "$(get_manager)" = ksud ]; }
is_ap() { [ "$(get_manager)" = ap ]; }
