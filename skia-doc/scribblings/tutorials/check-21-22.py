#!/usr/bin/env python3
"""Compile, test and render Tutorials 21–22. GUI/GPU gates are explicitly selected."""
from __future__ import annotations

import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
TUTORIALS = ROOT / 'scribblings/tutorials'


class Images(HTMLParser):
    def __init__(self):
        super().__init__()
        self.sources = []
        self.described = []
        self.unresolved_markers = 0
        self.evaluation_error_markers = 0

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        classes = set((attributes.get('class') or '').split())
        self.unresolved_markers += int('badlink' in classes)
        self.evaluation_error_markers += int('RktErr' in classes)
        if tag == 'img':
            self.sources.append(attributes.get('src', ''))
            self.described.append('skia-tutorial-figure' in classes)


def png_size(path: Path) -> tuple[int, int]:
    with path.open('rb') as stream:
        header = stream.read(24)
    if header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError(f'not a PNG with an IHDR: {path}')
    return struct.unpack('>II', header[16:24])


def inspect_html(path: Path, expected: int) -> dict:
    source = path.read_text(encoding='utf-8')
    parser = Images()
    parser.feed(source)
    if not parser.sources:
        raise ValueError(f'no images: {path}')
    figures = []
    for url, described in zip(parser.sources, parser.described):
        parts = urlsplit(url)
        if parts.scheme or parts.netloc:
            continue
        image = path.parent / unquote(parts.path)
        if not image.is_file():
            raise ValueError(f'missing image: {image}')
        if described or re.fullmatch(r'pict(?:_\d+)?\.png', image.name):
            width, height = png_size(image)
            if width <= 0 or height <= 0:
                raise ValueError(f'empty image: {image}')
            figures.append(dict(file=image.name, width=width, height=height))
    if len(figures) != expected:
        raise ValueError(f'{path.name}: expected {expected} figure placements, got {len(figures)}')
    return dict(figures=figures, machine_local_links=source.count('file:///'),
                unresolved_markers=parser.unresolved_markers,
                evaluation_error_markers=parser.evaluation_error_markers)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket', default='racket')
    parser.add_argument('--gui', action='store_true', help='also run both CPU window smoke tests')
    parser.add_argument('--gpu', action='store_true', help='also run GPU windows; implies --gui')
    parser.add_argument('--online-doc-links', action='store_true')
    args = parser.parse_args()
    (ROOT / 'output').mkdir(exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='tutorials-21-22-', dir=ROOT / 'output'))
    report = dict(status='failed', commands=[], gui_requested=args.gui or args.gpu,
                  gpu_requested=args.gpu, gpu_window_smoke_passed=False,
                  physical_display_verified=False, performance_measured=False)

    def run(name: str, command: list[str], timeout: int = 180) -> str:
        log = output / (name + '.log')
        record = dict(name=name, command=command, log=log.name, status='running')
        report['commands'].append(record)
        try:
            result = subprocess.run(command, cwd=ROOT, text=True, encoding='utf-8',
                                    errors='replace', capture_output=True, timeout=timeout)
            text = result.stdout + result.stderr
            log.write_text('$ ' + repr(command) + '\n' + text, encoding='utf-8')
            if result.returncode:
                raise RuntimeError(f'{name} exited {result.returncode}; see {log}')
            record['status'] = 'passed'
            return text
        except Exception:
            record['status'] = 'failed'
            raise

    try:
        run('checker-tests', [sys.executable, str(TUTORIALS / 'test-check-21-22.py')])
        racket = shutil.which(args.racket)
        if not racket:
            raise FileNotFoundError(f'Racket executable not found: {args.racket}')
        modules = sorted(str(path) for name in ('sprites', 'squadron')
                         for path in (TUTORIALS / name).glob('*.rkt'))
        shared = [TUTORIALS / 'support' / name for name in
                  ('sprite-assets.rkt', 'sprite-window.rkt', 'sprite-figures.rkt', 'sprite-math.rkt')]
        run('compile', [racket, '-l', 'raco', '--', 'make', *modules, *map(str, shared)])
        tests = [TUTORIALS / 'support/sprite-math.rkt',
                 TUTORIALS / 'sprites/initial-bounds-test.rkt']
        tests += [TUTORIALS / name / 'model-test.rkt' for name in ('sprites', 'squadron')]
        run('pure-tests', [racket, '-l', 'raco', '--', 'test', *map(str, tests)])
        tests = [TUTORIALS / name / 'native-test.rkt' for name in ('sprites', 'squadron')]
        run('native-tests', [racket, '-l', 'raco', '--', 'test', *map(str, tests)])
        for folder, entry, dimensions, count in (
            ('sprites', 'balls.rkt', (800, 480), 5),
            ('squadron', 'squadron.rkt', (640, 760), 8),
        ):
            program = TUTORIALS / folder / entry
            png = output / (folder + '.png')
            run(folder + '-snapshot', [racket, str(program), '--snapshot', str(png)])
            if png_size(png) != dimensions:
                raise ValueError(f'wrong snapshot dimensions: {png}')
            doc = output / folder
            doc.mkdir()
            command = [racket, '-l', 'raco', '--', 'scribble', '--html', '--dest', str(doc)]
            if args.online_doc_links:
                command += ['--redirect-main', 'https://docs.racket-lang.org/']
            command.append(str(TUTORIALS / folder / (folder + '.scrbl')))
            run(folder + '-manual', command)
            report[folder] = inspect_html(doc / (folder + '.html'), count)
            modes = ['raster', 'gpu'] if args.gpu else (['raster'] if args.gui else [])
            for mode in modes:
                text = run(folder + '-' + mode + '-smoke',
                           [racket, str(program), '--renderer', mode, '--smoke'], timeout=90)
                expected = 1 if mode == 'gpu' else 0
                pattern = rf'sprite-window-smoke: {mode} / \d+ frames / {expected} uploads / closed'
                if len(re.findall(pattern, text)) != 1:
                    raise ValueError(f'{folder}: missing/duplicate {mode} smoke completion')
        report['status'] = 'passed'
        report['gpu_window_smoke_passed'] = args.gpu
    except Exception as error:
        report['error'] = str(error)
        print(f'FAILED: {error}')
    finally:
        (output / 'validation.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(f'Validation record: {output}')
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
