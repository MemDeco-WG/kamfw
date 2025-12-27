# shellcheck shell=ash

if is_magisk; then
    import magisk
fi

if is_ksu; then
    import ksu
fi

if is_ap; then
    import ap
fi

ui_print() {
    print "$@"
}

require_module() {
    _module_id="$1"
    if [ -z "$_module_id" ]; then
        abort "! Module ID is required!"
    fi
    _msg="${2:-Module $1 is required!}"

    if [ -d "/data/adb/modules/$_module_id" ] && [ -f "/data/adb/modules/$_module_id/module.prop" ] && [ ! -f "/data/adb/modules/$_module_id/remove" ]; then
        unset _module_id _msg
        return 0
    else
        abort "$_msg"
    fi
}

conflict_module() {
    _module_id="$1"
    if [ -z "$_module_id" ]; then
        abort "! Module ID is required!"
    fi
    _msg="${2:-Module $1 conflicts with this module!}"

    if [ -d "/data/adb/modules/$_module_id" ] && [ -f "/data/adb/modules/$_module_id/module.prop" ] && [ ! -f "/data/adb/modules/$_module_id/remove" ]; then
        abort "$_msg"
    else
        unset _module_id _msg
        return 0
    fi
}

module_exists() {
    _module_id="$1"
    [ -d "/data/adb/modules/$_module_id" ] && [ -f "/data/adb/modules/$_module_id/module.prop" ] && [ ! -f "/data/adb/modules/$_module_id/remove" ]
}

# kam install
# kam manager
kam (){
    _kam_cmd="$1"
    shift

    case "$_kam_cmd" in
        install)
            install_module "$@"
            ;;
        manager)
            get_manager
            ;;
        *)
            error "Invalid command!"
            return 1
            ;;
    esac

    unset _kam_cmd
}

