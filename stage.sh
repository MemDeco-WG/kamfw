# shellcheck shell=ash
get_stage() {
    # 1. 首先判断是否处于安装阶段
    # Magisk/KSU 在执行 customize.sh 时会注入 SKIPUNZIP
    if [ -n "$SKIPUNZIP" ]; then
        echo "install"
        return
    fi

    # 2. 获取当前执行脚本的文件名
    _gs_fn=$(basename "$0")

    # 3. 匹配元模块特有钩子 (Metamodule-specific hooks)
    # 4. 匹配标准模块文件 (Standard module files)
    case "$_gs_fn" in
        # 元模块特有
        metamount.sh)      echo "metamount"      ; return ;;
        metainstall.sh)    echo "metainstall"    ; return ;;
        metauninstall.sh)  echo "metauninstall"  ; return ;;
        
        # 标准脚本
        post-fs-data.sh)   echo "post-fs-data"   ; return ;;
        service.sh)        echo "service"        ; return ;;
        boot-completed.sh) echo "boot-completed" ; return ;;
        uninstall.sh)      echo "uninstall"      ; return ;;
        action.sh)         echo "action"         ; return ;;
        
        # 兼容性兜底
        customize.sh)      echo "install"        ; return ;;
    esac

}

is_installing()   { [ "$(get_stage)" = "install" ] ; }
is_metamount()    { [ "$(get_stage)" = "metamount" ] ; }
is_metainstall()  { [ "$(get_stage)" = "metainstall" ] ; }
is_post_fs()      { [ "$(get_stage)" = "post-fs-data" ] ; }
is_service()      { [ "$(get_stage)" = "service" ] ; }
is_boot_done()    { [ "$(get_stage)" = "boot-completed" ] ; }
