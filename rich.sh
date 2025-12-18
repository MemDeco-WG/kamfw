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
        print ""
        _n=$((_n - 1))
    done
}

# 操作指南函数
guide() {
    # Usage:
    # guide "GUIDE_TITLE" "GUIDE_CONTENT"
    # Print a guide with a title and content

    title="$1"
    content="$2"
    newline
    print "${COL_CYN}${title}${COL_RST}"
    print "${COL_CYN}${content}${COL_RST}"
    divider "^"
}

ask() {
    # Usage:
    # ask "QUESTION" "opt1_text" "opt1_cmd" "opt2_text" "opt2_cmd" ... [default_index]
    # Backwards-compatible with older call: ask "QUESTION" "opt1_text" "opt2_text" "opt1_cmd" "opt2_cmd" [default_index]
    # Supports arbitrary number of options. Controls:
    # - Volume Down: cycle to next option (wraps around)
    # - Volume Up: confirm current selection and execute its command

    question="$1"
    shift || true

    # 检查是否为 i18n 键值（不包含空格或特殊字符）
    if printf '%s' "$question" | grep -q '^[[:alpha:]_][[:alnum:]_]*$'; then
        question=$(i18n "$question")
    fi

    _opt_count=0
    default_selected=0

    # New-style: parse text/cmd pairs, optional trailing default index
    while [ "$#" -gt 0 ]; do
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

    # If getevent isn't available (e.g., running in a plain terminal), fall back to typed input.
    # Otherwise use volume keys: volume-down cycles (wrap), volume-up confirms.
    if ! command -v getevent >/dev/null 2>&1; then
        printf '> '
        if ! read -r sel; then
            sel="$default_selected"
        fi
        [ -z "$sel" ] && sel="$default_selected"

        case "$sel" in
            *[!0-9]*) sel="$default_selected" ;;
        esac

        # ensure within range (numeric check via test redirects errors)
        if [ "$sel" -ge 0 ] 2>/dev/null && [ "$sel" -lt "$_opt_count" ] 2>/dev/null; then
            eval "_txt=\$opt_text_${sel}"
            eval "_cmd=\$opt_cmd_${sel}"
        else
            sel="$default_selected"
            eval "_txt=\$opt_text_${sel}"
            eval "_cmd=\$opt_cmd_${sel}"
        fi

        print "$(i18n 'CONFIRM'): ${_txt}"
        eval "$_cmd"
    else
        # interactive loop: volume-down cycles, volume-up confirms
        while :; do
            _k=$(wait_key_up_down)
            case "$_k" in
                down)
                    _sel=$(( (_sel + 1) % _opt_count ))
                    # move cursor up (options + trailing blank line) lines to redraw
                    printf '\033[%dA' "$((_opt_count + 1))"

                    _i=0
                    while [ "$_i" -lt "$_opt_count" ]; do
                        eval "_txt=\$opt_text_${_i}"
                        # clear entire line
                        printf '\033[2K\r'
                        if [ "$_i" -eq "$_sel" ]; then
                            printf '%b\n' "${COL_CYN}-> ${_i}) ${_txt}${COL_RST}"
                        else
                            printf '%b\n' "   ${_i}) ${_txt}"
                        fi
                        _i=$((_i + 1))
                    done
                    # clear trailing blank line and emit a fresh one
                    printf '\033[2K\r\n'
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
    fi

    newline
    return
}
