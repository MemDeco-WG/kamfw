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

load_i18n() {
    _lic_file="$1"
    [ -f "$_lic_file" ] || return 1

    # 逐行读取
    # IFS='|' 指定分隔符
    while IFS='|' read -r _lic_key _lic_zh _lic_en _lic_ja _lic_ko || [ -n "$_lic_key" ]; do
        # 1. 跳过注释行（以 # 开头）
        case "$_lic_key" in
            \#*|"") continue ;;
        esac

        # 2. 调用你已有的 set_i18n 函数
        # 注意：这里假设你的 set_i18n 接受这几种固定语言
        set_i18n "$_lic_key" \
            "zh" "$_lic_zh" \
            "en" "$_lic_en" \
            "ja" "$_lic_ja" \
            "ko" "$_lic_ko"

    done < "$_lic_file"

    # 清理变量
    unset _lic_file _lic_key _lic_zh _lic_en _lic_ja _lic_ko
}

dump_i18n() {
    _dic_file="$1"
    [ -n "$_dic_file" ] || return 1
    printf 'KEY|zh|en|ja|ko\n' > "$_dic_file"

    _dic_keys=$(set | grep '^_I18N_' | cut -d'_' -f3 | sort -u)

    for _dic_k in $_dic_keys; do
        eval "_dic_zh=\"\${_I18N_${_dic_k}_zh:-}\""
        eval "_dic_en=\"\${_I18N_${_dic_k}_en:-}\""
        eval "_dic_ja=\"\${_I18N_${_dic_k}_ja:-}\""
        eval "_dic_ko=\"\${_I18N_${_dic_k}_ko:-}\""

        printf '%s|%s|%s|%s|%s\n' \
            "$_dic_k" "$_dic_zh" "$_dic_en" "$_dic_ja" "$_dic_ko" >> "$_dic_file"
    done

    unset _dic_file _dic_keys _dic_k _dic_zh _dic_en _dic_ja _dic_ko
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
set_i18n "ASK_GUIDE_TITLE" "zh" "操作提示" "en" "How to use" "ja" "使い方" "ko" "사용 방법"
set_i18n "ASK_GUIDE_CONTENT" \
    "zh" "音量键：音量减切换选项（循环），音量加确认并执行。" \
    "en" "Volume keys: Volume Down cycles options (wraps around); Volume Up confirms and executes." \
    "ja" "音量キー：ボリュームダウンで選択肢を切替（ループします）、音量アップで選択を確定して実行します。" \
    "ko" "볼륨 키: 볼륨 작게로 항목 전환(반복), 볼륨 크게로 선택 확인 및 실행합니다."


# 调试相关
set_i18n "DEBUG_MODE"   "zh" "是否开启调试模式？" "en" "Enable debug mode?" "ja" "デバッグモードを有効にしますか？" "ko" "디버그 모드를 활성화하시겠습니까?"
set_i18n "DEBUG_ON"     "zh" "调试模式已开启" "en" "Debug mode enabled" "ja" "デバッグモードが有効になりました" "ko" "디버그 모드가 활성화되었습니다"
set_i18n "DEBUG_OFF"    "zh" "调试模式已关闭" "en" "Debug mode disabled" "ja" "デバッグモードが無効になりました" "ko" "디버그 모드가 비활성화되었습니다"
set_i18n "DEBUG_STATUS" "zh" "调试模式状态" "en" "Debug status" "ja" "デバッグステータス" "ko" "디버그 상태"

# 社交/支持
set_i18n "FEED_STAR" "zh" "投喂星光" "en" "Feed star" "ja" "星を餌付け" "ko" "별에게 먹이를 주세요"

# i18n labels (shell UI)
set_i18n "SWITCH_LANGUAGE" "zh" "切换语言"    "en" "Switch Language"  "ja" "言語切替"           "ko" "언어 전환"
set_i18n "LANG_AUTO"       "zh" "自动(系统)"  "en" "Auto (system)"    "ja" "自動(システム)"      "ko" "자동(시스템)"
set_i18n "LANG_EN"         "zh" "英文"       "en" "English"          "ja" "英語"               "ko" "영어"
set_i18n "LANG_ZH"         "zh" "中文"       "en" "Chinese"          "ja" "中国語"             "ko" "중국어"
set_i18n "LANG_JA"         "zh" "日语"       "en" "Japanese"         "ja" "日本語"             "ko" "일본어"
set_i18n "LANG_KO"         "zh" "韩语"       "en" "Korean"           "ja" "韓国語"             "ko" "한국어"
set_i18n "LANG_SAVE"       "zh" "语言已保存"  "en" "Language saved"   "ja" "言語が保存されました" "ko" "언어가 저장되었습니다"
set_i18n "LANG_SAVE_ERROR" "zh" "保存失败"    "en" "Operation failed" "ja" "操作に失敗しました"   "ko" "작업 실패"
