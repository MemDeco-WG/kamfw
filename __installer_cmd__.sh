# shellcheck shell=ash

installer() {
    case "${1:-}" in
        exclude) shift; install_exclude "$@" ;;
        include) shift; install_include "$@" ;;
        show) install_show_filters ;;
        check) shift; install_check "${1:-}" ;;
        run|schedule)
            _ir_action=$1
            _ir_source=${2:-}
            _ir_files=$(install_check "$_ir_source") || return 1
            _ir_count=$(__inst__count_lines "$_ir_files")
            [ "$_ir_count" -gt 0 ] || { info "$(i18n INSTALL_NO_FILES)"; return 0; }
            if [ "$_ir_action" = schedule ]; then
                __inst__register_hook "$_ir_source"
                info "$(i18n INSTALL_WILL_ON_EXIT | t "$_ir_count")"
            else
                info "$(i18n INSTALL_RUNNING_NOW | t "$_ir_count")"
                __inst__invoke_install "$_ir_source" "$_ir_files" || return 1
                info "$(i18n INSTALL_DONE)"
            fi
            ;;
        ''|help|-h|--help) print 'installer: usage: installer <exclude|include|show|check|run|schedule> [args]' ;;
        *) installer schedule "$1" ;;
    esac
}
