#!/usr/bin/env python3
"""Executable kamfw contracts and optional differential checks against a git baseline."""
import argparse
import json
import os
import shlex
from pathlib import Path
import subprocess
import tempfile
import unittest

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path)
parser.add_argument('--shell', default='sh')
args, remaining = parser.parse_known_args()
ROOT = Path(__file__).resolve().parents[1]
BASELINE = args.baseline.resolve() if args.baseline else None


def run(root, body, files=None, collect=(), timeout=20):
    with tempfile.TemporaryDirectory(prefix='kamfw-contract-') as tmp:
        tmp = Path(tmp)
        module = tmp / 'module'
        (module / '.config/kamfw').mkdir(parents=True)
        (module / '.config/kamfw/.envrc').write_text(
            f"KAMFW_DIR='{root}'\nKAM_MODULES=''\nKAM_HOME='{module}'\nKAM_UI_LANGUAGE=en\n"
        )
        for name, content in (files or {}).items():
            file = tmp / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(content)
        env = dict(os.environ, MODDIR=str(module), MODPATH=str(module), FIXTURE=str(tmp),
                   IMPL=str(root), TMPDIR=str(tmp), KAM_UI_LANGUAGE='en')
        program = '. "$IMPL/.kamfwrc" || exit $?\n' + body
        result = subprocess.run(shlex.split(args.shell) + ['-c', program], cwd=tmp, env=env,
                                capture_output=True, text=True, timeout=timeout)
        normalize = lambda s: s.replace(str(tmp), '<fixture>').replace(str(root), '<kamfw>')
        snapshot = {}
        for name in collect:
            file = tmp / name
            snapshot[name] = normalize(file.read_text()) if file.exists() else None
        return dict(code=result.returncode, stdout=normalize(result.stdout),
                    stderr=normalize(result.stderr), files=snapshot)


