# shellcheck shell=ash
#
# singbox helper utilities
#

import rich
import self

singbox_pids() {
    if command -v pidof >/dev/null 2>&1; then
        pidof sing-box 2>/dev/null | tr ' ' '\n'
        _pidof_rc=$?
        [ "$_pidof_rc" -eq 0 ] && {
            unset _pidof_rc
            return 0
        }
    fi
    for _proc_comm in /proc/[0-9]*/comm; do
        [ -r "$_proc_comm" ] || continue
        if [ "$(cat "$_proc_comm" 2>/dev/null)" = "sing-box" ]; then
            _pid=${_proc_comm#/proc/}
            printf '%s\n' "${_pid%/comm}"
        fi
    done
    unset _pidof_rc _proc_comm _pid
}

singbox_set_status_description() {
    if [ "$1" = "running" ]; then
        _singbox_description="$(i18n 'SINGBOX_STATUS'): $(i18n 'RUNNING')"
    else
        _singbox_description="$(i18n 'SINGBOX_STATUS'): $(i18n 'NOT_RUNNING')"
    fi
    _singbox_current_description="$(config get override.description 2>/dev/null || true)"
    if [ "$_singbox_current_description" != "$_singbox_description" ]; then
        config set override.description "$_singbox_description"
    fi
    unset _singbox_description _singbox_current_description
}

is_singbox_running() {
    # Check if sing-box is running.
    # Returns 0 if sing-box is running, 1 otherwise.
    if [ -n "$(singbox_pids)" ]; then
        singbox_set_status_description running
        return 0
    else
        singbox_set_status_description stopped
        return 1
    fi
}

singbox_wait_ready() {
    _tries="${MAGICNET_SINGBOX_READY_TRIES:-5}"
    _delay="${MAGICNET_SINGBOX_READY_DELAY:-1}"
    _try=0
    while [ "$_try" -lt "$_tries" ]; do
        if is_singbox_running >/dev/null 2>&1; then
            if command -v curl >/dev/null 2>&1 &&
                curl -sS --max-time 1 http://127.0.0.1:9090/version >/dev/null 2>&1; then
                unset _tries _delay _try
                return 0
            fi
            if [ "$_try" -gt 0 ]; then
                unset _tries _delay _try
                return 0
            fi
        fi
        _try=$((_try + 1))
        sleep "$_delay"
    done
    unset _tries _delay _try
    return 1
}

singbox_tun() {
    mkdir -p /dev/net
    info "创建/dev/net/目录"

    if [ ! -e /dev/net/tun ]; then
        ln -s /dev/tun /dev/net/tun
        info "创建/dev/net/tun符号链接"
    fi

    if [ ! -c "/dev/net/tun" ]; then
        error "无法创建 /dev/net/tun，可能的原因："
        warn "系统不支持 TUN/TAP 驱动或内核不兼容"
        exit 1
    fi
    info "/dev/net/tun 为字符设备，检查通过"

}

singbox_prepare_route_config() {
    _singbox_route_config="$1"
    [ -f "$_singbox_route_config" ] || return 0

    _jq="${MODDIR}/bin/jq"
    if [ ! -x "$_jq" ]; then
        _jq="$(command -v jq 2>/dev/null || true)"
    fi
    if [ -n "$_jq" ]; then
        _tmp="${_singbox_route_config}.route.new"
        if "$_jq" '
            .route = ((.route // {})
                | .auto_detect_interface = false
                | del(.default_interface))
            | .outbounds = ((.outbounds // []) | map(
                if (.type // "") == "direct" then
                    del(.bind_interface)
                elif (.type // "") == "selector" then
                    .interrupt_exist_connections = true
                else
                    .
                end
            ))
        ' "$_singbox_route_config" >"$_tmp"; then
            mv -f "$_tmp" "$_singbox_route_config"
            unset _singbox_route_config _jq _tmp
            return 0
        fi
        rm -f "$_tmp"
    fi

    # Last-resort text fallback for minimal Android environments without jq.
    # Without jq, keep routing delegated to Android rather than retaining a stale interface.
    _tmp="${_singbox_route_config}.route.new"
    awk '
        function flush_previous() {
            if (have_previous) {
                print previous
            }
        }
        function count_structural_brace(text, target,    i, char, escaped, quoted, count) {
            for (i = 1; i <= length(text); i++) {
                char = substr(text, i, 1)
                if (quoted) {
                    if (escaped) {
                        escaped = 0
                    } else if (char == "\\") {
                        escaped = 1
                    } else if (char == "\"") {
                        quoted = 0
                    }
                } else if (char == "\"") {
                    quoted = 1
                } else if (char == target) {
                    count++
                }
            }
            return count
        }
        {
            current = $0
            open_count = count_structural_brace(current, "{")
            for (i = 1; i <= open_count; i++) {
                object_depth++
                object_type[object_depth] = ""
            }
            if (current ~ /^[[:space:]]*"type"[[:space:]]*:/) {
                current_type = current
                sub(/^.*"type"[[:space:]]*:[[:space:]]*"/, "", current_type)
                sub(/".*/, "", current_type)
                object_type[object_depth] = current_type
            }
            if (current ~ /^[[:space:]]*"auto_detect_interface"[[:space:]]*:/) {
                sub(/:[[:space:]]*(true|false)/, ": false", current)
            }
            if (object_type[object_depth] == "selector" &&
                current ~ /^[[:space:]]*"interrupt_exist_connections"[[:space:]]*:/) {
                sub(/:[[:space:]]*(true|false)/, ": true", current)
            }
            if (current ~ /^[[:space:]]*"(default_interface|bind_interface)"[[:space:]]*:/) {
                if (current !~ /,[[:space:]]*$/ && have_previous) {
                    sub(/,[[:space:]]*$/, "", previous)
                }
                next
            }
            flush_previous()
            previous = current
            have_previous = 1
            close_count = count_structural_brace(current, "}")
            for (i = 1; i <= close_count; i++) {
                delete object_type[object_depth]
                object_depth--
            }
        }
        END {
            flush_previous()
        }
    ' "$_singbox_route_config" >"$_tmp" && mv -f "$_tmp" "$_singbox_route_config" || rm -f "$_tmp"
    unset _singbox_route_config _jq _tmp
}

singbox_start() {
    if is_singbox_running; then
        warn "sing-box is already running."
        return 0
    fi

    singbox_tun

    _config="${MODDIR}/.config/sing-box/config.json"
    _log="${MODDIR}/.log/sing-box.log"
    _workdir="${MODDIR}/.config/sing-box"

    if [ ! -f "$_config" ]; then
        error "Config file not found: $_config"
        return 1
    fi

    singbox_prepare_route_config "$_config"
    [ -d "${MODDIR}/.log" ] || mkdir -p "${MODDIR}/.log"

    _attempt=1
    while [ "$_attempt" -le "${MAGICNET_SINGBOX_START_ATTEMPTS:-1}" ]; do
        info "Starting sing-box..."
        # 使用 nohup 后台运行，并将日志重定向
        nohup sing-box run -c "$_config" -D "$_workdir" >"$_log" 2>&1 &

        if singbox_wait_ready; then
            success "sing-box started successfully."
            unset _config _log _workdir _attempt
            return 0
        fi

        warn "sing-box process did not stay running; stopping partial start."
        singbox_stop >/dev/null 2>&1 || true
        _attempt=$((_attempt + 1))
        [ "$_attempt" -le "${MAGICNET_SINGBOX_START_ATTEMPTS:-1}" ] && sleep 1
    done

    error "sing-box failed to start. Check $_log for details."
    if [ -f "$_log" ]; then
        print "--- Log tail ---"
        tail -n 5 "$_log"
        print "----------------"
    fi
    unset _config _log _workdir _attempt
    return 1
}

singbox_stop() {
    if is_singbox_running; then
        info "Stopping sing-box..."
        _pids=$(singbox_pids)
        [ -n "$_pids" ] && kill $_pids 2>/dev/null || true
        sleep 1
        # 再次检查，如果还在运行则强杀
        if is_singbox_running; then
            _pids=$(singbox_pids)
            [ -n "$_pids" ] && kill -9 $_pids 2>/dev/null || true
        fi
    fi

    if ! is_singbox_running; then
        success "sing-box stopped."
        unset _pids
        return 0
    else
        error "Failed to stop sing-box."
        unset _pids
        return 1
    fi
}

toggle_singbox() {
    if is_singbox_running; then
        info "Stop and check"
        singbox_stop
    else
        info "Start and check"
        singbox_start
    fi
}

set_i18n "TOGGLE_SINGBOX" \
    "zh" "切换 sing-box 状态" \
    "en" "Toggle sing-box status" \
    "ja" "sing-box の状態を切り替え" \
    "ko" "sing-box 상태 전환"

set_i18n "SINGBOX_STATUS" \
    "zh" "sing-box状态" \
    "en" "sing-box status" \
    "ja" "sing-box の状態" \
    "ko" "sing-box 상태"

set_i18n "RUNNING" \
    "zh" "正在运行" \
    "en" "Running" \
    "ja" "実行中" \
    "ko" "실행 중"

set_i18n "NOT_RUNNING" \
    "zh" "未运行" \
    "en" "Not running" \
    "ja" "実行していません" \
    "ko" "実行 중 아님"

ask_toggle_singbox() {
    # Ask the user to toggle sing-box.
    # Question key:    TOGGLE_SINGBOX
    if is_singbox_running; then
        _singbox_state="$(i18n 'RUNNING')"
    else
        _singbox_state="$(i18n 'NOT_RUNNING')"
    fi
    panel "$(i18n 'SINGBOX_STATUS')"
    panel_row "$(i18n 'SINGBOX_STATUS')" "$_singbox_state"
    panel_end
    ask "TOGGLE_SINGBOX" \
        "CONFIRM" \
        'toggle_singbox' \
        "REFUSE" \
        'exit 0' \
        0
    unset _singbox_state
}
