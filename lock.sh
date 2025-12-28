# shellcheck shell=ash
#
# kamfw - kam.lock utilities
#
# Responsibilities:
#  - provide a simple, robust locking primitive for /data/adb/kam operations
#  - maintain a small kam.lock metadata file
#  - support rebuild/GC of object pool to remove garbage
#
# Design notes:
#  - Lock implementation is mkdir-based (atomic) on a lock directory,
#    the lock metadata is written to /data/adb/kam/kam.lock.
#  - Use object-pool layout:
#      /data/adb/kam/objects/<sha256>           (canonical object blob)
#      /data/adb/kam/providers/<kind>/<name>/<modid>   (hardlink to object)
#      /data/adb/kam/<kind>/<name>              (global hardlink to object)
#
# Usage (examples):
#   . /data/adb/modules/asl/lib/kamfw/lock.sh
#   kam_lock_acquire 30 || abort 'lock failed'
#   ... perform install/uninstall operations ...
#   kam_lock_release
#
######################################################################

# Configurable variables (can be overridden by caller)
KAM_DIR="${KAM_DIR:-/data/adb/kam}"
KAM_LOCK_FILE="${KAM_LOCK_FILE:-${KAM_DIR}/kam.lock}"
KAM_LOCK_DIR="${KAM_LOCK_DIR:-${KAM_DIR}/.kam_lockdir}"  # internal lock directory
KAM_LOCK_WAIT="${KAM_LOCK_WAIT:-30}"    # seconds to wait for lock acquisition
KAM_LOCK_STALE="${KAM_LOCK_STALE:-3600}" # seconds after which a lock is considered stale (1 hour)

# internal utilities
_kam_log() {
    printf '%s\n' "$@" >&2
}

_kam_now() {
    date +%s 2>/dev/null || echo "$(perl -e 'print time')" 2>/dev/null || echo "$(python -c 'import time; print(int(time.time()))')" 2>/dev/null || echo 0
}

_kam_pid_alive() {
    _pid="$1"
    [ -z "$_pid" ] && return 1
    kill -0 "$_pid" >/dev/null 2>&1 && return 0 || return 1
}

# Compute sha256 hash of a file and print it to stdout.
# Returns 0 and prints the hex hash when successful. Returns non-zero when
# no hashing tool is available or when hashing is explicitly disabled by
# setting KAMFW_FORCE_NO_HASH=1 (useful for tests/environments).
get_hash() {
    _file="$1"
    # Allow tests or deployments to force "no hash available" behavior.
    if [ "${KAMFW_FORCE_NO_HASH:-0}" -eq 1 ]; then
        return 1
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$_file" | awk '{print $1}'
        return 0
    elif command -v openssl >/dev/null 2>&1; then
        # openssl prints something like "SHA256(filename)= <hash>", so take the last token
        openssl dgst -sha256 "$_file" | awk '{print $NF}'
        return 0
    else
        # No supported hash tool available
        return 1
    fi
}

# Write lock metadata. Called only by successful acquirer.
_kam_write_lock_meta() {
    _owner_pid="$1"
    _when="$2"
    _who="${3:-unknown}"
    mkdir -p "${KAM_DIR}" 2>/dev/null || true
    {
        printf 'pid:%s\n' "$_owner_pid"
        printf 'ts:%s\n' "$_when"
        printf 'who:%s\n' "$_who"
    } > "${KAM_LOCK_FILE}.tmp" && mv -f "${KAM_LOCK_FILE}.tmp" "${KAM_LOCK_FILE}"
    chmod 0600 "${KAM_LOCK_FILE}" 2>/dev/null || true
}

# Read lock metadata; exports LOCK_PID LOCK_TS LOCK_WHO (caller can inspect)
_kam_read_lock_meta() {
    LOCK_PID=""
    LOCK_TS=""
    LOCK_WHO=""
    [ -f "${KAM_LOCK_FILE}" ] || return 1
    while IFS= read -r _line; do
        case "$_line" in
            pid:*) LOCK_PID="${_line#pid:}" ;;
            ts:*) LOCK_TS="${_line#ts:}" ;;
            who:*) LOCK_WHO="${_line#who:}" ;;
        esac
    done <"${KAM_LOCK_FILE}"
    return 0
}

