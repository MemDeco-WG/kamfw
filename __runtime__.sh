# shellcheck shell=ash
# __runtime__.sh
# 统一生命周期运行时：负责 KAM_HOME 初始化、PATH/LD_LIBRARY_PATH、以及 phase 调度

import __termux__

# -----------------------------
# KAM_HOME / HOME 初始化
# Lead 定案：KAM_HOME = $MODDIR
# -----------------------------
kamfw_init_home() {
    # MODDIR 在入口脚本里通常已设置；这里做兜底
    if [ -z "$MODDIR" ]; then
        MODDIR=${0%/*}
        export MODDIR
    fi

    export KAM_HOME="$MODDIR"
    export HOME="$MODDIR"

    # 约定目录（类 XDG，但根是 $MODDIR）
    # 注：按需求显式创建 .config/.local/...，不引入新的 .kam 根目录
    for _d in \
        "$KAM_HOME/.config" \
        "$KAM_HOME/.local" \
        "$KAM_HOME/.local/bin" \
        "$KAM_HOME/.local/lib" \
        "$KAM_HOME/.cache" \
        "$KAM_HOME/.state" \
        "$KAM_HOME/.log" \
        "$KAM_HOME/.tmp"; do
        [ -d "$_d" ] || mkdir -p "$_d" 2>/dev/null
    done

    unset _d
}

# -----------------------------
# Termux 环境（若可用则激活）
# -----------------------------
kamfw_init_termux() {
    # __termux__ 内部可能会判断环境；这里保持调用幂等
    active_termux_env
}

# -----------------------------
# PATH / LD_LIBRARY_PATH
# -----------------------------
kamfw_init_paths() {
    # 优先模块 HOME 的 .local/bin，其次模块自带 bin
    # 再补齐 root manager 与系统常用路径
    export PATH="$KAM_HOME/.local/bin:$MODDIR/bin:/data/adb/magisk:/data/adb/ksu/bin:/system/bin:/system/xbin:/sbin:$PATH"

    # 动态库优先模块 HOME 的 .local/lib
    export LD_LIBRARY_PATH="$KAM_HOME/.local/lib:$MODDIR/lib:$LD_LIBRARY_PATH"
}

# -----------------------------
# 生命周期调度（最小实现）
# 入口脚本应调用：kamfw run <phase> -- "$@"
# -----------------------------
kamfw() {
    _cmd="$1"; shift

    case "$_cmd" in
        run)
            kamfw_run "$@"
            ;;
        *)
            # 兼容未来扩展
            # 关键路径：输出必须走统一通道；error 失败视为框架未初始化，直接 abort。
            error "Invalid kamfw command: $_cmd" || abort "Invalid kamfw command: $_cmd"
            return 1
            ;;
    esac

    unset _cmd
}

kamfw_run() {
    _phase="$1"; shift

    # 允许：kamfw run <phase> -- <args>
    if [ "${1:-}" = "--" ]; then
        shift
    fi

    kamfw_init_home
    kamfw_init_termux
    kamfw_init_paths

    # Phase 路由：优先调用 shell 侧实现（后续 rust CLI ready 后可改为优先 rust）
    case "$_phase" in
        install)
            import __install_core__
            kamfw_phase_install "$@"
            ;;
        post-fs-data)
            kamfw_phase_post_fs_data "$@"
            ;;
        service)
            kamfw_phase_service "$@"
            ;;
        boot-completed)
            kamfw_phase_boot_completed "$@"
            ;;
        uninstall)
            import __uninstall__
            kamfw_phase_uninstall "$@"
            ;;
        action)
            kamfw_phase_action "$@"
            ;;
        post-mount)
            kamfw_phase_post_mount "$@"
            ;;
        *)
            # 关键路径：输出必须走统一通道；error 失败视为框架未初始化，直接 abort。
            error "Unknown phase: $_phase" || abort "Unknown phase: $_phase"
            return 2
            ;;
    esac

    unset _phase
}

# -----------------------------
# 默认 phase 实现（模板最小可运行；业务可覆盖这些函数）
# -----------------------------
kamfw_phase_install() { :; }
kamfw_phase_post_fs_data() { :; }
kamfw_phase_service() { :; }
kamfw_phase_boot_completed() { :; }
kamfw_phase_uninstall() { :; }
kamfw_phase_action() { :; }
kamfw_phase_post_mount() { :; }
