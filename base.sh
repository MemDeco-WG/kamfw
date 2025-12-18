# shellcheck shell=ash
#
export COL_RED='\033[0;31m'
export COL_GRN='\033[0;32m'
export COL_YLW='\033[0;33m'
export COL_BLU='\033[0;34m'
export COL_PUR='\033[0;35m'
export COL_CYN='\033[0;36m'
export COL_RST='\033[0m'

info () {
    print "${COL_GRN}$1${COL_RST}"
}

green () {
    print "${COL_GRN}$1${COL_RST}"
}

error () {
    print "${COL_RED}$1${COL_RST}"
}

red() {
    print "${COL_RED}$1${COL_RST}"
}

warn () {
    print "${COL_YLW}$1${COL_RST}"
}

yellow() {
    print "${COL_YLW}$1${COL_RST}"
}

success () {
    print "${COL_GRN}$1${COL_RST}"
}

debug() {
    if [ "${KAM_DEBUG:-0}" = "1" ]; then
        print "${COL_CYN}[DEBUG] $1${COL_RST}"
    fi
}

cyan() {
    print "${COL_CYN}$1${COL_RST}"
}

wait_key() {
    _wkr_match_list="$*"
    _wkr_event=""
    _wkr_res=""

    while :; do
        _wkr_event=$(getevent -qlc 1 2>/dev/null | awk '$2~/0001|EV_KEY/ && $4~/00000001|DOWN/ {print $3; exit}')
        [ -z "$_wkr_event" ] && continue
        case "$_wkr_event" in
            KEY_VOLUMEUP|0073)   _wkr_res="up"    ;;
            KEY_VOLUMEDOWN|0072) _wkr_res="down"  ;;
            KEY_POWER|0074)      _wkr_res="power" ;;
            KEY_MUTE|0071)       _wkr_res="mute"  ;;
            KEY_F*)              _wkr_res="f${_wkr_event#KEY_F}" ;;
            *)                   _wkr_res=""      ;;
        esac

        if [ -n "$_wkr_res" ]; then
            if [ "$_wkr_match_list" = "any" ]; then
                printf '%s' "$_wkr_res"
                break
            else
                case " ${_wkr_match_list} " in
                    *" ${_wkr_res} "*)
                        printf '%s' "$_wkr_res"
                        break
                        ;;
                esac
            fi
        fi
    done
    unset _wkr_match_list _wkr_event _wkr_res
}

wait_key_up() {
    wait_key "up"
}

wait_key_down() {
    wait_key "down"
}

wait_key_up_down() {
    wait_key "up" "down"
}

wait_key_power() {
    wait_key "power"
}

wait_key_mute() {
    wait_key "mute"
}

wait_key_f() {
    wait_key "f1" "f2" "f3" "f4" "f5" "f6" "f7" "f8" "f9" "f10" "f11" "f12"
}

# 用于“按任意键继续”
wait_key_any() {
    wait_key "any"
}

# 分支不计入
get_manager() {
    if [ -n "$_GM_CACHE" ]; then
        printf '%s' "$_GM_CACHE"
        return 0
    fi

    _gm_type="unknown"
    if command -v magisk >/dev/null 2>&1; then
        _gm_type="magisk"
    elif [ -f "/data/adb/ksud" ] || command -v ksud >/dev/null 2>&1; then
        _gm_type="ksud"
    elif [ -f "/data/adb/apd" ] || command -v apd >/dev/null 2>&1; then
        _gm_type="ap"
    fi

    _GM_CACHE="$_gm_type"
    printf '%s' "$_gm_type"
    unset _gm_type
}

is_magisk() {
    _im_mgr=$(get_manager)
    [ "$_im_mgr" = "magisk" ]
}

is_ksu() {
    _ik_mgr=$(get_manager)
    [ "$_ik_mgr" = "ksud" ]
}

is_ap() {
    _ia_mgr=$(get_manager)
    [ "$_ia_mgr" = "ap" ]
}
