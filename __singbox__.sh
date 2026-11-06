# shellcheck shell=ash
import rich
import self

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

set_i18n "PROCESS_STATE_UNKNOWN" \
    "zh" "进程状态未知" \
    "en" "Process state unknown" \
    "ja" "プロセス状態不明" \
    "ko" "프로세스 상태 알 수 없음"

set_i18n "SINGBOX_INBOUND_CHECK_UNAVAILABLE" \
    "zh" "无法读取 sing-box 受管透明入站类型" \
    "en" "Unable to read the managed sing-box transparent inbound type" \
    "ja" "sing-box の管理対象透過インバウンド種別を読み取れません" \
    "ko" "관리되는 sing-box 투명 인바운드 유형을 읽을 수 없습니다"

set_i18n "SINGBOX_MANAGED_INBOUND_INVALID" \
    "zh" "sing-box 配置不能同时包含多个 tun 或 ebpf 透明入站" \
    "en" "The sing-box config cannot contain multiple tun or ebpf transparent inbounds" \
    "ja" "sing-box 設定に複数の tun または ebpf 透過インバウンドを含めることはできません" \
    "ko" "sing-box 구성에는 여러 tun 또는 ebpf 투명 인바운드를 포함할 수 없습니다"

set_i18n "SINGBOX_START_CLEANUP_FAILED" \
    "zh" "sing-box 启动回收未完成，已取消重试。" \
    "en" "Partial sing-box shutdown is incomplete; startup retry aborted."
set_i18n "SINGBOX_STOP_PROCESS_CHANGED" \
    "zh" "停止期间 sing-box 进程已变化，未执行强制终止。" \
    "en" "sing-box process set changed during stop; escalation aborted."
set_i18n "SINGBOX_STOP_GRACE_EXPIRED" \
    "zh" "sing-box 正常退出等待超时，正在强制停止。" \
    "en" "sing-box graceful shutdown timed out; forcing stop."
set_i18n "SINGBOX_STOP_SIGNAL_FAILED" \
    "zh" "sing-box 停止信号未送达，进程状态仍未确认。" \
    "en" "Failed to deliver sing-box stop signal; process state is unresolved."

singbox_pids_to_file() {
    if command -v magicnet_singbox_owned_pids_to_file >/dev/null 2>&1; then
        magicnet_singbox_owned_pids_to_file "$MODDIR/.config/sing-box/config.json" "$1"
    elif command -v magicnet_proc_named_pids_to_file >/dev/null 2>&1; then
        magicnet_proc_named_pids_to_file sing-box "$1"
    else return 2; fi
}

singbox_pids() (
    command -v magicnet_proc_query_temp_create >/dev/null 2>&1 || return 2
    file=$(magicnet_proc_query_temp_create) || return 2
    trap 'rm -f "$file"' EXIT
    singbox_pids_to_file "$file" || return $?
    cat "$file"
)

singbox_set_status_description() (
    [ "$1" = running ] || [ ! -s "$MODDIR/.state/startup-error" ] || return 0
    if [ "$1" = running ]; then status=$(i18n RUNNING); else status=$(i18n NOT_RUNNING); fi
    description="$(i18n SINGBOX_STATUS): $status"
    [ "$(config get override.description 2>/dev/null)" = "$description" ] || config set override.description "$description"
)

is_singbox_running() (
    file=$(magicnet_proc_query_temp_create) || return 2
    trap 'rm -f "$file"' EXIT
    if singbox_pids_to_file "$file"; then result=0; else result=$?; fi
    case "$result" in
        0) singbox_set_status_description running ;;
        1) singbox_set_status_description stopped ;;
        *) return 2 ;;
    esac
    return "$result"
)

singbox_wait_ready() (
    attempt=0
    while [ "$attempt" -lt "${MAGICNET_SINGBOX_READY_TRIES:-5}" ]; do
        if is_singbox_running >/dev/null 2>&1; then
            if command -v curl >/dev/null 2>&1 && curl -sS --max-time 1 http://127.0.0.1:9090/version >/dev/null 2>&1; then return 0; fi
            [ "$attempt" -eq 0 ] || return 0
        fi
        attempt=$((attempt + 1))
        sleep "${MAGICNET_SINGBOX_READY_DELAY:-1}"
    done
    return 1
)