CASES = {
    'i18n_languages': ('''set_i18n TITLE en 'Hello' zh '你好' ja 'こんにちは' ko '안녕'
for KAM_UI_LANGUAGE in en zh-CN ja-JP ko-KR ru; do i18n TITLE; done
set_i18n QUOTE en 'line one\n$HOME & | \\ literal'
KAM_UI_LANGUAGE=en i18n QUOTE
printf '%s\\n' 'Hello $_1 / $_2 / $_1' | t 'a & b | c' 'quoted " text'
''', {}, ()),
    'i18n_table': ('''load_i18n "$FIXTURE/table" || exit 1
KAM_UI_LANGUAGE=zh i18n ROW
KAM_UI_LANGUAGE=ja i18n ROW
KAM_UI_LANGUAGE=en i18n EMPTY
''', {'table': 'KEY|en|zh\nROW|fallback|中文\nEMPTY||\n'}, ()),
    'loader_public_functions': ('''import __installer__
import __installer__
for name in set_i18n print kamfw installer install_check at_exit_add; do
    command -v "$name" >/dev/null || exit 1
    printf '%s\\n' "$name"
done
''', {}, ()),
    'runtime_phases': ('''kamfw_init_paths() { :; }
kamfw_phase_service() { printf 'service:<%s>:<%s>\\n' "$1" "$2"; }
kamfw_phase_action() { printf 'action:<%s>\\n' "$1"; }
kamfw run service -- 'one two' 'three'
kamfw run action test
kamfw --help
''', {}, ()),
    'directories': ('''kam_init_dirs --required
for dir in .config .cache .state .log; do [ -d "$KAM_HOME/$dir" ] || exit 1; printf '%s\\n' "$dir"; done
[ ! -d "$KAM_HOME/.tmp" ]
''', {}, ()),
    'architecture': ('''import arch
ARCH=arm64
support_arch arm arm64 x86
for a in arm arm64 x86 x64 invalid; do is_arch "$a"; printf '%s:%s\\n' "$a" "$?"; done
''', {}, ()),
    'manager_detection': ('''for manager in magisk ksud ap unknown; do
    _GM_CACHE=$manager
    get_manager
    is_magisk; printf 'magisk:%s\\n' "$?"
    is_ksu; printf 'ksu:%s\\n' "$?"
    is_ap; printf 'ap:%s\\n' "$?"
done
''', {}, ()),
    'termux_environment': ('''import __termux__
old_path=$PATH
old_home=${HOME:-}
active_termux_env
set_termux_home
deactivate_termux_env
[ "$PATH" = "$old_path" ] && [ "${HOME:-}" = "$old_home" ]
''', {}, ()),
    'time_helpers': ('''import time
for seconds in 0 1 59 60 3600 3661 90061; do format_duration "$seconds"; done
_kam_get_now() { printf '100\\n'; }
timer_start test
_kam_get_now() { printf '345\\n'; }
timer_get_interval test
timer_stop test
[ -z "${KAM_T_test:-}" ]
''', {}, ()),
    'log_levels': ('''log() { printf 'log:%s\\n' "$*"; }
for level in info WARN error DEBUG; do
    set_loglevel "$level"
    info example
    warn example
    error example
    debug example
    success example
done
''', {}, ()),
    'log_rotation': ('''import logrotate
for size in 1 2k 3M 1g; do logrotate_size_bytes "$size"; done
printf abc >"$FIXTURE/current.log"
logrotate --size 3 --keep 2 "$FIXTURE/current.log"
printf def >"$FIXTURE/current.log"
logrotate --size 3 --keep 2 "$FIXTURE/current.log"
''', {}, ('current.log', 'current.log.1', 'current.log.2')),
    'exit_handlers': ('''import __at_exit__
info() { :; }
warn() { :; }
at_exit_add 'printf first' 'printf second' 'printf first'
at_exit_remove 'printf second'
at_exit_list
__at_exit_run_handlers
printf '\\n'
at_exit_clear
at_exit_list
''', {}, ()),
    'install_filters': ('''import __installer__
install_reset_filters
install_exclude 'bin/*' '*.txt'
install_include 'bin/tool'
install_check "$FIXTURE/source"
''', {'source/bin/tool': '#!/bin/sh\nprintf ok', 'source/bin/helper': '#!/bin/sh\n:',
      'source/config.json': '{}', 'source/notes.txt': 'notes'}, ()),
    'install_directory': ('''import __installer__
info() { :; }; success() { :; }; warn() { :; }
installer run "$FIXTURE/source"
[ -x "$MODDIR/bin/tool" ]
''', {'source/bin/tool': '#!/bin/sh\nprintf ok\n', 'source/config.json': '{}'},
      ('module/bin/tool', 'module/config.json')),
    'install_preserves_existing': ('''import __installer__
info() { :; }; success() { :; }; warn() { :; }
installer run "$FIXTURE/source"
''', {'source/config.json': 'new', 'module/config.json': 'user choice'}, ('module/config.json',)),
    'uninstall_hooks': ('''import __uninstall__
kamfw_phase_uninstall 'one two'
''', {'module/.config/kamfw/uninstall.d/a.sh': 'printf "first:%s\\n" "$1"\n',
      'module/lib/kamfw/uninstall.d/b.sh': 'printf "second:%s\\n" "$1"\n'}, ()),
    'launcher_url_and_app': ('''import launcher
_launch_run() { printf '%s\\n' "$*" >>"$FIXTURE/launch.calls"; }
am() { :; }; monkey() { :; }
launch url 'https://example.test/a?b=c'
launch app com.example.app
launch app com.example.app/.Main
''', {}, ('launch.calls',)),
    'launcher_browser_fallback': ('''import launcher
am() { :; }; cmd() { :; }
_launch_run() {
    printf '%s\\n' "$*" >>"$FIXTURE/launch.calls"
    case "$*" in
        'am get-current-user') printf 10 ;;
        'cmd role get-role-holders'*) printf com.browser ;;
        *' -p com.browser '*) printf 'Error: unavailable'; return 0 ;;
    esac
}
launch browser 'https://example.test/a'
''', {}, ('launch.calls',)),
}


