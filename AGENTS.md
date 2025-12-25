# .kamfwrc
# shellcheck shell=ash
##########################################################################################
#
# KAM framework- Cross-Root Manager Utility Library
# 跨 Root 管理器工具框架--模块开发辅助库
#
##########################################################################################export MODDIR=${MODPATH:-${0%/*}}

# 环境变量
export PATH=${MODDIR}/.local/bin/:$PATH：/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin
export LD_LIBRARY_PATH=${MODDIR}/.local/lib/:$LD_LIBRARY_PATH:/data/data/com.termux/files/usr/lib
export HOME=${MODDIR}

export KAMFW_DIR=${MODDIR}/lib/kamfw
export KAM_MODULES=${KAM_MODULES:-""}

export MODDIR=${MODPATH:-${0%/*}}

# =============================================================================
# 基础函数
# =============================================================================
# ui_print plus
print() {
    _print_msg="$1"
    printf '%b\n' "$_print_msg"

    if [ -n "${OUTFD:-}" ] && [ -e "/proc/self/fd/$OUTFD" ]; then
        _print_clean_msg=$(printf '%b' "$_print_msg" | sed 's/\x1b\[[0-9;]*m//g')
        printf 'ui_print %s\n' "$_print_clean_msg" >&"$OUTFD"
        printf 'ui_print \n' >&"$OUTFD"
    fi
}

# =============================================================================
# 工具加载库
# =============================================================================

kamfw() {
    # 指令：
    # load 加载子模块
    # unload 卸载子模块
    # list 列出所有子模块
    # help 显示帮助信息
    case "$1" in
        load)
            shift
            _kamfw_load "$@"
            ;;
        list)
            _kamfw_list
            ;;
        *)
            _kamfw_help
            ;;

    esac
}

import() { kamfw load "$@"; }

if [ -n "${PS1:-}" ]; then
  alias import='kamfw load'
fi
import base

# base.sh
# shellcheck shell=ash
#

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
