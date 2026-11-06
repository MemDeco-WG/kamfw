# shellcheck shell=ash
set_i18n "CACHE_DOWNLOAD_MISSING_URL" \
	"zh" "cache_download: URL 不能为空" \
	"en" "cache_download: url is required"

set_i18n "CACHE_DOWNLOAD_MISSING_DEST" \
	"zh" "cache_download: 目标文件不能为空" \
	"en" "cache_download: destination file is required"

set_i18n "CACHE_DOWNLOAD_MISSING_TOOL" \
	"zh" "cache_download: 缺少必需工具: \$_1" \
	"en" "cache_download: required command not found: \$_1"

set_i18n "CACHE_DOWNLOAD_DOWNLOAD_FAILED" \
	"zh" "cache_download: 下载失败: \$_1" \
	"en" "cache_download: download failed: \$_1"

set_i18n "CACHE_DOWNLOAD_HASH_FAILED" \
	"zh" "cache_download: 无法计算 sha256: \$_1" \
	"en" "cache_download: cannot compute sha256: \$_1"

set_i18n "CACHE_DOWNLOAD_HASH_MISMATCH" \
	"zh" "cache_download: sha256 不匹配: local=\$_1 expected=\$_2" \
	"en" "cache_download: sha256 mismatch: local=\$_1 expected=\$_2"

set_i18n "CACHE_DOWNLOAD_UP_TO_DATE" \
	"zh" "cache_download: 已是最新: \$_1" \
	"en" "cache_download: up to date: \$_1"

set_i18n "CACHE_DOWNLOAD_UPDATED" \
	"zh" "cache_download: 已更新: \$_1" \
	"en" "cache_download: updated: \$_1"

cache_download_msg() (
    key=$1
    fallback=$2
    shift 2
    message=$(i18n "$key")
    if [ -n "$message" ]; then printf '%s' "$message" | t "$@"; else printf '%s' "$fallback"; fi
)
cache_download_require() {
    command -v "$1" >/dev/null 2>&1 || { error "$(i18n CACHE_DOWNLOAD_MISSING_TOOL | t "$1")"; return 1; }
}
cache_download_sha256() (
    if command -v sha256sum >/dev/null 2>&1; then
        value=$(sha256sum "$1") || return 1
        printf '%s\n' "${value%% *}"
    elif command -v shasum >/dev/null 2>&1; then
        value=$(shasum -a 256 "$1") || return 1
        printf '%s\n' "${value%% *}"
    elif command -v openssl >/dev/null 2>&1; then
        value=$(openssl dgst -sha256 <"$1") || return 1
        printf '%s\n' "${value##* }"
    else return 1; fi
)
cache_download_text_sha256() { printf '%s' "$1" | cache_download_sha256 /proc/self/fd/0; }
cache_download_state_dir() (
    directory=${KAM_CACHE_DOWNLOAD_STATE_DIR:-${KAM_HOME:-${MODDIR:-${MODPATH:-/tmp}}}/.cache/downloads}
    mkdir -p "$directory" || return 1
    printf '%s\n' "$directory"
)
cache_download_hash_file() (
    directory=$(cache_download_state_dir) || return 1
    key=$(cache_download_text_sha256 "$1|$2") || return 1
    printf '%s/%s.sha256\n' "$directory" "$key"
)
cache_download_parse_hash() { sed -n 's/.*\([0-9a-fA-F]\{64\}\).*/\1/p' | head -n1 | tr '[:upper:]' '[:lower:]'; }
cache_download_remote_hash() (
    cache_download_require curl || return 1
    body=$(curl -fsSL "$1") || return 1
    hash=$(printf '%s' "$body" | cache_download_parse_hash)
    [ -n "$hash" ] && printf '%s\n' "$hash"
)

_cache_download_transaction() (
    expected=''
    hash_url=''
    hash_file=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --hash|--hash-url|--hash-file)
                [ $# -ge 2 ] || return 2
                case "$1" in
                    --hash) expected=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]') ;;
                    --hash-url) hash_url=$2 ;;
                    --hash-file) hash_file=$2 ;;
                esac
                shift 2
                ;;
            -h|--help) print 'Usage: cache_download [--hash SHA256 | --hash-url URL] [--hash-file FILE] <url> <dest>'; return 3 ;;
            *) break ;;
        esac
    done
    url=${1:-}
    dest=${2:-}
    [ -n "$url" ] || { error "$(i18n CACHE_DOWNLOAD_MISSING_URL)"; return 1; }
    [ -n "$dest" ] || { error "$(i18n CACHE_DOWNLOAD_MISSING_DEST)"; return 1; }
    cache_download_require curl || return 1
    [ -n "$hash_file" ] || hash_file=$(cache_download_hash_file "$url" "$dest") || return 1
    mkdir -p "$(dirname "$dest")" "$(dirname "$hash_file")" || return 1
    if [ -n "$hash_url" ]; then
        expected=$(cache_download_remote_hash "$hash_url") || { error "$(i18n CACHE_DOWNLOAD_DOWNLOAD_FAILED | t "$hash_url")"; return 1; }
    fi
    current=''
    [ ! -f "$dest" ] || current=$(cache_download_sha256 "$dest") || return 1
    if [ -n "$expected" ] && [ "$current" = "$expected" ] && [ -f "$hash_file" ]; then
        info "$(i18n CACHE_DOWNLOAD_UP_TO_DATE | t "$dest")"
        return 3
    fi
    temporary=$(mktemp "$(dirname "$dest")/.${dest##*/}.kamfw-download.XXXXXX") || return 1
    trap 'rm -f "$temporary"' EXIT
    curl -fsSL -o "$temporary" "$url" || {
        error "$(i18n CACHE_DOWNLOAD_DOWNLOAD_FAILED | t "$url")"; return 1;
    }
    digest=$(cache_download_sha256 "$temporary") || { error "$(i18n CACHE_DOWNLOAD_HASH_FAILED | t "$temporary")"; return 1; }
    if [ -n "$expected" ] && [ "$digest" != "$expected" ]; then
        error "$(i18n CACHE_DOWNLOAD_HASH_MISMATCH | t "$digest" "$expected")"
        return 1
    fi
    if [ "$digest" = "$current" ] && [ -f "$hash_file" ]; then
        info "$(i18n CACHE_DOWNLOAD_UP_TO_DATE | t "$dest")"
        return 3
    fi
    mv -f "$temporary" "$dest" || return 1
    printf '%s\n' "$digest" >"$hash_file" 2>/dev/null || true
    success "$(i18n CACHE_DOWNLOAD_UPDATED | t "$dest")"
)

cache_download() {
    export KAM_CACHE_DOWNLOAD_CHANGED=0
    if _cache_download_transaction "$@"; then
        export KAM_CACHE_DOWNLOAD_CHANGED=1
    else
        _cd_result=$?
        [ "$_cd_result" -eq 3 ] || return "$_cd_result"
    fi
}
download_if_changed() { cache_download "$@"; }
cache_download_if_changed() { cache_download "$@"; }
