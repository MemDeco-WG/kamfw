# shellcheck shell=ash

dedup_path() {
	PATH=$(echo "$PATH" | tr ':' '\n' | awk '!x[$0]++' | tr '\n' ':' | sed 's/:$//')
	export PATH
}

kam_add_path() {
	_id="$1"
	if module_exists "$_id"; then
		_path="/data/adb/modules/$_id/.local/bin"
		export PATH="$_path:$PATH"
		unset _id _path
		dedup_path
		return 0
	fi
	return 1
}

kam_reset_path() {
	dedup_path
	export KAMFW_PATH_BAK="$PATH"
	export PATH="/product/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/system_ext/bin:/system/bin/:/system/xbin:/odm/bin:/vendor/bin:/vendor/xbin"
}

add_path_ksu() {
	export PATH="$PATH:/data/adb/ksu/bin"
	dedup_path
}

add_path_ap() {
	export PATH="$PATH:/data/adb/ap/bin"
	dedup_path
}

add_path_magisk() {
	export PATH="$PATH:/data/adb/magisk/bin"
	dedup_path
}

# 备份全部环境变量到指定文件
env_save() {
	_save_path="$1"
	# 为空直接报错
	[ -z "$_save_path" ] && abort "env_save: _path"
	export -p >"$_save_path"
	unset _save_path
}

# 从备份文件恢复环境变量
env_restore() {
	_restore_path="$1"
	[ -z "$_restore_path" ] && abort "env_restore: _restore_path"
	if [ -f "$_restore_path" ]; then
		. "$_restore_path"
		return 0
	else
		return 1
	fi
	unset _restore_path
}
