# shellcheck shell=ash
# This file is a compatibility loader; implementation lives in split parts.
__kamfw_rich_dir="${KAMFW_DIR:-${MODDIR:-${0%/*}}/lib/kamfw}"
if [ ! -d "${__kamfw_rich_dir}/rich_parts" ]; then
    printf '%s\n' "Missing split library: ${__kamfw_rich_dir}/rich_parts" >&2
    return 1 2>/dev/null || exit 1
fi
. "${__kamfw_rich_dir}/rich_parts/part_01.sh" || { __kam_part_status=$?; unset __kamfw_rich_dir; return "$__kam_part_status" 2>/dev/null || exit "$__kam_part_status"; }
. "${__kamfw_rich_dir}/rich_parts/part_02.sh" || { __kam_part_status=$?; unset __kamfw_rich_dir; return "$__kam_part_status" 2>/dev/null || exit "$__kam_part_status"; }
. "${__kamfw_rich_dir}/rich_parts/part_03.sh" || { __kam_part_status=$?; unset __kamfw_rich_dir; return "$__kam_part_status" 2>/dev/null || exit "$__kam_part_status"; }
unset __kamfw_rich_dir __kam_part_status
