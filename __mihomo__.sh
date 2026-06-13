# shellcheck shell=ash
#
# mihomo helper utilities
#

import rich
import self

mihomo_pids() {
	if command -v pidof >/dev/null 2>&1; then
		pidof mihomo 2>/dev/null | tr ' ' '\n'
		_pidof_rc=$?
		[ "$_pidof_rc" -eq 0 ] && {
			unset _pidof_rc
			return 0
		}
	fi
	for _proc_comm in /proc/[0-9]*/comm; do
		[ -r "$_proc_comm" ] || continue
		if [ "$(cat "$_proc_comm" 2>/dev/null)" = "mihomo" ]; then
			_pid=${_proc_comm#/proc/}
			printf '%s\n' "${_pid%/comm}"
		fi
	done
	unset _pidof_rc _proc_comm _pid
}

mihomo_set_status_description() {
	if [ "$1" = "running" ]; then
		_mihomo_description="$(i18n 'MIHOMO_STATUS'): $(i18n 'RUNNING')"
	else
		_mihomo_description="$(i18n 'MIHOMO_STATUS'): $(i18n 'NOT_RUNNING')"
	fi
	_mihomo_current_description="$(config get override.description 2>/dev/null || true)"
	if [ "$_mihomo_current_description" != "$_mihomo_description" ]; then
		config set override.description "$_mihomo_description"
	fi
	unset _mihomo_description _mihomo_current_description
}

is_mihomo_running() {
	# Check if MiHoMo is running.
	# Returns 0 if MiHoMo is running, 1 otherwise.
	if [ -n "$(mihomo_pids)" ]; then
		mihomo_set_status_description running
		return 0
	else
		mihomo_set_status_description stopped
		return 1
	fi
}

mihomo_protect_pid() {
	_pid="$1"
	[ -n "$_pid" ] || return 0

	if [ -w "/proc/$_pid/oom_score_adj" ]; then
		echo -1000 >"/proc/$_pid/oom_score_adj" 2>/dev/null || true
	fi
	if [ -w "/proc/$_pid/oom_adj" ]; then
		echo -17 >"/proc/$_pid/oom_adj" 2>/dev/null || true
	fi
}

mihomo_protect_running() {
	for _pid in $(mihomo_pids); do
		mihomo_protect_pid "$_pid"
	done
	unset _pid
}

mihomo_tun() {
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

mihomo_start() {
	if is_mihomo_running; then
		warn "mihomo is already running."
		mihomo_protect_running
		return 0
	fi

	mihomo_tun

	_config="${MODDIR}/.config/mihomo/config.yaml"
	_workdir="${MODDIR}/.config/mihomo"
	_log="${MODDIR}/.log/mihomo.log"

	if [ ! -f "$_config" ]; then
		error "Config file not found: $_config"
		mihomo_set_status_description stopped
		return 1
	fi

	[ -d "${MODDIR}/.log" ] || mkdir -p "${MODDIR}/.log"

	info "Starting mihomo..."
	nohup mihomo -f "$_config" -d "$_workdir" >"$_log" 2>&1 &
	_pid=$!
	mihomo_protect_pid "$_pid"

	sleep 1

	if is_mihomo_running; then
		mihomo_protect_running
		success "mihomo started successfully."
		return 0
	fi

	error "mihomo failed to start. Check $_log for details."
	if [ -f "$_log" ]; then
		print "--- Log tail ---"
		tail -n 5 "$_log"
		print "----------------"
	fi
	return 1
}

mihomo_stop() {
	if is_mihomo_running; then
		info "Stopping mihomo..."
		for _pid in $(mihomo_pids); do
			kill "$_pid" 2>/dev/null || true
		done
		unset _pid
		sleep 1
		if is_mihomo_running; then
			for _pid in $(mihomo_pids); do
				kill -9 "$_pid" 2>/dev/null || true
			done
			unset _pid
			sleep 1
		fi
	fi

	if ! is_mihomo_running; then
		success "mihomo stopped."
		return 0
	fi

	error "Failed to stop mihomo."
	return 1
}

toggle_mihomo() {
	if is_mihomo_running; then
		info "Stop and check"
		mihomo_stop
	else
		info "Start and check"
		mihomo_start
	fi
	is_mihomo_running >/dev/null 2>&1
}

set_i18n "TOGGLE_MIHOMO" \
	"zh" "切换mihomo状态" \
	"en" "Toggle MiHoMo status" \
	"ja" "mihomo の状態を切り替え" \
	"ko" "mihomo 상태 전환"

set_i18n "MIHOMO_STATUS" \
	"zh" "mihomo状态" \
	"en" "MiHoMo status" \
	"ja" "mihomo の状態" \
	"ko" "mihomo 상태"

set_i18n "RUNNING" \
	"zh" "正在运行" \
	"en" "Running" \
	"ja" "実行中" \
	"ko" "실행 중"

set_i18n "NOT_RUNNING" \
	"zh" "未运行" \
	"en" "Not running" \
	"ja" "実行していません" \
	"ko" "실行 중 아님"

ask_toggle_mihomo() {
	# Ask the user to toggle MiHoMo.
	# Question key:    TOGGLE_MIHOMO
	if is_mihomo_running; then
		_mihomo_state="$(i18n 'RUNNING')"
	else
		_mihomo_state="$(i18n 'NOT_RUNNING')"
	fi
	panel "$(i18n 'MIHOMO_STATUS')"
	panel_row "$(i18n 'MIHOMO_STATUS')" "$_mihomo_state"
	panel_end
	ask "TOGGLE_MIHOMO" \
		"CONFIRM" \
		'toggle_mihomo' \
		"REFUSE" \
		'exit 0' \
		0
	unset _mihomo_state
}
