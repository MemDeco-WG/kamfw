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

    # Prefer reading from environment variables (exported by set_i18n) instead of using eval.
    # This avoids eval's security risks and works in shells where indirect expansion may be missing.
    _i1_text=$(env | awk -F= -v key="${_i1_var_name}" '$1==key {print substr($0, length($1)+2); exit}')

    if [ -z "$_i1_text" ] && [ "$_i1_lang" != "en" ]; then
        _i1_var_name="_I18N_${_i1_key}_en"
        _i1_text=$(env | awk -F= -v key="${_i1_var_name}" '$1==key {print substr($0, length($1)+2); exit}')
    fi

    [ -z "$_i1_text" ] && _i1_text="$_i1_key"

    printf '%s' "$_i1_text" # 传值

    unset _i1_key _i1_lang _i1_var_name _i1_text
}

load_i18n() {
    _lic_file="$1"
    [ -f "$_lic_file" ] || return 1

    # 逐行读取
    # 支持首行为表头：KEY|lang1|lang2|...
    # 若文件没有表头将使用默认顺序 zh en ja ko
    _lic_langs=""
    while IFS= read -r _lic_line || [ -n "$_lic_line" ]; do
        # 跳过注释行或空行（以 # 开头）
        case "$_lic_line" in
            \#*|"") continue ;;
        esac

        # 如果首个非注释行是表头（以 KEY| 开头），则解析语言列
        if [ -z "$_lic_langs" ]; then
            case "$_lic_line" in
                KEY\|*)
                    _lic_hdr="${_lic_line#KEY|}"
                    _lic_langs=$(printf '%s' "$_lic_hdr" | tr '|' ' ')
                    continue
                    ;;
            esac
            # 未找到表头 -> 兼容旧格式
            _lic_langs="zh en ja ko"
            # 继续处理当前行为数据行
        fi

        # 提取 key（第一个字段）
        _lic_key=$(printf '%s' "$_lic_line" | cut -d'|' -f1)
        case "$_lic_key" in
            ''|\#*) continue ;;
        esac

        # 按语言顺序取对应字段并调用 set_i18n（对兼容性采用每对字段单独调用）
        _field_idx=2
        for _lic_lang in $_lic_langs; do
            _lic_val=$(printf '%s' "$_lic_line" | cut -d'|' -f"$_field_idx")
            set_i18n "$_lic_key" "$_lic_lang" "$_lic_val"
            _field_idx=$((_field_idx + 1))
        done

    done < "$_lic_file"

    # 清理变量
    unset _lic_file _lic_line _lic_hdr _lic_langs _lic_key _lic_val _field_idx _lic_lang
}

dump_i18n() {
    _dic_file="$1"
    [ -n "$_dic_file" ] || return 1

    # 自动收集当前已注册的语言（取变量名最后一段作为语言标识）
    _dic_langs=$(env | grep '^_I18N_' | sed -n 's/^_I18N_.*_\([^=]*\)=.*/\1/p' | sort -u)

    # 若未找到任何语言（极少情况），输出一个兼容的默认表头
    if [ -z "$_dic_langs" ]; then
        _dic_langs="zh en ja ko"
    fi

    # 打印表头
    _hdr="KEY"
    for _lang in $_dic_langs; do
        _hdr="${_hdr}|${_lang}"
    done
    printf '%s\n' "$_hdr" > "$_dic_file"

    # 收集所有 keys（变量名中 _I18N_ 与最后一个 '_' 之间的部分）
    _dic_keys=$(env | grep '^_I18N_' | sed -n 's/^_I18N_\(.*\)_\([^=]*\)=.*/\1/p' | sort -u)

    for _dic_k in $_dic_keys; do
        _out="${_dic_k}"
        for _lang in $_dic_langs; do
            _var="_I18N_${_dic_k}_${_lang}"
            _val=$(env | awk -F= -v key="${_var}" '$1==key {print substr($0, length($1)+2); exit}')
            _out="${_out}|${_val}"
        done
        printf '%s\n' "$_out" >> "$_dic_file"
    done

    unset _dic_file _dic_langs _hdr _dic_keys _dic_k _lang _var _val _out
    success "I18N data dumped to: $_dic_file"
}

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

