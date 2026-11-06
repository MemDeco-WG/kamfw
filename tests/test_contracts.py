#!/usr/bin/env python3
"""Executable kamfw contracts and optional differential checks against a git baseline."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path)
args, remaining = parser.parse_known_args()
ROOT = Path(__file__).resolve().parents[1]
BASELINE = args.baseline.resolve() if args.baseline else None


def run(root, body, files=None, collect=()):
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
        result = subprocess.run(['sh', '-c', program], cwd=tmp, env=env,
                                capture_output=True, text=True, timeout=20)
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
    'i18n_table': ('''load_i18n "$FIXTURE/table"
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


class Contracts(unittest.TestCase):
    def test_public_contracts(self):
        for name, (body, files, collect) in CASES.items():
            with self.subTest(contract=name):
                actual = run(ROOT, body, files, collect)
                self.assertEqual(actual['code'], 0, actual)
                if BASELINE:
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
