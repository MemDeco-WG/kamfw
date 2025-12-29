# shellcheck shell=ash
#
# __at_exit__.sh
#
# General-purpose at-exit helper for kamfw
#
# Features:
# - Provides APIs to register arbitrary handlers to run on shell EXIT:
#     - `at_exit_add <command_or_function_name>`    # add a handler (unique, newline-separated)
#     - `at_exit_remove <command_or_function_name>` # remove matching handlers
#     - `at_exit_list`                              # diagnostic: list handlers
#     - `at_exit_clear`                             # remove all handlers
#     - `at_exit_register_trap` / `at_exit_unregister_trap`
# - Includes a ready-to-use handler for installing files according to
#   install_exclude/install_include filters (compatible with previous behavior).
#   This handler is implemented as `__at_exit_install_from_filters` and can be
#   added via `at_exit_add '__at_exit_install_from_filters'` (or it is added
#   automatically when this file is loaded and $MODPATH is set).
#
# Notes & Guidelines:
# - All user-visible strings use i18n keys via set_i18n / i18n / t().
# - External commands are checked with `command -v` before invocation when
#   they are critical.
# - Default policy: do NOT overwrite existing files in non-interactive contexts.
#
# Backwards compatibility:
# - Provides wrappers `install_register_exit_hook` / `install_unregister_exit_hook`
#   that mirror the legacy behavior (register trap + add install handler).
#
# Test / verification (suggested):
# 1. Source this helper and call `at_exit_add 'echo hi'` then exit the shell;
#    verify the handler ran.
# 2. During a simulated install (export MODPATH/KAM_MODULE_ROOT), add filters
#    and verify that `__at_exit_install_from_filters` installs matching files
#    when the shell exits (it is auto-added if MODPATH is present).
#
# New i18n keys added:
#   AT_EXIT_REGISTERED, AT_EXIT_NO_HANDLERS, AT_EXIT_RUN_START,
#   AT_EXIT_DONE, AT_EXIT_HANDLER_FAILED
#
# (This file intentionally keeps the AUTO_EXTRACT_* i18n keys used by the
#  install-from-filters handler for compatibility.)
#

# -----------------------------------------------------------------------------
# i18n: generic at-exit messages
# -----------------------------------------------------------------------------
set_i18n "AT_EXIT_REGISTERED" \
	"zh" "已注册 at-exit 钩子" \
	"en" "At-exit hook registered" \
	"ja" "終了時フックが登録されました" \
	"ko" "종료 훅이 등록되었습니다"

set_i18n "AT_EXIT_NO_HANDLERS" \
	"zh" "没有注册任何 at-exit 处理器" \
	"en" "No at-exit handlers registered" \
	"ja" "登録された終了時ハンドラはありません" \
	"ko" "등록된 종료 훅이 없습니다"

set_i18n "AT_EXIT_RUN_START" \
	"zh" "执行 at-exit 处理器..." \
	"en" "Running at-exit handlers..." \
	"ja" "終了時ハンドラを実行します..." \
	"ko" "종료 훅 실행 중..."

set_i18n "AT_EXIT_DONE" \
	"zh" "at-exit 处理完成" \
	"en" "At-exit handlers finished" \
	"ja" "終了時ハンドラの実行が完了しました" \
	"ko" "종료 훅 실행이 완료되었습니다"

set_i18n "AT_EXIT_HANDLER_FAILED" \
	"zh" "处理器失败: %s" \
	"en" "Handler failed: %s" \
	"ja" "ハンドラ失敗: %s" \
	"ko" "훅 실패: %s"

# -----------------------------------------------------------------------------
# Internal state
# -----------------------------------------------------------------------------
__at_exit_installed="" # non-empty after trap registration
__at_exit_prev_trap="" # previous EXIT trap body (best-effort capture)
__at_exit_running=""   # guard to prevent re-entry
__at_exit_handlers=""  # newline-separated list of handler commands/functions

