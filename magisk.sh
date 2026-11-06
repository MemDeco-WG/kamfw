# shellcheck shell=ash

kam_magisk_prepare_installer() (
    [ ! -f "$MODDIR/boot-completed.sh" ] || mv "$MODDIR/boot-completed.sh" "$MODDIR/service.sh" || return 1
    dir="$MODDIR/META-INF/com/google/android"
    mkdir -p "$dir" || return 1
    [ -f "$dir/updater-script" ] || printf '%s\n' '#MAGISK' >"$dir/updater-script" || return 1
    [ ! -f "$dir/update-binary" ] || return 0
    cat >"$dir/update-binary" <<'INSTALLER'
#!/sbin/sh
umask 022
require_new_magisk() {
    printf '%s\n' '*******************************' ' Please install Magisk v20.4+! ' '*******************************' >&2
    exit 1
}
OUTFD=$2
ZIPFILE=$3
mount /data 2>/dev/null
[ -f /data/adb/magisk/util_functions.sh ] || require_new_magisk
. /data/adb/magisk/util_functions.sh
[ "$MAGISK_VER_CODE" -ge 20400 ] || require_new_magisk
install_module
INSTALLER
)

install_module() {
    [ -f "${1:-}" ] && magisk --install-module "$1"
}
