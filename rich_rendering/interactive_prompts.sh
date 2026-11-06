# shellcheck shell=ash

ask_can_redraw() { [ -t 1 ] && [ -n "${ANSI_CURSOR_UP:-}" ] && [ -n "${ANSI_CLEAR_LINE:-}" ]; }
ask_print_option() {
    if [ "$3" = 1 ]; then ask_print_selection "$1" "$2"
    else printf '%b\n' "    $(($1 + 1)). $2"; fi
}
ask_print_selection() { printf '  %s\n' "$(__rich_cyan "> $(($1 + 1)). $2")"; }

ask() {
    _ask_question=${1:-}
    [ $# -eq 0 ] || shift
    if _kamfw_i18n_key_is_safe "$_ask_question"; then _ask_question=$(i18n "$_ask_question"); fi
    _ask_count=0
    _ask_default=0
    while [ $# -gt 0 ]; do
        if [ $# -eq 1 ]; then _ask_default=$1; break; fi
        _ask_text=$1
        if _kamfw_i18n_key_is_safe "$_ask_text"; then _ask_text=$(i18n "$_ask_text"); fi
        eval "_ask_text_${_ask_count}=\$_ask_text"
        eval "_ask_command_${_ask_count}=\$2"
        _ask_count=$((_ask_count + 1))
        shift 2
    done
    [ "$_ask_count" -gt 0 ] || { printf '%s\n' "$_ask_question"; return; }
    guide "$(i18n ASK_GUIDE_TITLE)" "$(i18n ASK_GUIDE_CONTENT)"
    case "$_ask_default" in ''|*[!0-9]*) _ask_default=0 ;; esac
    [ "$_ask_default" -lt "$_ask_count" ] || _ask_default=0
    _ask_selected=$_ask_default
    printf '%s\n' "$_ask_question"
    _ask_render_options
    newline
    while :; do
        case "$(wait_key_up_down)" in
            down)
                _ask_selected=$(((_ask_selected + 1) % _ask_count))
                if ask_can_redraw; then
                    printf "$ANSI_CURSOR_UP" "$((_ask_count + 1))"
                    _ask_render_options redraw
                    printf "\r${ANSI_CLEAR_LINE}\n"
                else
                    eval "_ask_text=\$_ask_text_$_ask_selected"
                    ask_print_selection "$_ask_selected" "$_ask_text"
                fi
                ;;
            up)
                eval "_ask_text=\$_ask_text_$_ask_selected"
                eval "_ask_command=\$_ask_command_$_ask_selected"
                printf '  %s\n' "$(__rich_green "$(i18n CONFIRM): $_ask_text")"
                eval "$_ask_command"
                _ask_result=$?
                newline
                return "$_ask_result"
                ;;
        esac
    done
}

_ask_render_options() {
    _ask_index=0
    while [ "$_ask_index" -lt "$_ask_count" ]; do
        eval "_ask_text=\$_ask_text_$_ask_index"
        [ "${1:-}" != redraw ] || printf "\r$ANSI_CLEAR_LINE"
        if [ "$_ask_index" -eq "$_ask_selected" ]; then ask_print_option "$_ask_index" "$_ask_text" 1
        else ask_print_option "$_ask_index" "$_ask_text" 0; fi
        _ask_index=$((_ask_index + 1))
    done
}

confirm() { ask "${1:-CONFIRM_ACTION}" YES 'return 0' NO 'return 1' "${2:-1}"; }
