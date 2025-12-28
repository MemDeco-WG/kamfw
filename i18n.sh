# shellcheck shell=ash
##########################################################################################
# KAM Framework - Internationalization (i18n) Module
# Optimized for multi-line text and ash environment (2025 Revised)
##########################################################################################

# 设置国际化文本
# 用法: set_i18n "KEY" "zh" "文本内容" "en" "Text Content" ...
set_i18n() {
    _s_key="$1"
    shift

    while [ $# -ge 2 ]; do
        _s_lang="$1"
        _s_text="$2"
        shift 2
        # 处理语言代码中的特殊字符 (如 zh-CN -> zh_CN)
        _s_safe_lang=$(printf '%s' "$_s_lang" | tr '-' '_')
        _s_var_name="_I18N_${_s_key}_${_s_safe_lang}"

        # 直接导出变量，允许包含换行符
        export "$_s_var_name"="$_s_text"
    done

    unset _s_key _s_lang _s_text _s_safe_lang _s_var_name
}

# 获取并打印国际化文本
# 用法: i18n "WELCOME_MSG"
i18n() {
    _i1_key="$1"

    # 获取当前语言优先级: KAM_LANG > 系统属性 > 默认 en
    _i1_lang="${KAM_LANG:-$(getprop persist.sys.locale 2>/dev/null | cut -d'-' -f1)}"
    _i1_lang="${_i1_lang:-en}"

    case "$_i1_lang" in
        zh*|cn*|CN*) _i1_lang="zh" ;;
        ja*|JP*)     _i1_lang="ja" ;;
        ko*|KR*)     _i1_lang="ko" ;;
        *)           _i1_lang="en" ;;
    esac

    _i1_var_name="_I18N_${_i1_key}_${_i1_lang}"

    # 使用 eval 直接读取变量，以支持多行内容
    eval "_i1_text=\$${_i1_var_name}"

    # 自动回退机制：如果目标语言为空且不是英文，尝试读取英文
    if [ -z "$_i1_text" ] && [ "$_i1_lang" != "en" ]; then
        _i1_var_name="_I18N_${_i1_key}_en"
        eval "_i1_text=\$${_i1_var_name}"
    fi

    # 如果依然为空，则返回 Key 名本身
    if [ -z "$_i1_text" ]; then
        printf '%s' "$_i1_key"
    else
        # 使用 %b 确保解析字符串中的 \n 转义符
        printf '%b' "$_i1_text"
    fi

    unset _i1_key _i1_lang _i1_var_name _i1_text
}

# 从文件加载 I18N 数据
load_i18n() {
    _lic_file="$1"
    [ -f "$_lic_file" ] || return 1

    _lic_langs=""
    while IFS= read -r _lic_line || [ -n "$_lic_line" ]; do
        case "$_lic_line" in
            \#*|"") continue ;;
        esac

        # 解析表头 KEY|zh|en...
        if [ -z "$_lic_langs" ]; then
            case "$_lic_line" in
                KEY\|*)
                    _lic_hdr="${_lic_line#KEY|}"
                    _lic_langs=$(printf '%s' "$_lic_hdr" | tr '|' ' ')
                    continue
                    ;;
            esac
            _lic_langs="zh en ja ko"
        fi

        _lic_key=$(printf '%s' "$_lic_line" | cut -d'|' -f1)
        [ -z "$_lic_key" ] && continue

        _field_idx=2
        for _lic_lang in $_lic_langs; do
            _lic_val=$(printf '%s' "$_lic_line" | cut -d'|' -f"$_field_idx")
            set_i18n "$_lic_key" "$_lic_lang" "$_lic_val"
            _field_idx=$((_field_idx + 1))
        done
    done < "$_lic_file"

    unset _lic_file _lic_line _lic_hdr _lic_langs _lic_key _lic_val _field_idx _lic_lang
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
    printf '%s\n' "$_hdr" > "$_dic_file"

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
        printf '%s\n' "$_out" >> "$_dic_file"
    done

    unset _dic_file _dic_langs _hdr _dic_keys _dic_k _lang _var _val _out
}

# =============================================================================
# 预设基础文本
# =============================================================================

# 状态与开关
set_i18n "ENABLE"    "zh" "开启" "en" "Enable" "ja" "有効" "ko" "활성화"
set_i18n "DISABLE"   "zh" "关闭" "en" "Disable" "ja" "無効" "ko" "비활성화"
set_i18n "ON"        "zh" "开启" "en" "ON" "ja" "オン" "ko" "켜짐"
set_i18n "OFF"       "zh" "关闭" "en" "OFF" "ja" "オフ" "ko" "꺼짐"

# 按钮与交互
set_i18n "CONFIRM"   "zh" "确定" "en" "Confirm" "ja" "確認" "ko" "확인"
set_i18n "REFUSE"    "zh" "残忍拒绝" "en" "Refuse" "ja" "拒否" "ko" "거절"
set_i18n "SUCCESS"   "zh" "成功" "en" "Success" "ja" "成功" "ko" "성공"
set_i18n "FAILED"    "zh" "失败" "en" "Failed" "ja" "失敗" "ko" "실패"