# Acquire the global kam lock.
# Usage: kam_lock_acquire [timeout_seconds] [who-string]
# Returns: 0 on success (lock held), nonzero on failure.
kam_lock_acquire() {
    _timeout="${1:-$KAM_LOCK_WAIT}"
    _who="${2:-$$}"
    _now=$( _kam_now )
    _deadline=$(( _now + _timeout ))

    # Re-entrancy: if lock directory already exists and is owned by this PID,
    # treat the lock as already held and return success.
    if [ -d "${KAM_LOCK_DIR}" ]; then
        _kam_read_lock_meta 2>/dev/null || true
        if [ "${LOCK_PID:-}" = "$$" ]; then
            # Already held by this process — re-entrant acquire
            return 0
        fi
    fi

    while true; do
        # Try to create lock directory atomically
        if mkdir "${KAM_LOCK_DIR}" 2>/dev/null; then
            # we got it; write metadata
            _ts=$(_kam_now)
            _kam_write_lock_meta "$$" "$_ts" "$_who"
            return 0
        fi

        # Could not create - inspect what's holding it
        if _kam_read_lock_meta; then
            # LOCK_PID, LOCK_TS available
            : # we have variables
        else
            LOCK_PID=""
            LOCK_TS=""
            LOCK_WHO=""
        fi

        # If lock seems stale, try to take it
        now=$(_kam_now)
        if [ -n "$LOCK_TS" ] && [ "$now" -ge $((LOCK_TS + KAM_LOCK_STALE)) ]; then
            # if pid no longer exists, take it over
            if [ -n "$LOCK_PID" ] && ! _kam_pid_alive "$LOCK_PID"; then
                _kam_log "kam.lock: stale lock by pid ${LOCK_PID} (ts ${LOCK_TS}), taking over"
                # attempt to remove stale lockdir (only succeed if empty)
                rmdir "${KAM_LOCK_DIR}" 2>/dev/null || rm -rf "${KAM_LOCK_DIR}" 2>/dev/null || true
                # and try again next loop
                sleep 0.2
                continue
            fi
        fi

        # Timeout?
        now=$(_kam_now)
        if [ "$now" -ge "$_deadline" ]; then
            _kam_log "kam.lock: acquire timeout (waited ${_timeout}s), held by pid ${LOCK_PID:-(unknown)}"
            return 2
        fi

        sleep 0.2
    done
}

# Release the global kam lock.
# Usage: kam_lock_release [force]
# Returns 0 on success, nonzero on failure.
kam_lock_release() {
    _force="${1:-0}"
    # check ownership
    _kam_read_lock_meta
    _owner="${LOCK_PID:-}"
    if [ -z "$_owner" ]; then
        # no metadata, try to remove dir directly
        rmdir "${KAM_LOCK_DIR}" 2>/dev/null && return 0
        rm -rf "${KAM_LOCK_DIR}" 2>/dev/null || true
        [ -d "${KAM_LOCK_DIR}" ] && return 1 || return 0
    fi
    if [ "$_owner" = "$$" ] || [ "$_force" != "0" ]; then
        _ts=$(_kam_now)
        # Make release idempotent for the same PID: avoid appending duplicate
        # released_by/released_at entries if this PID already recorded a release.
        _releaser="$$"
        if ! grep -q "^released_by:${_releaser}$" "${KAM_LOCK_FILE}" 2>/dev/null; then
            {
                printf 'released_by:%s\n' "$_releaser"
                printf 'released_at:%s\n' "$_ts"
            } >> "${KAM_LOCK_FILE}" 2>/dev/null || true
        fi
        rm -rf "${KAM_LOCK_DIR}" 2>/dev/null || true
        return 0
    else
        _kam_log "kam.lock: current pid $$ not owner (${_owner}), use kam_lock_release force to override"
        return 3
    fi
}

