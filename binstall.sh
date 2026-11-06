# shellcheck shell=ash
set_i18n "BINSTALL_MISSING_CURL" \
    "zh" "缺少下载工具：curl，无法继续" \
    "en" "Required tool 'curl' not found; cannot download"

set_i18n "BINSTALL_MISSING_GH" \
    "zh" "缺少 GitHub CLI：gh，无法检测最新 release" \
    "en" "Required tool 'gh' not found; cannot query GitHub releases"

set_i18n "BINSTALL_NO_URL_OR_REPO" \
    "zh" "未提供 URL 或 GitHub 仓库/asset 信息" \
    "en" "No URL or GitHub repo/asset information provided"

set_i18n "BINSTALL_DOWNLOAD_FAILED" \
    "zh" '下载失败：$_1' \
    "en" 'Download failed: $_1'

set_i18n "BINSTALL_EXTRACT_FAILED" \
    "zh" '解压失败：$_1' \
    "en" 'Extract failed: $_1'

set_i18n "BINSTALL_INSTALL_OK" \
    "zh" '安装完成: $_1' \
    "en" 'Installed: $_1'

set_i18n "BINSTALL_WRITING_VERSION" \
    "zh" '写入版本文件: $_1' \
    "en" 'Writing version file: $_1'

binstall() (
    name='' target='' url='' repo='' tag='' asset='' arch='' result='' version='' version_file='' final=''
    mode=0755
    tmpbase=${TMPDIR:-/tmp}
    dryrun=0
    keep=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dryrun=1; shift; continue ;;
            --no-clean) keep=1; shift; continue ;;
            --help|-h) print 'Usage: binstall --name NAME --target DIR [--url URL | --repo REPO --asset ASSET [--tag TAG]] [options]'; return 0 ;;
            --name|--target|--url|--repo|--tag|--asset|--arch|--result-name|--chmod|--version|--version-file|--tmpdir)
                [ $# -ge 2 ] || { error "binstall: value required for $1"; return 2; }
                case "$1" in
                    --name) name=$2 ;; --target) target=$2 ;; --url) url=$2 ;;
                    --repo) repo=$2 ;; --tag) tag=$2 ;; --asset) asset=$2 ;; --arch) arch=$2 ;;
                    --result-name) result=$2 ;; --chmod) mode=$2 ;; --version) version=$2 ;;
                    --version-file) version_file=$2 ;; --tmpdir) tmpbase=$2 ;;
                esac
                shift 2
                ;;
            *) shift ;;
        esac
    done
    [ -n "$name" ] || abort 'binstall: --name required'
    [ -n "$target" ] || abort 'binstall: --target required'
    mkdir -p "$target" || abort "binstall: cannot create target dir $target"
    if [ -z "$url" ]; then
        [ -n "$repo" ] && [ -n "$asset" ] || abort "$(i18n BINSTALL_NO_URL_OR_REPO)"
        if [ -z "$tag" ] || [ "$tag" = latest ]; then
            command -v gh >/dev/null 2>&1 || abort "$(i18n BINSTALL_MISSING_GH)"
            tag=$(gh release view --repo "$repo" --json tagName --template '{{.tagName}}') || return 1
            [ -n "$tag" ] || abort "binstall: failed to query latest tag for $repo"
        fi
        # Substitute literal placeholders without evaluating the release name.
        asset=$(printf '%s' "$asset" | sed 's/${TAG}/$_1/g;s/${ARCH}/$_2/g' | t "$tag" "$arch")
        url="https://github.com/$repo/releases/download/$tag/$asset"
    fi
    info "Downloading: $url"
    command -v curl >/dev/null 2>&1 || abort "$(i18n BINSTALL_MISSING_CURL)"
    temporary=$(mktemp -d "$tmpbase/binstall.XXXXXX") || return 1
    trap '[ "$keep" = 1 ] || rm -rf "$temporary"' EXIT
    filename=${url##*/}
    archive=$temporary/$filename
    if [ "$dryrun" = 1 ]; then
        info "DRY-RUN: would download $url -> $archive"
        info "DRY-RUN: would extract/copy and place as $target/$name (chmod $mode)"
        return 0
    fi
    curl -fL -o "$archive" "$url" || abort "$(i18n BINSTALL_DOWNLOAD_FAILED | t "$url")"
    unpacked=$temporary/unpacked
    mkdir "$unpacked" || return 1
    case "$filename" in
        *.tar.gz|*.tgz) tar -xzf "$archive" -C "$unpacked" || abort "$(i18n BINSTALL_EXTRACT_FAILED | t "$archive")" ;;
        *.zip) unzip -o "$archive" -d "$unpacked" >/dev/null || abort "$(i18n BINSTALL_EXTRACT_FAILED | t "$archive")" ;;
        *.gz) gunzip -c "$archive" >"$unpacked/${filename%.gz}" || abort "$(i18n BINSTALL_EXTRACT_FAILED | t "$archive")" ;;
        *) final=$archive ;;
    esac
    if [ -z "${final:-}" ]; then
        if [ -n "$result" ]; then final=$unpacked/$result
        else
            candidates=$(find "$unpacked" -type f ! -name '*.sha*' ! -name '*.sig')
            case "$candidates" in
                ''|*'
'*) abort "$(i18n BINSTALL_EXTRACT_FAILED | t 'Multiple files in archive; specify --result-name')" ;;
            esac
            final=$candidates
        fi
    fi
    [ -f "$final" ] || abort "$(i18n BINSTALL_EXTRACT_FAILED | t 'no final file')"
    chmod "$mode" "$final" || return 1
    mv -f "$final" "$target/$name" || return 1
    success "$(i18n BINSTALL_INSTALL_OK | t "$target/$name")"
    if [ -n "$version_file" ] && [ -n "${version:-$tag}" ]; then
        printf '%s\n' "${version:-$tag}" >"$version_file" || return 1
        info "$(i18n BINSTALL_WRITING_VERSION | t "$version_file")"
    fi
    [ "$keep" != 1 ] || info "binstall: tmpdir kept: $temporary"
)
