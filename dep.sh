# shellcheck shell=ash

# =============================================================================
# 依赖检查接口 (Dependency Checker)
# =============================================================================
# 功能：验证当前环境是否满足指定的管理器、应用或模块依赖。
#
# 用法: depends_on <类型> <目标列表> [版本规范]
#
# 参数说明:
#   <类型>      : manager (Root管理器), app (应用程序包名), module (Magisk/KSU 模块 ID)
#   <目标列表>  : 支持单个目标或空格分隔的多个目标（多选一）。
#   [版本规范]  : 可选。支持 =, ==, >=, <=, >, < (例如 ">=1.0.0")。
#                  可显式比较版本代号（versionCode），在规范前加 `code` 或 `versionCode` 前缀，例如 "code>=123"。
#                  默认比较版本名（应用的 versionName 或模块的 version/versionName）。
#
# 返回值:
#   0 - 依赖已满足
#   1 - 类型错误或参数无效
#   2 - 依赖未安装或管理器类型不匹配
#   3 - 依赖已安装但无法获取所需版本信息（例如缺少 versionName 或 versionCode），因此跳过校验
#   4 - 依赖已安装但版本不满足规范
#
# 示例:
#   depends_on manager "magisk ksu" ">=26.0"        # 支持 Magisk 或 KSU，且 Magisk 需 >= 26.0
#   depends_on manager "magisk ksu ap"              # 只要是这三者之一即可，不检查版本
#   depends_on app "com.android.settings"           # 检查系统设置是否存在
#   depends_on app "com.example.app" ">=1.2.3"      # 检查应用的 versionName
#   depends_on app "com.example.app" "code>=123"    # 检查应用的 versionCode
#   depends_on module "busybox-ndk" ">=1.34.1"      # 检查模块的 version/versionName
#   depends_on module "busybox-ndk" "code>=42"      # 检查模块的 versionCode
#
# 注: 2025年适配已支持 Magisk (-v), KernelSU (ksud -V), APatch (apd -V) 的版本提取。
# =============================================================================

_depends_on_manager() {
    _dom_target="$1"
    _dom_spec="$2"
    _dom_curr=$(get_manager)
    _dom_ret=0

    case " $_dom_target " in
        *" $_dom_curr "*)
            if [ -n "$_dom_spec" ]; then
                _dom_v=""
                case "$_dom_curr" in
                    magisk) _dom_v=$(magisk -v 2>/dev/null | cut -d':' -f1) ;;
                    ksu)   _dom_v=$(ksud -V 2>/dev/null | cut -d' ' -f1)
                            [ -z "$_dom_v" ] && _dom_v=$(getprop kernelsu.version) ;;
                    ap)     _dom_v=$(apd -V 2>/dev/null | cut -d' ' -f1) ;;
                esac

                if [ -n "$_dom_v" ]; then
                    _dom_p=$(_depends_parse_version_spec "$_dom_spec")
                    _dom_op=${_dom_p%% *}
                    _dom_req=${_dom_p#* }
                    # 如果用户指定了 versionCode，尝试提取数字代号再比较
                    if [ "${_DEPENDS_SPEC_FIELD:-ver}" = "code" ]; then
                        _dom_v_num=$(printf '%s' "$_dom_v" | sed 's/[^0-9].*$//')
                        if [ -n "$_dom_v_num" ]; then
                            _dom_v="$_dom_v_num"
                        else
                            warn "Unable to get version code for $_dom_curr, skipping check."
                            _dom_ret=3
                        fi
                    fi

                    if [ "$_dom_ret" -eq 0 ]; then
                        _depends_version_satisfies "$_dom_v" "$_dom_op" "$_dom_req"
                        _dom_ret=$?
                    fi
                else
                    warn "Unable to get version for $_dom_curr, skipping check."
                    _dom_ret=3
                fi
            fi
            ;;
        *)
            error "Manager mismatch: current is $_dom_curr, but requires: $_dom_target"
            _dom_ret=2
            ;;
    esac
    _dom_final_ret=$_dom_ret
    unset _dom_target _dom_spec _dom_curr _dom_ret _dom_v _dom_p _DEPENDS_SPEC_FIELD
    return "$_dom_final_ret"
}

# ---------------------------
# 版本解析与比较辅助函数
# ---------------------------

