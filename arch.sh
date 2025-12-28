# shellcheck shell=ash

support_arch() {
    _arch="$@"
    _flag=false
    for _arch in "$@"; do
        case "$_arch" in
            arm|arm64|x86|x64)
                ;;
            *)
                unset _arch _flag
                abort "out of range [ arm, arm64, x86, x64 ]"
                ;;
        esac
        if [ "$ARCH" = "$_arch" ]; then
            _flag=true
            break
        fi
    done

    if [ "$_flag" = false ]; then
        unset _arch _flag
        abort "architecture not supported"
    fi

    unset _arch _flag
}