# -----------------------------------------------------------------------------
# Logging helpers (use existing ui helpers when available; fallback to print)
# -----------------------------------------------------------------------------
__at_exit_log_info() {
	msg="$(i18n "$1" 2>/dev/null || echo "$1")"
	if type info >/dev/null 2>&1; then
		info "$msg"
	else
		print "$msg"
	fi
}

__at_exit_log_success_t() {
	key="$1"
	arg="$2"
	_msg="$(i18n "$key" 2>/dev/null | t "$arg" 2>/dev/null || i18n "$key" 2>/dev/null || echo "$key")"
	if type success >/dev/null 2>&1; then
		success "$_msg"
	else
		print "$_msg"
	fi
}

__at_exit_log_warn_t() {
	key="$1"
	arg="$2"
	_msg="$(i18n "$key" 2>/dev/null | t "$arg" 2>/dev/null || i18n "$key" 2>/dev/null || echo "$key")"
	if type warn >/dev/null 2>&1; then
		warn "$_msg"
	else
		print "$_msg"
	fi
}

# -----------------------------------------------------------------------------
# Handler list management
# -----------------------------------------------------------------------------
# Add handler(s) (unique). Handlers are arbitrary shell commands or function names.
at_exit_add() {
	[ $# -eq 0 ] && return 0
	for cmd in "$@"; do
		# Deduplicate against existing list
		eval 'cur=${__at_exit_handlers}'
		OLDIFS=$IFS
		IFS='
'
		_found=0
		for l in $cur; do
			if [ "$l" = "$cmd" ]; then
				_found=1
				break
			fi
		done
		IFS=$OLDIFS
		if [ "$_found" -eq 0 ]; then
			if [ -z "${cur:-}" ]; then
				__at_exit_handlers="$cmd"
			else
				__at_exit_handlers="$cur
$cmd"
			fi
		fi
	done
	return 0
}

# Remove handler(s) by exact match
at_exit_remove() {
	[ $# -eq 0 ] && return 0
	OLDIFS=$IFS
	IFS='
'
	_new=""
	for l in ${__at_exit_handlers:-}; do
		_skip=0
		for rm in "$@"; do
			if [ "$l" = "$rm" ]; then
				_skip=1
				break
			fi
		done
		[ "$_skip" -eq 1 ] && continue
		if [ -z "${_new:-}" ]; then
			_new="$l"
		else
			_new="$_new
$l"
		fi
	done
	IFS=$OLDIFS
	__at_exit_handlers="${_new:-}"
	return 0
}

# List handlers (diagnostic)
at_exit_list() {
	[ -z "${__at_exit_handlers:-}" ] && {
		print "$(i18n 'AT_EXIT_NO_HANDLERS' 2>/dev/null || echo 'No at-exit handlers registered')"
		return 0
	}
	OLDIFS=$IFS
	IFS='
'
	for l in $__at_exit_handlers; do
		print "$l"
	done
	IFS=$OLDIFS
	return 0
}

# Clear all handlers
at_exit_clear() {
	unset __at_exit_handlers
	return 0
}

# -----------------------------------------------------------------------------
# Previous trap chaining (best-effort)
# -----------------------------------------------------------------------------
__at_exit_run_prev_trap() {
	if [ -n "${__at_exit_prev_trap:-}" ]; then
		# run previously registered trap body in a subshell to reduce interference
		(eval "$__at_exit_prev_trap") 2>/dev/null || true
	fi
}

# -----------------------------------------------------------------------------
# Run registered handlers (executed in the trap context)
# -----------------------------------------------------------------------------
__at_exit_run_handlers() {
	[ -z "${__at_exit_handlers:-}" ] && return 0

	__at_exit_log_info "AT_EXIT_RUN_START"

	OLDIFS=$IFS
	IFS='
'
	for h in $__at_exit_handlers; do
		[ -z "$h" ] && continue
		# Execute handler in the current shell (so critical failures like `abort`
		# behave consistently). If a handler needs isolation, it may run its own subshell.
		if ! eval "$h"; then
			__at_exit_log_warn_t "AT_EXIT_HANDLER_FAILED" "$h"
		fi
	done
	IFS=$OLDIFS

	__at_exit_log_info "AT_EXIT_DONE"
	return 0
}

# -----------------------------------------------------------------------------
# Master EXIT handler (chained with previous traps)
# -----------------------------------------------------------------------------
__at_exit_master_handler() {
	[ -n "${__at_exit_running:-}" ] && return 0
	__at_exit_running=1

	# If no handlers are registered, just run previous trap body (if any).
	if [ -z "${__at_exit_handlers:-}" ]; then
		__at_exit_log_info "AT_EXIT_NO_HANDLERS"
		__at_exit_run_prev_trap
		unset __at_exit_running
		return 0
	fi

	# Run each registered handler
	__at_exit_run_handlers || true

	# Run previous trap (if any)
	__at_exit_run_prev_trap

	unset __at_exit_running
	return 0
}

# -----------------------------------------------------------------------------
# Trap registration / unregistration
# -----------------------------------------------------------------------------
at_exit_register_trap() {
	[ -n "${__at_exit_installed:-}" ] && return 0

	prev="$(trap -p EXIT 2>/dev/null || true)"
	if [ -n "$prev" ]; then
		__at_exit_prev_trap="$(printf '%s' "$prev" | sed -n \"s/^trap -- '\\\\(.*\\\\)' EXIT$/\\\\1/p\")" || __at_exit_prev_trap=""
	fi

	trap "__at_exit_master_handler" EXIT
	__at_exit_installed=1

	# Informative message in interactive sessions
	[ -t 1 ] && __at_exit_log_info "AT_EXIT_REGISTERED"
	return 0
}

at_exit_unregister_trap() {
	[ -z "${__at_exit_installed:-}" ] && return 0

	if [ -n "${__at_exit_prev_trap:-}" ]; then
		trap "$__at_exit_prev_trap" EXIT 2>/dev/null || trap - EXIT 2>/dev/null || true
	else
		trap - EXIT 2>/dev/null || true
	fi
	unset __at_exit_installed __at_exit_prev_trap
	return 0
}

# -----------------------------------------------------------------------------
# Legacy install-on-exit handler (kept for compatibility).
# This implements the previous behavior of installing files on exit according
# to install_exclude / install_include filters.
# It can be registered via: at_exit_add '__at_exit_install_from_filters'
# -----------------------------------------------------------------------------
__at_exit_install_from_filters() {
	# Only meaningful during an installation (MODPATH present)
	[ -z "${MODPATH:-}" ] && {
		__at_exit_log_info "AUTO_EXTRACT_NO_MODPATH"
		return 0
	}

	# Determine files to install
	files="$(install_check 2>/dev/null || true)"
	if [ -z "${files:-}" ]; then
		__at_exit_log_info "AUTO_EXTRACT_NO_FILES"
		return 0
	fi

	__at_exit_log_info "AUTO_EXTRACT_START"

	OLDIFS=$IFS
	IFS='
'
	for rel in $files; do
		[ -z "$rel" ] && continue

		dst="$MODPATH/$rel"

		# Prefer source in module root
		if [ -n "${KAM_MODULE_ROOT:-}" ] && [ -f "${KAM_MODULE_ROOT}/$rel" ]; then
			src="${KAM_MODULE_ROOT}/$rel"
			if [ -f "$dst" ]; then
				if [ -t 0 ] && type "__confirm_install_file_do" >/dev/null 2>&1; then
					__confirm_install_file_do "$src" "$rel" || true
				else
					__at_exit_log_warn_t "AUTO_EXTRACT_SKIP_EXISTING_NONINTERACTIVE" "$rel"
				fi
			else
				mkdir -p "$(dirname "$dst")" 2>/dev/null || true
				if cp -a "$src" "$dst" 2>/dev/null; then
					if head -n1 "$dst" 2>/dev/null | grep -q '^#!'; then chmod +x "$dst" 2>/dev/null || true; fi
					__at_exit_log_success_t "AUTO_EXTRACT_INSTALL_OK" "$rel"
				else
					__at_exit_log_warn_t "AUTO_EXTRACT_INSTALL_FAILED" "$rel"
				fi
			fi
			continue
		fi

		# Try to extract from ZIPFILE if available
		if [ -n "${ZIPFILE:-}" ] && [ -f "${ZIPFILE}" ]; then
			has_command "unzip" || has_command "zipinfo" || abort "$(i18n 'ZIPTOOLS_MISSING' 2>/dev/null || echo 'zip tools missing')"

			entry=""
			if type "__find_zip_entry" >/dev/null 2>&1; then
				entry=$(__find_zip_entry "${ZIPFILE}" "$rel" 2>/dev/null || true)
			else
				entry="$(__install__get_files_from_zip "${ZIPFILE}" 2>/dev/null | awk -v r=\"$rel\" '{ if ($0==r){print; exit} if (length($0)>=length(r) && substr($0,length($0)-length(r)+1)==r){print; exit} }' || true)"
			fi

			if [ -n "$entry" ]; then
				if [ -t 0 ] && type "__confirm_install_file_do_from_zip" >/dev/null 2>&1; then
					__confirm_install_file_do_from_zip "${ZIPFILE}" "$entry" "$rel" || true
				else
					TMPDIR="${TMPDIR:-/tmp}"
					tmpdir="$(mktemp -d "${TMPDIR}/kamfw.extract.XXXXXX" 2>/dev/null || mktemp -d 2>/dev/null || true)"
					if [ -z "$tmpdir" ]; then
						__at_exit_log_warn_t "AUTO_EXTRACT_INSTALL_FAILED" "$rel"
						continue
					fi

					if has_command "unzip"; then
						unzip -o -j "${ZIPFILE}" "$entry" -d "$tmpdir" >/dev/null 2>&1 || {
							rm -rf "$tmpdir"
							__at_exit_log_warn_t "AUTO_EXTRACT_INSTALL_FAILED" "$rel"
							continue
						}
					else
						unzip -p "${ZIPFILE}" "$entry" >"$tmpdir/$(basename "$entry")" 2>/dev/null || {
							rm -rf "$tmpdir"
							__at_exit_log_warn_t "AUTO_EXTRACT_INSTALL_FAILED" "$rel"
							continue
						}
					fi

					srcfile="$tmpdir/$(basename "$entry")"
					if [ -f "$dst" ]; then
						__at_exit_log_warn_t "AUTO_EXTRACT_SKIP_EXISTING_NONINTERACTIVE" "$rel"
					else
						mkdir -p "$(dirname "$dst")" 2>/dev/null || true
						if cp -a "$srcfile" "$dst" 2>/dev/null; then
							if head -n1 "$dst" 2>/dev/null | grep -q '^#!'; then chmod +x "$dst" 2>/dev/null || true; fi
							__at_exit_log_success_t "AUTO_EXTRACT_INSTALL_OK" "$rel"
						else
							__at_exit_log_warn_t "AUTO_EXTRACT_INSTALL_FAILED" "$rel"
						fi
					fi
					rm -rf "$tmpdir"
				fi
			else
				# entry not found in zip
				__at_exit_log_warn_t "AUTO_EXTRACT_INSTALL_FAILED" "$rel"
			fi
		fi
	done
	IFS=$OLDIFS
	return 0
}

# -----------------------------------------------------------------------------
# Backwards-compatibility wrappers for legacy API
# -----------------------------------------------------------------------------
install_register_exit_hook() {
	at_exit_register_trap
	at_exit_add '__at_exit_install_from_filters'
}

install_unregister_exit_hook() {
	at_exit_remove '__at_exit_install_from_filters'
	at_exit_unregister_trap
}

# -----------------------------------------------------------------------------
# Autoregister trap on load (so other code may add handlers) and, if this is
# being loaded during an install stage, register the install handler as well.
# -----------------------------------------------------------------------------
at_exit_register_trap || true

if [ -n "${MODPATH:-}" ]; then
	at_exit_add '__at_exit_install_from_filters'
fi

# End of file
