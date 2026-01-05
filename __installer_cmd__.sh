# shellcheck shell=ash
#
# CLI entry for installer operations
#
# This module provides the `installer` command (small surface) so the main
# installer helper file can remain compact and single-responsibility.
#
# Usage:
#   installer <exclude|include|show|check|run|schedule> [args]
#
# Note: This function delegates to the core helpers in `__install_core__`
# (file listing, extraction, install-on-exit). It assumes those helpers are
# already available in the runtime environment (via `import __install_core__`).
#
installer() {
    cmd="$1"
    shift || true

    case "$cmd" in
    exclude)
        install_exclude "$@"
        return 0
        ;;
    include)
        install_include "$@"
        return 0
        ;;
    show)
        install_show_filters
        return 0
        ;;
    check)
        install_check "$1"
        return $?
        ;;
    run)
        src="$1"
        files="$(install_check "$src" 2>/dev/null || true)"
        cnt="$(__inst__count_lines "$files")"

        [ "$cnt" -eq 0 ] && {
            _msg="$(i18n 'INSTALL_NO_FILES' 2>/dev/null)"; [ -n "$_msg" ] || _msg="No files to install"; info "$_msg"
            return 0
        }

        info "$(i18n 'INSTALL_RUNNING_NOW' 2>/dev/null | t "$cnt" 2>/dev/null || printf 'Installing %s files now' "$cnt")"
        __inst__invoke_install "$src"
        _msg="$(i18n 'INSTALL_DONE' 2>/dev/null)"; [ -n "$_msg" ] || _msg="Install completed"; info "$_msg"
        return 0
        ;;
    schedule)
        src="$1"
        files="$(install_check "$src" 2>/dev/null || true)"
        cnt="$(__inst__count_lines "$files")"

        [ "$cnt" -eq 0 ] && {
            info "$(i18n 'INSTALL_NO_FILES' 2>/dev/null || echo 'No files to install')"
            return 0
        }

        __inst__register_hook
        info "$(i18n 'INSTALL_WILL_ON_EXIT' 2>/dev/null | t "$cnt" 2>/dev/null || printf 'Will install %s files on exit' "$cnt")"
        return 0
        ;;
    "" | help | -h | --help)
        print "installer: usage: installer <exclude|include|show|check|run|schedule> [args]"
        return 0
        ;;
    *)
        # Backwards-compatible behavior: treat unrecognized argument as <src> to schedule.
        installer schedule "$cmd"
        return $?
        ;;
    esac
}