singbox_tun() {
    mkdir -p /dev/net || return 1
    info '创建/dev/net/目录'
    if [ ! -e /dev/net/tun ]; then
        ln -s /dev/tun /dev/net/tun || return 1
        info '创建/dev/net/tun符号链接'
    fi
    if [ ! -c /dev/net/tun ]; then
        error '无法创建 /dev/net/tun，可能的原因：'
        warn '系统不支持 TUN/TAP 驱动或内核不兼容'
        return 1
    fi
    info '/dev/net/tun 为字符设备，检查通过'
}

singbox_managed_inbound_type() (
    [ -f "$1" ] && [ -x "$MODDIR/bin/jq" ] || { error "$(i18n SINGBOX_INBOUND_CHECK_UNAVAILABLE)"; return 1; }
    type=$("$MODDIR/bin/jq" -r '
        [.inbounds[]? | select((.type // "") == "tun" or (.type // "") == "ebpf") | .type]
        | if length == 0 then "none" elif length == 1 then .[0] else "" end
    ' "$1") || return 1
    case "$type" in none|tun|ebpf) printf '%s\n' "$type" ;; *) error "$(i18n SINGBOX_MANAGED_INBOUND_INVALID)"; return 1 ;; esac
)

singbox_prepare_dataplane() {
    case "$(singbox_managed_inbound_type "$1")" in tun) singbox_tun ;; none|ebpf) return 0 ;; *) return 1 ;; esac
}

singbox_start() (
    if is_singbox_running; then state=0; else state=$?; fi
    case "$state" in
        0) warn 'sing-box is already running.'; return 0 ;;
        1) ;;
        *) error 'sing-box process discovery is indeterminate; start aborted.'; return 2 ;;
    esac
    config=$MODDIR/.config/sing-box/config.json
    logfile=$MODDIR/.log/sing-box.log
    [ -f "$config" ] || { error "Config file not found: $config"; return 1; }
    singbox_prepare_dataplane "$config" && singbox_prepare_route_config "$config" || return 1
    mkdir -p "$MODDIR/.log" || return 1
    attempt=1
    while [ "$attempt" -le "${MAGICNET_SINGBOX_START_ATTEMPTS:-1}" ]; do
        info 'Starting sing-box...'
        if command -v magicnet_core_launch >/dev/null 2>&1; then
            magicnet_core_launch singbox_wait_ready && { success 'sing-box started successfully.'; return 0; }
        else
            nohup sing-box run -c "$config" -D "${config%/*}" >"$logfile" 2>&1 &
            singbox_wait_ready && { success 'sing-box started successfully.'; return 0; }
        fi
        warn 'sing-box process did not stay running; stopping partial start.'
        singbox_stop || { error "$(i18n SINGBOX_START_CLEANUP_FAILED)"; return 2; }
        attempt=$((attempt + 1))
        [ "$attempt" -gt "${MAGICNET_SINGBOX_START_ATTEMPTS:-1}" ] || sleep 1
    done
    error "sing-box failed to start. Check $logfile for details."
    if [ -f "$logfile" ]; then print '--- Log tail ---'; tail -n 5 "$logfile"; print '----------------'; fi
    return 1
)

toggle_singbox() {
    if is_singbox_running; then _st_state=0; else _st_state=$?; fi
    case "$_st_state" in
        0) info 'Stop and check'; singbox_stop ;;
        1) info 'Start and check'; singbox_start ;;
        *) error 'sing-box process discovery is indeterminate; toggle aborted.'; return 2 ;;
    esac
}

ask_toggle_singbox() {
    if is_singbox_running; then _st_state=0; else _st_state=$?; fi
    case "$_st_state" in 0) _st_label=RUNNING ;; 1) _st_label=NOT_RUNNING ;; *) _st_label=PROCESS_STATE_UNKNOWN ;; esac
    panel "$(i18n SINGBOX_STATUS)"
    panel_row "$(i18n SINGBOX_STATUS)" "$(i18n "$_st_label")"
    panel_end
    ask TOGGLE_SINGBOX CONFIRM toggle_singbox REFUSE 'exit 0' 0
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
            if mv -f "$_tmp" "$_singbox_route_config"; then
                unset _singbox_route_config _jq _tmp
                return 0
            fi
        fi
        rm -f "$_tmp"
    fi

    # Last-resort text fallback for minimal Android environments without jq.
    # Without jq, keep routing delegated to Android rather than retaining a stale interface.
    _tmp="${_singbox_route_config}.route.new"
    _route_rc=1
    if awk '
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
    ' "$_singbox_route_config" >"$_tmp" &&
        mv -f "$_tmp" "$_singbox_route_config"; then
        _route_rc=0
    else
        rm -f "$_tmp"
    fi
    unset _singbox_route_config _jq _tmp
    return "$_route_rc"
}

