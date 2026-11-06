#!/usr/bin/env python3
"""Regression contracts for corrected baseline defects and transactional writes."""
import unittest

from test_contracts import ROOT, BASELINE, remaining, run


QUIET = 'info() { :; }; success() { :; }; warn() { :; }; error() { :; }\n'
CURL = r'''
curl() {
    output=''
    while [ $# -gt 0 ]; do
        case "$1" in
            -o) output=$2; shift 2 ;;
            --connect-timeout|--max-time) shift 2 ;;
            -*) shift ;;
            *) url=$1; shift ;;
        esac
    done
    printf '%s\n' "$url" >>"$FIXTURE/download.calls"
    cp "$FIXTURE/download" "$output"
}
'''


class Regressions(unittest.TestCase):
    def test_single_archive_install_and_release_placeholders(self):
        body = QUIET + CURL + r'''
import binstall
tar -czf "$FIXTURE/download" -C "$FIXTURE/payload" tool
binstall --name tar-tool --target "$MODDIR/bin" --url https://example.test/tool.tgz || exit 1
test -x "$MODDIR/bin/tar-tool" || exit 1
gzip -c "$FIXTURE/payload/tool" >"$FIXTURE/download"
binstall --name gzip-tool --target "$MODDIR/bin" --url https://example.test/tool.gz || exit 1
(cd "$FIXTURE/payload" && zip -q "$FIXTURE/bundle.zip" tool extra)
cp "$FIXTURE/bundle.zip" "$FIXTURE/download"
binstall --name zip-tool --target "$MODDIR/bin" --url https://example.test/tool.zip --result-name tool || exit 1
cp "$FIXTURE/payload/tool" "$FIXTURE/download"
binstall --name raw-tool --target "$MODDIR/bin" --repo owner/repo --tag v1.2 --asset 'tool-${TAG}-${ARCH}' --arch arm64 --version-file "$MODDIR/version" || exit 1
'''
        files = {'payload/tool': '#!/bin/sh\nprintf installed\n', 'payload/extra': 'data'}
        names = ('module/bin/tar-tool', 'module/bin/gzip-tool', 'module/bin/zip-tool',
                 'module/bin/raw-tool', 'module/version', 'download.calls')
        result = run(ROOT, body, files, names)
        self.assertEqual(result['code'], 0, result)
        for name in names[:4]:
            self.assertEqual(result['files'][name], files['payload/tool'])
        self.assertEqual(result['files']['module/version'], 'v1.2\n')
        self.assertIn('https://github.com/owner/repo/releases/download/v1.2/tool-v1.2-arm64',
                      result['files']['download.calls'])

    def test_ambiguous_archive_preserves_installed_binary(self):
        body = QUIET + CURL + r'''
import binstall
tar -czf "$FIXTURE/download" -C "$FIXTURE/payload" one two
binstall --name tool --target "$MODDIR/bin" --url https://example.test/tool.tgz
'''
        result = run(ROOT, body, {'payload/one': 'one', 'payload/two': 'two',
                                 'module/bin/tool': 'installed'}, ('module/bin/tool',))
        self.assertNotEqual(result['code'], 0, result)
        self.assertEqual(result['files']['module/bin/tool'], 'installed')

    def test_corrupted_destination_is_repaired(self):
        body = QUIET + CURL + r'''
import cache_download
cache_download --hash-file "$FIXTURE/digest" https://example.test "$MODDIR/body" || exit 1
printf corrupt >"$MODDIR/body"
cache_download --hash-file "$FIXTURE/digest" https://example.test "$MODDIR/body" || exit 1
printf '%s\n' "$KAM_CACHE_DOWNLOAD_CHANGED"
'''
        result = run(ROOT, body, {'download': 'trusted'}, ('module/body',))
        self.assertEqual(result['code'], 0, result)
        self.assertEqual(result['files']['module/body'], 'trusted')
        self.assertEqual(result['stdout'], '1\n')
        if BASELINE:
            original = run(BASELINE, body, {'download': 'trusted'}, ('module/body',))
            self.assertEqual(original['files']['module/body'], 'corrupt')

    def test_failed_hash_fetch_preserves_destination(self):
        body = QUIET + r'''
import cache_download
curl() { return 28; }
cache_download --hash-url https://example.test/hash https://example.test "$MODDIR/body"
'''
        result = run(ROOT, body, {'module/body': 'installed'}, ('module/body',))
        self.assertNotEqual(result['code'], 0, result)
        self.assertEqual(result['files']['module/body'], 'installed')

    def test_config_stdin_does_not_leak_and_paths_stay_local(self):
        body = QUIET + r'''
import self
is_ksu() { return 1; }
config set --stdin first <<EOF
stdin
EOF
config set second 'ordinary value'
config get second
config set ../outside escaped && exit 1
config get ../outside && exit 1
config delete ../outside && exit 1
exit 0
'''
        result = run(ROOT, body)
        self.assertEqual(result['code'], 0, result)
        self.assertEqual(result['stdout'], 'ordinary value')

    def test_architecture_pruning_and_dry_run(self):
        body = QUIET + r'''
import bins
prune_zygisk_for_arch arm64 "$FIXTURE/libs" --dry-run || exit 1
test -e "$FIXTURE/libs/x86.so" || exit 1
prune_zygisk_for_arch arm64 "$FIXTURE/libs" || exit 1
test -e "$FIXTURE/libs/arm64-v8a.so" && test -e "$FIXTURE/libs/armeabi-v7a.so" || exit 1
test ! -e "$FIXTURE/libs/x86.so" && test ! -e "$FIXTURE/libs/x86_64.so"
'''
        files = {f'libs/{name}.so': name for name in ('arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64')}
        result = run(ROOT, body, files)
        self.assertEqual(result['code'], 0, result)

    def test_property_rollback_is_literal_and_first_value_wins(self):
        body = QUIET + r'''
import prop
resetprop() {
    if [ $# = 1 ]; then cat "$FIXTURE/property"
    elif [ "$1" = -n ] && [ "$2" = -p ]; then printf '%s' "$4" >"$FIXTURE/property"
    else : >"$FIXTURE/property"; fi
}
persistprop test.prop first || exit 1
persistprop test.prop second || exit 1
. "$MODPATH/uninstall.sh"
'''
        value = "original 'quote' $HOME $(printf unsafe) `printf unsafe` \\ end"
        result = run(ROOT, body, {'property': value}, ('property', 'module/uninstall.sh'))
        self.assertEqual(result['code'], 0, result)
        self.assertEqual(result['files']['property'], value)
        self.assertEqual(result['files']['module/uninstall.sh'].count('resetprop -n -p'), 1)

    def test_existing_rollback_survives_upgrade(self):
        body = QUIET + r'''
import prop
resetprop() {
    if [ $# = 1 ]; then cat "$FIXTURE/property"
    else printf '%s' "$4" >"$FIXTURE/property"; fi
}
persistprop test.prop newest || exit 1
. "$MODPATH/uninstall.sh"
'''
        rollback = '#!/system/bin/sh\nresetprop -n -p "test.prop" "original"\n'
        result = run(ROOT, body, {'property': 'changed', 'module/uninstall.sh': rollback},
                     ('property', 'module/uninstall.sh'))
        self.assertEqual(result['code'], 0, result)
        self.assertEqual(result['files']['property'], 'original')
        self.assertEqual(result['files']['module/uninstall.sh'], rollback)

    def test_declined_confirmation_returns_failure(self):
        result = run(ROOT, QUIET + r'''
import rich
wait_key_up_down() { printf up; }
confirm 'Continue?' 1 >/dev/null
''')
        self.assertEqual(result['code'], 1, result)

    def test_zero_intervals_never_create_busy_loop(self):
        result = run(ROOT, r'''
import fswatch
import watchdog
for interval in 0 00 00000; do
    fswatch_valid_interval "$interval" && exit 1
    watchdog_valid_interval "$interval" && exit 1
done
exit 0
''')
        self.assertEqual(result['code'], 0, result)


if __name__ == '__main__':
    unittest.main(argv=['test_regressions.py'] + remaining)
