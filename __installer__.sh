# shellcheck shell=ash
# Compact installer helper for kamfw
# - Provides install_exclude/include/show/check/run/schedule
# - Small, reusable, and keeps runtime i18n/at-exit integration
#
# Usage (after import):
#   install_exclude 'test/*'
#   install_include 'bin/*'
#   installer check [<src>]
#   installer run [<src>]
#   installer schedule [<src>]
#
# Notes:
# - All user-visible strings are i18n keys.
# - Critical external deps (zip tools) fail-fast with i18n key ZIPTOOLS_MISSING.
# - This helper intentionally keeps a minimal surface to be imported by customize.sh.
#
# (Keep this file compact and under 200 lines.)
import __at_exit__  # provides __at_exit_install_from_filters and install_register_exit_hook

# i18n (user-facing)
set_i18n "INSTALL_NO_FILES" "zh" "没有需要安装的文件" "en" "No files to install"
set_i18n "INSTALL_WILL_ON_EXIT" "zh" "将在退出时自动安装 \\$_1 个文件" "en" "Will install \\$_1 files on exit"
set_i18n "INSTALL_RUNNING_NOW" "zh" "正在立即安装 \\$_1 个文件" "en" "Installing \\$_1 files now"
set_i18n "INSTALL_DONE" "zh" "自动安装完成" "en" "Install completed"

# Internal pattern storage (newline-separated)
__install_exclude_patterns=""; __install_include_patterns=""

# Helpers
__inst__add_unique() {
    var="$1"; val="$2"
    eval "cur=\${$var}"
    if [ -n "${cur:-}" ]; then
        printf '%s\n' "$cur" | grep -F -x -- "$val" >/dev/null 2>&1 && return 0
        # Use printf to build a newline-separated value at runtime (avoid literal newline in source)
        eval "$var=\"\$(printf '%s\n%s' \"\$cur\" \"$val\")\""
    else
        eval "$var=\$val"
    fi
    return 0
}

