"""Independent validation for the 0.54 raster DC evidence (stdlib only).

The tiny oracle is specified here, not derived from either renderer's pixels.
The larger Racket/Skia comparison is a manual review, not a pixel-equality gate.
"""
from __future__ import annotations

import hashlib
import html
import json
from pathlib import Path
import struct
import zlib

STAGE = '0.54'
PURE_CASES = 60
NATIVE_CASES = 31
COMPAT_PURE_CASES = 36
COMPAT_NATIVE_CASES = 34
PNG_MAGIC = b'\x89PNG\r\n\x1a\n'
SOURCE_PATHS = ('dc.rkt', 'private/dc-support.rkt', 'private/dc-class.rkt',
                'private/dc-render.rkt', 'private/dc-geometry.rkt',
                'tests/dc-pure-test.rkt', 'tests/dc-native-test.rkt',
                'examples/dc-primitives.rkt', 'tools/dc-doctor.rkt',
                'tools/dc_validation.py', 'tools/validate-dc.py',
                'private/core.rkt', 'private/dc-region-adapter.rkt', 'private/dc-bitmap.rkt',
                'private/dc-native-util.rkt', 'private/dc-text-spec.rkt', 'private/dc-text.rkt',
                'tests/dc-compat-pure-test.rkt', 'tests/dc-compat-native-test.rkt',
                'examples/dc-compatibility.rkt')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def exact(value, expected):
    return type(value) is int and value == expected


def pairs_unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f'duplicate JSON key: {key}')
        result[key] = value
    return result


def read_json(path):
    def bad_constant(value):
        raise ValueError(f'nonfinite JSON value: {value}')
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=pairs_unique,
                      parse_constant=bad_constant)


def write_json(path, value):
    path = Path(path)
    data = json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + '\n'
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(data, encoding='utf-8')
    temporary.replace(path)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_fingerprint(root):
    return {name: sha256(Path(root) / name) for name in SOURCE_PATHS}


