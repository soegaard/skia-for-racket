#!/usr/bin/env python3
"""Required raster skia-dc% regression, independent pixels and review runner."""
from __future__ import annotations
import argparse
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import dc_validation as validation

ROOT = Path(__file__).resolve().parents[1]


class Runner:
    def __init__(self, directory, timeout=300):
        self.directory = directory
        self.timeout = timeout
        self.commands = []
        (directory / 'logs').mkdir()

    def run(self, argv, *, cwd):
        argv = [str(a) for a in argv]
        logfile = self.directory / 'logs' / f'{len(self.commands)+1:03}.log'
        entry = dict(argv=argv, cwd=str(cwd), log=str(logfile.relative_to(self.directory)))
        self.commands.append(entry)
        print('+', subprocess.list2cmdline(argv), flush=True)
        started = time.monotonic()
        try:
            env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', SKIA_SOURCE_SUMS_MODE='check')
            completed = subprocess.run(argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, timeout=self.timeout, check=False)
            output = completed.stdout
            entry['returncode'] = completed.returncode
        except subprocess.TimeoutExpired as exc:
            output = exc.stdout or b''
            logfile.write_bytes(output)
            entry['timed_out'] = True
            raise RuntimeError(f'command timeout; see {logfile}') from exc
        except OSError as exc:
            logfile.write_text(str(exc), encoding='utf-8')
            entry['launch_error'] = str(exc)
            raise
        else:
            logfile.write_bytes(output)
            text = output.decode('utf-8', errors='replace')
            print(text, end='' if text.endswith('\n') else '\n', flush=True)
            if completed.returncode:
                raise RuntimeError(f'command exited {completed.returncode}; see {logfile}')
            return text
        finally:
            entry['elapsed_seconds'] = time.monotonic() - started
            validation.write_json(self.directory / 'commands.json', self.commands)


def execute(root, directory, racket, *, manifest_only=False, runner=None):
    runner = runner or Runner(directory)
    checks = {}
    state = dict(schema=1, stage='0.55', status='running', validation_run=directory.name,
                 racket_executable=racket, checks=checks, gpu_execution_verified=False,
                 full_drop_in_compatibility=False)
    try:
        manifest_command = [sys.executable, root/'tools/update-source-sums.py', '--check']
        if manifest_only:
            manifest_command.append('--manifest-only')
        runner.run(manifest_command, cwd=root)
        before_manifest = validation.sha256(root/'SOURCE-SHA256SUMS.txt')
        before = validation.source_fingerprint(root)
        identity_text = runner.run([racket, root/'tools/ci-identity.rkt'], cwd=root)
        identity = validation.json.loads(identity_text)
        validation.require(exact_identity(identity), 'unsupported Racket identity')
        state['identity'] = identity
        modules = ['dc.rkt', 'tools/dc-doctor.rkt', 'examples/dc-primitives.rkt',
                   'tests/dc-pure-test.rkt', 'tests/dc-native-test.rkt',
                   'tests/dc-compat-pure-test.rkt', 'tests/dc-compat-native-test.rkt',
                   'examples/dc-compatibility.rkt', 'examples/dc-replay.rkt',
                   'tests/dc-alpha-test.rkt', 'tests/dc-replay-pure-test.rkt',
                   'tests/dc-replay-native-test.rkt']
        runner.run([racket, '-l', 'raco', '--', 'make', *[root/name for name in modules]], cwd=root)
        checks['racket_compilation'] = True
        runner.run([racket, root/'tools/dc-doctor.rkt', '--directory', directory], cwd=root)
        inspected = validation.inspect_directory(directory, identity=identity)
        checks['native_dc_and_pixels'] = True
        runner.run(manifest_command, cwd=root)
        validation.require(before_manifest == validation.sha256(root/'SOURCE-SHA256SUMS.txt') and
                           before == validation.source_fingerprint(root), 'source changed during DC validation')
        checks['source_unchanged'] = True
        state.update(status='passed', source_manifest_sha256=before_manifest, sources=before,
                     inspection=inspected)
        validation.write_review(directory, inspected)
        validation.write_json(directory/'dc.inspection.json', inspected)
        validation.write_json(directory/'validation.json', state)
        print(f'DC foundation passed: {validation.PURE_CASES} pure cases, '
              f'{validation.NATIVE_CASES} native foundation cases; '
              f'{validation.COMPAT_PURE_CASES} pure + {validation.COMPAT_NATIVE_CASES} native compatibility cases; '
              f'{validation.REPLAY_PURE_CASES} pure + {validation.REPLAY_NATIVE_CASES} native replay cases; '
              f'two exact oracles and three bounded alpha/replay oracles; {directory}')
        return 0
    except (OSError, ValueError, TypeError, KeyError, RuntimeError, subprocess.SubprocessError) as exc:
        state.update(status='failed', error=str(exc))
        for name in ('dc.inspection.json', 'validation.json', 'dc.review.html'):
            (directory/name).unlink(missing_ok=True)
        validation.write_json(directory/'validation.failed.json', state)
        print(f'DC foundation FAILED: {exc}', file=sys.stderr)
        return 1


def exact_identity(value):
    return (isinstance(value, dict) and validation.exact(value.get('pointer_bytes'), 8)
            and value.get('vm') == 'chez-scheme' and value.get('os') in ('windows', 'unix', 'macosx')
            and value.get('architecture') in ('x86_64', 'aarch64')
            and supported_version(value.get('version')))


def supported_version(value):
    if not isinstance(value,str) or re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,3}',value) is None:
        return False
    parts = tuple(map(int,value.split('.')))
    return parts + (0,)*(4-len(parts)) >= (8,18,0,0)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket', default=os.environ.get('RACKET', 'racket'))
    parser.add_argument('--output', type=Path, help='new evidence directory; existing paths are refused')
    parser.add_argument('--manifest-only', action='store_true', help='installed source package without Git inventory')
    args = parser.parse_args(argv)
    executable = shutil.which(args.racket)
    if not executable:
        parser.error('selected Racket executable was not found')
    if args.output:
        directory = args.output.resolve()
        try:
            directory.mkdir(parents=True, exist_ok=False)
        except OSError as exc:
            parser.error(f'evidence directory must be new: {exc}')
    else:
        parent = ROOT/'output'; parent.mkdir(exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix='dc-0.55-', dir=parent))
    return execute(ROOT, directory, str(Path(executable).resolve()), manifest_only=args.manifest_only)


if __name__ == '__main__':
    raise SystemExit(main())
