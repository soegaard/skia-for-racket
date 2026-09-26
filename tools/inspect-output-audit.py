#!/usr/bin/env python3
"""Inspect the 0.29 probe reports and real SVG/PDF structure; not a renderer."""
from __future__ import annotations
import argparse
import base64
import copy
import json
import math
from pathlib import Path
import re
import struct
import sys
import unittest
import xml.etree.ElementTree as ET
import zlib

LIMIT = 64 * 1024 * 1024
STATUSES = {'vector', 'embedded-raster', 'native-expansion', 'needs-raster',
            'viewer-dependent', 'rasterized', 'discarded', 'unknown', 'unsupported'}
BLOCKING = {'needs-raster', 'discarded', 'unknown', 'unsupported'}
FEATURES = set('geometry native-text image linear-gradient radial-gradient sweep-gradient '
               'conical-gradient solid-shader image-shader shader-composition shader-local-matrix '
               'runtime-shader color-filter runtime-color-filter image-filter mask-filter '
               'dash-effect path-effect blend-mode runtime-blender inverse-path clip-intersect '
               'clip-difference transform annotation picture raster-group unknown-resource '
               'unknown-operation'.split())
EXPECTED = {'vector': [(600, 340)], 'filters': [(624, 364), (624, 364)],
            'recorded': [(600, 340)]}

def need(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)

def integer(x: object) -> bool:
    return type(x) is int

def finite(x: object) -> bool:
    return type(x) in (int, float) and math.isfinite(x)

def bounded_read(path: Path) -> bytes:
    with path.open('rb') as f:
        data = f.read(LIMIT + 1)
    need(len(data) <= LIMIT, f'{path}: file exceeds inspection byte limit')
    return data

def check_report(report: object) -> dict:
    need(isinstance(report, dict), 'report must be an object')
    need(report.get('backend') in ('pdf', 'svg', 'raster'), 'invalid report backend')
    need(report.get('mode') in ('preflight', 'export'), 'invalid report mode')
    pages = report.get('pages')
    need(integer(pages) and pages > 0, 'invalid page count')
    need(isinstance(report.get('scope'), str), 'missing scope disclaimer')
    events = report.get('events')
    need(isinstance(events, list) and len(events) <= 100000, 'invalid/bounded event list')
    groups = []
    for event in events:
        need(isinstance(event, dict), 'event must be an object')
        need(integer(event.get('page')) and 1 <= event['page'] <= pages, 'invalid event page')
        need(isinstance(event.get('operation'), str) and event['operation'], 'missing operation')
        need(isinstance(event.get('scope'), list) and
             all(isinstance(s, str) for s in event['scope']), 'invalid scope labels')
        need(event.get('feature') in FEATURES, 'unknown event feature')
        need(event.get('status') in STATUSES, 'unknown event status')
        need(isinstance(event.get('reason'), str) and event['reason'], 'missing reason')
        details = event.get('details')
        need(isinstance(details, dict), 'details must be a plain JSON object')
        # All current details are finite geometric/pixel numbers, never handles.
        need(all(isinstance(k, str) and finite(v) for k, v in details.items()), 'non-numeric details')
        if event['feature'] == 'raster-group':
            need(event['status'] == 'rasterized', 'raster group has incorrect status')
            need(all(integer(details.get(k)) and 1 <= details[k] <= 32768
                     for k in ('pixel_width', 'pixel_height')), 'missing/invalid raster pixel size')
            need(all(finite(details.get(k)) for k in ('x', 'y', 'width', 'height')),
                 'missing raster rectangle')
            need(details['width'] > 0 and details['height'] > 0, 'invalid raster extent')
            groups.append((details['pixel_width'], details['pixel_height']))
    need(type(report.get('blocking')) is bool and
         report['blocking'] == any(e['status'] in BLOCKING for e in events), 'blocking flag mismatch')
    need(type(report.get('vector_only')) is bool and
         report['vector_only'] == all(e['status'] == 'vector' for e in events), 'vector-only flag mismatch')
    return {'backend': report['backend'], 'mode': report['mode'], 'pages': pages,
            'events': len(events), 'blocking': report['blocking'], 'vector_only': report['vector_only'],
            'raster_groups': groups,
            'statuses': sorted(set(e['status'] for e in events))}

