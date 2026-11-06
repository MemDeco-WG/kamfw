# shellcheck shell=ash

_kamfw_i18n_key_is_safe() {
    case "${1:-}" in ''|[!A-Za-z_]*|*[!A-Za-z0-9_]*) return 1 ;; esac
}

_kamfw_i18n_lang_is_safe() {
    case "${1:-}" in ''|[!A-Za-z]*|*[!A-Za-z0-9_-]*) return 1 ;; esac
}

_kamfw_i18n_pairs_are_safe() {
    [ $(( $# % 2 )) -eq 0 ] || return 1
    while [ $# -gt 0 ]; do
        _kamfw_i18n_lang_is_safe "$1" || return 1
        shift 2
    done
}

set_i18n() {
    [ $# -gt 0 ] && _kamfw_i18n_key_is_safe "$1" || return 1
    _si_key=$1
    shift
    _kamfw_i18n_pairs_are_safe "$@" || return 1
    while [ $# -gt 0 ]; do
        case "$1" in
            *-*) _si_lang=$(printf '%s' "$1" | tr '-' '_') ;;
            *) _si_lang=$1 ;;
        esac
        export "_I18N_${_si_key}_${_si_lang}=$2"
        shift 2
    done
    unset _si_key _si_lang
}

i18n() {
    _kamfw_i18n_key_is_safe "${1:-}" || return 1
    _il_lang=${KAM_UI_LANGUAGE:-${KAM_LANG:-}}
    [ -n "$_il_lang" ] || _il_lang=$(getprop persist.sys.locale 2>/dev/null)
    if [ -z "${KAM_UI_LANGUAGE:-}" ] && [ -n "${KAM_LANG:-}" ] && [ "${KAM_DEBUG_I18N:-}" = 1 ]; then
        print 'Warning: KAM_LANG is deprecated; please use KAM_UI_LANGUAGE'
    fi
    case "$_il_lang" in
        zh*|cn*|CN*) _il_lang=zh ;;
        ja*|JP*) _il_lang=ja ;;
        ko*|KR*) _il_lang=ko ;;
        *) _il_lang=en ;;
    esac
    eval "_il_text=\${_I18N_${1}_${_il_lang}:-}"
    [ -n "$_il_text" ] || eval "_il_text=\${_I18N_${1}_en:-}"
    if [ -n "$_il_text" ]; then print "$(printf '%b' "$_il_text")"; else print "$1"; fi
    unset _il_lang _il_text
}

# Validate the whole table before publishing any translation. Both passes use
# the same literal field parser, including empty values and regional languages.
_kamfw_i18n_table_pass() {
    case "${2:-}" in validate|apply) ;; *) return 1 ;; esac
    _lt_langs=''
    while IFS= read -r _lt_line || [ -n "$_lt_line" ]; do
        case "$_lt_line" in ''|\#*) continue ;; esac
        if [ -z "$_lt_langs" ]; then
            case "$_lt_line" in
                KEY\|*)
                    _lt_langs=${_lt_line#KEY|}
                    case "$_lt_langs" in ''|\|*|*\||*\|\|*) return 1 ;; esac
                    _lt_rest=$_lt_langs
                    while :; do
                        _kamfw_i18n_lang_is_safe "${_lt_rest%%|*}" || return 1
                        case "$_lt_rest" in *\|*) _lt_rest=${_lt_rest#*|} ;; *) break ;; esac
                    done
                    continue
                    ;;
                *) _lt_langs='zh|en|ja|ko' ;;
            esac
        fi
        _lt_key=${_lt_line%%|*}
        _kamfw_i18n_key_is_safe "$_lt_key" || return 1
        _lt_rest=$_lt_line
        _lt_languages=$_lt_langs
        while :; do
            case "$_lt_rest" in *\|*) _lt_rest=${_lt_rest#*|} ;; *) return 1 ;; esac
            _lt_lang=${_lt_languages%%|*}
            if [ "$2" = apply ]; then set_i18n "$_lt_key" "$_lt_lang" "${_lt_rest%%|*}" || return 1; fi
            case "$_lt_languages" in
                *\|*) _lt_languages=${_lt_languages#*|} ;;
                *) case "$_lt_rest" in *\|*) return 1 ;; esac; break ;;
            esac
        done
    done <"$1"
    unset _lt_langs _lt_line _lt_rest _lt_key _lt_languages _lt_lang
}

load_i18n() {
    [ -f "${1:-}" ] && _kamfw_i18n_table_pass "$1" validate && _kamfw_i18n_table_pass "$1" apply
}

dump_i18n() (
    [ -n "${1:-}" ] || return 1
    langs=$(env | sed -n 's/^_I18N_.*_\([^=]*\)=.*/\1/p' | sort -u)
    keys=$(env | sed -n 's/^_I18N_\(.*\)_\([^=]*\)=.*/\1/p' | sort -u)
    [ -n "$langs" ] || langs='zh en ja ko'
    {
        printf KEY
        for lang in $langs; do printf '|%s' "$lang"; done
        printf '\n'
        for key in $keys; do
            printf '%s' "$key"
            for lang in $langs; do
                eval "value=\${_I18N_${key}_${lang}:-}"
                printf '|%s' "$(printf '%s' "$value" | sed ':a;N;$!ba;s/\n/\\n/g')"
            done
            printf '\n'
        done
    } >"$1"
)

t() {
    if [ -t 0 ]; then [ $# -eq 0 ] || print "$1"; return 0; fi
    _tt_text=$(cat)
    _tt_index=1
    for _tt_arg in "$@"; do
        _tt_token="\$_${_tt_index}"
        _tt_rest=$_tt_text
        _tt_text=''
        while :; do
            case "$_tt_rest" in
                *"$_tt_token"*)
                    _tt_text="${_tt_text}${_tt_rest%%"$_tt_token"*}${_tt_arg}"
                    _tt_rest=${_tt_rest#*"$_tt_token"}
                    ;;
                *) break ;;
            esac
        done
        _tt_text=$_tt_text$_tt_rest
        _tt_index=$((_tt_index + 1))
    done
    print "$_tt_text"
    unset _tt_text _tt_index _tt_arg _tt_token _tt_rest
}

import i18ns