CASES.update({
    'config_precedence_and_deletion': (r'''import self
is_ksu() { return 1; }
config set key persistent
config set --temp key temporary
config set other 'with spaces'
config get key; printf '\n'
config list
config delete --temp key
config get key; printf '\n'
config clear
config get key; printf 'missing:%s\n' "$?"
disable; test -f "$MODDIR/disable"
enable; test ! -f "$MODDIR/disable"
''', {}, ()),
    'config_stdin': (r'''import self
is_ksu() { return 1; }
printf 'one\ntwo\n' | config set --stdin text
config get text
''', {}, ()),
    'notify_direct_fallback': (r'''import notify
success() { :; }
su() { return 1; }
cmd() {
    printf '<%s>' "$@" >>"$FIXTURE/notify.calls"
    printf '\n' >>"$FIXTURE/notify.calls"
    case "$*" in *' -i '*) return 1 ;; esac
}
notify alert tag "Title with 'quote'" 'Body & literal $text' second
''', {}, ('notify.calls',)),
    'notify_shell_and_validation': (r'''import notify
success() { :; }
error() { printf '%s\n' "$1"; }
cmd() { printf '<%s>' "$@" >>"$FIXTURE/notify.calls"; printf '\n' >>"$FIXTURE/notify.calls"; }
su() { eval "$3"; }
notify post tag Title 'One two'
notify post '' Title body; printf 'code:%s\n' "$?"
notify post tag '' body; printf 'code:%s\n' "$?"
notify post tag Title ''; printf 'code:%s\n' "$?"
''', {}, ('notify.calls',)),
    'cache_download_transactions': (r'''import cache_download
info() { :; }; success() { :; }; error() { printf '%s\n' "$1"; }
curl() {
    output=''
    while [ $# -gt 0 ]; do
        case "$1" in -o) output=$2; shift 2 ;; --connect-timeout|--max-time) shift 2 ;; *) shift ;; esac
    done
    if [ -n "$output" ]; then cp "$FIXTURE/remote" "$output"; else cat "$FIXTURE/remote.hash"; fi
}
expected=$(cache_download_sha256 "$FIXTURE/remote")
printf '%s\n' "$expected" >"$FIXTURE/remote.hash"
cache_download --hash-file "$FIXTURE/digest" https://example.test "$FIXTURE/dest"
printf 'changed:%s\n' "$KAM_CACHE_DOWNLOAD_CHANGED"
cache_download --hash-file "$FIXTURE/digest" https://example.test "$FIXTURE/dest"
printf 'changed:%s\n' "$KAM_CACHE_DOWNLOAD_CHANGED"
cache_download --hash "$expected" --hash-file "$FIXTURE/digest" https://example.test "$FIXTURE/dest"
printf 'changed:%s\n' "$KAM_CACHE_DOWNLOAD_CHANGED"
cache_download --hash-url https://example.test/hash --hash-file "$FIXTURE/digest" https://example.test "$FIXTURE/dest"
printf 'changed:%s\n' "$KAM_CACHE_DOWNLOAD_CHANGED"
cache_download --hash 0000000000000000000000000000000000000000000000000000000000000000 --hash-file "$FIXTURE/digest" https://example.test "$FIXTURE/dest"
printf 'mismatch:%s\n' "$?"
''', {'remote': 'download body\n'}, ('dest', 'digest')),
    'watcher_snapshots_and_changes': (r'''import fswatch
KAM_FSWATCH_PRUNE_NAMES='generated stage'
fswatch_snapshot "$FIXTURE/tree"
fswatch_changed "$FIXTURE/tree" "$FIXTURE/snapshot"; printf 'initial:%s\n' "$?"
fswatch_changed "$FIXTURE/tree" "$FIXTURE/snapshot"; printf 'same:%s\n' "$?"
printf changed >"$FIXTURE/tree/generated/ignored"
fswatch_changed "$FIXTURE/tree" "$FIXTURE/snapshot"; printf 'pruned:%s\n' "$?"
printf changed >"$FIXTURE/tree/input"
fswatch_changed "$FIXTURE/tree" "$FIXTURE/snapshot"; printf 'edited:%s\n' "$?"
''', {'tree/input': 'body', 'tree/with space/child': 'data', 'tree/generated/ignored': 'output', 'tree/stage/ignored': 'stage'}, ()),
    'watchdog_once_and_validation': (r'''import watchdog
watchdog once 'printf "body\\n"; exit 37'; printf 'code:%s\n' "$?"
for interval in 0 1 05 -1 1.5 x ''; do
    watchdog_valid_interval "$interval"; printf '%s:%s\n' "$interval" "$?"
done
''', {}, ()),
    'rich_layout': (r'''import rich
COL_CYN='' COL_GRN='' COL_YLW='' COL_RED='' COL_RST=''
__rich_terminal_width() { printf 24; }
panel Heading
panel_row Key 'some value'
panel_note Note
panel_success Done
panel_warn Warning
panel_error Error
panel_end
panel_line content
panel_divider
panel_status success healthy
guide first second
__rich_pad_right text 8; printf '\n'
''', {}, ()),
    'rich_prompt_selection': (r'''import rich
COL_CYN='' COL_GRN='' COL_YLW='' COL_RED='' COL_RST=''
wait_key_up_down() { printf up; }
ask 'Choose an option' 'First option' 'printf "selected:first\\n"' 'Second option' 'printf "selected:second\\n"' 1
''', {}, ()),
    'logging_lines_and_ansi': (r'''date() { printf '2026-01-02 03:04:05\n'; }
log -f "$FIXTURE/test.log" 'first message'
printf '\033[31mred\033[0m\nlast without newline' | log -f "$FIXTURE/test.log"
log -w -f "$FIXTURE/overwrite.log" old
log -w -f "$FIXTURE/overwrite.log" new
''', {}, ('test.log', 'overwrite.log')),
    'property_conditional_updates': (r'''import prop
info() { :; }
resetprop() {
    if [ $# = 1 ]; then cat "$FIXTURE/property"
    elif [ "$1" = --delete ]; then : >"$FIXTURE/property"
    else printf '%s' "$3" >"$FIXTURE/property"; fi
}
resetprop_if_diff test.prop old
cat "$FIXTURE/property"; printf '\n'
resetprop_if_match test.prop old new
cat "$FIXTURE/property"; printf '\n'
resetprop_if_match test.prop absent unchanged
cat "$FIXTURE/property"; printf '\n'
delprop_if_exist test.prop
''', {'property': 'old'}, ('property',)),
})


