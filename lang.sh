# shellcheck shell=ash
#
# Language selection module for KAM framework (KAMFW)
#
# Usage:
#   import lang
#   select_language        # interactive selection (uses `ask`)
#   set_kam_language en    # programmatically set language to `en`
#   unset_kam_language     # remove override (back to system / auto)
#
# Notes:
# - Persists choice to "${KAMFW_DIR}/.kamfw_lang" as `export KAM_LANG="..."`.
# - Tries to set system property `persist.sys.locale` via `resetprop -w` or
#   `setprop` when available (best-effort).
# - Uses the existing `i18n` + `ask` helpers for localized menu and input.
#

# Ensure we have a sane default for KAMFW_DIR when sourced standalone.
: "${KAMFW_DIR:=${MODDIR:-${0%/*}}/lib/kamfw}"
: "${KAM_LANG_FILE:=${KAMFW_DIR}/.kamfw_lang}"

# helper: return normalized current language (zh|en|ja|ko)
_lang_current() {
    _l="${KAM_LANG:-$(getprop persist.sys.locale 2>/dev/null | cut -d'-' -f1)}"
    _l="${_l:-en}"
    case "$_l" in
        zh*|cn*|CN*) printf 'zh' ;;
        ja*|JP*)     printf 'ja' ;;
        ko*|KR*)     printf 'ko' ;;
        *)           printf 'en' ;;
    esac
}

# Persist the override to file (or remove it for 'auto')
_lang_persist() {
    _lang="$1"
    mkdir -p "${KAMFW_DIR}" 2>/dev/null || true

    if [ -z "$_lang" ] || [ "$_lang" = "auto" ]; then
        [ -f "${KAMFW_DIR}/.kamfw_lang" ] && rm -f "${KAMFW_DIR}/.kamfw_lang" 2>/dev/null || true
        unset KAM_LANG
        return 0
    fi

    printf 'export KAM_LANG="%s"\n' "$_lang" > "${KAMFW_DIR}/.kamfw_lang"
}

# Best-effort setprop/resetprop for system locale
_lang_setprop() {
    _lang="$1"
    if command -v resetprop >/dev/null 2>&1; then
        resetprop -w persist.sys.locale "$_lang" >/dev/null 2>&1 || true
    elif command -v setprop >/dev/null 2>&1; then
        setprop persist.sys.locale "$_lang" >/dev/null 2>&1 || true
    fi
}

# Set language (public)
set_lang() {
    _lang="$1"
    [ -n "$_lang" ] || return 1

    # immediate effect for current session
    if [ "$_lang" = "auto" ]; then
        _lang_persist "auto" \
            && success "$(i18n 'LANG_SAVE' 2>/dev/null || echo 'Language saved'): $(i18n 'lang_auto' 2>/dev/null || echo 'Auto (system)')" \
            || error "$(i18n 'LANG_SAVE_ERROR' 2>/dev/null || echo 'Failed to remove language override')"
        return $?
    fi

    export KAM_LANG="$_lang"

    if _lang_persist "$_lang"; then
        _lang_setprop "$_lang"
        success "$(i18n 'LANG_SAVE' 2>/dev/null || echo 'Language saved'): $(i18n "lang_${_lang}" 2>/dev/null || echo "$_lang")"
        return 0
    else
        error "$(i18n 'LANG_SAVE_ERROR' 2>/dev/null || echo 'Failed to write language override')"
        return 1
    fi
}

# Remove language override (public)
unset_lang() {
    set_kam_language auto
}

# Interactive language menu (uses ask); exported as `select_language`
select_lang() {
    # Ensure helpers available (import is a kamfw helper)
    import i18n || true
    import rich  || true

    # Determine default selection based on current language
    _cur="$(_lang_current)"
    _default=0
    case "$_cur" in
        en) _default=1 ;;
        zh) _default=2 ;;
        ja) _default=3 ;;
        ko) _default=4 ;;
        *)  _default=0 ;;
    esac

    # ask usage: ask "QUESTION" "opt1_text" "opt1_cmd" "opt2_text" "opt2_cmd" ... [default_index]
    ask "SWITCH_LANGUAGE" \
        "LANG_AUTO" 'set_kam_language auto' \
        "LANG_EN"  'set_kam_language en' \
        "LANG_ZH"  'set_kam_language zh' \
        "LANG_JA"  'set_kam_language ja' \
        "LANG_KO"  'set_kam_language ko' \
        "$_default"
}
