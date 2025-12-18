# shellcheck shell=ash

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