__inst__matches_any() {
    path="$1"; patterns_var="$2"
    eval "pats=\${$patterns_var}"
    [ -z "${pats:-}" ] && return 1
    OLDIFS=$IFS; IFS='
'
    for pat in $pats; do
    case "$path" in $pat) IFS=$OLDIFS; return 0 ;; esac
        done
        IFS=$OLDIFS
        return 1
    }

    __inst__count_lines() {
        # Compact count using awk; returns 0 for empty input
        printf '%s\n' "$1" | awk 'NF{c++} END{print c+0}'
    }

    __inst__invoke_install() {
        src="$1"
        if [ -n "$src" ]; then
            if [ -d "$src" ]; then
                KAM_MODULE_ROOT="$src"
                __at_exit_install_from_filters
                unset KAM_MODULE_ROOT
                return 0
            fi
            if [ -f "$src" ]; then
                ZIPFILE="$src"
                __at_exit_install_from_filters
                unset ZIPFILE
                return 0
            fi
        fi
        __at_exit_install_from_filters
    }

    __inst__register_hook() {
        if type install_register_exit_hook >/dev/null 2>&1; then
            install_register_exit_hook
        else
            at_exit_add '__at_exit_install_from_filters'
        fi
    }

    __inst__show_patterns() {
        var="$1"; label="$2"
        print "$label"
        eval "val=\${$var:-}"
        if [ -z "${val:-}" ]; then
            print "  <none>"
            return 0
        fi
        OLDIFS=$IFS; IFS='
'
        for p in $val; do print "  $p"; done
        IFS=$OLDIFS
    }

    # File listing utilities
    __list_files_from_dir() {
        root="$1"
        if [ -z "$root" ] || [ "$root" = "." ]; then
            find . -type f 2>/dev/null | sed 's|^\./||'
            return 0
        fi
        if [ -d "$root" ]; then
            (cd "$root" 2>/dev/null && find . -type f 2>/dev/null | sed 's|^\./||')
            return 0
        fi
        return 1
    }

    __list_files_from_zip() {
        zipfile="$1"
        if command -v zipinfo >/dev/null 2>&1; then
            zipinfo -1 "$zipfile" 2>/dev/null | sed '/\/$/d'
            return 0
        fi
        if command -v unzip >/dev/null 2>&1; then
            if unzip -Z1 "$zipfile" >/dev/null 2>&1; then
                unzip -Z1 "$zipfile" 2>/dev/null | sed '/\/$/d'
                return 0
            fi
            unzip -l "$zipfile" 2>/dev/null | awk '{print $4}' | sed '/\/$/d' | sed '/^$/d'
            return 0
        fi
        return 1
    }

    # Public API: filters
    install_reset_filters() { unset __install_exclude_patterns __install_include_patterns; return 0; }

    install_show_filters() {
        __inst__show_patterns __install_exclude_patterns "Exclude patterns:"
        __inst__show_patterns __install_include_patterns "Include patterns:"
        return 0
    }

    install_exclude() {
        [ $# -eq 0 ] && return 0
        for pat in "$@"; do pat="${pat#./}"; pat="${pat#/}"; __inst__add_unique __install_exclude_patterns "$pat"; done
        return 0
    }

    install_include() {
        [ $# -eq 0 ] && return 0
        for pat in "$@"; do pat="${pat#./}"; pat="${pat#/}"; __inst__add_unique __install_include_patterns "$pat"; done
        return 0
    }

    # install_check: (all_files - excludes) U includes
    install_check() {
        src="$1"
        if [ -z "$src" ]; then
            if [ -n "${KAM_MODULE_ROOT:-}" ] && [ -d "${KAM_MODULE_ROOT}" ]; then src="${KAM_MODULE_ROOT}"
            elif [ -n "${ZIPFILE:-}" ] && [ -f "${ZIPFILE}" ]; then src="${ZIPFILE}"
        else src="."; fi
        fi

        files=""
        if [ -d "$src" ]; then
            files="$(__list_files_from_dir "$src")"
        elif [ -f "$src" ]; then
            files="$(__list_files_from_zip "$src")" || abort "$(i18n 'ZIPTOOLS_MISSING' 2>/dev/null || echo 'zip tools missing')"
        else
            files="$(__list_files_from_dir ".")"
        fi

        selected=""
        OLDIFS=$IFS; IFS='
'
        for f in $files; do
            [ -z "$f" ] && continue
            __inst__matches_any "$f" "__install_exclude_patterns" && continue
            __inst__add_unique selected "$f"
        done
        if [ -n "${__install_include_patterns:-}" ]; then
            for f in $files; do
                [ -z "$f" ] && continue
                __inst__matches_any "$f" "__install_include_patterns" && __inst__add_unique selected "$f"
            done
        fi
        IFS=$OLDIFS

        OLDIFS=$IFS; IFS='
'
        for f in $selected; do [ -n "$f" ] && print "$f"; done
        IFS=$OLDIFS
        return 0
    }

    # Single entry installer (small command set)
    installer() {
        cmd="$1"; shift || true
        case "$cmd" in
            exclude) install_exclude "$@" ; return 0 ;;
            include) install_include "$@" ; return 0 ;;
            show) install_show_filters; return 0 ;;
            check) install_check "$1"; return $? ;;
            run)
                src="$1"
                files="$(install_check "$src" 2>/dev/null || true)"
                cnt="$(__inst__count_lines "$files")"
                [ "$cnt" -eq 0 ] && { info "$(i18n 'INSTALL_NO_FILES' 2>/dev/null || echo 'No files to install')"; return 0; }
                info "$(i18n 'INSTALL_RUNNING_NOW' 2>/dev/null | t "$cnt" 2>/dev/null || printf 'Installing %s files now' "$cnt")"
                __inst__invoke_install "$src"
                info "$(i18n 'INSTALL_DONE' 2>/dev/null || echo 'Install completed')"
                return 0
                ;;
            schedule)
                src="$1"
                files="$(install_check "$src" 2>/dev/null || true)"
                cnt="$(__inst__count_lines "$files")"
                [ "$cnt" -eq 0 ] && { info "$(i18n 'INSTALL_NO_FILES' 2>/dev/null || echo 'No files to install')"; return 0; }
                __inst__register_hook
                info "$(i18n 'INSTALL_WILL_ON_EXIT' 2>/dev/null | t "$cnt" 2>/dev/null || printf 'Will install %s files on exit' "$cnt")"
                return 0
                ;;
            ""|help|-h|--help)
                print "installer: usage: installer <exclude|include|show|check|run|schedule> [args]"
                return 0
                ;;
            *)
                # Backwards-compatible: `install <src>` => schedule
                installer schedule "$cmd"
                return $?
                ;;
        esac
    }
