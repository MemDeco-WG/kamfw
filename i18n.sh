# shellcheck shell=ash

set_i18n() {
    _s_key="$1"
    shift

    while [ $# -ge 2 ]; do
        _s_lang="$1"
        _s_text="$2"
        shift 2
        _s_safe_lang=$(printf '%s' "$_s_lang" | tr '-' '_')

        _s_var_name="_I18N_${_s_key}_${_s_safe_lang}"

        export "$_s_var_name"="$_s_text"
    done

    unset _s_key _s_lang _s_text _s_safe_lang _s_var_name
}

# 获取国际化文本
# 用法: i18n "WELCOME_MSG"
i18n() {
    _i1_key="$1"

    _i1_lang="${KAM_LANG:-$(getprop persist.sys.locale 2>/dev/null | cut -d'-' -f1)}"
    _i1_lang="${_i1_lang:-en}"

    case "$_i1_lang" in
        zh*|cn*|CN*) _i1_lang="zh" ;;
        ja*|JP*)     _i1_lang="ja" ;;
        ko*|KR*)     _i1_lang="ko" ;;
        *)           _i1_lang="en" ;;
    esac

    _i1_var_name="_I18N_${_i1_key}_${_i1_lang}"

    eval "_i1_text=\"\${${_i1_var_name}:-}\""

    if [ -z "$_i1_text" ] && [ "$_i1_lang" != "en" ]; then
        _i1_var_name="_I18N_${_i1_key}_en"
        eval "_i1_text=\"\${${_i1_var_name}:-}\""
    fi

    [ -z "$_i1_text" ] && _i1_text="$_i1_key"

    printf '%s' "$_i1_text" # 传值

    unset _i1_key _i1_lang _i1_var_name _i1_text
}