# 解析版本规范，输出 "<op> <version>"，例如 ">= 1.2.3"
# 支持显式指定版本代号 (versionCode)，例： "code>=100" 或 "versionCode >= 100"
_depends_parse_version_spec() {
    _dps_spec="$1"
    _dps_spec=$(printf '%s' "$_dps_spec" | awk '{$1=$1;print}')

    # 默认比较字段为 version name
    _DEPENDS_SPEC_FIELD="ver"
    _dps_lc=$(printf '%s' "$_dps_spec" | tr '[:upper:]' '[:lower:]')
    case "$_dps_lc" in
        code:*|code=*|code\ *)
            _DEPENDS_SPEC_FIELD="code"
            _dps_spec=$(printf '%s' "$_dps_spec" | sed -E 's/^[cC][oO][dD][eE][[:space:][:punct:]]*//')
            ;;
        versioncode:*|versioncode=*|versioncode\ *)
            _DEPENDS_SPEC_FIELD="code"
            _dps_spec=$(printf '%s' "$_dps_spec" | sed -E 's/^[vV][eE][rR][sS][iI][oO][nN][cC][oO][dD][eE][[:space:][:punct:]]*//')
            ;;
    esac

    case "$_dps_spec" in
        '=='*) _op='==' ; _ver="${_dps_spec#==}" ;;
        '='*)  _op='==' ; _ver="${_dps_spec#=}"  ;;
        '>='*) _op='>=' ; _ver="${_dps_spec#>=}" ;;
        '<='*) _op='<=' ; _ver="${_dps_spec#<=}" ;;
        '>'*)  _op='>'  ; _ver="${_dps_spec#>}"  ;;
        '<'*)  _op='<'  ; _ver="${_dps_spec#<}"  ;;
        *)     _op='==' ; _ver="$_dps_spec"       ;;
    esac
    _ver=$(printf '%s' "$_ver" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    printf '%s %s' "$_op" "$_ver"
}

# 比较两个版本号，输出 -1 (v1<v2), 0 (v1==v2), 1 (v1>v2)
_depends_version_cmp() {
    _v1="$1"
    _v2="$2"

    # 规范化：去掉前导 v/V，将非数字字符替换为点，合并连续点，去除首尾点
    _v1=$(printf '%s' "$_v1" | sed 's/^[vV]//;s/[^0-9.]/./g' | tr -s '.' | sed 's/^\.//;s/\.$//')
    _v2=$(printf '%s' "$_v2" | sed 's/^[vV]//;s/[^0-9.]/./g' | tr -s '.' | sed 's/^\.//;s/\.$//')

    _r1="$_v1"
    _r2="$_v2"
    while [ -n "$_r1" ] || [ -n "$_r2" ]; do
        s1=$(printf '%s' "$_r1" | cut -d. -f1)
        s2=$(printf '%s' "$_r2" | cut -d. -f1)
        s1=${s1:-0}
        s2=${s2:-0}

        if [ "$s1" -lt "$s2" ] 2>/dev/null; then
            printf '%s' -1
            return 0
        elif [ "$s1" -gt "$s2" ] 2>/dev/null; then
            printf '%s' 1
            return 0
        fi

        if printf '%s' "$_r1" | grep -q '\.'; then
            _r1=$(printf '%s' "$_r1" | cut -d. -f2-)
        else
            _r1=""
        fi
        if printf '%s' "$_r2" | grep -q '\.'; then
            _r2=$(printf '%s' "$_r2" | cut -d. -f2-)
        else
            _r2=""
        fi
    done

    printf '%s' 0
}

# 判断版本是否满足规范：
# 返回 0 表示满足，3 表示无法获取版本（跳过），4 表示版本不满足，1 表示未知操作符或错误
_depends_version_satisfies() {
    _curr="$1"
    _op="$2"
    _req="$3"

    if [ -z "$_curr" ] || [ -z "$_req" ]; then
        return 3
    fi

    _cmp=$(_depends_version_cmp "$_curr" "$_req")
    case "$_op" in
        '=='| '=')
            [ "$_cmp" -eq 0 ] && return 0 || return 4
            ;;
        '>')
            [ "$_cmp" -gt 0 ] && return 0 || return 4
            ;;
        '<')
            [ "$_cmp" -lt 0 ] && return 0 || return 4
            ;;
        '>=')
            [ "$_cmp" -ge 0 ] && return 0 || return 4
            ;;
        '<=')
            [ "$_cmp" -le 0 ] && return 0 || return 4
            ;;
        *)
            warn "Unknown version operator: $_op"
            return 1
            ;;
    esac
}