def png_size(data: bytes) -> tuple[int, int]:
    need(data.startswith(b'\x89PNG\r\n\x1a\n'), 'embedded image is not PNG')
    at = 8
    size = None
    seen_idat = False
    while at < len(data):
        need(at + 12 <= len(data), 'truncated PNG chunk')
        n = struct.unpack('>I', data[at:at+4])[0]
        need(n <= LIMIT and at + 12 + n <= len(data), 'PNG chunk exceeds bounds')
        kind, payload = data[at+4:at+8], data[at+8:at+8+n]
        crc = struct.unpack('>I', data[at+8+n:at+12+n])[0]
        need(zlib.crc32(kind + payload) & 0xffffffff == crc, 'PNG CRC mismatch')
        if size is None:
            need(kind == b'IHDR' and n == 13, 'PNG lacks first IHDR')
            size = struct.unpack('>II', payload[:8])
            need(all(0 < d <= 32768 for d in size), 'invalid PNG size')
        elif kind == b'IHDR':
            raise ValueError('duplicate IHDR')
        if kind == b'IDAT':
            seen_idat = True
        at += 12 + n
        if kind == b'IEND':
            need(n == 0 and at == len(data) and seen_idat, 'invalid PNG ending')
            return size
    raise ValueError('PNG has no IEND')

def check_svg(data: bytes, expected: list[tuple[int, int]]) -> dict:
    need(len(data) <= LIMIT, 'SVG exceeds byte limit')
    need(b'<!DOCTYPE' not in data.upper() and b'<!ENTITY' not in data.upper(), 'SVG must not declare entities')
    root = ET.fromstring(data)
    tag = lambda e: e.tag.rsplit('}', 1)[-1]
    need(tag(root) == 'svg', 'not an SVG root')
    for attribute, desired in (('width', 720), ('height', 500)):
        value = root.get(attribute, '')
        need(value.endswith('pt') and float(value[:-2]) == desired, 'wrong physical SVG size')
    need([float(x) for x in root.get('viewBox', '').split()] == [0, 0, 720, 500], 'wrong viewBox')
    nodes = list(root.iter())
    need(not any(tag(n) == 'text' for n in nodes), 'probe labels must be outlined')
    ids = [n.get('id') for n in nodes if n.get('id') is not None]
    need(len(ids) == len(set(ids)), 'duplicate SVG ID')
    need(any(tag(n) == 'path' for n in nodes), 'probe lacks vector geometry')
    sizes = []
    for node in nodes:
        for value in node.attrib.values():
            for ref in re.findall(r'url\(#([^)]*)\)', value):
                need(ref in ids, 'unresolved SVG resource')
        href = node.get('href') or node.get('{http://www.w3.org/1999/xlink}href', '')
        if tag(node) == 'use' and href.startswith('#'):
            need(href[1:] in ids, 'unresolved SVG use')
        if tag(node) == 'image':
            need(href.startswith('data:image/png;base64,'), 'effect panel must be embedded PNG')
            encoded = href.split(',', 1)[1]
            need(len(encoded) < 2 * LIMIT, 'encoded panel too large')
            sizes.append(png_size(base64.b64decode(encoded, validate=True)))
    need(sorted(sizes) == sorted(expected), f'wrong embedded panels: {sizes}, expected {expected}')
    return {'size_points': [720, 500], 'embedded_png_sizes': sizes,
            'vector_paths': sum(tag(n) == 'path' for n in nodes)}