def png_rgba(path, expected_size):
    """Read only the bounded RGB/RGBA8, noninterlaced PNGs our encoders emit."""
    data = Path(path).read_bytes()
    require(len(data) <= 8 * 1024 * 1024 and data.startswith(PNG_MAGIC), 'invalid/oversized PNG')
    offset = len(PNG_MAGIC)
    width = height = channels = None
    compressed = bytearray()
    seen_idat = ended_idat = ended = False
    while offset < len(data):
        require(offset + 12 <= len(data), 'truncated PNG chunk')
        size = struct.unpack_from('>I', data, offset)[0]
        kind = data[offset + 4:offset + 8]
        stop = offset + 12 + size
        require(stop <= len(data), 'truncated PNG payload')
        payload = data[offset + 8:offset + 8 + size]
        crc = struct.unpack_from('>I', data, offset + 8 + size)[0]
        require(zlib.crc32(kind + payload) & 0xffffffff == crc, 'PNG CRC mismatch')
        require(all(65 <= c <= 90 or 97 <= c <= 122 for c in kind), 'invalid PNG chunk type')
        if width is None:
            require(kind == b'IHDR' and size == 13, 'IHDR must be the first chunk')
            width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', payload)
            require((width, height) == tuple(expected_size), 'wrong PNG dimensions')
            require(0 < width * height <= 460 * 320, 'PNG pixel budget exceeded')
            require(depth == 8 and color in (2, 6) and (compression, filtering, interlace) == (0, 0, 0),
                    'expected RGB/RGBA8 noninterlaced PNG')
            channels = 3 if color == 2 else 4
        elif kind == b'IHDR':
            raise ValueError('duplicate PNG header')
        elif kind == b'IDAT':
            require(not ended_idat, 'noncontiguous PNG image data')
            seen_idat = True
            compressed.extend(payload)
        elif kind == b'IEND':
            require(size == 0 and seen_idat, 'invalid PNG end')
            require(stop == len(data), 'trailing bytes after PNG end')
            ended = True
        elif kind == b'PLTE':
            require(not seen_idat and size > 0 and size % 3 == 0 and size <= 768, 'invalid optional PNG palette')
        else:
            require(kind[0] & 32, 'unknown critical PNG chunk')
            # tRNS changes alpha semantics; our supported encoders use RGBA.
            require(kind != b'tRNS', 'unsupported PNG transparency chunk')
            if seen_idat:
                ended_idat = True
        offset = stop
        if ended:
            break
    require(ended, 'missing PNG end')
    stride = width * channels
    expected_bytes = height * (stride + 1)
    decoder = zlib.decompressobj()
    raw = decoder.decompress(bytes(compressed), expected_bytes + 1)
    require(len(raw) == expected_bytes and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail,
            'truncated, excessive, or trailing compressed image bytes')
    rows = []
    previous = bytearray(stride)
    def paeth(a, b, c):
        p = a + b - c
        da, db, dc = abs(p-a), abs(p-b), abs(p-c)
        return a if da <= db and da <= dc else (b if db <= dc else c)
    for y in range(height):
        start = y * (stride + 1)
        filter_type = raw[start]
        require(filter_type <= 4, 'unknown PNG filter')
        row = bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            left = row[x - channels] if x >= channels else 0
            above = previous[x]
            upper_left = previous[x - channels] if x >= channels else 0
            predictor = (0, left, above, (left+above)//2, paeth(left, above, upper_left))[filter_type]
            row[x] = (row[x] + predictor) & 255
        rows.append(row)
        previous = row
    output = bytearray()
    for row in rows:
        for x in range(0, stride, channels):
            output.extend(row[x:x+3])
            output.append(row[x+3] if channels == 4 else 255)
    return bytes(output)


def oracle_rgba():
    """24x20 logical units at 2x; four quadrants, fixed clip, clipped erase."""
    output = bytearray()
    for y in range(40):
        for x in range(48):
            color = ((255, 0, 0, 255) if x < 24 else (0, 200, 0, 255)) if y < 20 else (
                (0, 0, 255, 255) if x < 24 else (255, 255, 0, 255))
            if 8 <= x < 14 and 10 <= y < 18:
                color = (120, 30, 200, 255)
            if 36 <= x < 44 and 30 <= y < 36:
                color = (0, 0, 0, 0)
            output.extend(color)
    return bytes(output)


def compatibility_oracle_rgba():
    """64x48 oracle; independent of the Racket fixture and rendered captures."""
    def pattern(x, y): return (30 + 40*x, 20 + 40*y, 70, 255)
    pixels = bytearray(bytes((20, 30, 40, 255)) * (64*48))
    def put(x, y, c): pixels[4*(y*64+x):4*(y*64+x+1)] = bytes(c)
    for x0 in (2, 14, 44):
        for y in range(4):
            for x in range(4): put(x0+x, 2+y, pattern(x,y))
    for y in range(4):
        for x in range(2): put(8+x, 2+y, pattern(x,y))
    for y in range(2):
        for x in range(2): put(20+x, 2+y, (255,0,0,255) if x==y else (0,128,0,255))
    for y in range(12,24):
        for x in range(2,14):
            if not (6<=x<10 and 16<=y<20): put(x,y,(240,120,20,255))
    for y in range(15,22):
        for x in range(25,30): put(x,y,(130,30,190,255))
    for y in range(12,20):
        for x in range(35,41): put(x,y,(255,230,0,255))
    for y in range(32,36):
        for x in range(8): put(2+x,y,((x if x<2 else x-2)*30,80,160,255))
    return bytes(pixels)


def inspect_directory(directory, *, identity=None):
    directory = Path(directory).resolve()
    raw = read_json(directory / 'dc.diagnostic.json')
    require(isinstance(raw, dict), 'DC report must be an object')
    require(exact(raw.get('schema'), 1) and raw.get('stage') == STAGE, 'wrong DC report schema/stage')
    require(raw.get('status') == 'passed', 'DC doctor did not pass')
    require(raw.get('validation_run') == directory.name, 'foreign/stale DC run')
    require(raw.get('storage') == 'persistent-cpu-raster', 'wrong DC backing')
    require(raw.get('native_package') == '3.119.1' and raw.get('native_version') == '119.0', 'wrong native pin/version')
    for key in ('gpu_execution_verified', 'gui_initialized', 'full_drop_in_compatibility',
                'universal_pixel_identity_claimed', 'demo_pixel_equivalence_verified'):
        require(raw.get(key) is False, f'unsupported DC claim: {key}')
    for key, expected in [('pure_cases', PURE_CASES), ('native_cases', NATIVE_CASES),
                          ('pure_failures', 0), ('native_failures', 0),
                          ('compat_pure_cases', COMPAT_PURE_CASES), ('compat_native_cases', COMPAT_NATIVE_CASES),
                          ('compat_pure_failures', 0), ('compat_native_failures', 0)]:
        require(exact(raw.get(key), expected), f'incomplete DC test evidence: {key}')
    require(raw.get('snapshots_encoded_after_dc_close') is True, 'missing post-close image encoding')
    require(raw.get('os') in ('unix', 'windows', 'macosx'), 'missing/unknown execution OS')
    require(raw.get('architecture') in ('x86_64', 'aarch64'), 'missing/unknown execution architecture')
    require(isinstance(raw.get('racket_version'), str) and raw['racket_version'], 'missing Racket version')
    if identity is not None:
        for report_key, identity_key in [('os', 'os'), ('architecture', 'architecture'), ('racket_version', 'version')]:
            require(raw[report_key] == identity[identity_key], f'foreign interpreter: {report_key}')
    captures = [('oracle', 'dc-oracle.png', (48, 40)),
                ('skia_demo', 'dc-primitives.skia.png', (460, 320)),
                ('reference_demo', 'dc-primitives.racket.png', (460, 320)),
                ('compat_oracle', 'dc-compat-oracle.png', (64,48)),
                ('text_sample', 'dc-text.skia.png', (320,104))]
    receipts = []
    for key, name, dimensions in captures:
        require(raw.get(key) == name, 'unexpected capture filename')
        path = directory / name
        require(path.is_file() and not path.is_symlink(), 'missing or symlinked capture')
        pixels = png_rgba(path, dimensions)
        if key == 'oracle':
            require(pixels == oracle_rgba(), 'DC pixels differ from independent oracle')
        elif key == 'compat_oracle':
            require(pixels == compatibility_oracle_rgba(), 'bitmap/region/copy pixels differ from independent oracle')
        elif key == 'text_sample':
            red = sum(pixels[i] > pixels[i+1]+20 and pixels[i] > pixels[i+2]+20
                      for i in range(0,len(pixels),4))
            blue = sum(pixels[i+2] > pixels[i]+20 and pixels[i+2] > pixels[i+1]+20
                       for i in range(0,len(pixels),4))
            require(red >= 10 and blue >= 10, 'text sample lacks actual red/blue ink')
        else:
            # This only establishes nonempty actual images, not their fidelity.
            unique = {pixels[i:i+4] for i in range(0, len(pixels), 4)}
            require(len(unique) >= 8, 'demonstration PNG is blank or lacks expected variety')
        receipts.append(dict(file=name, width=dimensions[0], height=dimensions[1], sha256=sha256(path)))
    return dict(schema=1, stage=STAGE, status='passed', validation_run=directory.name,
                storage='persistent-cpu-raster', pure_cases=PURE_CASES, native_cases=NATIVE_CASES,
                compat_pure_cases=COMPAT_PURE_CASES, compat_native_cases=COMPAT_NATIVE_CASES,
                compatibility_oracle_pixels_verified=True, text_sample_nonempty_verified=True,
                exact_oracle_pixels_verified=True, snapshots_encoded_after_dc_close=True,
                demo_pixel_equivalence_verified=False, manual_demo_review_required=True,
                full_drop_in_compatibility=False, gpu_execution_verified=False,
                captures=receipts)


def write_review(directory, report):
    directory = Path(directory)
    require(report.get('status') == 'passed', 'no success review for a failed report')
    title = html.escape(directory.name)
    body = ['<!doctype html><meta charset="utf-8"><title>Skia DC 0.54 review</title>',
            '<h1>Skia DC 0.54</h1><p>' + title + '</p>',
            '<p>The 48×40 oracle is checked exactly. The larger images are for manual comparison; '
            'Font pixels are reviewed manually; the 64×48 bitmap/region/copy oracle is checked exactly. '
            'Universal pixel equivalence and full drop-in compatibility are not certified.</p>']
    for item in report['captures']:
        name = html.escape(item['file'], quote=True)
        body.append(f'<h2>{name}</h2><img src="{name}" alt="{name}"><p>SHA-256: {item["sha256"]}</p>')
    (directory / 'dc.review.html').write_text('\n'.join(body) + '\n', encoding='utf-8')