# ---------------------------
# 应用依赖检查
# 支持多个候选包（只需满足其中一个），可选版本规则
# 返回:
# 0 - 依赖已满足
# 2 - 未安装
# 3 - 已安装但无法获取版本（跳过）
# 4 - 已安装但版本不满足
# ---------------------------
_depends_on_app() {
    _doa_target="$1"
    _doa_spec="$2"
    _doa_ret=2

    for _pkg in $_doa_target; do
        if command -v pm >/dev/null 2>&1 && pm path "$_pkg" >/dev/null 2>&1; then
            if [ -z "$_doa_spec" ]; then
                _doa_ret=0
                break
            fi

            # 先解析规格以支持 versionCode 比较
            _doa_p=$(_depends_parse_version_spec "$_doa_spec")
            _doa_op=${_doa_p%% *}
            _doa_req=${_doa_p#* }
            _doa_field=${_DEPENDS_SPEC_FIELD:-ver}

            # 只调用一次 dumpsys，提取 versionName / versionCode
            _dumpsys=$(dumpsys package "$_pkg" 2>/dev/null)
            _vn=$(printf '%s' "$_dumpsys" | sed -n 's/.*versionName=\(.*\)/\1/p' | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            _vc=$(printf '%s' "$_dumpsys" | sed -n 's/.*versionCode=\(.*\)/\1/p' | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            if [ "$_doa_field" = "code" ]; then
                if [ -n "$_vc" ]; then
                    _doa_v="$_vc"
                else
                    warn "Unable to get version code for package $_pkg, skipping check."
                    _doa_ret=3
                fi
            else
                if [ -n "$_vn" ]; then
                    _doa_v="$_vn"
                elif [ -n "$_vc" ]; then
                    # 当没有 versionName 时回退使用 versionCode
                    _doa_v="$_vc"
                else
                    warn "Unable to get version for package $_pkg, skipping check."
                    _doa_ret=3
                fi
            fi

            if [ -n "$_doa_v" ]; then
                _depends_version_satisfies "$_doa_v" "$_doa_op" "$_doa_req"
                _doa_ret=$?
            fi

            unset _DEPENDS_SPEC_FIELD _dumpsys _vn _vc
            break
        fi
    done

    unset _doa_target _doa_spec _doa_v _doa_p _pkg _DEPENDS_SPEC_FIELD _dumpsys _vn _vc
    return "$_doa_ret"
}

# ---------------------------
# 模块依赖检查（Magisk / KSU 常见路径）
# 支持多个候选模块 id（多选一），可选版本规格
# 返回码与应用一致
# ---------------------------
_depends_on_module() {
    _dom_target="$1"
    _dom_spec="$2"
    _dom_ret=2
    _found_dir=""

    for _mid in $_dom_target; do
        if [ -d "/data/adb/modules/$_mid" ]; then
            _found_dir="/data/adb/modules/$_mid"
        fi

        if [ -n "$_found_dir" ]; then
            _dom_ret=0
            break
        fi
    done

    if [ "$_dom_ret" -ne 0 ]; then
        error "Module not installed: $_dom_target"
        unset _dom_target _dom_spec _mid _found_dir
        return 2
    fi

    if [ -n "$_dom_spec" ]; then
        _prop="$_found_dir/module.prop"
        _dom_v=""
        _dom_p=$(_depends_parse_version_spec "$_dom_spec")
        _dom_op=${_dom_p%% *}
        _dom_req=${_dom_p#* }
        _dom_field=${_DEPENDS_SPEC_FIELD:-ver}

        if [ -f "$_prop" ]; then
            _dom_vn=$(sed -n -e 's/^version=//p' -e 's/^versionName=//p' "$_prop" | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            _dom_vc=$(sed -n -e 's/^versionCode=//p' "$_prop" | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi

        if [ "${_dom_field}" = "code" ]; then
            if [ -n "$_dom_vc" ]; then
                _dom_v="$_dom_vc"
            else
                warn "Unable to get version code for module $_mid, skipping check."
                _dom_ret=3
            fi
        else
            if [ -n "$_dom_vn" ]; then
                _dom_v="$_dom_vn"
            elif [ -n "$_dom_vc" ]; then
                # 回退到 versionCode（如果没有 versionName）
                _dom_v="$_dom_vc"
            else
                warn "Unable to get version for module $_mid, skipping check."
                _dom_ret=3
            fi
        fi

        if [ -n "$_dom_v" ]; then
            _depends_version_satisfies "$_dom_v" "$_dom_op" "$_dom_req"
            _dom_ret=$?
        fi

        unset _DEPENDS_SPEC_FIELD _dom_vn _dom_vc _dom_op _dom_req _dom_field
    fi

    unset _dom_target _dom_spec _mid _found_dir _prop _dom_v _dom_p _DEPENDS_SPEC_FIELD _dom_vn _dom_vc _dom_op _dom_req _dom_field
    return "$_dom_ret"
}

# ---------------------------
# 统一入口：depends_on <type> <targets> [spec]
# ---------------------------
depends_on() {
    _do_type="$1"
    _do_target="$2"
    _do_spec="$3"
    _do_res=0

    case "$_do_type" in
        manager) _depends_on_manager "$_do_target" "$_do_spec" ;;
        app)     _depends_on_app "$_do_target" "$_do_spec" ;;
        module)  _depends_on_module "$_do_target" "$_do_spec" ;;
        *)
            error "Unknown dependency type: $_do_type"
            _do_res=1
            ;;
    esac

    # 捕获子函数的返回码
    _do_res=${_do_res:-$?}

    unset _do_type _do_target _do_spec
    return "$_do_res"
}
