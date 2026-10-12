#!/usr/bin/env python3
"""Run Batch 3A regressions; keep Python, native, and installed-doc evidence separate."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TUTORIALS = ROOT / 'scribblings/tutorials'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket', default='racket')
    parser.add_argument('--python-only', action='store_true')
    parser.add_argument('--setup', action='store_true',
                        help='also build registered installed manuals')
    args = parser.parse_args()
    if args.python_only and args.setup:
        parser.error('--python-only cannot be combined with --setup')
    (ROOT / 'output').mkdir(exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='tutorial-3a-', dir=ROOT / 'output'))
    racket = shutil.which(args.racket)
    raco = [racket or args.racket, '-l', 'raco', '--']
    stages = [
        ('python-checker', [sys.executable, '-B', str(TUTORIALS / 'test-check-21-22.py')]),
        ('compile-linux-example', [*raco, 'make',
                                   str(TUTORIALS / 'gpu/linux-opengl.rkt')]),
        ('pure-regressions', [*raco, 'test', *[str(TUTORIALS / name) for name in (
            'registration-test.rkt',
            'support/sprite-math.rkt', 'sprites/model-test.rkt',
            'sprites/initial-bounds-test.rkt', 'squadron/model-test.rkt')]]),
        ('native-font-and-label-regressions', [*raco, 'test',
                                               str(TUTORIALS / 'shaping/language-sampler.rkt'),
                                               str(TUTORIALS / 'interaction/scene.rkt')]),
        ('registered-documents', [*raco, 'setup', '--check-pkg-deps', 'skia']),
    ]
    report = dict(status='in-progress', commands=[], unexecuted=[name for name, _ in stages],
                  racket_executable=racket, gpu_executed=False, physical_display_tested=False,
                  isolated_install_tested=False, source_manifest_checked=False)

    def checkpoint() -> None:
        temporary = output / 'validation.json.tmp'
        temporary.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        temporary.replace(output / 'validation.json')

    checkpoint()
    try:
        for index, (name, command) in enumerate(stages):
            if args.python_only and index:
                continue
            if name == 'registered-documents' and not args.setup:
                continue
            if index and not racket:
                raise FileNotFoundError(f'Racket executable not found: {args.racket}')
            record = dict(name=name, command=command, status='running', log=name + '.log')
            report['commands'].append(record)
            checkpoint()
            try:
                result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                        encoding='utf-8', errors='replace', timeout=1800)
            except subprocess.TimeoutExpired as error:
                report['unexecuted'].remove(name)
                record['status'] = 'timed-out'
                (output / record['log']).write_text(str(error), encoding='utf-8')
                raise
            except OSError:
                record['status'] = 'launch-failed'
                raise
            (output / record['log']).write_text(result.stdout + result.stderr, encoding='utf-8')
            report['unexecuted'].remove(name)
            record['exit_code'] = result.returncode
            record['status'] = 'passed' if result.returncode == 0 else 'failed'
            checkpoint()
            if result.returncode:
                raise RuntimeError(f'{name} failed; see {output / record["log"]}')
            print(f'{name}: passed')
        report['status'] = 'python-only-passed' if args.python_only else 'requested-checks-passed'
    except Exception as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        print(f'FAILED: {error}', file=sys.stderr)
    finally:
        checkpoint()
        print(f'Validation record: {output}')
        print('Unexecuted: ' + ', '.join(report['unexecuted']))
    return 1 if report['status'] == 'failed' else 0


if __name__ == '__main__':
    raise SystemExit(main())
