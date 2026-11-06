# shellcheck shell=ash

kamfw_init_home() {
    : "${MODDIR:=${0%/*}}"
    export MODDIR KAM_HOME="$MODDIR" HOME="$MODDIR"
    kam_init_dirs
}

kamfw_init_paths() {
    export PATH="$MODDIR/bin:/data/adb/magisk:/data/adb/ksu/bin:/system/bin:/system/xbin:/sbin"
    export LD_LIBRARY_PATH="$MODDIR/lib"
}

kamfw() {
    case "${1:-help}" in
        run) shift; kamfw_run "$@" ;;
        help|-h|--help) printf '%s\n' 'Usage: kamfw run <phase> -- [args...]' ;;
        *) error "Invalid kamfw command: $1" || abort "Invalid kamfw command: $1"; return 1 ;;
    esac
}

kamfw_run() {
    [ -n "${1:-}" ] || { error 'Missing phase' || abort 'Missing phase'; return 2; }
    _kamfw_phase=$1
    shift
    [ "${1:-}" != -- ] || shift
    kamfw_init_home || return 1
    kamfw_init_paths
    case "$_kamfw_phase" in
        install) import __install_core__ && kamfw_phase_install "$@" ;;
        post-fs-data) kamfw_phase_post_fs_data "$@" ;;
        service) kamfw_phase_service "$@" ;;
        boot-completed) kamfw_phase_boot_completed "$@" ;;
        uninstall) import __uninstall__ && kamfw_phase_uninstall "$@" ;;
        action) kamfw_phase_action "$@" ;;
        post-mount) kamfw_phase_post_mount "$@" ;;
        *) error "Unknown phase: $_kamfw_phase" || abort "Unknown phase: $_kamfw_phase"; return 2 ;;
    esac
}

kamfw_phase_install() { :; }
kamfw_phase_post_fs_data() { :; }
kamfw_phase_service() { :; }
kamfw_phase_boot_completed() { :; }
kamfw_phase_uninstall() { :; }
kamfw_phase_action() { :; }
kamfw_phase_post_mount() { :; }
