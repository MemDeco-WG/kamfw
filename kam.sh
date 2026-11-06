# shellcheck shell=ash
import __runtime__
import init_dirs
kam_init_dirs

case "$(get_manager)" in
    magisk) import magisk ;;
    ksud) import ksu ;;
    ap) import ap ;;
esac

module_exists() {
    [ -n "${1:-}" ] && [ -d "/data/adb/modules/$1" ] &&
        [ -f "/data/adb/modules/$1/module.prop" ] &&
        [ ! -f "/data/adb/modules/$1/remove" ]
}

require_module() {
    [ -n "${1:-}" ] || abort '! Module ID is required!'
    module_exists "$1" || abort "${2:-Module $1 is required!}"
}

conflict_module() {
    [ -n "${1:-}" ] || abort '! Module ID is required!'
    if module_exists "$1"; then abort "${2:-Module $1 conflicts with this module!}"; fi
}

kam() {
    case "${1:-}" in
        install) shift; install_module "$@" ;;
        manager) get_manager ;;
        *) kamfw "$@" ;;
    esac
}