# YES/NO used by confirm dialogs
set_i18n "YES" "zh" "是" "en" "Yes" "ja" "はい" "ko" "예"
set_i18n "NO"  "zh" "否" "en" "No"  "ja" "いいえ" "ko" "아니요"

# Force update confirmation (use placeholder $_1; keep literal by escaping $)
set_i18n "FORCE_UPDATE_FILE" \
    "zh" "文件 \$_1 已安装，是否强制更新？" \
    "en" "File \$_1 is already installed. Force update it?" \
    "ja" "ファイル \$_1 は既にインストールされています。強制的に更新しますか？" \
    "ko" "파일 \$_1 이 이미 설치되어 있습니다. 강제로 업데이트하시겠습니까？"

# Language selection / labels
set_i18n "SWITCH_LANGUAGE" \
    "zh" "选择语言" \
    "en" "Switch language" \
    "ja" "言語を切り替え" \
    "ko" "언어 선택"

set_i18n "LANG_AUTO" \
    "zh" "自动 (系统)" \
    "en" "Auto (system)" \
    "ja" "自動（システム）" \
    "ko" "자동(시스템)"

# Save messages for language persistence
set_i18n "LANG_SAVE" \
    "zh" "语言已保存" \
    "en" "Language saved" \
    "ja" "言語が保存されました" \
    "ko" "언어가 저장되었습니다"

set_i18n "LANG_SAVE_ERROR" \
    "zh" "写入语言设置失败" \
    "en" "Failed to write language override" \
    "ja" "言語設定の保存に失敗しました" \
    "ko" "언어 설정을 기록하지 못했습니다"

# Language names (upper-case keys used in menu generation)
set_i18n "LANG_EN" "zh" "ENGLISH" "en" "ENGLISH" "ja" "ENGLISH" "ko" "ENGLISH"
set_i18n "LANG_ZH" "zh" "中文"    "en" "中文"    "ja" "中文"    "ko" "中文"
set_i18n "LANG_JA" "zh" "日本語" "en" "日本語" "ja" "日本語" "ko" "日本語"
set_i18n "LANG_KO" "zh" "한국어" "en" "한국어" "ja" "한국어" "ko" "한국어"

# Language names (lower-case variants used in success messages)
set_i18n "lang_en" "zh" "ENGLISH" "en" "ENGLISH" "ja" "ENGLISH" "ko" "ENGLISH"
set_i18n "lang_zh" "zh" "中文"    "en" "中文"    "ja" "中文"    "ko" "中文"
set_i18n "lang_ja" "zh" "日本語" "en" "日本語" "ja" "日本語" "ko" "日本語"
set_i18n "lang_ko" "zh" "한국어" "en" "한국어" "ja" "한국어" "ko" "한국어"

# 操作指南 (支持多行)
set_i18n "ASK_GUIDE_TITLE" "zh" "🎮 操作指南 🎮" "en" "🎮 Control Guide 🎮" "ja" "🎮 操作ガイド 🎮" "ko" "🎮 조작 가이드 🎮"
set_i18n "ASK_GUIDE_CONTENT" \
    "zh" "🔉 音量减：循环选择选项\n🔊 音量加：确认当前选择" \
    "en" "🔉 Volume Down: Loop through options\n🔊 Volume Up: Confirm current selection" \
    "ja" "🔉 音量-：選択肢をループ\n🔊 音量+：現在の選択を確認" \
    "ko" "🔉 볼륨 다운: 옵션 반복\n🔊 볼륨 업: 현재 선택 확인"

# 调试相关
set_i18n "DEBUG_MODE" "zh" "是否开启调试模式？" "en" "Enable debug mode?" "ja" "デバッグモードを有効にしますか？" "ko" "디버г 모드를 활성화하시겠습니까?"
set_i18n "DEBUG_ON" "zh" "调试模式已开启" "en" "Debug mode enabled" "ja" "デバッグモードが有効です" "ko" "디버그 모드가 활성화되었습니다"

# Template function for string substitution
# Usage: echo "Hello " | t "World"
t() {
    _template=""
    if [ -t 0 ]; then
        # If stdin is a terminal, use the argument as template
        printf '%s' "$_template"
    else
        # If piped, read from stdin and substitute
        while IFS= read -r _line || [ -n "$_line" ]; do
            _result="$_line"
            shift 1
            _arg_num=1
            while [ $# -gt 0 ]; do
                _result=$(printf '%s' "$_result" | sed "s/\\\$_arg_num//g")
                shift
                _arg_num=$((_arg_num + 1))
            done
            printf '%s\n' "$_result"
        done
    fi
    unset _template _line _result _arg_num
}
