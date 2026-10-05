#!/usr/bin/env python3
"""0.68a typeface acceptance: full regressions and controlled PDF/SVG output."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from typeface_validation import inspect_documents

ROOT = Path(__file__).resolve().parents[1]


def compile_targets(root: Path):
    text = (root/'run-tests.rkt').read_text(encoding='utf-8')
    dynamic = sorted(set(re.findall(r'\(define-runtime-path\s+\S+\s+"(tests/[^"\n]+\.rkt)"\)', text)))
    if not dynamic:
        raise ValueError('no dynamically required regression suites discovered')
    for name in dynamic:
        if any(p in ('', '.', '..') for p in name.split('/')) or '\\' in name or ':' in name:
            raise ValueError('unsafe regression target')
    return [root/p for p in dict.fromkeys(('main.rkt', 'typefaces.rkt', 'run-tests.rkt', *dynamic,
                                          'tools/typeface-doctor.rkt', 'examples/typefaces.rkt'))]


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--racket', default='racket')
    p.add_argument('--directory', type=Path)
    p.add_argument('--require-renderers', action='store_true')
    p.add_argument('--timeout', type=float, default=1200)
    args = p.parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        p.error('positive finite timeout required')
    executable = shutil.which(args.racket)
    if not executable:
        p.error('selected Racket executable not found')
    racket = str(Path(executable).resolve())
    if args.directory:
        if args.directory.exists():
            p.error('evidence directory already exists')
        args.directory.mkdir(parents=True)
        out = args.directory.resolve()
    else:
        (ROOT/'output').mkdir(exist_ok=True)
        out = Path(tempfile.mkdtemp(prefix='typefaces-0.68a-', dir=ROOT/'output'))
    (out/'logs').mkdir()
    token = uuid.uuid4().hex
    commands = []
    report = dict(schema=1, stage='0.68a', package_version='0.68.1', run_token=token, status='failed',
                  regressions_passed=False, documents_passed=False, native_generation_passed=False,
                  independent_renderers_required=args.require_renderers, independent_renderers_passed=False,
                  rendering_executed=False, gui_executed=False, gpu_executed=False)
    def run(command):
        command = [str(a) for a in command]
        commands.append(command)
        log = out/'logs'/f'{len(commands):03d}.log'
        print('+ ' + ' '.join(command), flush=True)
        with log.open('w', encoding='utf-8') as f:
            f.write('$ ' + repr(command) + '\n'); f.flush()
            try:
                subprocess.run(command, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT, check=True,
                               timeout=args.timeout, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
            except (OSError, subprocess.SubprocessError):
                report.update(failed_command=command, failed_log=str(log))
                raise
    try:
        run([sys.executable, ROOT/'tools/update-source-sums.py', '--check'])
        before = hashlib.sha256((ROOT/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest()
        report['manifest_before'] = before
        run([sys.executable, ROOT/'tools/api-inventory.py', '--check'])
        run([sys.executable, ROOT/'tools/test-typefaces.py'])
        run([sys.executable, ROOT/'tools/test-typeface-document-inspector.py'])
        run([racket, '-l', 'raco', '--', 'make', *compile_targets(ROOT)])
        run([racket, ROOT/'run-tests.rkt'])
        report['regressions_passed'] = True
        run([racket, ROOT/'tools/typeface-doctor.rkt', '--directory', out/'documents', '--token', token])
        report.update(native_generation_passed=True, rendering_executed=True)
        render = None
        if args.require_renderers:
            poppler, rsvg = shutil.which('pdftoppm'), shutil.which('rsvg-convert')
            if not poppler or not rsvg:
                raise ValueError('pdftoppm and rsvg-convert are required')
            (out/'rendered').mkdir()
            def render(path, fmt):
                png = out/'rendered'/(path.name + '.png')
                if fmt == 'pdf':
                    run([poppler, '-singlefile', '-r', '72', '-png', path, png.with_suffix('')])
                else:
                    run([rsvg, '--width', '160', '--height', '100', '--output', png, path])
                return png
        result = inspect_documents(out/'documents', token, render=render)
        (out/'inspection.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        report.update(documents_passed=True, independent_renderers_passed=args.require_renderers)
        run([sys.executable, ROOT/'tools/update-source-sums.py', '--check'])
        after = hashlib.sha256((ROOT/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest()
        if before != after:
            raise ValueError('source manifest changed during validation')
        report.update(manifest_after=after, status='passed')
    except (OSError, ValueError, ImportError, subprocess.SubprocessError) as error:
        report['error'] = type(error).__name__ + ': ' + str(error)
        print('Typefaces FAILED: ' + report['error'], file=sys.stderr)
    finally:
        for name, value in (('commands.json', commands), ('validation.json', report)):
            (out/name).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
        print('Evidence: ' + str(out))
        if report.get('failed_log'):
            print('Failed command log: ' + report['failed_log'])
    if report['status'] == 'passed':
        print('Typeface resources selected gates passed; no GPU/GUI execution claim.')
        return 0
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
