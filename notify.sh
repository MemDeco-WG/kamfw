# shellcheck shell=ash
set_i18n "NOTIFY_TAG_REQUIRED" \
	"zh" "notify: tag 不能为空" \
	"en" "notify: tag is required" \
	"ja" "notify: tag が必要です" \
	"ko" "notify: tag 가 필요합니다"

set_i18n "NOTIFY_TITLE_REQUIRED" \
	"zh" "notify: 标题不能为空" \
	"en" "notify: title is required" \
	"ja" "notify: タイトルが必要です" \
	"ko" "notify: 제목이 필요합니다"

set_i18n "NOTIFY_TEXT_REQUIRED" \
	"zh" "notify: 内容不能为空" \
	"en" "notify: text is required" \
	"ja" "notify: 内容が必要です" \
	"ko" "notify: 내용이 필요합니다"

set_i18n "NOTIFY_TOOL_MISSING" \
	"zh" "notify: 缺少必需工具: \$_1" \
	"en" "notify: required command not found: \$_1" \
	"ja" "notify: 必要なコマンドがありません: \$_1" \
	"ko" "notify: 필수 명령이 없습니다: \$_1"

set_i18n "NOTIFY_POSTED" \
	"zh" "通知已发送: \$_1" \
	"en" "notification posted: \$_1" \
	"ja" "通知を送信しました: \$_1" \
	"ko" "알림 게시됨: \$_1"

set_i18n "NOTIFY_POST_FAILED" \
	"zh" "通知发送失败: \$_1" \
	"en" "notification failed: \$_1" \
	"ja" "通知の送信に失敗しました: \$_1" \
	"ko" "알림 실패: \$_1"

set_i18n "NOTIFY_EXPANDED" \
	"zh" "通知栏已展开" \
	"en" "notification shade expanded" \
	"ja" "通知シェードを展開しました" \
	"ko" "알림 창 펼쳐짐"

set_i18n "NOTIFY_EXPAND_FAILED" \
	"zh" "通知栏展开失败" \
	"en" "failed to expand notification shade" \
	"ja" "通知シェードの展開に失敗しました" \
	"ko" "알림 창 펼치기 실패"

notify_require_cmd() {
    command -v cmd >/dev/null 2>&1 || { error "$(i18n NOTIFY_TOOL_MISSING | t cmd)"; return 1; }
}
notify_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
notify_run_as_shell() {
    [ "${KAM_NOTIFY_AS_SHELL:-1}" = 1 ] && command -v su >/dev/null 2>&1 || return 1
    su shell -c "$1" 2>/dev/null
}

_notify_post_attempts() (
    tag=$1 title=$2 text=$3
    style=${KAM_NOTIFY_STYLE:-bigtext}
    icon=${KAM_NOTIFY_ICON:-@android:drawable/stat_notify_error}
    for runner in shell direct; do
        for with_icon in yes no; do
            set -- cmd notification post
            [ "${KAM_NOTIFY_VERBOSE:-0}" != 1 ] || set -- "$@" -v
            set -- "$@" -S "$style"
            [ "$with_icon" != yes ] || set -- "$@" -i "$icon"
            set -- "$@" -t "$title" "$tag" "$text"
            if [ "$runner" = direct ]; then
                "$@" && return 0
            else
                command=''
                for argument in "$@"; do command="$command $(notify_quote "$argument")"; done
                notify_run_as_shell "$command" && return 0
            fi
        done
    done
    return 1
)

notify_post_cmd() {
    if [ "${KAM_NOTIFY_VERBOSE:-0}" = 1 ]; then _notify_post_attempts "$@"
    else _notify_post_attempts "$@" >/dev/null 2>&1; fi
}

notify_post() {
    [ -n "${1:-}" ] || { error "$(i18n NOTIFY_TAG_REQUIRED)"; return 2; }
    [ -n "${2:-}" ] || { error "$(i18n NOTIFY_TITLE_REQUIRED)"; return 2; }
    _np_tag=$1 _np_title=$2
    shift 2
    [ -n "$*" ] || { error "$(i18n NOTIFY_TEXT_REQUIRED)"; return 2; }
    notify_require_cmd || return 1
    if notify_post_cmd "$_np_tag" "$_np_title" "$*"; then
        success "$(i18n NOTIFY_POSTED | t "$_np_tag")"
    else
        error "$(i18n NOTIFY_POST_FAILED | t "$_np_tag")"
        return 1
    fi
}

notify_expand() {
    notify_require_cmd || return 1
    if cmd statusbar expand-notifications >/dev/null 2>&1; then success "$(i18n NOTIFY_EXPANDED)"
    else error "$(i18n NOTIFY_EXPAND_FAILED)"; return 1; fi
}
notify_alert() {
    notify_post "$@" || return $?
    notify_expand >/dev/null 2>&1 || true
}
notify_test() { notify_alert kamfw_notify_test 'Kam Test' "kamfw notification test at $(date +%H:%M:%S)"; }
notify() {
    case "${1:-}" in
        post) shift; notify_post "$@" ;;
        alert) shift; notify_alert "$@" ;;
        expand) notify_expand ;;
        test) notify_test ;;
        *)
            print 'Usage: notify post <tag> <title> <text...>'
            print '       notify alert <tag> <title> <text...>'
            print '       notify expand'
            print '       notify test'
            return 2
            ;;
    esac
}
