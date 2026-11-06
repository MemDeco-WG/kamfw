# shellcheck shell=ash

__rich_terminal_width() (
    width=''
    if command -v tput >/dev/null 2>&1; then width=$(tput cols 2>/dev/null); fi
    case "$width" in
        ''|*[!0-9]*)
            if command -v stty >/dev/null 2>&1; then
                size=$(stty size 2>/dev/null)
                width=${size#* }
            fi
            ;;
    esac
    width=${width:-${COLUMNS:-80}}
    case "$width" in ''|*[!0-9]*|0) width=80 ;; esac
    printf '%s' "$width"
)

__rich_repeat() (
    count=${2:-80}
    case "$count" in ''|*[!0-9]*|0) count=80 ;; esac
    while [ "$count" -gt 0 ]; do printf '%s' "${1:-─}"; count=$((count - 1)); done
)

__rich_pad_right() (
    text=${1:-}
    width=${2:-0}
    case "$width" in ''|*[!0-9]*) width=0 ;; esac
    printf '%s' "$text"
    padding=$((width - ${#text}))
    [ "$padding" -le 0 ] || printf '%*s' "$padding" ''
)

__rich_style() {
    if is_tty 2>/dev/null; then printf '%b' "${1:-}${2:-}${COL_RST}"
    else printf '%s' "${2:-}"; fi
}
__rich_cyan() { __rich_style "$COL_CYN" "$1"; }
__rich_green() { __rich_style "$COL_GRN" "$1"; }
__rich_yellow() { __rich_style "$COL_YLW" "$1"; }
__rich_red() { __rich_style "$COL_RED" "$1"; }

divider() { print "$(__rich_cyan "$(__rich_repeat "${1:-▚}" "${2:-$(__rich_terminal_width)}")")"; }
newline() (
    count=${1:-1}
    case "$count" in ''|*[!0-9]*) count=1 ;; esac
    while [ "$count" -gt 0 ]; do printf '\n'; count=$((count - 1)); done
)
guide() { print "$(__rich_yellow "${1:-}")"; print "$(__rich_yellow "${2:-}")"; }

panel() {
    newline
    divider '━'
    [ -z "${1:-}" ] || printf '%b\n' "$COL_CYN$1$COL_RST"
    divider '─'
}
panel_end() { divider '━'; }
panel_row() { printf '%b\n' "$COL_CYN${1:-}$COL_RST  ${2:-}"; }
panel_note() { printf '%b\n' "$COL_YLW${1:-}$COL_RST"; }
panel_success() { printf '%b\n' "$COL_GRN${1:-}$COL_RST"; }
panel_warn() { panel_note "$@"; }
panel_error() { printf '%b\n' "$COL_RED${1:-}$COL_RST"; }

panel_line() (
    inner=${__KAMFW_PANEL_INNER:-$(($(__rich_terminal_width) - 4))}
    case "$inner" in ''|*[!0-9]*|0) inner=76 ;; esac
    print "$(__rich_cyan '┃') $(__rich_pad_right "${1:-}" "$inner") $(__rich_cyan '┃')"
)
panel_blank() { panel_line ''; }
panel_divider() (
    width=${__KAMFW_PANEL_WIDTH:-$(__rich_terminal_width)}
    case "$width" in ''|*[!0-9]*|0) width=80 ;; esac
    [ "$width" -ge 24 ] || width=24
    print "$(__rich_cyan "┣$(__rich_repeat '─' "$((width - 2))")┫")"
)
panel_status() (
    case "${1:-info}" in
        ok|success) mark=$(__rich_green ok) ;;
        warn|warning) mark=$(__rich_yellow warn) ;;
        error|fail|failed) mark=$(__rich_red error) ;;
        *) mark=$(__rich_cyan note) ;;
    esac
    panel_line "[$mark] ${2:-}"
)

_do_update_file() {
    _uf_old=$_installed_module_path/$_relative_path
    _uf_new=$MODPATH/$_relative_path
    mv "$_uf_new" "$_uf_new.update" || return 1
    if [ -f "$_uf_old" ]; then
        mkdir -p "${_uf_new%/*}" && cp -a "$_uf_old" "$_uf_new" || return 1
    fi
    unset _relative_path _module_id _installed_module_path _uf_old _uf_new
}
