# shellcheck shell=ash
##########################################################################################
# KAM Framework - Internationalization (i18n) Module
# Optimized for multi-line text and ash environment (2025 Revised)
##########################################################################################

# Reject keys that cannot safely form shell variable names.
_magicnet_i18n_valid_key() {
    case "$1" in
    '' | [0-9]* | *[!A-Za-z0-9_]*) return 1 ;;
    *) return 0 ;;
    esac
}

# Language tags: letter start, then alnum / _ / - (hyphen normalized to _).
_magicnet_i18n_valid_lang() {
    case "$1" in
    '' | [!A-Za-z]* | *[!A-Za-z0-9_-]*) return 1 ;;
    *) return 0 ;;
    esac
}

_magicnet_i18n_normalize_lang() {
    case "$1" in
    *-*)
        printf '%s' "$1" | tr '-' '_'
        ;;
    *)
        printf '%s' "$1"
        ;;
    esac
}

# 设置国际化文本
# 用法: set_i18n "KEY" "zh" "文本内容" "en" "Text Content" ...
# Fails atomically: no exports if any key/language pair is invalid.
set_i18n() {
    _s_key="$1"
    shift
    _magicnet_i18n_valid_key "$_s_key" || {
        unset _s_key
        return 1
    }

    # Pass 1: validate all language tags before exporting anything.
    _s_argc=$#
    _s_i=1
    while [ "$_s_i" -le "$_s_argc" ]; do
        eval "_s_lang=\${$_s_i}"
        _s_i=$((_s_i + 1))
        [ "$_s_i" -le "$_s_argc" ] || {
            unset _s_key _s_argc _s_i _s_lang
            return 1
        }
        _magicnet_i18n_valid_lang "$_s_lang" || {
            unset _s_key _s_argc _s_i _s_lang
            return 1
        }
        _s_i=$((_s_i + 1))
    done

    # Pass 2: export all pairs.
    while [ $# -ge 2 ]; do
        _s_lang="$1"
        _s_text="$2"
        shift 2
        _s_safe_lang=$(_magicnet_i18n_normalize_lang "$_s_lang")
        _s_var_name="_I18N_${_s_key}_${_s_safe_lang}"
        export "$_s_var_name"="$_s_text"
    done
    unset _s_key _s_lang _s_text _s_safe_lang _s_var_name _s_argc _s_i
    return 0
}

# 获取并打印国际化文本
# 用法: i18n "WELCOME_MSG"
i18n() {
    _i1_key="$1"
    _magicnet_i18n_valid_key "$_i1_key" || {
        unset _i1_key
        return 1
    }

    # 获取当前语言优先级: KAM_UI_LANGUAGE > KAM_LANG (legacy) > 系统属性 > 默认 en
    _i1_lang="${KAM_UI_LANGUAGE:-${KAM_LANG:-$(getprop persist.sys.locale 2>/dev/null | cut -d'-' -f1)}}"
    _i1_lang="${_i1_lang:-en}"

    # 如果使用了 legacy KAM_LANG 并且启用了调试（KAM_DEBUG_I18N=1），则打印弃用提示
    if [ -z "${KAM_UI_LANGUAGE:-}" ] && [ -n "${KAM_LANG:-}" ] && [ "${KAM_DEBUG_I18N:-}" = "1" ]; then
        print "Warning: KAM_LANG is deprecated; please use KAM_UI_LANGUAGE"
    fi

    case "$_i1_lang" in
    zh* | cn* | CN*) _i1_lang="zh" ;;
    ja* | JP*) _i1_lang="ja" ;;
    ko* | KR*) _i1_lang="ko" ;;
    *) _i1_lang="en" ;;
    esac

    _i1_var_name="_I18N_${_i1_key}_${_i1_lang}"

    # 使用 eval 直接读取变量，以支持多行内容（nounset-safe default empty）
    eval "_i1_text=\${${_i1_var_name}-}"

    # 自动回退机制：如果目标语言为空且不是英文，尝试读取英文
    if [ -z "$_i1_text" ] && [ "$_i1_lang" != "en" ]; then
        _i1_var_name="_I18N_${_i1_key}_en"
        eval "_i1_text=\${${_i1_var_name}-}"
    fi

    # 如果依然为空，则返回 Key 名本身
    if [ -z "$_i1_text" ]; then
        print "$_i1_key"
    else
        # 展开转义序列（如 \n）再使用 print 输出，保持输出函数一致性
        _i1_out=$(printf '%b' "$_i1_text")
        print "$_i1_out"
    fi

    unset _i1_key _i1_lang _i1_var_name _i1_text _i1_out
    return 0
}

