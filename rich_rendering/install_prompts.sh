# shellcheck shell=ash
import __install_core__

confirm_update_file() {
    [ -n "${MODPATH:-}" ] && [ -n "${1:-}" ] && [ -f "$MODPATH/module.prop" ] || return 0
    _relative_path=$1
    _module_id=$(sed -n 's/^id=//p' "$MODPATH/module.prop" | head -n1)
    [ -n "$_module_id" ] || return 0
    _installed_module_path=/data/adb/modules/$_module_id
    [ -d "$_installed_module_path" ] || return 0
    ask "$(i18n FORCE_UPDATE_FILE | t "$1")" YES \
        'unset _relative_path _module_id _installed_module_path; return 0' NO _do_update_file 1
}

__confirm_install_file_do() {
    [ -n "${1:-}" ] && [ -f "$1" ] || { error "Source not found: ${1:-}"; return 1; }
    if [ -f "$MODPATH/$2" ] && ! confirm "$(i18n FORCE_UPDATE_FILE | t "$2")" 1; then
        __confirm_install_file_cancel=1
        return 0
    fi
    mkdir -p "$(dirname "$MODPATH/$2")" && cp -a "$1" "$MODPATH/$2" || return 1
    success "$(i18n FILE_INSTALLED)$2"
    __confirm_install_file_installed=$2
}

__confirm_install_file_do_from_zip() {
    _cz_temp=$(mktemp -d "${TMPDIR:-/tmp}/kamfw.extract.XXXXXX") || return 1
    if unzip -o -j "$1" "$2" -d "$_cz_temp" >/dev/null 2>&1; then
        __confirm_install_file_do "$_cz_temp/${2##*/}" "$3"
        _cz_result=$?
        [ -z "${__confirm_install_file_installed:-}" ] || __inst__mark_script_executable "$MODPATH/$3"
    else
        error "Failed to extract $2 from $1"
        _cz_result=1
    fi
    rm -rf "$_cz_temp"
    return "$_cz_result"
}

confirm_install_file() {
    [ -n "${MODPATH:-}" ] && [ $# -gt 0 ] || return 0
    if [ -f "${ZIPFILE:-}" ] && ! command -v unzip >/dev/null 2>&1; then __inst__abort_ziptools_missing; fi
    _cf_count=0
    for _cf_relative in "$@"; do
        _cf_source=${KAM_MODULE_ROOT:-.}/$_cf_relative
        _cf_in_zip=0
        if [ -f "$_cf_source" ]; then
            _cf_command="__confirm_install_file_do $(__inst__quote "$_cf_source") $(__inst__quote "$_cf_relative")"
        elif [ -f "${ZIPFILE:-}" ] && _cf_entry=$(__find_zip_entry "$ZIPFILE" "$_cf_relative"); then
            _cf_command="__confirm_install_file_do_from_zip $(__inst__quote "$ZIPFILE") $(__inst__quote "$_cf_entry") $(__inst__quote "$_cf_relative")"
            _cf_in_zip=1
        else continue; fi
        _cf_label=$_cf_relative
        if [ -f "$MODPATH/$_cf_relative" ]; then _cf_label="$_cf_label ($(i18n INSTALLED))"
        elif [ "$_cf_in_zip" = 1 ]; then _cf_label="$_cf_label ($(i18n IN_ZIP))"; fi
        eval "_cf_label_$_cf_count=\$_cf_label"
        eval "_cf_command_$_cf_count=\$_cf_command"
        _cf_count=$((_cf_count + 1))
    done
    [ "$_cf_count" -gt 0 ] || { warn "$(i18n NO_FILES_AVAILABLE)"; return 0; }
    set -- "$(i18n SELECT_INSTALL_FILE)"
    _cf_index=0
    while [ "$_cf_index" -lt "$_cf_count" ]; do
        eval "_cf_label=\$_cf_label_$_cf_index"
        eval "_cf_command=\$_cf_command_$_cf_index"
        set -- "$@" "$_cf_label" "$_cf_command"
        _cf_index=$((_cf_index + 1))
    done
    unset __confirm_install_file_installed __confirm_install_file_cancel
    ask "$@" "$(i18n CANCEL)" 'unset __confirm_install_file_installed; __confirm_install_file_cancel=1; return 0' 0
    _cf_result=1
    [ -z "${__confirm_install_file_installed:-}" ] || _cf_result=0
    unset __confirm_install_file_installed __confirm_install_file_cancel
    return "$_cf_result"
}
