# shellcheck shell=ash
set_i18n "LOGROTATE_FILE_REQUIRED" \
    "zh" "logrotate: 日志文件不能为空" \
    "en" "logrotate: log file is required" \
    "ja" "logrotate: ログファイルが必要です" \
    "ko" "logrotate: 로그 파일이 필요합니다"

set_i18n "LOGROTATE_SIZE_INVALID" \
    "zh" "logrotate: 轮转大小必须是正整数，可带 k/m/g 后缀" \
    "en" "logrotate: rotate size must be a positive integer, optionally with k/m/g suffix" \
    "ja" "logrotate: ローテーションサイズは正の整数で、任意で k/m/g 接尾辞を指定できます" \
    "ko" "logrotate: 순환 크기는 양의 정수여야 하며 k/m/g 접미사를 사용할 수 있습니다"

set_i18n "LOGROTATE_KEEP_INVALID" \
    "zh" "logrotate: 保留份数必须是非负整数" \
    "en" "logrotate: keep count must be a non-negative integer" \
    "ja" "logrotate: 保持数は 0 以上の整数である必要があります" \
    "ko" "logrotate: 보관 개수는 0 이상의 정수여야 합니다"

set_i18n "LOGROTATE_USAGE" \
    "zh" "用法: logrotate [-s size] [-k keep] <file>" \
    "en" "Usage: logrotate [-s size] [-k keep] <file>" \
    "ja" "使用法: logrotate [-s size] [-k keep] <file>" \
    "ko" "사용법: logrotate [-s size] [-k keep] <file>"

logrotate_size_bytes() (
    size=${1:-}
    multiplier=1
    case "$size" in
        *[kK]) size=${size%?}; multiplier=1024 ;;
        *[mM]) size=${size%?}; multiplier=1048576 ;;
        *[gG]) size=${size%?}; multiplier=1073741824 ;;
    esac
    case "$size" in ''|*[!0-9]*|0) return 1 ;; esac
    # Strip leading zeroes before shell arithmetic (08 is decimal, not octal).
    while [ "${size#0}" != "$size" ]; do size=${size#0}; done
    [ -n "$size" ] || return 1
    print "$((size * multiplier))"
)

logrotate_valid_keep() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; }
logrotate_file_size() (
    [ -f "$1" ] || { print 0; return; }
    size=$(wc -c <"$1") || return 1
    set -- $size
    print "${1:-0}"
)
logrotate_needed() (
    [ -n "${1:-}" ] || return 1
    limit=$(logrotate_size_bytes "${2:-}") || return 1
    size=$(logrotate_file_size "$1") || return 1
    [ "$size" -ge "$limit" ]
)

logrotate_file() (
    size=${KAM_LOG_ROTATE_SIZE:-}
    keep=${KAM_LOG_ROTATE_KEEP:-1}
    while [ $# -gt 0 ]; do
        case "$1" in
            -s|--size|--rotate-size) [ $# -ge 2 ] || { error "$(i18n LOGROTATE_USAGE)"; return 2; }; size=$2; shift 2 ;;
            -k|--keep|--rotate-keep) [ $# -ge 2 ] || { error "$(i18n LOGROTATE_USAGE)"; return 2; }; keep=$2; shift 2 ;;
            --) shift; break ;;
            -*) error "$(i18n LOGROTATE_USAGE)"; return 2 ;;
            *) break ;;
        esac
    done
    [ -n "${1:-}" ] || { error "$(i18n LOGROTATE_FILE_REQUIRED)"; return 2; }
    limit=$(logrotate_size_bytes "$size") || { error "$(i18n LOGROTATE_SIZE_INVALID)"; return 2; }
    logrotate_valid_keep "$keep" || { error "$(i18n LOGROTATE_KEEP_INVALID)"; return 2; }
    size=$(logrotate_file_size "$1") || return 1
    [ "$size" -ge "$limit" ] || return 0
    if [ "$keep" -gt 0 ]; then
        rm -f "$1.$keep" || return 1
        while [ "$keep" -gt 1 ]; do
            previous=$((keep - 1))
            [ ! -e "$1.$previous" ] || mv "$1.$previous" "$1.$keep" || return 1
            keep=$previous
        done
        mv "$1" "$1.1" || return 1
    fi
    : >"$1"
)

logrotate() {
    case "${1:-}" in help|-h|--help) print "$(i18n LOGROTATE_USAGE)" ;; *) logrotate_file "$@" ;; esac
}
