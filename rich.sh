# shellcheck shell=ash

# divider
# divider "#" 10
# divider "=" 20
divider() {
     _divider_char="${1:-▚}"
     # 优先获取终端宽度：tput > stty > COLUMNS > 兜底80
     _divider_terminal_width="$(tput cols 2>/dev/null || stty size 2>/dev/null | awk '{print $2}' || echo "${COLUMNS:-80}")"
     # 校验宽度为有效正整数
     case "${_divider_terminal_width}" in
         ''|*[!0-9]*|0) _divider_terminal_width=80 ;;
     esac
     _divider_width="${2:-${_divider_terminal_width}}"
     # 无循环填充：生成指定宽度空白串，替换为分隔符
     printf "%b" "${COL_CYN}$(printf "%${_divider_width}s" "" | tr ' ' "${_divider_char}")${COL_RST}\n"
 }

newline () {
    # Print N blank lines (default: 1)
    _n="${1:-1}"

    # If argument is not a non-negative integer, fall back to 1
    case "$_n" in
        ''|*[!0-9]*)
            _n=1
            ;;
    esac

    while [ "$_n" -gt 0 ]; do
        print '\n'
        _n=$((_n - 1))
    done
}

# guide
guide() {
    _title="${1:-}"
    _content="${2:-}"
    print '%b\n' "${COL_YLW}${_title}${COL_RST}"
    print '%b\n' "${COL_YLW}${_content}${COL_RST}"
}

# ask - Interactive menu with volume key support
# Usage: ask "QUESTION" "opt1_text" "opt1_cmd" "opt2_text" "opt2_cmd" ... [default_index]
ask() {
    question="$1"
    shift || true

    # i18n for question text if it's a key
    if printf '%s' "$question" | grep -q '^[[:alpha:]_][[:alnum:]_]*$'; then
        question=$(i18n "$question")
    fi

    _opt_count=0
    default_selected=0

    # parse arguments: pairs of (text, command) + optional trailing default index
    while [ $# -gt 0 ]; do
            _txt="$1"
            shift || true

            if [ "$#" -eq 0 ]; then
                # single trailing arg -> treat as default index
                default_selected="$_txt"
                break
            fi

            _cmd="$1"
            shift || true

            # i18n for option text if it's a key
            if printf '%s' "$_txt" | grep -q '^[[:alpha:]_][[:alnum:]_]*$'; then
                _txt=$(i18n "$_txt")
            fi

            __tmp="$_txt"; eval "opt_text_${_opt_count}=\"\$__tmp\""
            __tmp="$_cmd";  eval "opt_cmd_${_opt_count}=\"\$__tmp\""
            _opt_count=$((_opt_count + 1))
    done


    # nothing to choose -> just show question
    if [ "$_opt_count" -eq 0 ]; then
        print "$question"
        return
    fi

    # show localized guide for this interactive prompt (uses i18n)
    guide "$(i18n 'ASK_GUIDE_TITLE')" "$(i18n 'ASK_GUIDE_CONTENT')"

    # sanitize default_selected
    case "${default_selected:-0}" in
        ''|*[!0-9]*) default_selected=0 ;;
    esac
    if [ "$default_selected" -ge "$_opt_count" ]; then
        default_selected=0
    fi

    _sel="$default_selected"

    # initial render
    print "$question"
    _i=0
    while [ "$_i" -lt "$_opt_count" ]; do
        eval "_txt=\$opt_text_${_i}"
        if [ "$_i" -eq "$_sel" ]; then
            printf '%b\n' "${COL_CYN}-> ${_i}) ${_txt}${COL_RST}"
        else
            printf '%b\n' "   ${_i}) ${_txt}"
        fi
        _i=$((_i + 1))
    done

    newline

    # interactive loop: volume-down cycles, volume-up confirms
    while :; do
        _k=$(wait_key_up_down)
        case "$_k" in
            down)
                _sel=$(( (_sel + 1) % _opt_count ))
                # move cursor up only for options + trailing blank line (not the question)
                printf "${ANSI_CURSOR_UP}" "$((_opt_count + 1))"

                _i=0
                while [ "$_i" -lt "$_opt_count" ]; do
                    eval "_txt=\$opt_text_${_i}"
                    # clear entire line and redraw
                    printf "\r${ANSI_CLEAR_LINE}"
                    if [ "$_i" -eq "$_sel" ]; then
                        printf '%b\n' "${COL_CYN}-> ${_i}) ${_txt}${COL_RST}"
                    else
                        printf '%b\n' "   ${_i}) ${_txt}"
                    fi
                    _i=$((_i + 1))
                done
                # clear trailing blank line and emit a fresh one
                printf "\r${ANSI_CLEAR_LINE}\n"
                ;;
            up)
                eval "_txt=\$opt_text_${_sel}"
                eval "_cmd=\$opt_cmd_${_sel}"
                print "$(i18n 'CONFIRM'): ${_txt}"
                eval "$_cmd"
                break
                ;;
        esac
    done
        newline

        return

    }


# confirm - Simple confirmation dialog with customizable default
# Usage: confirm "QUESTION_KEY" [default] && do_something
# default: 0 for yes, 1 for no (default: 1)
# Returns: 0 if yes, 1 if no
confirm() {
    _question="${1:-CONFIRM_ACTION}"
    _default="${2:-1}"

    if binary_choice "$_question" "YES" "NO" "$_default"; then
        unset _question _default
        return 0
    else
        unset _question _default
        return 1
    fi
}
