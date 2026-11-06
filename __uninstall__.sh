# shellcheck shell=ash

kamfw_run_uninstall_hooks() (
    result=0
    for dir in "$KAM_HOME/.config/kamfw/uninstall.d" "$KAM_HOME/lib/kamfw/uninstall.d"; do
        for hook in "$dir/"*.sh; do
            [ -f "$hook" ] || continue
            sh "$hook" "$@" || result=1
        done
    done
    return "$result"
)

kamfw_phase_uninstall() { kamfw_run_uninstall_hooks "$@"; }
