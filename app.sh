# shellcheck shell=ash

# --- I18N 定义 ---

set_i18n "TERMUX_NOT_FOUND" \
    "zh" "未检测到 Termux，是否立即下载并安装？" \
    "en" "Termux not found. Download and install it now?" \
    "ja" "Termux が见つかりません。今すぐダウンロードしてインストールしますか？"

set_i18n "INSTALLING_TERMUX" \
    "zh" "正在安装 Termux..." \
    "en" "Installing Termux..." \
    "ja" "Termux をインストール中..."

set_i18n "TERMUX_INSTALLED" \
    "zh" "Termux 已就绪" \
    "en" "Termux is ready" \
    "ja" "Termux の准备が完了しました"

set_i18n "DOWNLOADING" \
    "zh" "正在下载..." \
    "en" "Downloading..." \
    "ja" "ダウンロード中..."

set_i18n "DOWNLOAD_FAILED" \
    "zh" "下载失败，请检查网络" \
    "en" "Download failed, please check your network" \
    "ja" "ダウンロードに失败しました。ネットワークを確認してください"

set_i18n "INSTALL_FAILED" \
    "zh" "安装失败" \
    "en" "Installation failed" \
    "ja" "インストールに失败しました"

set_i18n "ERR_NO_URL" \
    "zh" "错误: 未提供下载链接" \
    "en" "Error: No download URL provided" \
    "ja" "エラー: ダウンロードURLが指定されていません"

# --- 功能函数 ---

# 参数: $1 = 包名
is_app_installed() {
    [ -z "$1" ] && return 1
    pm list packages "$1" 2>/dev/null | grep -qx "package:$1"
}

# 参数: $1 = 下载链接
install_app_from() {
    _iaf_url="$1"
    _iaf_tmp="/data/local/tmp/app_$(date +%s)_$$.apk"
    
    if [ -z "$_iaf_url" ]; then
        print "! $(get_i18n "ERR_NO_URL")"
        return 1
    fi

    print "* $(get_i18n "DOWNLOADING")"

    if ! curl -Lfk --retry 3 -s "$_iaf_url" -o "$_iaf_tmp"; then
        print "! $(get_i18n "DOWNLOAD_FAILED")"
        rm -f "$_iaf_tmp"
        return 1
    fi

    if [ ! -s "$_iaf_tmp" ]; then
        print "! $(get_i18n "DOWNLOAD_FAILED")"
        rm -f "$_iaf_tmp"
        return 1
    fi

    print "* $(get_i18n "INSTALLING_TERMUX")"
    # pm install 输出捕获，用于分析失败原因
    _iaf_res=$(pm install -r -d -g -t "$_iaf_tmp" 2>&1)
    _iaf_status=$?

    rm -f "$_iaf_tmp"

    if [ $_iaf_status -eq 0 ] && echo "$_iaf_res" | grep -qi "Success"; then
        return 0
    else
        print "! $(get_i18n "INSTALL_FAILED"): $_iaf_res"
        return 1
    fi
}

ensure_termux() {
    _et_pkg="com.termux"
    
    # 2025年 Termux v0.119.0 (F-Droid 镜像直链，兼容性最好)
    _et_url="f-droid.org"

    if is_app_installed "$_et_pkg"; then
        return 0
    fi

    # confirm 函数内部会调用 ask 弹出选择框
    if confirm "TERMUX_NOT_FOUND" 0; then
        if install_app_from "$_et_url"; then
            print "$(get_i18n "TERMUX_INSTALLED")"
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}
