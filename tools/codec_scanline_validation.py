"""Inspect actual scanline bytes and state receipts; no native fallback or skip.

The synthetic fixtures used by test-codec-scanlines.py test this inspector only.
Pillow decodes the native evidence files independently of Skia.
"""
from __future__ import annotations
import hashlib
import io
import json
from pathlib import Path
import re
import struct

PURE_CASES = 32
NATIVE_CASES = 47
BMP_SIZE = (7, 5)
JPEG_SIZE = (16, 12)
ACTIONS = {
    'bottom': [('read', 2), ('read', 1), ('read', 2)],
    'top': [('read', 2), ('read', 1), ('read', 2)],
    'skip': [('skip', 1), ('read', 2), ('skip', 1), ('read', 1)],
    'short-bottom': [('read', 5)], 'short-top': [('read', 5)],
    'empty': [('read', 2), ('read', 1)], 'skip-failed': [('skip', 5)],
    'jpeg': [('read', 3), ('read', 4), ('read', 5)],
    'jpeg-half': [('read', 2), ('read', 1), ('read', 3)],
    'rotated-half': [('read', 2), ('read', 4)],
}
SOURCE_FILES = ('bottom.bmp', 'top.bmp', 'short-bottom.bmp', 'short-top.bmp',
                'reference.jpeg', 'rotated.jpeg', 'unsupported.png')


def need(value, message):
    if not value:
        raise ValueError(message)


def integer(value, expected, message):
    need(type(value) is int and value == expected, message)


def flag(value, expected, message):
    need(type(value) is bool and value is expected, message)


def row(value, expected, message):
    if expected is None:
        flag(value, False, message)
    else:
        integer(value, expected, message)


def unique(pairs):
    out = {}
    for key, value in pairs:
        need(key not in out, 'duplicate JSON field: ' + key)
        out[key] = value
    return out


def read(root, name, limit=1_048_576):
    need(type(name) is str and name and '/' not in name and '\\' not in name and ':' not in name
         and name not in ('.', '..'), 'unsafe evidence filename')
    p = root / name
    need(p.is_file() and not p.is_symlink(), 'missing/symlink evidence: ' + name)
    need(p.stat().st_size <= limit, 'evidence exceeds bounded fixture size: ' + name)
    return p.read_bytes()


def fixture_pixels(width=7, height=5):
    return bytes(channel for y in range(height) for x in range(width)
                 for channel in ((19+31*x+17*y) % 256, (43+13*x+29*y) % 256,
                                 (71+23*x+11*y) % 256, 255))


def suite_output(text, suite, count):
    text = text.replace('\r\n', '\n')
    marker = f'{suite}: {count} cases, 0 failures'
    need(text.splitlines().count(marker) == 1, 'missing/duplicate focused completion marker')
    summaries = re.findall(r'(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run', text)
    need(summaries == [(str(count), '0', '0', str(count))], 'focused suite did not complete cleanly')
    need(not re.search(r'(?m)^\s*(?:FAILURE|ERROR|FAIL|Traceback)\b', text), 'failure printed in focused suite')


