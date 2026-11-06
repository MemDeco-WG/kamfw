# shellcheck shell=ash
set_i18n "PRUNE_ZYGISK_START" \
	"zh" '开始清理 zygisk，架构: $_1 目录: $_2' \
	"en" 'Pruning zygisk for arch $_1 in $_2'

set_i18n "PRUNE_ZYGISK_NO_DIR" \
	"zh" '目录不存在或不可访问，跳过：$_1' \
	"en" 'Zygisk directory not found or not accessible, skipping: $_1'

set_i18n "PRUNE_ZYGISK_NO_FILES" \
	"zh" '未发现需要删除的 zygisk 文件（架构：$_1）' \
	"en" 'No zygisk files matched removal patterns for arch $_1'

set_i18n "PRUNE_ZYGISK_WOULD_REMOVE" \
	"zh" '（干跑）将删除：$_1' \
	"en" 'Would remove: $_1'

set_i18n "PRUNE_ZYGISK_REMOVED" \
	"zh" '已删除：$_1' \
	"en" 'Removed: $_1'

set_i18n "PRUNE_ZYGISK_REMOVE_FAILED" \
	"zh" '删除失败：$_1' \
	"en" 'Failed to remove: $_1'

set_i18n "PRUNE_ZYGISK_DRY_DONE" \
	"zh" '干跑完成：$_1 个匹配项' \
	"en" 'Dry run: $_1 files match removal patterns'

set_i18n "PRUNE_ZYGISK_DONE" \
	"zh" '清理完成：已删除 $_1 个文件' \
	"en" 'Prune complete: removed $_1 files'

set_i18n "PRUNE_ZYGISK_UNKNOWN_ARCH" \
	"zh" '未知架构：$_1，跳过清理' \
	"en" 'Unknown arch: $_1; skipping prune'

set_i18n "PRUNE_ZYGISK_FIND_MISSING" \
	"zh" "缺少必需工具：find，无法执行清理" \
	"en" "Required command 'find' not found; cannot prune zygisk libs"

prune_zygisk_for_arch() (
    arch=${1:-${ARCH:-}}
    directory=${2:-${MODPATH:-}/zygisk}
    dryrun=0
    [ $# -lt 2 ] || shift 2
    for option in "$@"; do case "$option" in -n|--dry-run) dryrun=1 ;; esac; done
    [ -n "$arch" ] || abort "$(i18n PRUNE_ZYGISK_UNKNOWN_ARCH | t '')"
    [ -d "$directory" ] || { info "$(i18n PRUNE_ZYGISK_NO_DIR | t "$directory")"; return 0; }
    command -v find >/dev/null 2>&1 || abort "$(i18n PRUNE_ZYGISK_FIND_MISSING)"
    info "$(i18n PRUNE_ZYGISK_START | t "$arch" "$directory")"
    case "$(printf '%s' "$arch" | tr '[:upper:]' '[:lower:]')" in
        arm64|aarch64|arm64-v8a) set -- 'mips*.so' 'riscv*.so' 'x86*.so' 'x64*.so' ;;
        arm|armeabi|armeabi-v7a) set -- 'mips*.so' 'riscv*.so' 'x86*.so' 'x64*.so' '*64*.so' ;;
        x64|x86_64) set -- 'mips*.so' 'riscv*.so' ;;
        x86) set -- 'mips*.so' 'riscv*.so' '*64*.so' ;;
        riscv64|riscv) set -- 'mips*.so' 'arm*.so' 'x86*.so' 'x64*.so' ;;
        mips64) set -- 'riscv*.so' 'arm*.so' 'x86*.so' 'x64*.so' ;;
        mips) set -- 'riscv*.so' 'arm*.so' 'x86*.so' 'x64*.so' '*64*.so' ;;
        *) warn "$(i18n PRUNE_ZYGISK_UNKNOWN_ARCH | t "$arch")"; return 1 ;;
    esac
    files=$(find "$directory" -type f | LC_ALL=C sort) || return 1
    count=0
    removed=0
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        matched=0
        for pattern in "$@"; do case "${file##*/}" in $pattern) matched=1; break ;; esac; done
        [ "$matched" = 1 ] || continue
        count=$((count + 1))
        if [ "$dryrun" = 1 ]; then info "$(i18n PRUNE_ZYGISK_WOULD_REMOVE | t "$file")"
        elif rm -f -- "$file"; then removed=$((removed + 1)); success "$(i18n PRUNE_ZYGISK_REMOVED | t "$file")"
        else warn "$(i18n PRUNE_ZYGISK_REMOVE_FAILED | t "$file")"; fi
    done <<FILES
$files
FILES
    if [ "$count" = 0 ]; then info "$(i18n PRUNE_ZYGISK_NO_FILES | t "$arch")"
    elif [ "$dryrun" = 1 ]; then info "$(i18n PRUNE_ZYGISK_DRY_DONE | t "$count")"
    else success "$(i18n PRUNE_ZYGISK_DONE | t "$removed")"; fi
)
