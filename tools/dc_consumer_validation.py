"""Independent checks for the narrow 0.56 consumer corpus, not universal fidelity.

Pict solid/bitmap/group interiors have analytical expected pixels. Plot ink is
checked at known data coordinates by independently interpolating the two plot
corners. Target-specific metrics are allowed to differ. Only the two replay
forms of the SAME recording are compared numerically (two channel units).
"""
from __future__ import annotations
import math
from pathlib import Path
import dc_validation as d

NATIVE_CASES = 16
SIZE = (320, 240)
KINDS = ('pict', 'plot')
MODES = ('direct', 'procedure', 'datum', 'reference')
CHANNEL_TOLERANCE = 2
PROBE_RADIUS = 3


def filename(kind, mode):
    return f'dc-consumer-{kind}.{mode}.png'


def pixel(pixels, x, y):
    i = 4 * (y * SIZE[0] + x)
    return tuple(pixels[i:i + 4])


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def plot_position(layout, x, y):
    d.require(isinstance(layout, dict) and set(layout) == {'lower_left', 'upper_right'},
              'invalid plot layout')
    lo, hi = layout['lower_left'], layout['upper_right']
    for point in (lo, hi):
        d.require(isinstance(point, list) and len(point) == 2 and all(map(finite, point)),
                  'invalid plot corner')
    d.require(5 <= lo[0] < hi[0] <= 315 and hi[0] - lo[0] >= 100 and
              5 <= hi[1] < lo[1] <= 235 and lo[1] - hi[1] >= 100,
              'plot corners are outside the expected viewport or reversed')
    return (lo[0] + (x + 2) / 4 * (hi[0] - lo[0]),
            lo[1] + (y + 1.5) / 3 * (hi[1] - lo[1]))


def color_ink(p, color):
    r, g, b, a = p
    return a > 240 and ((b > 160 and r < 100 and g < 100) if color == 'blue'
                        else (r > 160 and g < 100 and b < 100))


def check_pict(pixels):
    for x, y, expected in ((24, 24, (255, 0, 0, 255)),
                           (18, 72, (255, 128, 128, 255)),
                           (36, 72, (128, 128, 255, 255)),
                           (164, 16, (20, 180, 60, 255))):
        d.require(all(abs(a - b) <= CHANNEL_TOLERANCE
                      for a, b in zip(pixel(pixels, x, y), expected)),
                  'pict solid/bitmap/alpha probe failed')
    navy = sum(r < 160 and g < 160 and b > r + 20 and a > 240
               for y in range(126, 172) for x in range(12, 165)
               for r, g, b, a in (pixel(pixels, x, y),))
    d.require(navy >= 12, 'pict lacks actual navy text ink')


def check_plot(pixels, layout):
    probes = ((-1.5, -.75, 'blue'), (-.5, -.25, 'blue'),
              (.5, .25, 'blue'), (1.5, .75, 'blue'), (-1, 1, 'red'), (1, -1, 'red'))
    for px, py, color in probes:
        x, y = (round(n) for n in plot_position(layout, px, py))
        d.require(any(color_ink(pixel(pixels, xx, yy), color)
                      for xx in range(max(0, x - PROBE_RADIUS), min(SIZE[0], x + PROBE_RADIUS + 1))
                      for yy in range(max(0, y - PROBE_RADIUS), min(SIZE[1], y + PROBE_RADIUS + 1))),
                  f'plot lacks {color} data ink near ({px}, {py})')
    # Title is a real plot/no-gui text operation, not a separately drawn marker.
    dark = sum(max(pixel(pixels, x, y)[:3]) < 150 and pixel(pixels, x, y)[3] > 240
               for y in range(0, 28) for x in range(60, 260))
    d.require(dark >= 12, 'plot lacks title ink')


def inspect_consumers(directory, *, identity=None):
    directory = Path(directory)
    path = directory / 'dc-consumers.json'
    d.require(path.is_file() and not path.is_symlink(), 'missing/symlinked consumer report')
    raw = d.read_json(path)
    d.require(isinstance(raw, dict) and d.exact(raw.get('schema'), 1) and raw.get('stage') == '0.56',
              'wrong consumer schema/stage')
    d.require(raw.get('status') == 'passed' and raw.get('validation_run') == directory.name,
              'failed or stale consumer report')
    d.require(d.exact(raw.get('native_cases'), NATIVE_CASES) and d.exact(raw.get('native_failures'), 0),
              'incomplete consumer test evidence')
    for key in ('gui_initialized', 'gpu_execution_verified', 'full_drop_in_compatibility',
                'reference_pixel_equivalence_claimed'):
        d.require(raw.get(key) is False, f'unsupported consumer claim: {key}')
    d.require(raw.get('snapshots_encoded_after_dc_close') is True, 'consumer snapshots not encoded after close')
    d.require(raw.get('os') in ('unix', 'windows', 'macosx') and
              raw.get('architecture') in ('x86_64', 'aarch64') and
              isinstance(raw.get('racket_version'), str) and raw['racket_version'],
              'missing consumer execution identity')
    if identity is not None:
        for k, ik in (('os', 'os'), ('architecture', 'architecture'), ('racket_version', 'version')):
            d.require(raw[k] == identity[ik], f'foreign consumer interpreter: {k}')
    captures = raw.get('captures')
    d.require(isinstance(captures, list) and len(captures) == 8, 'expected eight consumer captures')
    seen, decoded, receipts = set(), {}, []
    for cap in captures:
        d.require(isinstance(cap, dict), 'invalid consumer capture')
        kind, mode = cap.get('kind'), cap.get('mode')
        d.require(kind in KINDS and mode in MODES and (kind, mode) not in seen,
                  'invalid/duplicate consumer capture')
        seen.add((kind, mode))
        name = filename(kind, mode)
        d.require(cap.get('file') == name, 'unsafe or unexpected consumer capture path')
        path = directory / name
        d.require(path.is_file() and not path.is_symlink(), 'missing/symlinked consumer capture')
        pixels = d.png_rgba(path, SIZE)
        if kind == 'pict':
            d.require(cap.get('layout') is False, 'unexpected pict layout')
            check_pict(pixels)
        else:
            check_plot(pixels, cap.get('layout'))
        decoded[kind, mode] = pixels
        receipts.append(dict(file=name, width=SIZE[0], height=SIZE[1], sha256=d.sha256(path)))
    differences = {}
    for kind in KINDS:
        a, b = decoded[kind, 'procedure'], decoded[kind, 'datum']
        d.require(all(abs(x - y) <= CHANNEL_TOLERANCE for x, y in zip(a, b)),
                  'consumer procedure/datum replay mismatch')
        a, b = decoded[kind, 'direct'], decoded[kind, 'reference']
        differences[kind] = dict(max_channel_error=max(abs(x - y) for x, y in zip(a, b)),
                                changed_pixels=sum(a[i:i+4] != b[i:i+4] for i in range(0, len(a), 4)),
                                acceptance_threshold=None)
    return dict(status='passed', native_cases=NATIVE_CASES, captures=receipts,
                semantic_probes_verified=True, replay_forms_verified=True,
                replay_channel_tolerance=CHANNEL_TOLERANCE, plot_probe_radius=PROBE_RADIUS,
                reference_comparison=differences, manual_reference_review_required=True,
                reference_pixel_equivalence_claimed=False)
