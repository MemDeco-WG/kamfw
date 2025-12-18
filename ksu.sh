# shellcheck shell=ash
#
# rule-1
#
# 如果存在META-INF文件夹

if [ -d "${MODDIR}/META-INF" ]; then
  # 清理掉即可
  rm -rf "${MODDIR}/META-INF"
fi

# KSU 管理器：安装模块的实现
install_module() {
    _im_zip="$1"
    [ -f "$_im_zip" ] || return 1

    _im_bin=$(command -v ksud || echo "/data/adb/ksud")
    "$_im_bin" module install "$_im_zip"

    unset _im_zip _im_bin
}
