# shellcheck shell=ash

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
