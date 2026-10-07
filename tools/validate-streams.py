#!/usr/bin/env python3
"""0.75a native streams, ownership and explicitly buffered Racket-port acceptance.

Full regressions are the standalone default. --regressions=none retains every
stream-specific native test and byte oracle. No GPU or live-port claim is made.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid
from validation_regressions import add_regression_argument, global_compile_targets, RegressionGate
import stream_validation as checks

ROOT = Path(__file__).resolve().parents[1]


def main(argv=None, *, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket', default=os.environ.get('RACKET', 'racket'))
    parser.add_argument('--directory', type=Path)
    parser.add_argument('--timeout', type=float, default=1200)
    add_regression_argument(parser)
    args = parser.parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error('positive finite --timeout required')
    racket = shutil.which(args.racket)
    if not racket:
        parser.error('selected Racket executable not found')
    racket = str(Path(racket).resolve())
    root = Path(root).resolve()
    if args.directory:
        output = args.directory.resolve()
        output.mkdir(parents=True, exist_ok=False)
    else:
        (root / 'output').mkdir(exist_ok=True)
        output = Path(tempfile.mkdtemp(prefix='streams-0.75a-', dir=root / 'output'))
    (output / 'logs').mkdir()
    token = uuid.uuid4().hex
    commands = []
    report = dict(schema=1, stage='0.75a', package_version='0.75', run_token=token,
                  status='failed', pure_passed=False, native_passed=False, byte_oracles_passed=False,
                  live_port_callbacks=False, gpu_executed=False, commands=commands)
    regressions = RegressionGate(args.regressions, report)

    def run(command):
        command = list(map(str, command))
        log = output / 'logs' / f'{len(commands)+1:03d}.log'
        commands.append(command)
        print('+ ' + subprocess.list2cmdline(command), flush=True)
        try:
            with log.open('w', encoding='utf-8') as stream:
                stream.write('$ ' + repr(command) + '\n')
                stream.flush()
                subprocess.run(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                               timeout=args.timeout, check=True,
                               env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1', 'PYTHONUTF8': '1'})
            # The command line is not part of the RackUnit completion output.
            return log.read_text(encoding='utf-8', errors='replace').split('\n', 1)[1]
        except (OSError, subprocess.SubprocessError):
            report.update(failed_command=command, failed_log=str(log))
            raise
    try:
        run([sys.executable, root/'tools/update-source-sums.py', '--check'])
        before = hashlib.sha256((root/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest()
        run([sys.executable, root/'tools/api-inventory.py', '--check'])
        run([sys.executable, root/'tools/test-streams.py'])
        run([racket, root/'tools/check-package-version.rkt'])
        targets = [root/name for name in ('main.rkt', 'streams.rkt', 'stream-inputs.rkt',
                   'tests/stream-pure-test.rkt', 'tests/stream-native-test.rkt',
                   'tools/stream-doctor.rkt', 'examples/streams.rkt')]
        if args.regressions == 'full':
            targets += global_compile_targets(root)
        run([racket, '-l', 'raco', '--', 'make', *dict.fromkeys(targets)])
        regressions.run(lambda: run([racket, root/'run-tests.rkt']))
        for name, count, flag in (('stream-pure', checks.PURE_CASES, 'pure_passed'),
                                  ('stream-native', checks.NATIVE_CASES, 'native_passed')):
            checks.suite_output(run([racket, root/f'tests/{name}-test.rkt']), name, count)
            report[flag] = True
        run([racket, root/'examples/streams.rkt'])
        run([racket, root/'tools/stream-doctor.rkt', '--directory', output/'native', '--token', token])
        result = checks.inspect(output/'native', token)
        (output/'inspection.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        report['byte_oracles_passed'] = True
        run([sys.executable, root/'tools/update-source-sums.py', '--check'])
        after = hashlib.sha256((root/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest()
        checks.need(before == after, 'source manifest changed during validation')
        report.update(status='passed', manifest_sha256=after)
    except Exception as error:
        report['error'] = type(error).__name__ + ': ' + str(error)
        print('Streams FAILED: ' + report['error'], file=sys.stderr)
        if report.get('failed_log'):
            try:
                print(Path(report['failed_log']).read_bytes()[-20000:].decode('utf-8', errors='replace'), file=sys.stderr)
            except OSError:
                pass
    finally:
        (output/'validation.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
        (output/'commands.json').write_text(json.dumps(commands, indent=2)+'\n', encoding='utf-8')
        print('Evidence: ' + str(output))
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
