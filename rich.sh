# shellcheck shell=ash
for _rich_part in layout interactive_prompts install_prompts; do
    . "${KAMFW_DIR:-${MODDIR:-${0%/*}}/lib/kamfw}/rich_rendering/$_rich_part.sh" || return $?
done
unset _rich_part
