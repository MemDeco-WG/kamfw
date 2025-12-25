# shellcheck shell=ash

# Unified configuration helper
# - When running under KernelSU (is_ksu), forwards to `ksud module config ...`
# - Otherwise uses a lightweight file-backed fallback (persist + tmp) with the
#   same CLI semantics (get/set/list/delete/clear) and supports --temp and --stdin.
#
# Usage (same as ksud):
#   config get <key>
#   config set [--temp] [--stdin] <key> [value]
#   config list
#   config delete [--temp] <key>
#   config clear [--temp]
config() {
    _cmd="$1"
    [ -n "$_cmd" ] && shift

    # Help / usage
    if [ -z "$_cmd" ] || [ "$_cmd" = "help" ]; then
        cat <<'EOF'
Usage:
  config get <key>
  config set [--temp] [--stdin] <key> [value]
  config list
  config delete [--temp] <key>
  config clear [--temp]
EOF
        return 0
    fi

    # If KernelSU is present, delegate directly to ksud (preserve the behavior)
    if is_ksu; then
        _ksud_bin=$(command -v ksud || echo "/data/adb/ksud")
        # Ensure KSU_MODULE is set when possible so ksud knows which module to operate on
        if [ -z "${KSU_MODULE:-}" ] && [ -n "${MODDIR:-}" ] && [ -f "$MODDIR/module.prop" ]; then
            _ksu_id=$(sed -n 's/^id=//p' "$MODDIR/module.prop" | head -n1)
            [ -n "$_ksu_id" ] && export KSU_MODULE="$_ksu_id"
        fi
        "$_ksud_bin" module config "$_cmd" "$@"
        return $?
    fi

    # --- Fallback implementation (file-backed) ---

    # Determine module id (prefer KSU_MODULE, then module.prop id, then MODDIR basename)
    _module_id="${KSU_MODULE:-}"
    if [ -z "$_module_id" ] && [ -n "${MODDIR:-}" ] && [ -f "$MODDIR/module.prop" ]; then
        _module_id=$(sed -n 's/^id=//p' "$MODDIR/module.prop" | head -n1)
    fi
    if [ -z "$_module_id" ] && [ -n "${MODDIR:-}" ]; then
        _module_id="${MODDIR##*/}"
    fi
    if [ -z "$_module_id" ]; then
        error "Unable to determine module id for config fallback"
        return 1
    fi

    # Validate module id to avoid path traversal / invalid filenames
    _len=${#_module_id}
    if [ "$_len" -lt 1 ] || [ "$_len" -gt 128 ]; then
        error "Invalid module id length: $_len"
        return 1
    fi
    case "$_module_id" in
        [A-Za-z][A-Za-z0-9._-]* ) ;;
        * )
            error "Invalid module id: $_module_id"
            return 1
            ;;
    esac

    # Use KernelSU path for storage
    _root="/data/adb/ksu/module_configs"
    _store="$_root/$_module_id"
    mkdir -p "$_store" || {
        error "Unable to create config directory: $_store"
        return 1
    }
    # Restrict directory permissions (owner-only) to avoid accidental exposure
    chmod 0700 "$_store" 2>/dev/null || true

    _persist="$_store/persist"
    _tmp="$_store/tmp"
    mkdir -p "$_persist" "$_tmp" || {
        error "Unable to create config persist/tmp directories: $_persist $_tmp"
        return 1
    }
    chmod 0700 "$_persist" "$_tmp" 2>/dev/null || true

    # Validate key according to ^[a-zA-Z][a-zA-Z0-9._-]+$ and length constraints
    _validate_key() {
        _k="$1"
        if [ -z "$_k" ]; then
            error "Key cannot be empty"
            return 1
        fi
        _len=${#_k}
        if [ "$_len" -lt 2 ] || [ "$_len" -gt 256 ]; then
            error "Key length must be between 2 and 256 characters"
            return 1
        fi
        case "$_k" in
            [A-Za-z][A-Za-z0-9._-]* ) return 0 ;;
            * )
                error "Invalid key format. Must match ^[a-zA-Z][a-zA-Z0-9._-]+$"
                return 1
                ;;
        esac
    }

    # Count unique keys across persist + tmp
    _count_entries() {
        _a=$(ls -1 "$_persist" 2>/dev/null || true)
        _b=$(ls -1 "$_tmp" 2>/dev/null || true)
        _both=$(printf '%s\n%s\n' "$_a" "$_b" | awk NF | sort -u 2>/dev/null || true)
        if [ -z "$_both" ]; then
            printf '0'
        else
            printf '%s' "$_both" | wc -l
        fi
    }

    case "$_cmd" in
        get)
            _key="$1"
            [ -n "$_key" ] || { error "Missing key"; return 1; }
            _validate_key "$_key" || return 1
            if [ -f "$_tmp/$_key" ]; then
                cat "$_tmp/$_key"
                return 0
            elif [ -f "$_persist/$_key" ]; then
                cat "$_persist/$_key"
                return 0
            else
                return 1
            fi
            ;;
        set)
            _temp=false
            _stdin=false
            # Parse flags for set
            while [ $# -gt 0 ]; do
                case "$1" in
                    --temp) _temp=true; shift ;;
                    --stdin) _stdin=true; shift ;;
                    --) shift; break ;;
                    *) break ;;
                esac
            done

            _key="$1"; shift || _key=""
            [ -n "$_key" ] || { error "Missing key"; return 1; }
            _validate_key "$_key" || return 1

            # Prepare value into a temp file (support --stdin or piped/missing value)
            _tf=$(mktemp) || {
                error "mktemp command failed"
                return 1
            }
            # Ensure the temporary file is owner-only (defensive)
            chmod 0600 "$_tf" 2>/dev/null || true

            if [ "$_stdin" = true ]; then
                cat - > "$_tf"
            elif [ $# -eq 0 ] && [ ! -t 0 ]; then
                cat - > "$_tf"
            else
                if [ $# -gt 0 ]; then
                    printf '%s' "$*" > "$_tf"
                else
                    rm -f "$_tf" 2>/dev/null || true
                    error "Missing value for set"
                    return 1
                fi
            fi

            _size=$(wc -c < "$_tf" 2>/dev/null | tr -d ' ')
            if [ -z "$_size" ]; then _size=0; fi
            if [ "$_size" -gt 1048576 ]; then
                rm -f "$_tf" 2>/dev/null || true
                error "Value too large (max 1048576 bytes)"
                return 1
            fi

            # Enforce max entries (32 unique keys)
            _exists=false
            if [ -f "$_persist/$_key" ] || [ -f "$_tmp/$_key" ]; then
                _exists=true
            fi
            _count=$(_count_entries)
            if [ "$_exists" = false ] && [ "$_count" -ge 32 ]; then
                rm -f "$_tf" 2>/dev/null || true
                error "Maximum config entries (32) reached"
                return 1
            fi

            if [ "$_temp" = true ]; then
                mv -f "$_tf" "$_tmp/$_key" 2>/dev/null || ( cp -f "$_tf" "$_tmp/$_key" 2>/dev/null && rm -f "$_tf" )
                # Ensure the stored file is owner-only
                chmod 0600 "$_tmp/$_key" 2>/dev/null || true
            else
                mv -f "$_tf" "$_persist/$_key" 2>/dev/null || ( cp -f "$_tf" "$_persist/$_key" 2>/dev/null && rm -f "$_tf" )
                # Ensure the stored file is owner-only
                chmod 0600 "$_persist/$_key" 2>/dev/null || true
            fi
            return 0
            ;;
        list)
            _a=$(ls -1 "$_persist" 2>/dev/null || true)
            _b=$(ls -1 "$_tmp" 2>/dev/null || true)
            _both=$(printf '%s\n%s\n' "$_a" "$_b" | awk NF | sort -u 2>/dev/null || true)
            for _k in $_both; do
                if [ -f "$_tmp/$_k" ]; then
                    printf '%s=' "$_k"
                    cat "$_tmp/$_k"
                else
                    printf '%s=' "$_k"
                    cat "$_persist/$_k"
                fi
            done
            return 0
            ;;
        delete)
            _temp=false
            if [ "$1" = "--temp" ]; then _temp=true; shift; fi
            _key="$1"
            [ -n "$_key" ] || { error "Missing key"; return 1; }
            _validate_key "$_key" || return 1
            if [ "$_temp" = true ]; then
                rm -f "$_tmp/$_key" 2>/dev/null || true
            else
                rm -f "$_tmp/$_key" "$_persist/$_key" 2>/dev/null || true
            fi
            return 0
            ;;
        clear)
            _temp=false
            if [ "$1" = "--temp" ]; then _temp=true; fi
            if [ "$_temp" = true ]; then
                rm -f "$_tmp"/* 2>/dev/null || true
            else
                rm -f "$_persist"/* 2>/dev/null || true
            fi
            return 0
            ;;
        *)
            error "Unknown command: $_cmd"
            return 1
            ;;
    esac
}
