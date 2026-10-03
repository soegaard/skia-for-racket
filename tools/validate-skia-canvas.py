#!/usr/bin/env python3
"""Validate persistent raster skia-canvas storage, with an explicit required GUI gate.

The default is headless: production lifecycle, native Skia pixels, and the
public bitmap% transfer API. --require-gui additionally requires real shown
windows and eventspace callbacks. A missing display is a failure in that mode.
Neither mode claims independent screen pixel equivalence or GPU execution.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

import dc_validation as common

ROOT = Path(__file__).resolve().parents[1]
PURE_CASES = 38
NATIVE_CASES = 14
GUI_CASES = 15
SOURCE_PATHS = tuple(dict.fromkeys((*common.SOURCE_PATHS,
    'canvas.rkt', 'private/canvas-backing.rkt', 'private/harfbuzz-native.rkt', 'tests/canvas-dc-pure-test.rkt',
    'tests/canvas-dc-native-test.rkt', 'tests/canvas-gui-test.rkt', 'tests/canvas-text-load-order.rkt',
    'tools/validate-skia-canvas.py', 'tools/test-validate-skia-canvas.py',
    'run-tests.rkt', 'info.rkt')))


def source_fingerprint(root):
    return {name: common.sha256(Path(root) / name) for name in SOURCE_PATHS}


def supported_identity(identity):
    if not isinstance(identity, dict):
        return False
    version = identity.get('version')
    if not isinstance(version, str) or re.fullmatch(r'\d+(?:\.\d+){1,3}', version) is None:
        return False
    parts = tuple(map(int, version.split('.')))
    return (parts + (0,) * (4 - len(parts)) >= (8, 18, 0, 0)
            and common.exact(identity.get('pointer_bytes'), 8)
            and identity.get('vm') == 'chez-scheme'
            and identity.get('os') in ('windows', 'unix', 'macosx')
            and identity.get('architecture') in ('x86_64', 'aarch64'))


def validate_suite_output(output, name, cases):
    """Require both a complete RackUnit result and the suite's own count marker.

    A zero exit code with missing/partial/skip output must not establish a GUI
    or native result. In particular, check failures on a GUI eventspace must
    reach the RackUnit suite before it can report success.
    """
    marker = re.findall(rf'^{re.escape(name)}: (\d+) cases, (\d+) failures; .+$', output, re.MULTILINE)
    common.require(marker == [(str(cases), '0')], f'{name}: missing, duplicate or incorrect completion marker')
    summaries = re.findall(
        r'^(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run$',
        output, re.MULTILINE)
    common.require(summaries == [(str(cases), '0', '0', str(cases))],
                   f'{name}: incomplete or failed RackUnit result')


def validate_load_order_output(output, order):
    markers = re.findall(r'^canvas-text-load-order: (.+)$', output, re.MULTILINE)
    common.require(len(markers) == 1, 'missing or duplicate text load-order result')
    result = common.json.loads(markers[0], object_pairs_hook=common.pairs_unique)
    common.require(isinstance(result, dict) and result.get('status') == 'passed'
                   and result.get('load_order') == order and result.get('gui_initialized') is True
                   and common.exact(result.get('skia_text_checks'), 2)
                   and common.exact(result.get('racket_text_checks'), 2),
                   f'incomplete or failed text load-order result: {order}')
    return result


class Runner:
    def __init__(self, directory, timeout=300):
        self.directory = Path(directory)
        self.timeout = timeout
        self.commands = []
        (self.directory / 'logs').mkdir()

    def run(self, argv, *, cwd):
        argv = [str(part) for part in argv]
        logfile = self.directory / 'logs' / f'{len(self.commands) + 1:03}.log'
        entry = dict(argv=argv, cwd=str(cwd), log=str(logfile.relative_to(self.directory)))
        self.commands.append(entry)
        print('+', subprocess.list2cmdline(argv), flush=True)
        started = time.monotonic()
        try:
            env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', SKIA_SOURCE_SUMS_MODE='check')
            completed = subprocess.run(argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, timeout=self.timeout, check=False)
            logfile.write_bytes(completed.stdout)
            entry['returncode'] = completed.returncode
            output = completed.stdout.decode('utf-8', errors='replace')
            print(output, end='' if output.endswith('\n') else '\n', flush=True)
            if completed.returncode:
                raise RuntimeError(f'command exited {completed.returncode}; see {logfile}')
            return output
        except subprocess.TimeoutExpired as exc:
            logfile.write_bytes(exc.stdout or b'')
            entry['timed_out'] = True
            raise RuntimeError(f'command timed out; see {logfile}') from exc
        except OSError as exc:
            logfile.write_text(str(exc), encoding='utf-8')
            entry['launch_error'] = str(exc)
            raise
        finally:
            entry['elapsed_seconds'] = time.monotonic() - started
            common.write_json(self.directory / 'commands.json', self.commands)


def execute(root, directory, racket, *, require_gui=False, manifest_only=False, runner=None):
    root, directory = Path(root), Path(directory)
    runner = runner or Runner(directory)
    checks = dict(pure_lifecycle=False, native_pixels_and_bitmap_bridge=False,
                  required_gui=False, text_load_orders=False, source_unchanged=False)
    gui = dict(required=bool(require_gui), executed=False, status='not-run', cases=0,
               text_load_orders=[])
    state = dict(schema=1, stage='0.58', status='running', validation_run=directory.name,
                 racket_executable=str(racket), checks=checks, gui=gui,
                 gpu_execution_verified=False, full_drop_in_compatibility=False,
                 screen_pixel_equivalence_claimed=False, presentation_submission_verified=False)
    for name in ('validation.json', 'validation.failed.json'):
        (directory / name).unlink(missing_ok=True)
    try:
        manifest_command = [sys.executable, root / 'tools/update-source-sums.py', '--check']
        if manifest_only:
            manifest_command.append('--manifest-only')
        runner.run(manifest_command, cwd=root)
        manifest_before = common.sha256(root / 'SOURCE-SHA256SUMS.txt')
        sources_before = source_fingerprint(root)
        identity = common.json.loads(runner.run([racket, root / 'tools/ci-identity.rkt'], cwd=root),
                                     object_pairs_hook=common.pairs_unique)
        common.require(supported_identity(identity), 'unsupported Racket identity; require 64-bit Racket CS 8.18 or later')
        state['identity'] = identity
        modules = ('dc.rkt', 'private/canvas-backing.rkt', 'tests/canvas-dc-pure-test.rkt',
                   'tests/canvas-dc-native-test.rkt')
        runner.run([racket, '-l', 'raco', '--', 'make', *[root / name for name in modules]], cwd=root)
        checks['headless_compilation'] = True
        for filename, marker, count, check in (
                ('canvas-dc-pure-test.rkt', 'canvas-dc-pure', PURE_CASES, 'pure_lifecycle'),
                ('canvas-dc-native-test.rkt', 'canvas-dc-native', NATIVE_CASES, 'native_pixels_and_bitmap_bridge')):
            output = runner.run([racket, root / 'tests' / filename], cwd=root)
            validate_suite_output(output, marker, count)
            checks[check] = True
        state['pure_cases'] = PURE_CASES
        state['native_cases'] = NATIVE_CASES
        if require_gui:
            gui['status'] = 'running'
            runner.run([racket, '-l', 'raco', '--', 'make', root / 'canvas.rkt',
                        root / 'tests/canvas-gui-test.rkt', root / 'tests/canvas-text-load-order.rkt'], cwd=root)
            gui['executed'] = True
            output = runner.run([racket, root / 'tests/canvas-gui-test.rkt'], cwd=root)
            validate_suite_output(output, 'canvas-gui', GUI_CASES)
            for order in ('gtk-first', 'skia-first'):
                output = runner.run([racket, root / 'tests/canvas-text-load-order.rkt', order], cwd=root)
                gui['text_load_orders'].append(validate_load_order_output(output, order))
            checks['text_load_orders'] = True
            gui.update(status='passed', cases=GUI_CASES)
            checks['required_gui'] = True
            state['presentation_submission_verified'] = True
        runner.run(manifest_command, cwd=root)
        common.require(manifest_before == common.sha256(root / 'SOURCE-SHA256SUMS.txt')
                       and sources_before == source_fingerprint(root),
                       'source or manifest changed during canvas validation')
        checks['source_unchanged'] = True
        state.update(status='passed', source_manifest_sha256=manifest_before, sources=sources_before)
        common.write_json(directory / 'validation.json', state)
        gui_summary = (f'{GUI_CASES} required GUI cases + both text load orders'
                       if require_gui else 'GUI NOT RUN (headless mode)')
        print(f'Skia canvas passed: {PURE_CASES} pure, {NATIVE_CASES} native; {gui_summary}; {directory}')
        return 0
    except (OSError, ValueError, TypeError, KeyError, RuntimeError, subprocess.SubprocessError) as exc:
        if gui['status'] == 'running':
            gui['status'] = 'failed'
        state.update(status='failed', error=str(exc))
        (directory / 'validation.json').unlink(missing_ok=True)
        common.write_json(directory / 'validation.failed.json', state)
        print(f'Skia canvas FAILED: {exc}', file=sys.stderr)
        return 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket', default=os.environ.get('RACKET', 'racket'))
    parser.add_argument('--output', type=Path, help='new evidence directory; existing paths are refused')
    parser.add_argument('--manifest-only', action='store_true', help='installed source package without Git inventory')
    parser.add_argument('--require-gui', '--gui', action='store_true',
                        help='require actual shown-window/eventspace tests; missing display fails')
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
        parent = ROOT / 'output'
        parent.mkdir(exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix='skia-canvas-0.58-', dir=parent))
    return execute(ROOT, directory, str(Path(executable).resolve()),
                   require_gui=args.require_gui, manifest_only=args.manifest_only)


if __name__ == '__main__':
    raise SystemExit(main())
