#!/usr/bin/env python3
"""Reproducible host microbenchmarks; never included in a module package."""
import argparse
import json
import os
from pathlib import Path
import shlex
import statistics
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path, required=True)
parser.add_argument('--samples', type=int, default=5)
parser.add_argument('--shell', default='sh')
parser.add_argument('--output', type=Path)
parser.add_argument('--time-command', default='time')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]

workloads = {
    'framework_load_40': '''i=0
while [ "$i" -lt 40 ]; do
    KAM_MODULES=''
    . "$IMPL/.kamfwrc" || exit 1
    i=$((i + 1))
done
''',
    'translation_table_300_rows': '''. "$IMPL/.kamfwrc" || exit 1
load_i18n "$FIXTURE/table" || exit 1
[ "$_I18N_ROW299_en" = 'English 299' ]
''',
    'template_300_calls_4_values': r'''. "$IMPL/.kamfwrc" || exit 1
i=0
while [ "$i" -lt 300 ]; do
    printf '%s\n' 'Hello $_1 $_2 $_3 $_4 / $_1' | t a b c d >/dev/null
    i=$((i + 1))
done
''',
    'installer_filter_400_files': '''. "$IMPL/.kamfwrc" || exit 1
import __installer__ || exit 1
install_exclude '*.tmp' 'private/*' '*.md' 'docs/*'
install_include 'docs/README.md' 'private/keep'
install_check "$FIXTURE/files" >"$FIXTURE/matched"
[ -s "$FIXTURE/matched" ]
''',
    'snapshot_400_files': '''. "$IMPL/.kamfwrc" || exit 1
import fswatch || exit 1
fswatch_snapshot "$FIXTURE/files" >"$FIXTURE/snapshot"
[ -s "$FIXTURE/snapshot" ]
''',
}

report = {'samples': args.samples, 'shell': args.shell,
          'baseline': str(args.baseline.resolve()), 'candidate': str(root),
          'rss_definition': 'time command maximum resident set size of a process in the measured command tree, KiB; not aggregate concurrent RSS',
          'results': {}}
with tempfile.TemporaryDirectory(prefix='kamfw-bench-') as directory:
    fixture = Path(directory)
    module = fixture / 'module'
    (module / '.config/kamfw').mkdir(parents=True)
    (fixture / 'files').mkdir()
    (fixture / 'table').write_text('KEY|en|zh|ja|ko\n' + ''.join(
        f'ROW{i}|English {i}|中文 {i}|日本語 {i}|한국어 {i}\n' for i in range(300)))
    for i in range(400):
        path = fixture / 'files' / ('docs' if i % 4 == 0 else 'bin') / f'{i}.txt'
        path.parent.mkdir(exist_ok=True)
        path.write_text(f'file {i}\n' * 8)
    for name, body in workloads.items():
        script = fixture / 'benchmark.sh'
        script.write_text(body)
        samples = {'baseline': [], 'candidate': []}
        for iteration in range(args.samples + 1):
            for label, implementation in [('baseline', args.baseline.resolve()), ('candidate', root)]:
                (module / '.config/kamfw/.envrc').write_text(
                    f'KAMFW_DIR={shlex.quote(str(implementation))}\nKAM_HOME={shlex.quote(str(module))}\nKAM_MODULES=\nKAM_UI_LANGUAGE=en\n')
                env = dict(os.environ, IMPL=str(implementation), FIXTURE=str(fixture),
                           MODDIR=str(module), MODPATH=str(module), TMPDIR=str(fixture))
                metrics = fixture / 'time.txt'
                started = time.perf_counter()
                result = subprocess.run(shlex.split(args.time_command) + ['-f', '%M', '-o', str(metrics)] +
                                        shlex.split(args.shell) + [str(script)], env=env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                        text=True, timeout=60)
                elapsed = time.perf_counter() - started
                if result.returncode:
                    raise RuntimeError(f'{label} {name}: {result.returncode}: {result.stderr}')
                if iteration:
                    samples[label].append({'seconds': elapsed, 'max_rss_kib': int(metrics.read_text())})
        summarized = {}
        for label, values in samples.items():
            summarized[label] = {'median_seconds': statistics.median(v['seconds'] for v in values),
                                 'median_max_rss_kib': statistics.median(v['max_rss_kib'] for v in values),
                                 'samples': values}
        summarized['speedup'] = summarized['baseline']['median_seconds'] / summarized['candidate']['median_seconds']
        report['results'][name] = summarized
        print(f'{name}: {summarized["speedup"]:.2f}x ({summarized["baseline"]["median_seconds"]:.4f}s -> {summarized["candidate"]["median_seconds"]:.4f}s)', flush=True)
text = json.dumps(report, indent=2) + '\n'
if args.output:
    args.output.write_text(text)
else:
    print(text)