# Run a command while holding the lock (acquire -> run -> release)
# Usage: kam_lock_run [timeout_seconds] -- cmd args...
kam_lock_run() {
    _timeout="${1:-$KAM_LOCK_WAIT}"
    shift || true
    # support the optional '--' separator
    if [ "$1" = "--" ]; then shift; fi
    if ! kam_lock_acquire "$_timeout" "$0"; then
        _kam_log "kam.lock: failed to acquire lock for command: $*"
        return 1
    fi
    # run command
    "$@"
    _rc=$?
    # always attempt release (best-effort)
    kam_lock_release || true
    return $_rc
}

# Rebuild provider/object relationship and fix inconsistencies.
# This function will:
#  - ensure every provider file has a corresponding object (by content hash)
#  - create missing objects
#  - ensure global targets are hardlinked to the object
# Notes: safe to call even when the current process already holds the kam lock;
# the function detects ownership and will avoid re-acquiring the lock.
kam_lock_rebuild_locked() {
    _objects_dir="${KAM_DIR}/objects"
    _providers_root="${KAM_DIR}/providers"
    mkdir -p "$_objects_dir" "$_providers_root"

    # iterate providers: for each provider entry compute hash and ensure object exists
    if [ -d "$_providers_root" ]; then
        for _kind_dir in "$_providers_root"/*; do
            [ -d "$_kind_dir" ] || continue
            for _name_dir in "$_kind_dir"/*; do
                [ -d "$_name_dir" ] || continue
                for _provider in "$_name_dir"/*; do
                    [ -e "$_provider" ] || continue
                    # compute hash
                    if _h=$(get_hash "$_provider") 2>/dev/null; then
                        _obj="${_objects_dir}/${_h}"
                        if [ ! -e "$_obj" ]; then
                            # try to create object from provider (prefer hardlink)
                            if ! ln "$_provider" "$_obj" 2>/dev/null; then
                                cp -a "$_provider" "$_obj"
                            fi
                        fi
                        # ensure provider is hardlink to object (if possible)
                        if ! cmp -s "$_provider" "$_obj" 2>/dev/null; then
                            # contents differ unexpectedly; replace provider with object copy
                            rm -f "$_provider"
                            if ! ln "$_obj" "$_provider" 2>/dev/null; then
                                cp -a "$_obj" "$_provider"
                            fi
                        else
                            # if provider exists but not same inode, relink to object to keep nlink accurate
                            if ! [ "$(ls -i "$_provider" | awk '{print $1}')" = "$(ls -i "$_obj" | awk '{print $1}')" ]; then
                                rm -f "$_provider"
                                if ! ln "$_obj" "$_provider" 2>/dev/null; then
                                    cp -a "$_obj" "$_provider"
                                fi
                            fi
                        fi
                    else
                        # no hash tool; skip this provider
                        continue
                    fi
                done
            done
        done
    fi

    # Ensure global targets point to an object (hardlink)
    for _kind in bin lib; do
        _target_dir="${KAM_DIR}/${_kind}"
        [ -d "$_target_dir" ] || continue
        for _t in "$_target_dir"/*; do
            [ -e "$_t" ] || continue
            if _h=$(get_hash "$_t") 2>/dev/null; then
                _obj="${_objects_dir}/${_h}"
                if [ -e "$_obj" ]; then
                    # if not same inode, relink
                    if ! [ "$(ls -i "$_t" | awk '{print $1}')" = "$(ls -i "$_obj" | awk '{print $1}')" ]; then
                        rm -f "$_t"
                        if ! ln "$_obj" "$_t" 2>/dev/null; then
                            cp -a "$_obj" "$_t"
                        fi
                    fi
                else
                    # create object from file and relink
                    if ! ln "$_t" "$_obj" 2>/dev/null; then
                        cp -a "$_t" "$_obj"
                    fi
                fi
            fi
        done
    done

    # After rebuild, run GC (assumes lock still held)
    kam_lock_gc

    return 0
}

kam_lock_rebuild() {
    # If we already hold the lock (owner pid matches our pid), call the locked
    # variant directly. Otherwise acquire the lock, run the rebuild, and release.
    if [ -d "${KAM_LOCK_DIR}" ]; then
        _kam_read_lock_meta
        if [ "${LOCK_PID:-}" = "$$" ]; then
            kam_lock_rebuild_locked
            return 0
        fi
    fi

    if ! kam_lock_acquire "${KAM_LOCK_WAIT}" "rebuild"; then
        _kam_log "kam.lock: cannot acquire lock for rebuild"
        return 1
    fi

    kam_lock_rebuild_locked

    kam_lock_release
    return 0
}

# Garbage collect unreferenced objects.
# Strategy:
#  - If object inode nlink > 1 => referenced by providers/targets, keep
#  - If nlink == 1, perform a hash scan to see whether any provider copy (or target) exists with same hash; if none, delete object
kam_lock_gc() {
    if ! kam_lock_acquire "${KAM_LOCK_WAIT}" "gc"; then
        _kam_log "kam.lock: cannot acquire lock for gc"
        return 1
    fi

    _objects_dir="${KAM_DIR}/objects"
    _providers_root="${KAM_DIR}/providers"
    [ -d "$_objects_dir" ] || { kam_lock_release; return 0; }

    for _obj in "$_objects_dir"/*; do
        [ -e "$_obj" ] || continue
        # get nlink
        _nlink=$(ls -ld "$_obj" | awk '{print $2}' 2>/dev/null || echo 0)
        if [ -n "$_nlink" ] && [ "$_nlink" -gt 1 ]; then
            # referenced by provider/target hardlinks; keep
            continue
        fi
        # compute hash (filename already is hash but check)
        _hash=$(basename "$_obj")
        _referenced=0
        # scan providers for same-hash content
        if [ -d "$_providers_root" ]; then
            for _p in "$_providers_root"/*/*/*; do
                [ -e "$_p" ] || continue
                if _h2=$(get_hash "$_p") 2>/dev/null && [ "$_h2" = "$_hash" ]; then
                    _referenced=1
                    break
                fi
            done
        fi
        # scan global targets for same hash
        if [ "$_referenced" -eq 0 ]; then
            for _k in bin lib; do
                for _t in "${KAM_DIR}/${_k}"/*; do
                    [ -e "$_t" ] || continue
                    if _h3=$(get_hash "$_t") 2>/dev/null && [ "$_h3" = "$_hash" ]; then
                        _referenced=1
                        break 2
                    fi
                done
            done
        fi

        if [ "$_referenced" -eq 0 ]; then
            _kam_log "kam.lock: removing unreferenced object ${_obj}"
            rm -f "$_obj" 2>/dev/null || true
        fi
    done

    # remove empty provider directories
    if [ -d "$_providers_root" ]; then
        for _kind_dir in "$_providers_root"/*; do
            [ -d "$_kind_dir" ] || continue
            for _name_dir in "$_kind_dir"/*; do
                [ -d "$_name_dir" ] || continue
                [ -z "$(ls -A "$_name_dir" 2>/dev/null)" ] && rmdir "$_name_dir" 2>/dev/null || true
            done
            [ -z "$(ls -A "$_kind_dir" 2>/dev/null)" ] && rmdir "$_kind_dir" 2>/dev/null || true
        done
        [ -z "$(ls -A "$_providers_root" 2>/dev/null)" ] && rmdir "$_providers_root" 2>/dev/null || true
    fi

    # final tiny cleanup: if KAM_DIR is empty remove it
    if [ -d "$KAM_DIR" ]; then
        [ -z "$(ls -A "$KAM_DIR" 2>/dev/null)" ] && rm -rf "$KAM_DIR" 2>/dev/null || true
    fi

    kam_lock_release
    return 0
}

# Display info about current lock
kam_lock_info() {
    if [ -d "$KAM_LOCK_DIR" ]; then
        if _kam_read_lock_meta; then
            _kam_log "kam.lock held by pid ${LOCK_PID:-unknown} (who=${LOCK_WHO:-unknown}) ts=${LOCK_TS:-unknown}"
            return 0
        else
            _kam_log "kam.lock directory exists but no metadata file present"
            return 0
        fi
    else
        _kam_log "kam.lock not held"
        return 1
    fi
}
# Make this file safe to source repeatedly
true
