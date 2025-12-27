# shellcheck shell=ash

config() {
    _cmd="$1"; [ -z "$_cmd" ] || shift
    
    # 1. KernelSU Delegate
    if is_ksu; then
        _ksud=$(command -v ksud || echo "/data/adb/ksud")
        [ -n "$KSU_MODULE" ] || [ ! -f "$MODDIR/module.prop" ] || export KSU_MODULE=$(sed -n 's/^id=//p' "$MODDIR/module.prop")
        "$_ksud" module config "$_cmd" "$@"
        return $?
    fi

    # 2. Help
    if [ "$_cmd" = "help" ] || [ -z "$_cmd" ]; then
        printf "Usage: config [get|set|list|delete|clear] [--temp] [--stdin] <key> [value]\n"
        return 0
    fi

    # 3. Path & Module ID Setup
    _mod_id="${KSU_MODULE:-${MODDIR##*/}}"
    [ -n "$_mod_id" ] || { error "Module ID unknown"; return 1; }
    
    _base="/data/adb/ksu/module_configs/$_mod_id"
    _p_dir="$_base/persist"; _t_dir="$_base/tmp"
    mkdir -p "$_p_dir" "$_t_dir" && chmod 0700 "$_base" "$_p_dir" "$_t_dir"

    # 4. Command Logic
    case "$_cmd" in
        get)
            _key="$1"
            [ -f "$_t_dir/$_key" ] && cat "$_t_dir/$_key" && return 0
            [ -f "$_p_dir/$_key" ] && cat "$_p_dir/$_key" && return 0
            return 1
            ;;
        set)
            _dir="$_p_dir"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --temp) _dir="$_t_dir"; shift ;;
                    --stdin) _stdin=1; shift ;;
                    *) break ;;
                esac
            done
            _key="$1"; shift
            [ -n "$_key" ] || return 1
            if [ "$_stdin" = "1" ]; then cat > "$_dir/$_key"; else printf '%s' "$*" > "$_dir/$_key"; fi
            ;;
        list)
            { ls -1 "$_p_dir"; ls -1 "$_t_dir"; } 2>/dev/null | sort -u
            ;;
        delete)
            _dir="$_p_dir"; [ "$1" = "--temp" ] && { _dir="$_t_dir"; shift; }
            rm -f "$_dir/$1"
            ;;
        clear)
            _dir="$_p_dir"; [ "$1" = "--temp" ] && { _dir="$_t_dir"; shift; }
            rm -rf "$_dir" && mkdir -m 0700 -p "$_dir"
            ;;
        *) return 1 ;;
    esac
}
