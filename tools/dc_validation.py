"""Independent validation for the 0.53 raster DC evidence (stdlib only).

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

STAGE = '0.53'
PURE_CASES = 60
NATIVE_CASES = 31
PNG_MAGIC = b'\x89PNG\r\n\x1a\n'
SOURCE_PATHS = ('dc.rkt', 'private/dc-support.rkt', 'private/dc-class.rkt',
                'private/dc-render.rkt', 'private/dc-geometry.rkt',
                'tests/dc-pure-test.rkt', 'tests/dc-native-test.rkt',
                'examples/dc-primitives.rkt', 'tools/dc-doctor.rkt',
                'tools/dc_validation.py', 'tools/validate-dc.py')


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
                          ('pure_failures', 0), ('native_failures', 0)]:
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
                ('reference_demo', 'dc-primitives.racket.png', (460, 320))]
    receipts = []
    for key, name, dimensions in captures:
        require(raw.get(key) == name, 'unexpected capture filename')
        path = directory / name
        require(path.is_file() and not path.is_symlink(), 'missing or symlinked capture')
        pixels = png_rgba(path, dimensions)
        if key == 'oracle':
            require(pixels == oracle_rgba(), 'DC pixels differ from independent oracle')
        else:
            # This only establishes nonempty actual images, not their fidelity.
            unique = {pixels[i:i+4] for i in range(0, len(pixels), 4)}
            require(len(unique) >= 8, 'demonstration PNG is blank or lacks expected variety')
        receipts.append(dict(file=name, width=dimensions[0], height=dimensions[1], sha256=sha256(path)))
    return dict(schema=1, stage=STAGE, status='passed', validation_run=directory.name,
                storage='persistent-cpu-raster', pure_cases=PURE_CASES, native_cases=NATIVE_CASES,
                exact_oracle_pixels_verified=True, snapshots_encoded_after_dc_close=True,
                demo_pixel_equivalence_verified=False, manual_demo_review_required=True,
                full_drop_in_compatibility=False, gpu_execution_verified=False,
                captures=receipts)


def write_review(directory, report):
    directory = Path(directory)
    require(report.get('status') == 'passed', 'no success review for a failed report')
    title = html.escape(directory.name)
    body = ['<!doctype html><meta charset="utf-8"><title>Skia DC 0.53 review</title>',
            '<h1>Skia DC 0.53</h1><p>' + title + '</p>',
            '<p>The 48×40 oracle is checked exactly. The larger images are for manual comparison; '
            'pixel equivalence, text support, and full drop-in compatibility are not certified.</p>']
    for item in report['captures']:
        name = html.escape(item['file'], quote=True)
        body.append(f'<h2>{name}</h2><img src="{name}" alt="{name}"><p>SHA-256: {item["sha256"]}</p>')
    (directory / 'dc.review.html').write_text('\n'.join(body) + '\n', encoding='utf-8')