def check_pdf(path: Path) -> dict:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise RuntimeError('--pdf requires pypdf; the SVG/report checks use only the standard library') from exc
    reader = PdfReader(path)
    need(len(reader.pages) == 3, 'expected three PDF pages')
    headings = ['Know what remains vector', 'Backend expansion is not vector preservation',
                'Recording does not erase resource provenance']
    result = []
    for page, title in zip(reader.pages, headings):
        dims = [float(page.mediabox.width), float(page.mediabox.height)]
        need(all(abs(a-b) < .01 for a, b in zip(dims, (720, 500))), 'wrong PDF media box')
        text = page.extract_text() or ''
        need(title in text, 'PDF heading is not extractable')
        images = []
        visited = set()
        def walk(resources: object) -> None:
            if not resources:
                return
            resources = resources.get_object()
            for ref in resources.get('/XObject', {}).get_object().values() if '/XObject' in resources else []:
                obj = ref.get_object()
                key = (getattr(ref, 'idnum', id(obj)), getattr(ref, 'generation', 0))
                if key in visited:
                    continue
                visited.add(key)
                if obj.get('/Subtype') == '/Image':
                    images.append([int(obj['/Width']), int(obj['/Height'])])
                elif obj.get('/Subtype') == '/Form':
                    walk(obj.get('/Resources'))
        walk(page.get('/Resources'))
        need(bool(images), 'PDF effect page has no images')
        result.append({'size_points': dims, 'images': images})
    return {'pages': result, 'note': 'Structural inspection only; no visual comparison or vector-fidelity certification.'}

def inspect(prefix: Path, with_pdf: bool) -> dict:
    def file(suffix: str) -> Path:
        return Path(str(prefix) + suffix)
    reports = {}
    raw = {}
    for name in ('pdf', *EXPECTED, 'unsafe'):
        report = json.loads(bounded_read(file('.' + name + '.audit.json')))
        raw[name] = report
        reports[name] = check_report(report)
        need(report['backend'] == ('pdf' if name == 'pdf' else 'svg'), 'wrong target backend')
        need(report['pages'] == (3 if name == 'pdf' else 1), 'wrong report page count')
        need(report['mode'] == ('preflight' if name == 'unsafe' else 'export'), 'wrong probe report mode')
        need(report['blocking'] == (name == 'unsafe'), 'safe/unsafe probe status mismatch')
    unsafe = raw['unsafe']['events']
    for feature in ('runtime-shader', 'image-filter'):
        need(any(e['feature'] == feature and e['status'] == 'needs-raster' for e in unsafe),
             'unsafe preflight did not expose ' + feature)
    need(not file('.unsafe.svg').exists(), 'unsafe preflight must not publish an SVG')
    svg = {}
    for name, sizes in EXPECTED.items():
        svg[name] = check_svg(bounded_read(file('.' + name + '.svg')), sizes)
        need(sorted(reports[name]['raster_groups']) == sorted(sizes), 'SVG report/raster group mismatch')
        need(png_size(bounded_read(file('.' + name + '.reference.png'))) == (1440, 1000), 'wrong reference size')
        need(any(e['feature'] == 'runtime-shader' and e['status'] == 'rasterized'
                 for e in raw[name]['events']) if name != 'filters' else
             any(e['feature'] == 'image-filter' and e['status'] == 'rasterized'
                 for e in raw[name]['events']), 'missing resolved effect observations')
    need(any(e['feature'] == 'image-filter' and e['status'] == 'native-expansion'
             for e in raw['pdf']['events']), 'PDF filter expansion observation missing')
    need(any(e['feature'] == 'annotation' and e['status'] == 'vector'
             for e in raw['recorded']['events']), 'outer document annotation observation missing')
    html = bounded_read(file('.review.html')).decode('utf-8')
    need('not a PDF/SVG rendering' in html, 'review must distinguish independent references')
    for value in re.findall(r'(?:href|src)="([^"]+)"', html):
        if not re.match(r'[A-Za-z]+:', value):
            need((prefix.parent / value).exists(), 'missing review target ' + value)
    return {'reports': reports, 'svg': svg,
            'pdf': check_pdf(file('.pdf')) if with_pdf else 'NOT CHECKED (use --pdf)',
            'visual_review': 'NOT PERFORMED by this structural inspector',
            'racket_execution': 'NOT PERFORMED by this inspector'}

