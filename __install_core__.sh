# shellcheck shell=ash
set_i18n "AUTO_EXTRACT_NO_MODPATH" \
    "zh" "没有指定 MODPATH，跳过自动安装" \
    "en" "No MODPATH set, skipping install"

set_i18n "AUTO_EXTRACT_NO_FILES" \
    "zh" "没有找到任何需要自动安装的文件" \
    "en" "No files to install on exit"

set_i18n "AUTO_EXTRACT_START" \
    "zh" "开始在退出时安装文件..." \
    "en" "Starting install-on-exit..."

set_i18n "AUTO_EXTRACT_INSTALL_OK" \
    "zh" "已安装：\$_1" \
    "en" "Installed: \$_1"

set_i18n "AUTO_EXTRACT_INSTALL_FAILED" \
    "zh" "安装失败：\$_1" \
    "en" "Failed to install: \$_1"

set_i18n "AUTO_EXTRACT_SKIP_EXISTING_NONINTERACTIVE" \
    "zh" "文件已存在，非交互模式下跳过：\$_1" \
    "en" "Skipping existing file in non-interactive mode: \$_1"

set_i18n "AUTO_EXTRACT_DONE" \
    "zh" "自动安装完成（\$_1 个文件）" \
    "en" "Install completed (\$_1 files)"

__inst__msg() {
    _im_text=$(i18n "$1" 2>/dev/null)
    printf '%s' "${_im_text:-$2}"
}
__inst__msg1() {
    _im_text=$(i18n "$1" 2>/dev/null | t "$3")
    printf '%s' "${_im_text:-$2}"
}
__inst__quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

__inst__add_unique() {
    case "$1" in ''|[!A-Za-z_]*|*[!A-Za-z0-9_]*) return 1 ;; esac
    eval "_iu_current=\${$1:-}"
    case "
$_iu_current
" in
        *"
$2
"*) return 0 ;;
    esac
    _iu_value="${_iu_current}${_iu_current:+
}$2"
    eval "$1=\$_iu_value"
}

__inst__matches_any() {
    eval "_im_patterns=\${$2:-}"
    while IFS= read -r _im_pattern; do
        [ -n "$_im_pattern" ] || continue
        # The filter is deliberately a shell pattern; filenames remain literal.
        case "$1" in $_im_pattern) return 0 ;; esac
    done <<PATTERNS
$_im_patterns
PATTERNS
    return 1
}

__inst__count_lines() { printf '%s\n' "$1" | awk 'NF { n++ } END { print n+0 }'; }
__inst__cleanup_dir() { [ -z "${1:-}" ] || rm -rf "$1"; }
__inst__ensure_parent_dir() { mkdir -p "${1%/*}" || abort "mkdir failed: ${1%/*}"; }
__inst__mark_script_executable() {
    IFS= read -r _ix_header <"$1" || true
    case "$_ix_header" in '#!'*) chmod +x "$1" || warn "chmod failed: $1" ;; esac
}
__inst__copy_file() {
    __inst__ensure_parent_dir "$2"
    if cp -a "$1" "$2"; then
        __inst__mark_script_executable "$2"
        success "$(i18n AUTO_EXTRACT_INSTALL_OK | t "$3")"
    else
        __inst__warn_install_failed "$3"
        return 1
    fi
}
__inst__warn_existing_noninteractive() { warn "$(i18n AUTO_EXTRACT_SKIP_EXISTING_NONINTERACTIVE | t "$1")"; }
__inst__warn_install_failed() { warn "$(i18n AUTO_EXTRACT_INSTALL_FAILED | t "$1")"; }
__inst__abort_ziptools_missing() { abort "$(i18n ZIPTOOLS_MISSING)"; }

__list_files_from_dir() (
    cd "${1:-.}" || return 1
    find . -type f | sed 's|^\./||'
)

__list_files_from_zip() (
    if command -v zipinfo >/dev/null 2>&1; then
        files=$(zipinfo -1 "$1" 2>/dev/null) || return 1
        printf '%s\n' "$files" | sed '/\/$/d'
    elif command -v unzip >/dev/null 2>&1; then
        if files=$(unzip -Z1 "$1" 2>/dev/null); then
            printf '%s\n' "$files" | sed '/\/$/d'
        else
            files=$(unzip -l "$1" 2>/dev/null) || return 1
            printf '%s\n' "$files" | awk '
                /^[[:space:]]*[-]+[[:space:]]+[-]+/ { body = !body; next }
                body && $1 ~ /^[0-9]+$/ { sub(/^[[:space:]]*[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, ""); if ($0 !~ /\/$/) print }
            '
        fi
    else
        __inst__abort_ziptools_missing
    fi
)

__install__get_files_from_zip() { __list_files_from_zip "$1"; }

__find_zip_entry() (
    files=$(__list_files_from_zip "$1") || return 1
    while IFS= read -r file; do
        case "$file" in "$2"|*/"$2") printf '%s' "$file"; return 0 ;; esac
    done <<FILES
$files
FILES
    return 1
)

__installer_install_from_filters() (
    [ -n "${MODPATH:-}" ] || { info "$(i18n AUTO_EXTRACT_NO_MODPATH)"; return 0; }
    files=${1:-$(install_check)}
    [ -n "$files" ] || { info "$(i18n AUTO_EXTRACT_NO_FILES)"; return 0; }
    info "$(i18n AUTO_EXTRACT_START)"
    extract=''
    result=0
    trap '[ -z "$extract" ] || rm -rf "$extract"' EXIT
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        case "$rel" in /*|..|../*|*/../*|*/..) __inst__warn_install_failed "$rel"; result=1; continue ;; esac
        dest=$MODPATH/$rel
        source=${KAM_MODULE_ROOT:-.}/$rel
        if [ -f "$source" ]; then
            if [ -f "$dest" ]; then
                if [ -t 0 ] && command -v __confirm_install_file_do >/dev/null 2>&1; then
                    __confirm_install_file_do "$source" "$rel" || result=1
                else
                    __inst__warn_existing_noninteractive "$rel"
                fi
            else
                __inst__copy_file "$source" "$dest" "$rel" || result=1
            fi
        elif [ -f "${ZIPFILE:-}" ]; then
            command -v unzip >/dev/null 2>&1 || __inst__abort_ziptools_missing
            if [ -f "$dest" ] && [ ! -t 0 ]; then
                __inst__warn_existing_noninteractive "$rel"
                continue
            fi
            if [ -t 0 ] && command -v __confirm_install_file_do_from_zip >/dev/null 2>&1; then
                __confirm_install_file_do_from_zip "$ZIPFILE" "$rel" "$rel" || result=1
                continue
            fi
            [ -n "$extract" ] || extract=$(mktemp -d "${TMPDIR:-/tmp}/kamfw.extract.XXXXXX") || return 1
            if unzip -o -j "$ZIPFILE" "$rel" -d "$extract" >/dev/null 2>&1; then
                __inst__copy_file "$extract/${rel##*/}" "$dest" "$rel" || result=1
            else
                __inst__warn_install_failed "$rel"
                result=1
            fi
        else
            __inst__warn_install_failed "$rel"
            result=1
        fi
    done <<FILES
$files
FILES
    [ "$result" -eq 0 ] || return "$result"
    success "$(i18n AUTO_EXTRACT_DONE | t "$(__inst__count_lines "$files")")"
)
