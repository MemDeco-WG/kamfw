# shellcheck shell=ash

support_arch() {
    _arch="$@"
    _flag=false
    for _arch in "$@"; do
        case "$_arch" in
            arm64|x64|arm|x86)
                ;;
            *)
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
}