def independently_decode(data, expected_format, size, *, half=False):
    from PIL import Image
    with Image.open(io.BytesIO(data)) as image:
        need(image.format == expected_format and image.size == size, 'wrong encoded fixture format/dimensions')
        if half:
            # Exercise native JPEG reduced-resolution IDCT, not a resampling oracle.
            image.draft('RGB', (size[0] // 2, size[1] // 2))
            need(image.size == (size[0] // 2, size[1] // 2), 'independent JPEG reduced decode unavailable')
        return image.convert('RGBA').tobytes()


def inspect(root: Path, token: str) -> dict:
    root = Path(root)
    need(root.is_dir() and not root.is_symlink(), 'missing/symlink evidence directory')
    data = json.loads(read(root, 'scanlines.json').decode('utf-8'), object_pairs_hook=unique)
    integer(data.get('schema'), 1, 'wrong schema')
    need(data.get('stage') == '0.76b' and data.get('run_token') == token, 'foreign stage/token')
    need(data.get('status') == 'passed' and data.get('native_version') == '119.0', 'native evidence not passed/pinned')
    need(data.get('session_scope') == 'owned-private-codec', 'wrong session ownership contract')
    flag(data.get('scaled_scanline_executed'), True, 'scaled scanlines not executed')
    for key in ('subset_decode_executed', 'incremental_decode_executed', 'live_port_callbacks', 'gpu_executed'):
        flag(data.get(key), False, 'unjustified execution claim: ' + key)
    unsupported = data.get('unsupported_png')
    need(type(unsupported) is dict and unsupported.get('result') == 'unimplemented', 'missing native unsupported result')
    integer(unsupported.get('code'), 9, 'wrong unsupported code')
    sources = {name: read(root, name) for name in SOURCE_FILES}
    for name, top in (('bottom.bmp', False), ('top.bmp', True)):
        content = sources[name]
        need(len(content) == 174 and content[:2] == b'BM', 'unexpected controlled BMP layout')
        need(struct.unpack_from('<I', content, 10)[0] == 54 and struct.unpack_from('<I', content, 14)[0] == 40,
             'wrong BMP data offset/header')
        need(struct.unpack_from('<ii', content, 18) == (7, -5 if top else 5), 'wrong BMP row-order fixture')
        need(struct.unpack_from('<HHI', content, 26) == (1, 24, 0), 'wrong BMP pixel encoding')
        need(independently_decode(content, 'BMP', BMP_SIZE) == fixture_pixels(), 'BMP fixture pixels disagree')
    for short, full in (('short-bottom.bmp', 'bottom.bmp'), ('short-top.bmp', 'top.bmp')):
        need(sources[short] == sources[full][:102], 'truncated fixture is not exactly two input rows')
    png_pixels = independently_decode(sources['unsupported.png'], 'PNG', BMP_SIZE)
    need(png_pixels == fixture_pixels(), 'unsupported PNG fixture is not valid expected content')
    jpeg = independently_decode(sources['reference.jpeg'], 'JPEG', JPEG_SIZE)
    need(all(abs(a-b) <= 6 for a, b in zip(jpeg, fixture_pixels(*JPEG_SIZE))), 'JPEG source differs from controlled pixels')
    half = independently_decode(sources['reference.jpeg'], 'JPEG', JPEG_SIZE, half=True)
    rotated = independently_decode(sources['rotated.jpeg'], 'JPEG', JPEG_SIZE, half=True)
    from PIL import Image
    with Image.open(io.BytesIO(sources['rotated.jpeg'])) as image:
        need(image.getexif().get(274) == 6, 'missing EXIF orientation test')
    need(rotated == half, 'orientation changed encoded JPEG pixels')
    cases = data.get('cases')
    need(type(cases) is list and len(cases) == len(ACTIONS), 'missing/extra native cases')
    indexed = {}
    for case in cases:
        need(type(case) is dict, 'bad case record')
        name = case.get('name')
        need(type(name) is str and name in ACTIONS and name not in indexed, 'foreign/duplicate case')
        indexed[name] = case
    inspected_rows = 0
    expected_files = {'scanlines.json', *SOURCE_FILES}
    captures = []
    for name, actions in ACTIONS.items():
        case = indexed[name]
        is_jpeg = name in ('jpeg', 'jpeg-half', 'rotated-half')
        w, h = (JPEG_SIZE if name == 'jpeg' else (8, 6)) if is_jpeg else BMP_SIZE
        bottom_up = name in ('bottom', 'skip', 'short-bottom', 'empty', 'skip-failed')
        order = 'bottom-up' if bottom_up else 'top-down'
        integer(case.get('width'), w, 'wrong scanline width')
        integer(case.get('height'), h, 'wrong scanline height')
        need(case.get('order') == order, 'wrong scanline order')
        need(case.get('color_type') == 'rgba-8888' and case.get('alpha_type') == 'unpremul'
             and case.get('color_space') == 'srgb', 'wrong destination representation')
        need(case.get('origin') == ('right-top' if name == 'rotated-half' else 'top-left'), 'wrong encoded origin')
        mappings = case.get('mappings')
        expected_map = list(reversed(range(h))) if bottom_up else list(range(h))
        need(type(mappings) is list and len(mappings) == h
             and all(type(a) is int and a == b for a, b in zip(mappings, expected_map)), 'wrong output-row mapping')
        steps = case.get('steps')
        need(type(steps) is list and len(steps) == len(actions), 'missing/extra scanline steps')
        ref = (jpeg if name == 'jpeg' else half) if is_jpeg else fixture_pixels()
        position = 0
        final_state = 'ready'
        for i, (step, (op, count)) in enumerate(zip(steps, actions)):
            need(type(step) is dict and step.get('op') == op, 'wrong step operation')
            integer(step.get('count'), count, 'wrong requested row count')
            integer(step.get('before'), position, 'wrong before cursor')
            row(step.get('before_row'), expected_map[position], 'wrong next native row before operation')
            details = step.get('result')
            need(type(details) is dict, 'missing step result')
            got = min(count, max(0, 2-position)) if name in ('short-bottom', 'short-top', 'empty') else count
            final_state = 'complete' if position+count == h else 'ready'
            if op == 'skip':
                success = name != 'skip-failed'
                flag(details.get('skipped'), success, 'wrong native skip result')
                if not success:
                    final_state = 'failed'
            else:
                if got < count:
                    final_state = 'incomplete'
                first = None if got == 0 else (h-position-got if bottom_up else position)
                stride = 32 if name == 'bottom' else w*4
                integer(details.get('decoded'), got, 'wrong decoded row count')
                integer(details.get('height'), got, 'batch height includes native filler')
                integer(details.get('row_bytes'), stride, 'wrong batch stride')
                row(details.get('first_row'), first, 'wrong batch first row')
                flag(details.get('complete'), got == count, 'wrong batch completion')
                file = f'{name}-{i}.rows'
                need(details.get('file') == file, 'wrong/unsafe row capture path')
                expected_files.add(file)
                raw = read(root, file)
                need(len(raw) == stride*got, 'batch bytes include filler or have a wrong length')
                for j in range(got):
                    pixels = raw[j*stride:j*stride+w*4]
                    expected = ref[((first+j)*w)*4:((first+j+1)*w)*4]
                    # JPEG IDCT implementations can differ slightly; BMP is exact.
                    tolerance = 3 if is_jpeg else 0
                    need(all(abs(a-b) <= tolerance for a, b in zip(pixels, expected)), 'decoded pixels/row placement differ: ' + file)
                    need(pixels[3::4] == bytes([255])*w, 'wrong decoded alpha')
                    need(raw[j*stride+w*4:(j+1)*stride] == bytes(stride-w*4), 'nonzero row padding')
                inspected_rows += got
                captures.append(dict(file=file, sha256=hashlib.sha256(raw).hexdigest(), rows=got))
            position += count
            integer(step.get('after'), position, 'cursor did not advance by requested count')
            need(step.get('state') == final_state, 'incorrect session state')
            next_row = expected_map[position] if final_state == 'ready' else None
            row(step.get('next_row'), next_row, 'invalid terminal/native next-row query')
        need(case.get('final_state') == final_state, 'false final session state')
        flag(case.get('closed'), True, 'native session not closed')
    actual_files = {p.name for p in root.iterdir()}
    need(actual_files == expected_files, 'evidence file inventory differs')
    return dict(status='passed', stage='0.76b', cases_checked=len(cases), rows_checked=inspected_rows,
                captures=captures, native_evidence_inspected=True, gpu_executed=False,
                incremental_decode_executed=False)