class Contracts(unittest.TestCase):
    def test_public_contracts(self):
        for name, (body, files, collect) in CASES.items():
            with self.subTest(contract=name):
                actual = run(ROOT, body, files, collect)
                self.assertEqual(actual['code'], 0, actual)
                if BASELINE:
                    if name == 'i18n_table' and Path(shlex.split(args.shell)[0]).name == 'mksh':
                        # Baseline treats unescaped | as pattern alternation and loops forever.
                        self.assertEqual(actual['stdout'], '中文\nfallback\nEMPTY\n')
                        with self.assertRaises(subprocess.TimeoutExpired):
                            run(BASELINE, body, files, collect, timeout=2)
                    else:
                        self.assertEqual(actual, run(BASELINE, body, files, collect))

    def test_nested_import_registration(self):
        result = run(ROOT, '''import __singbox__
for module in i18n i18ns base logging kam __runtime__ init_dirs __singbox__ rich self; do
    case " $KAM_MODULES " in *" $module "*) ;; *) printf '%s missing\\n' "$module"; exit 1 ;; esac
done
''')
        self.assertEqual(result['code'], 0, result)

    def test_phase_failure_reaches_caller(self):
        result = run(ROOT, '''kamfw_init_paths() { :; }
kamfw_phase_action() { return 37; }
kamfw run action
''')
        self.assertEqual(result['code'], 37, result)

    def test_install_filter_literals(self):
        result = run(ROOT, '''import __installer__
install_exclude 'bin/*'
install_include 'bin/a & b'
install_check "$FIXTURE/source"
''', {'source/bin/a & b': 'ok', 'source/bin/skip': 'skip'})
        self.assertEqual(result['stdout'], 'bin/a & b\n', result)

    def test_schedule_explicit_source(self):
        result = run(ROOT, '''import __installer__
info() { :; }; success() { :; }; warn() { :; }
installer schedule "$FIXTURE/source"
''', {'source/bin/tool': '#!/bin/sh\nprintf ok\n'}, ('module/bin/tool',))
        self.assertIsNotNone(result['files']['module/bin/tool'], result)


if __name__ == '__main__':
    unittest.main(argv=['test_contracts.py'] + remaining)