# 从文件加载 I18N 数据（整表校验通过后才导出，避免部分提交）
load_i18n() {
    _lic_file="$1"
    [ -f "$_lic_file" ] || return 1

    _lic_langs=""
    _lic_pending_file="${TMPDIR:-/tmp}/magicnet-i18n-pending.$$"
    : >"$_lic_pending_file" || return 1

    while IFS= read -r _lic_line || [ -n "$_lic_line" ]; do
        case "$_lic_line" in
        \#* | "") continue ;;
        esac

        # 解析表头 KEY|zh|en...
        if [ -z "$_lic_langs" ]; then
            case "$_lic_line" in
            KEY\|*)
                _lic_hdr="${_lic_line#KEY|}"
                # Empty language fields in header (e.g. KEY|en||zh) must fail.
                case "$_lic_hdr" in
                *'||'* | '|'*)
                    rm -f "$_lic_pending_file"
                    unset _lic_file _lic_line _lic_hdr _lic_langs _lic_key _lic_val _field_idx _lic_lang _lic_pending_file _lic_count
                    return 1
                    ;;
                esac
                _lic_langs=$(printf '%s' "$_lic_hdr" | tr '|' ' ')
                _lic_count=0
                for _lic_lang in $_lic_langs; do
                    [ -n "$_lic_lang" ] || {
                        rm -f "$_lic_pending_file"
                        unset _lic_file _lic_line _lic_hdr _lic_langs _lic_key _lic_val _field_idx _lic_lang _lic_pending_file _lic_count
                        return 1
                    }
                    _magicnet_i18n_valid_lang "$_lic_lang" || {
                        rm -f "$_lic_pending_file"
                        unset _lic_file _lic_line _lic_hdr _lic_langs _lic_key _lic_val _field_idx _lic_lang _lic_pending_file _lic_count
                        return 1
                    }
                    _lic_count=$((_lic_count + 1))
                done
                [ "$_lic_count" -gt 0 ] || {
                    rm -f "$_lic_pending_file"
                    unset _lic_file _lic_line _lic_hdr _lic_langs _lic_key _lic_val _field_idx _lic_lang _lic_pending_file _lic_count
                    return 1
                }
                continue
                ;;
            esac
            _lic_langs="zh en ja ko"
            _lic_count=4
        fi

        _lic_key=$(printf '%s' "$_lic_line" | cut -d'|' -f1)
        [ -z "$_lic_key" ] && continue
        _magicnet_i18n_valid_key "$_lic_key" || {
            rm -f "$_lic_pending_file"
            unset _lic_file _lic_line _lic_hdr _lic_langs _lic_key _lic_val _field_idx _lic_lang _lic_pending_file _lic_count
            return 1
        }

        # Require a value for every header language column.
        _lic_field_count=$(printf '%s' "$_lic_line" | awk -F'|' '{print NF}')
        [ "$_lic_field_count" -ge "$((_lic_count + 1))" ] || {
            rm -f "$_lic_pending_file"
            unset _lic_file _lic_line _lic_hdr _lic_langs _lic_key _lic_val _field_idx _lic_lang _lic_pending_file _lic_count _lic_field_count
            return 1
        }
        _field_idx=2
        for _lic_lang in $_lic_langs; do
            _lic_val=$(printf '%s' "$_lic_line" | cut -d'|' -f"$_field_idx")
            # Record as: KEY<RS>LANG<RS>VALUE with RS = unit separator unlikely in text
            printf '%s\036%s\036%s\n' "$_lic_key" "$_lic_lang" "$_lic_val" >>"$_lic_pending_file"
            _field_idx=$((_field_idx + 1))
        done
    done <"$_lic_file"

    # Commit only after full-file validation (same shell — no pipeline subshell).
    while IFS= read -r _lic_row || [ -n "$_lic_row" ]; do
        [ -n "$_lic_row" ] || continue
        _lic_key=$(printf '%s' "$_lic_row" | cut -d"$(printf '\036')" -f1)
        _lic_lang=$(printf '%s' "$_lic_row" | cut -d"$(printf '\036')" -f2)
        _lic_val=$(printf '%s' "$_lic_row" | cut -d"$(printf '\036')" -f3-)
        if ! set_i18n "$_lic_key" "$_lic_lang" "$_lic_val"; then
            rm -f "$_lic_pending_file"
            unset _lic_file _lic_line _lic_hdr _lic_langs _lic_key _lic_val _field_idx _lic_lang _lic_pending_file _lic_count _lic_field_count _lic_row
            return 1
        fi
    done <"$_lic_pending_file"

    rm -f "$_lic_pending_file"
    unset _lic_file _lic_line _lic_hdr _lic_langs _lic_key _lic_val _field_idx _lic_lang _lic_pending_file _lic_count _lic_field_count _lic_row
    return 0
}