# ask/choose guidance (used by `ask` via `guide`)
set_i18n "ASK_GUIDE_TITLE" "zh" "🎮 操作指南 🎮" "en" "🎮 Control Guide 🎮" "ja" "🎮 操作ガイド 🎮" "ko" "🎮 조작 가이드 🎮"
set_i18n "ASK_GUIDE_CONTENT" \
    "zh" "🔉 音量减：循环选择选项\n🔊 音量加：确认当前选择" \
    "en" "🔉 Volume Down: Loop through options\n🔊 Volume Up: Confirm current selection" \
    "ja" "🔉 音量-：選択肢をループ\n🔊 音量+：現在の選択を確認" \
    "ko" "🔉 볼륨 다운: 옵션 반복\n🔊 볼륨 업: 현재 선택 확인"


# 调试相关
set_i18n "DEBUG_MODE"   "zh" "是否开启调试模式？" "en" "Enable debug mode?" "ja" "デバッグモードを有効にしますか？" "ko" "디버그 모드를 활성화하시겠습니까?"
set_i18n "DEBUG_ON"     "zh" "调试模式已开启" "en" "Debug mode enabled" "ja" "デバッグモードが有効になりました" "ko" "디버그 모드가 활성화되었습니다"
set_i18n "DEBUG_OFF"    "zh" "调试模式已关闭" "en" "Debug mode disabled" "ja" "デバッグモードが無効になりました" "ko" "디버그 모드가 비활성화되었습니다"
set_i18n "DEBUG_STATUS" "zh" "调试模式状态" "en" "Debug status" "ja" "デバッグステータス" "ko" "디버그 상태"

# 支持
set_i18n "FEED_STAR" "zh" "投喂星光" "en" "Feed star" "ja" "星を餌付け" "ko" "별에게 먹이를 주세요"

# i18n labels (shell UI)
set_i18n "SWITCH_LANGUAGE" "zh" "切换语言"    "en" "Switch Language"  "ja" "言語切替"           "ko" "언어 전환"
set_i18n "LANG_AUTO"       "zh" "自动(系统)"  "en" "Auto (system)"    "ja" "自動(システム)"      "ko" "자동(시스템)"
set_i18n "LANG_EN"         "zh" "English"    "en" "English"          "ja" "English"           "ko" "English"
set_i18n "LANG_ZH"         "zh" "中文"       "en" "中文"             "ja" "中文"               "ko" "中文"
set_i18n "LANG_JA"         "zh" "日本語"     "en" "日本語"           "ja" "日本語"             "ko" "日本語"
set_i18n "LANG_KO"         "zh" "한국어"     "en" "한국어"           "ja" "한국어"             "ko" "한국어"
set_i18n "LANG_SAVE"       "zh" "语言已保存"  "en" "Language saved"   "ja" "言語が保存されました" "ko" "언어가 저장되었습니다"
set_i18n "LANG_SAVE_ERROR" "zh" "保存失败"    "en" "Operation failed" "ja" "操作に失敗しました"   "ko" "작업 실패"

# 文件更新确认
set_i18n "FORCE_UPDATE_FILE" \
    "zh" "强制更新 {} 嘛？" \
    "en" "Force update {}?" \
    "ja" "{} を強制更新しますか？" \
    "ko" "{} 를 강제 업데이트하시겠습니까?"

# 模板替换函数 - 支持管道符传递模板
# 用法1: echo "模板 {} 文本" | t "参数1" "参数2"
# 用法2: t "模板 {} 文本" "参数1" "参数2"
t() {
    _template=""

    # 检查是否有管道输入
    if [ ! -t 0 ]; then
        _template=$(cat)
    fi

    # 如果第一个参数是模板（没有管道输入或管道为空）
    if [ -z "$_template" ] && [ $# -gt 0 ]; then
        _template="$1"
        shift
    fi

    [ -z "$_template" ] && return 1

    _result="$_template"
    _arg_index=1

    # 依次替换每个占位符
    for _arg in "$@"; do
        # 使用sed替换第_arg_index个出现的{}
        _result=$(printf '%s' "$_result" | sed "s/{}/$(printf '%s' "$_arg" | sed 's/[\/&]/\\&/g')/")
        _arg_index=$((_arg_index + 1))
    done

    printf '%s' "$_result"

    unset _template _result _arg_index _arg
}

# Example usage in scripts (e.g. customize.sh):
# print "$(i18n "USAGE_GUIDE")"
# tprint "$(i18n "TERM_INSTALL_MSG")"
# gprint "$(i18n "GUI_INSTALL_MSG\")"
