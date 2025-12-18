# shellcheck shell=ash
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

# divider
# divider "#" 10
# divider "=" 20
divider() {
    _divider_char="${1:-=}"
    _divider_width="${2:-80}"
    _divider_terminal_width=$(stty size 2>/dev/null | cut -d' ' -f2 2>/dev/null)
    _divider_str=""
    i=0
    while [ "$i" -lt "$_divider_width" ]; do
        _divider_str="${_divider_str}${_divider_char}"
        i=$((i + 1))
    done
    print "${COL_CYN}${_divider_str}${COL_RST}"
}
