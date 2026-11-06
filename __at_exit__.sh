# shellcheck shell=ash
set_i18n "AT_EXIT_REGISTERED" \
    "zh" "已注册 at-exit 钩子" \
    "en" "At-exit hook registered" \
    "ja" "終了時フックが登録されました" \
    "ko" "종료 훅이 등록되었습니다"

set_i18n "AT_EXIT_NO_HANDLERS" \
    "zh" "没有注册任何 at-exit 处理器" \
    "en" "No at-exit handlers registered" \
    "ja" "登録された終了時ハンドラはありません" \
    "ko" "등록된 종료 훅이 없습니다"

set_i18n "AT_EXIT_RUN_START" \
    "zh" "执行 at-exit 处理器..." \
    "en" "Running at-exit handlers..." \
    "ja" "終了時ハンドラを実行します..." \
    "ko" "종료 훅 실행 중..."

set_i18n "AT_EXIT_DONE" \
    "zh" "at-exit 处理完成" \
    "en" "At-exit handlers finished" \
    "ja" "終了時ハンドラの実行が完了しました" \
    "ko" "종료 훅 실행이 완료되었습니다"

set_i18n "AT_EXIT_HANDLER_FAILED" \
    "zh" "处理器失败: %s" \
    "en" "Handler failed: %s" \
    "ja" "ハンドラ失敗: %s" \
    "ko" "훅 실패: %s"

__at_exit_installed=''
__at_exit_running=''
__at_exit_handlers=''

__at_exit_log_info() {
    if command -v info >/dev/null 2>&1; then info "$(i18n "$1")"; else print "$(i18n "$1")"; fi
}
__at_exit_log_success_t() {
    if command -v success >/dev/null 2>&1; then success "$(i18n "$1" | t "$2")"; else print "$(i18n "$1" | t "$2")"; fi
}
__at_exit_log_warn_t() {
    if command -v warn >/dev/null 2>&1; then warn "$(i18n "$1" | t "$2")"; else print "$(i18n "$1" | t "$2")"; fi
}

at_exit_add() {
    for _ae_command in "$@"; do
        case "
${__at_exit_handlers:-}
" in
            *"
$_ae_command
"*) ;;
            *) __at_exit_handlers="${__at_exit_handlers}${__at_exit_handlers:+
}$_ae_command" ;;
        esac
    done
}

at_exit_remove() {
    _ae_remaining=''
    while IFS= read -r _ae_handler; do
        [ -n "$_ae_handler" ] || continue
        _ae_keep=1
        for _ae_remove in "$@"; do [ "$_ae_handler" != "$_ae_remove" ] || _ae_keep=0; done
        [ "$_ae_keep" = 1 ] || continue
        _ae_remaining="${_ae_remaining}${_ae_remaining:+
}$_ae_handler"
    done <<HANDLERS
${__at_exit_handlers:-}
HANDLERS
    __at_exit_handlers=$_ae_remaining
    unset _ae_remaining _ae_handler _ae_keep _ae_remove
}

at_exit_list() {
    if [ -n "${__at_exit_handlers:-}" ]; then print "$__at_exit_handlers"; else print "$(i18n AT_EXIT_NO_HANDLERS)"; fi
}
at_exit_clear() { unset __at_exit_handlers; }

__at_exit_run_handlers() {
    [ -n "${__at_exit_handlers:-}" ] || return 0
    __at_exit_log_info AT_EXIT_RUN_START
    while IFS= read -r _ae_handler; do
        [ -n "$_ae_handler" ] || continue
        eval "$_ae_handler" || __at_exit_log_warn_t AT_EXIT_HANDLER_FAILED "$_ae_handler"
    done <<HANDLERS
$__at_exit_handlers
HANDLERS
    __at_exit_log_info AT_EXIT_DONE
}

__at_exit_master_handler() {
    [ -z "${__at_exit_running:-}" ] || return 0
    __at_exit_running=1
    if [ -n "${__at_exit_handlers:-}" ]; then
        __at_exit_run_handlers || warn 'WARN: __at_exit_run_handlers failed unexpectedly'
    else
        __at_exit_log_info AT_EXIT_NO_HANDLERS
    fi
    unset __at_exit_running
}

at_exit_register_trap() {
    [ -z "${__at_exit_installed:-}" ] || return 0
    trap '__at_exit_master_handler' EXIT
    __at_exit_installed=1
    [ ! -t 1 ] || __at_exit_log_info AT_EXIT_REGISTERED
}

at_exit_unregister_trap() {
    [ -n "${__at_exit_installed:-}" ] || return 0
    trap - EXIT 2>/dev/null || warn 'WARN: failed to clear EXIT trap'
    unset __at_exit_installed
}
