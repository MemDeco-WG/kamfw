# shellcheck shell=ash
#
# rule-1
#
# 如果存在boot-completed.sh 文件
if [ -f "${MODDIR}/boot-completed.sh" ]; then
    # 重命名为service.sh
    mv "${MODDIR}/boot-completed.sh" "${MODDIR}/service.sh"
fi

# rule-2
#
# 如果不存在META-INF/com/google/android/update-script 文件
if [ ! -f "${MODDIR}/META-INF/com/google/android/update-binary" ]; then
    # 写入 #MAGISK
    echo "#MAGISK" > "${MODDIR}/META-INF/com/google/android/update-script"
fi

# rule-3
#
# 如果不存在META-INF/com/google/android/update-binary 文件
if [ ! -f "${MODDIR}/META-INF/com/google/android/update-binary" ]; then
    # 写入
    cat <<EOF > "${MODDIR}/META-INF/com/google/android/update-binary"
#!/sbin/sh

#################
# Initialization
#################

umask 022

# echo before loading util_functions
ui_print() { echo "$1"; }
require_new_magisk() {
ui_print "*******************************"
ui_print " Please install Magisk v20.4+! "
ui_print "*******************************"
exit 1
}

#########################
# Load util_functions.sh
#########################

OUTFD=$2
ZIPFILE=$3

mount /data 2>/dev/null

[ -f /data/adb/magisk/util_functions.sh ] || require_new_magisk
. /data/adb/magisk/util_functions.sh
[ $MAGISK_VER_CODE -lt 20400 ] && require_new_magisk

install_module
exit 0
EOF
fi

# Magisk 管理器：安装模块的实现
install_module() {
    _im_zip="$1"
    [ -f "$_im_zip" ] || return 1

    magisk --install-module "$_im_zip"

    unset _im_zip
}
