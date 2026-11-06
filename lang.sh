# shellcheck shell=ash
: "${KAMFW_DIR:=${MODDIR:-${0%/*}}/lib/kamfw}"
: "${KAM_LANG_FILE:=$KAMFW_DIR/.kamfw_lang}"

_lang_current() (
    lang=${KAM_LANG:-}
    if [ -z "$lang" ] && [ -f "$KAM_LANG_FILE" ]; then
        lang=$(sed -n 's/^export KAM_LANG="\([A-Za-z][A-Za-z0-9_-]*\)"$/\1/p' "$KAM_LANG_FILE")
    fi
    [ -n "$lang" ] || lang=$(getprop persist.sys.locale 2>/dev/null)
    case "$lang" in
        auto) printf auto ;;
        zh*|cn*|CN*) printf zh ;;
        ja*|JP*) printf ja ;;
        ko*|KR*) printf ko ;;
        *) printf en ;;
    esac
)

_lang_persist() {
    case "${1:-}" in
        ''|auto) rm -f "$KAM_LANG_FILE" || return 1; unset KAM_LANG ;;
        *)
            _kamfw_i18n_lang_is_safe "$1" || return 1
            mkdir -p "${KAM_LANG_FILE%/*}" || return 1
            (umask 077; printf 'export KAM_LANG="%s"\n' "$1" >"$KAM_LANG_FILE.new") &&
                mv -f "$KAM_LANG_FILE.new" "$KAM_LANG_FILE"
            ;;
    esac
}

_lang_setprop() {
    [ "${KAM_LANG_SET_SYSTEM:-0}" = 1 ] || return 0
    if command -v resetprop >/dev/null 2>&1; then
        resetprop -w persist.sys.locale "$1" >/dev/null 2>&1 || true
    elif command -v setprop >/dev/null 2>&1; then
        setprop persist.sys.locale "$1" >/dev/null 2>&1 || true
    fi
}

set_lang() {
    [ -n "${1:-}" ] || return 1
    _lang_persist "$1" || { error "$(i18n LANG_SAVE_ERROR)"; return 1; }
    if [ "$1" = auto ]; then
        success "$(i18n LANG_SAVE): $(i18n lang_auto)"
    else
        export KAM_LANG="$1"
        _lang_setprop "$1"
        success "$(i18n LANG_SAVE): $(i18n "lang_$1")"
    fi
}

unset_lang() { set_lang auto; }

select_lang() {
    import i18n && import rich || return 1
    _sl_current=$(_lang_current)
    _sl_languages=$(env | sed -n 's/^_I18N_.*_\([^=]*\)=.*/\1/p' | sort -u)
    _sl_default=0
    _sl_index=1
    set -- SWITCH_LANGUAGE "$(i18n LANG_AUTO)" 'set_lang auto'
    for _sl_lang in ${_sl_languages:-en zh ja ko}; do
        _kamfw_i18n_lang_is_safe "$_sl_lang" || continue
        _sl_lang=$(printf '%s' "$_sl_lang" | tr '[:upper:]' '[:lower:]')
        _sl_label=$(printf '%s' "$_sl_lang" | tr '[:lower:]' '[:upper:]')
        set -- "$@" "$(i18n "LANG_$_sl_label")" "set_lang $_sl_lang"
        [ "$_sl_lang" != "$_sl_current" ] || _sl_default=$_sl_index
        _sl_index=$((_sl_index + 1))
    done
    ask "$@" "$_sl_default"
}
