# shellcheck shell=ash

install_module() {
    _im_zip="$1"
    [ -f "$_im_zip" ] || return 1

    _im_type=$(get_manager)

    case "$_im_type" in
        magisk)
            magisk --install-module "$_im_zip"
            ;;
        ksu)
            _im_bin=$(command -v ksud || echo "/data/adb/ksud")
            "$_im_bin" module install "$_im_zip"
            ;;
        ap)
            _im_bin=$(command -v apd || echo "/data/adb/apd")
            "$_im_bin" module install "$_im_zip"
            ;;
        *)
            error "No module manager detected!"
            return 1
            ;;
    esac

    unset _im_zip _im_type _im_bin
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