# 导出当前 I18N 数据到文件
dump_i18n() {
    _dic_file="$1"
    [ -n "$_dic_file" ] || return 1

    _dic_langs=$(env | grep '^_I18N_' | sed -n 's/^_I18N_.*_\([^=]*\)=.*/\1/p' | sort -u)
    [ -z "$_dic_langs" ] && _dic_langs="zh en ja ko"

    # 打印表头
    _hdr="KEY"
    for _lang in $_dic_langs; do _hdr="${_hdr}|${_lang}"; done
    printf '%s\n' "$_hdr" >"$_dic_file"

    _dic_keys=$(env | grep '^_I18N_' | sed -n 's/^_I18N_\(.*\)_\([^=]*\)=.*/\1/p' | sort -u)

    for _dic_k in $_dic_keys; do
        _out="${_dic_k}"
        for _lang in $_dic_langs; do
            _var="_I18N_${_dic_k}_${_lang}"
            eval "_val=\$${_var}"
            # 导出时将真实换行符转义为 \n 字符串以便单行存储
            _val=$(printf '%s' "$_val" | sed ':a;N;$!ba;s/\n/\\n/g')
            _out="${_out}|${_val}"
        done
        printf '%s\n' "$_out" >>"$_dic_file"
    done

    unset _dic_file _dic_langs _hdr _dic_keys _dic_k _lang _var _val _out
}

# Template function for string substitution
# Usage: echo "Hello $_1" | t "World"
t() {
    # If no piped stdin, fall back to printing the first argument (if any)
    if [ -t 0 ]; then
        if [ $# -gt 0 ]; then
            print "$1"
        fi
        return 0
    fi

    # Read entire piped input
    _template=$(cat -)

    _idx=1
    while [ $# -gt 0 ]; do
        _arg="$1"
        # Escape characters that may interfere with sed replacement
        _esc=$(printf '%s' "$_arg" | sed -e 's/\\/\\\\/g' -e 's/&/\\\&/g' -e 's/|/\\|/g')
        # Replace occurrences of $_<index> with the escaped argument
        _template=$(printf '%s' "$_template" | sed "s|\\\$_${_idx}|${_esc}|g")
        shift
        _idx=$((_idx + 1))
    done

    print "$_template"
    unset _template _idx _arg _esc
}

import i18ns