# Synthetic fixtures exercise only this inspector, not Racket or native Skia.
def chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind+payload) & 0xffffffff)

def fake_png(w: int = 2, h: int = 2) -> bytes:
    header = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress((b'\0'+b'\0'*4*w)*h)) + chunk(b'IEND', b'')

def fake_report(feature: str = 'geometry', status: str = 'vector') -> dict:
    return {'backend': 'svg', 'mode': 'export', 'pages': 1, 'scope': 'Synthetic fixture only',
            'blocking': status in BLOCKING, 'vector_only': status == 'vector',
            'events': [{'page': 1, 'operation': 'draw-rect', 'scope': [], 'feature': feature,
                        'status': status, 'reason': 'synthetic', 'details': {}}]}

class Checks(unittest.TestCase):
    def test_valid_report(self):
        self.assertFalse(check_report(fake_report())['blocking'])
    def test_status(self):
        r = fake_report(); r['events'][0]['status'] = 'guaranteed'
        with self.assertRaises(ValueError): check_report(r)
    def test_feature(self):
        r = fake_report(); r['events'][0]['feature'] = 'future'
        with self.assertRaises(ValueError): check_report(r)
    def test_boolean(self):
        r = fake_report(); r['blocking'] = True
        with self.assertRaises(ValueError): check_report(r)
    def test_page(self):
        r = fake_report(); r['events'][0]['page'] = 2
        with self.assertRaises(ValueError): check_report(r)
    def test_vector_only(self):
        r = fake_report('image', 'embedded-raster'); r['vector_only'] = True
        with self.assertRaises(ValueError): check_report(r)
    def test_missing_raster_size(self):
        with self.assertRaises(ValueError): check_report(fake_report('raster-group', 'rasterized'))
    def test_nonfinite(self):
        r = fake_report(); r['events'][0]['details'] = {'x': float('nan')}
        with self.assertRaises(ValueError): check_report(r)
    def test_details_not_handle(self):
        r = fake_report(); r['events'][0]['details'] = {'handle': '#<cpointer>'}
        with self.assertRaises(ValueError): check_report(r)
    def test_unsafe(self):
        r = fake_report('runtime-shader', 'needs-raster')
        self.assertTrue(check_report(r)['blocking'])
    def test_png(self):
        self.assertEqual(png_size(fake_png(12, 9)), (12, 9))
    def test_crc(self):
        raw = bytearray(fake_png()); raw[29] ^= 1
        with self.assertRaises(ValueError): png_size(bytes(raw))
    def test_truncated_png(self):
        with self.assertRaises(ValueError): png_size(fake_png()[:-1])
    def test_svg_panel_size(self):
        image = base64.b64encode(fake_png()).decode('ascii')
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="720pt" height="500pt" viewBox="0 0 720 500"><path d="M0 0L1 1"/><image href="data:image/png;base64,{image}"/></svg>'.encode()
        self.assertEqual(check_svg(svg, [(2, 2)])['embedded_png_sizes'], [(2, 2)])
        with self.assertRaises(ValueError): check_svg(svg, [(3, 2)])

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--probe-prefix', type=Path)
    parser.add_argument('--pdf', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        ok = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks)).wasSuccessful()
        if not ok: raise SystemExit(1)
    if args.probe_prefix:
        print(json.dumps(inspect(args.probe_prefix, args.pdf), indent=2))
    if not args.self_test and args.probe_prefix is None:
        parser.error('provide --self-test or --probe-prefix')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, ET.ParseError, RuntimeError) as exc:
        print(f'Inspection failed: {exc}', file=sys.stderr)
        raise SystemExit(1)
