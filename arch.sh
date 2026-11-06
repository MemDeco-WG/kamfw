# shellcheck shell=ash

support_arch() {
    for _kam_arch in "$@"; do
        case "$_kam_arch" in
            arm|arm64|x86|x64) [ "${ARCH:-}" != "$_kam_arch" ] || return 0 ;;
            *) abort 'out of range [ arm, arm64, x86, x64 ]' ;;
        esac
    done
    abort 'architecture not supported'
}

is_arch() {
    for _kam_arch in "$@"; do
        case "$_kam_arch" in
            arm|arm64|x86|x64) [ "${ARCH:-}" != "$_kam_arch" ] || return 0 ;;
        esac
    done
    return 1
}
