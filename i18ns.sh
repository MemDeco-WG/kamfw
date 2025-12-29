# shellcheck shell=ash
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

# Install file dialog / messages used by confirm_install_file
set_i18n "SELECT_INSTALL_FILE" \
    "zh" "选择要安装的文件" \
    "en" "Select file to install" \
    "ja" "インストールするファイルを選択" \
    "ko" "설치할 파일 선택"

set_i18n "FILE_INSTALLED" \
    "zh" "已安装: " \
    "en" "Installed: " \
    "ja" "インストール済: " \
    "ko" "설치됨: "

set_i18n "NO_FILES_AVAILABLE" \
    "zh" "没有可安装的文件" \
    "en" "No files available to install" \
    "ja" "インストール可能なファイルがありません" \
    "ko" "설치할 파일이 없습니다"

set_i18n "CANCEL" \
    "zh" "取消" \
    "en" "Cancel" \
    "ja" "キャンセル" \
    "ko" "취소"

set_i18n "IN_ZIP" \
    "zh" "在压缩包中" \
    "en" "in zip" \
    "ja" "ZIP内" \
    "ko" "zip 내"

set_i18n "ZIPTOOLS_MISSING" \
    "zh" "缺少 zip 工具（unzip/zipinfo），无法检查安装包内容，压缩内选项将不可用" \
    "en" "zip utilities (unzip/zipinfo) not found; cannot inspect ZIPFILE (in-zip options unavailable)" \
    "ja" "zip ユーティリティ（unzip/zipinfo）が見つかりません。ZIP の内容を検査できません（ZIP 内オプションは利用不可）" \
    "ko" "zip 도구(unzip/zipinfo)를 찾을 수 없습니다. ZIP 파일을 검사할 수 없습니다(압축 내 옵션 사용 불가)"

set_i18n "INSTALL_CHECK_SRC_NOT_FOUND" \
    "zh" "安装源未找到: %s" \
    "en" "install_check: source not found: %s" \
    "ja" "インストール元が見つかりません: %s" \
    "ko" "설치 소스가 없습니다: %s"

set_i18n "INSTALLED" \
    "zh" "已安装" \
    "en" "installed" \
    "ja" "インストール済" \
    "ko" "설치됨"

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
set_i18n "DEBUG_ON" "zh" "调试模式已开启" "en" "Debug mode enabled" "ja" "デバッグモードが有効です" "ko" "디버그 모드가 활성化되었습니다"

set_i18n "I18N_MISSING_KEY" \
    "zh" "缺少 i18n 键: %s" \
    "en" "Missing i18n key: %s" \
    "ja" "i18n キーがありません: %s" \
    "ko" "i18n 키가 없습니다: %s"
