# shellcheck shell=ash

kam_init_dirs() (
    [ -n "${KAM_HOME:-}" ] || {
        if command -v print >/dev/null 2>&1; then
            print 'ERROR: KAM_HOME is not set; cannot init dirs'
        else
            printf '%s\n' 'ERROR: KAM_HOME is not set; cannot init dirs' >&2
        fi
        return 1
    }
    for dir in "$KAM_HOME/.config" "$KAM_HOME/.cache" "$KAM_HOME/.state" "$KAM_HOME/.log"; do
        [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || {
            if command -v print >/dev/null 2>&1; then
                print "ERROR: failed to mkdir -p '$dir'"
            else
                printf '%s\n' "ERROR: failed to mkdir -p '$dir'" >&2
            fi
            return 1
        }
    done
    # Temporary workspaces belong to their individual owners.
    rmdir "$KAM_HOME/tmp" 2>/dev/null || true
)
