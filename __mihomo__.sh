# shellcheck shell=ash
#
# mihomo helper utilities
# Functions to get/set the redirect URL in $MODDIR/webroot/index.html
#

import rich
import self

# Get the current document.location URL from the webroot index.
# Usage: mihomo_get_ui_redirect [index_file]
# Prints the URL on stdout and returns 0 on success.
mihomo_get_ui_redirect() {
    _index="${1:-${MODDIR:-${0%/*}}/webroot/index.html}"
    if [ ! -f "$_index" ]; then
        error "Index file not found: $_index"
        return 1
    fi
    # Extract the single-quoted URL after document.location
    awk -F"'" '/document.location/ { print $2; exit }' "$_index"
}

# Set the document.location URL in the webroot index.
# Usage: mihomo_set_ui_redirect <url> [index_file]
# Returns 0 on success.
mihomo_set_ui_redirect() {
    _url="$1"
    _index="${2:-${MODDIR:-${0%/*}}/webroot/index.html}"
    if [ -z "$_url" ]; then
        error "Usage: mihomo_set_ui_redirect <url> [index_file]"
        return 2
    fi
    if [ ! -f "$_index" ]; then
        error "Index file not found: $_index"
        return 3
    fi
    if ! grep -q "document.location" "$_index"; then
        error "No document.location found in $_index"
        return 4
    fi
    # Escape potential sed metacharacters in the URL
    _url_escaped=$(printf '%s' "$_url" | sed 's/[&]/\\&/g')

    # Simple replacement (no backup, minimal complexity)
    if sed "s|\(document.location[[:space:]]*=[[:space:]]*\)['\"][^'\"]*['\"]|\1'${_url_escaped}'|" "$_index" > "${_index}.new"; then
        if mv -f -- "${_index}.new" "$_index"; then
            success "$(i18n 'WEBROOT_REDIRECT_UPDATED' 2>/dev/null || echo 'Webroot redirect updated to: ')$_url"
            return 0
        else
            rm -f -- "${_index}.new" 2>/dev/null || true
            error "$(i18n 'WEBROOT_REDIRECT_FAILED' 2>/dev/null || echo 'Failed to update webroot redirect')"
            return 4
        fi
    else
        rm -f -- "${_index}.new" 2>/dev/null || true
        error "$(i18n 'WEBROOT_REDIRECT_FAILED' 2>/dev/null || echo 'Failed to update webroot redirect')"
        return 5
    fi
}

set_default (){
    _url="http://127.0.0.1:9090/ui/"
    mihomo_set_ui_redirect "$_url"
    unset _url
}
set_yacd (){
    _url="https://yacd.metacubex.one/"
    mihomo_set_ui_redirect "$_url"
    unset _url
}

set_i18n "SET_UI_REDIRECT"  \
    "zh" "设置 WebUI 跳转" \
    "en" "Set WebUI redirect" \
    "ja" "WebUI リダイレクト設定" \
    "ko" "WebUI 리디렉션 설정"
set_i18n "USE_DEFAULT"      \
    "zh" "使用本地默认"   \
    "en" "Use local default"      \
    "ja" "ローカルのデフォルトを使用" \
    "ko" "로컬 기본 사용"
set_i18n "USE_YACD"  \
    "zh" "使用 Yacd 前端"  \
    "en" "Use Yacd frontend"      \
    "ja" "Yacd フロントエンドを使用"     \
    "ko" "Yacd 프론트엔드 사용"


ask_webui() {
    # Ask the user to choose between using the local default UI or the Yacd frontend.
    # Question key:    SET_UI_REDIRECT
    # Option keys:     USE_DEFAULT -> runs set_default
    #                  USE_YACD     -> runs set_yacd
    ask "SET_UI_REDIRECT" \
        "USE_DEFAULT" \
            'set_default' \
        "USE_YACD" \
            'set_yacd' \
        0
}

is_mihomo_running() {
    # Check if MiHoMo is running.
    # Returns 0 if MiHoMo is running, 1 otherwise.
    if pgrep -f "mihomo" > /dev/null; then
        config set override.description "$(i18n 'MIHOMO_STATUS'): $(i18n 'RUNNING')"
        return 0
    else
        config set override.description "$(i18n 'MIHOMO_STATUS'): $(i18n 'NOT_RUNNING')"
        return 1
    fi
}

mihomo_tun() {
    mkdir -p /dev/net
    info "创建/dev/net/目录"

    [ ! -L /dev/net/tun ] && ln -s /dev/tun /dev/net/tun
    info "创建/dev/net/tun符号链接"

    if [ ! -c "/dev/net/tun" ]; then
        error "无法创建 /dev/net/tun，可能的原因："
        warn "系统不支持 TUN/TAP 驱动或内核不兼容"
        exit 1
    fi
    info "/dev/net/tun 为字符设备，检查通过"

}

mihomo_start() {
    if is_mihomo_running; then
        return 1
    else
        mihomo_tun
        mihomo &
        is_mihomo_running
    fi
}

mihomo_stop() {
    if is_mihomo_running; then
        pkill -f "mihomo"
        is_mihomo_running
    else
        return 1
    fi
}

toggle_mihomo() {
    if is_mihomo_running; then
        info "Stop and check"
        mihomo_stop
    else
        info "Start and check"
        mihomo_start
    fi
}

set_i18n "TOGGLE_MIHOMO" \
    "zh" "切换mihomo状态" \
    "en" "Toggle MiHoMo status" \
    "ja" "mihomo の状態を切り替え" \
    "ko" "mihomo 상태 전환"

set_i18n "MIHOMO_STATUS" \
    "zh" "mihomo状态" \
    "en" "MiHoMo status" \
    "ja" "mihomo の状態" \
    "ko" "mihomo 상태"

set_i18n "RUNNING" \
    "zh" "正在运行" \
    "en" "Running" \
    "ja" "実行中" \
    "ko" "실행 중"

set_i18n "NOT_RUNNING" \
    "zh" "未运行" \
    "en" "Not running" \
    "ja" "実行していません" \
    "ko" "실行 중 아님"


ask_toggle_mihomo() {
    # Ask the user to toggle MiHoMo.
    # Question key:    TOGGLE_MIHOMO
    if is_mihomo_running; then
        _mihomo_state="$(i18n 'RUNNING')"
    else
        _mihomo_state="$(i18n 'NOT_RUNNING')"
    fi
    guide "$(i18n 'MIHOMO_STATUS')" "$_mihomo_state"
    ask "TOGGLE_MIHOMO" \
        "CONFIRM" \
            'toggle_mihomo' \
        "REFUSE" \
            'exit 0' \
        0
    unset _mihomo_state
}
