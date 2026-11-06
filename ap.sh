# shellcheck shell=ash
[ ! -d "$MODDIR/META-INF" ] || rm -rf "$MODDIR/META-INF"

install_module() (
    [ -f "${1:-}" ] || return 1
    manager=$(command -v apd 2>/dev/null) || manager=/data/adb/apd
    "$manager" module install "$1"
)