singbox_signal_pids_file() (
    _singbox_signal_file="$1"
    _singbox_signal="$2"
    _singbox_signal_probe=
    trap '[ -z "$_singbox_signal_probe" ] || rm -f "$_singbox_signal_probe"' EXIT
    case "$_singbox_signal" in 15 | 9) ;; *) return 2 ;; esac
    while IFS= read -r _singbox_signal_pid; do
        magicnet_pid_valid "$_singbox_signal_pid" || return 2
        if kill "-$_singbox_signal" "$_singbox_signal_pid" 2>/dev/null; then
            continue
        fi
        [ -n "$_singbox_signal_probe" ] ||
            _singbox_signal_probe=$(magicnet_proc_query_temp_create) || return 2
        if singbox_pids_to_file "$_singbox_signal_probe"; then
            if grep -Fx "$_singbox_signal_pid" "$_singbox_signal_probe" >/dev/null 2>&1; then
                :
            else
                _singbox_signal_state=$?
                [ "$_singbox_signal_state" -ne 1 ] || continue
            fi
        else
            _singbox_signal_state=$?
            [ "$_singbox_signal_state" -ne 1 ] || continue
        fi
        error "$(i18n 'SINGBOX_STOP_SIGNAL_FAILED')"
        return 2
    done <"$_singbox_signal_file"
)

singbox_wait_stopped() {
    _singbox_wait_file="$1"
    _singbox_wait_polls="$2"
    while :; do
        if singbox_pids_to_file "$_singbox_wait_file"; then
            :
        else
            _singbox_wait_state=$?
            case "$_singbox_wait_state" in
            1) return 1 ;;
            *) return 2 ;;
            esac
        fi
        [ "$_singbox_wait_polls" -gt 0 ] || return 0
        sleep 0.2 || return 2
        _singbox_wait_polls=$((_singbox_wait_polls - 1))
    done
}

singbox_stop() (
    _singbox_stop_file=$(magicnet_proc_query_temp_create) || return 2
    _singbox_stop_initial=$(magicnet_proc_query_temp_create) || {
        rm -f "$_singbox_stop_file"
        return 2
    }
    trap 'rm -f "$_singbox_stop_file" "$_singbox_stop_initial"' EXIT
    if singbox_pids_to_file "$_singbox_stop_initial"; then
        _singbox_stop_state=0
    else
        _singbox_stop_state=$?
    fi
    case "$_singbox_stop_state" in
    1)
        success "sing-box stopped."
        return 0
        ;;
    0) ;;
    *)
        error "sing-box process discovery is indeterminate; stop aborted."
        return 2
        ;;
    esac

    info "Stopping sing-box..."
    singbox_signal_pids_file "$_singbox_stop_initial" 15 || return 2
    # Android auto_redirect teardown can take ~3 seconds. Allow 10 seconds
    # of polling sleeps instead of interrupting cleanup with SIGKILL at 1s.
    if singbox_wait_stopped "$_singbox_stop_file" 50; then
        _singbox_stop_state=0
    else
        _singbox_stop_state=$?
    fi
    if [ "$_singbox_stop_state" -eq 0 ]; then
        # Newly discovered PIDs did not receive SIGTERM. Do not escalate a
        # replacement using the previous generation's already-expired budget.
        while IFS= read -r _singbox_stop_pid; do
            if ! grep -Fx "$_singbox_stop_pid" "$_singbox_stop_initial" >/dev/null 2>&1; then
                error "$(i18n 'SINGBOX_STOP_PROCESS_CHANGED')"
                return 2
            fi
        done <"$_singbox_stop_file"
        warn "$(i18n 'SINGBOX_STOP_GRACE_EXPIRED')"
        singbox_signal_pids_file "$_singbox_stop_file" 9 || return 2
        if singbox_wait_stopped "$_singbox_stop_file" 5; then
            _singbox_stop_state=0
        else
            _singbox_stop_state=$?
        fi
    fi
    case "$_singbox_stop_state" in
    1)
        success "sing-box stopped."
        return 0
        ;;
    2)
        error "sing-box stop state is indeterminate."
        return 2
        ;;
    *)
        error "Failed to stop sing-box."
        return 1
        ;;
    esac
)
