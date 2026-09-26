#!/usr/bin/env python3
"""Inspect actual canvas-primitives outputs, not rendered appearance.
Only --pdf requires pypdf; all XML/PNG/report checks use Python's standard library.
"""
from __future__ import annotations
import argparse
import base64
import binascii
import copy
import json
from pathlib import Path
import struct
import unittest
import xml.etree.ElementTree as ET
import zlib

NS = '{http://www.w3.org/2000/svg}'
XLINK = '{http://www.w3.org/1999/xlink}href'
PANELS = {'geometry': 1, 'clips': 0, 'layers': 3}
HEADINGS = ['Small primitives, explicit geometry',
            'Clipping and coordinates can be queried',
            'Group opacity is not per-object opacity']

def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)

def png_size(raw: bytes) -> tuple[int, int]:
    require(raw[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG')
    pos, dimensions, ended, saw_data = 8, None, False, False
    while pos < len(raw):
        require(pos + 12 <= len(raw), 'truncated PNG chunk')
        n = struct.unpack_from('>I', raw, pos)[0]
        require(n <= len(raw) - pos - 12, 'PNG chunk past end')
        kind = raw[pos+4:pos+8]
        data = raw[pos+8:pos+8+n]
        crc = struct.unpack_from('>I', raw, pos+8+n)[0]
        require(binascii.crc32(kind + data) & 0xffffffff == crc, 'bad PNG CRC')
        if pos == 8:
            require(kind == b'IHDR' and n == 13, 'missing PNG header')
        if kind == b'IHDR':
            require(dimensions is None and n == 13, 'duplicate/bad IHDR')
            dimensions = struct.unpack('>II', data[:8])
            require(min(dimensions) > 0, 'zero PNG extent')
        if kind == b'IDAT':
            saw_data = True
        pos += n + 12
        if kind == b'IEND':
            require(n == 0 and pos == len(raw) and saw_data, 'invalid PNG end')
            ended = True
            break
    require(ended and dimensions is not None, 'incomplete PNG')
    return dimensions

def svg_info(raw: bytes, name: str) -> dict:
    require(name in PANELS, 'unknown panel name')
    root = ET.fromstring(raw)
    require(root.tag == NS + 'svg', 'missing SVG root')
    require(root.get('viewBox') is not None, 'missing viewBox')
    view = list(map(float, root.get('viewBox').split()))
    require(view == [0, 0, 720, 500], 'wrong viewport')
    for key, expected in [('width', 720), ('height', 500)]:
        value = root.get(key, '')
        require(value.endswith('pt') and abs(float(value[:-2]) - expected) < 1e-5,
                'SVG physical size missing/incorrect')
    ids = [e.attrib['id'] for e in root.iter() if 'id' in e.attrib]
    require(len(ids) == len(set(ids)), 'duplicate SVG ID')
    images = []
    for e in root.iter():
        require(e.tag != NS + 'text', 'auto-outlined SVG contains native text')
        for key in ('width', 'height'):
            if key in e.attrib and e is not root:
                require(float(e.attrib[key]) >= 0, 'negative SVG extent')
        href = e.get('href', e.get(XLINK, ''))
        if e.tag == NS + 'image':
            require(href.startswith('data:image/png;base64,'), 'external/non-PNG image')
            raw_png = base64.b64decode(href.split(',', 1)[1], validate=True)
            images.append(list(png_size(raw_png)))
        elif href.startswith('#'):
            require(href[1:] in ids, 'unresolved local SVG reference')
    require(images == [[600, 224]] * PANELS[name], 'wrong embedded panel dimensions/count')
    require(any(e.tag == NS + 'path' for e in root.iter()), 'no vector paths')
    if name == 'clips':
        require(any(any(c.tag == NS + 'path' for c in e)
                    for e in root.iter(NS + 'clipPath')), 'rounded clip did not preserve its general path')
    return {'size_points': [720, 500], 'embedded_png_sizes': images, 'resource_count': len(ids)}

def audit_info(report: dict, name: str) -> dict:
    require(report.get('backend') in ('pdf', 'svg'), 'unexpected audit backend')
    require(report.get('mode') == 'export' and report.get('blocking') is False,
            'not a successful nonblocking export report')
    events = report.get('events', [])
    require(isinstance(events, list) and events, 'empty report')
    require(not any(e.get('status') in ('unknown', 'unsupported', 'discarded', 'needs-raster') for e in events),
            'blocking event in successful output')
    backend = report['backend']
    groups = [e for e in events if e.get('feature') == 'raster-group']
    if backend == 'svg':
        require(len(groups) == PANELS[name], 'wrong raster-group report count')
        for event in groups:
            d = event.get('details', {})
            require([d.get('pixel_width'), d.get('pixel_height')] == [600, 224], 'wrong reported pixels')
        if name == 'clips':
            require(report.get('vector_only') is True, 'clip page should remain vector-only')
    kinds = {(e.get('feature'), e.get('status')) for e in events}
    if name in ('geometry', 'pdf'):
        require(('point-sprites', 'vector' if backend == 'pdf' else 'rasterized') in kinds,
                'point-sprite provenance absent')
    if name in ('layers', 'pdf'):
        require(('layer', 'native-expansion' if backend == 'pdf' else 'rasterized') in kinds,
                'layer provenance absent')
    return {'events': len(events), 'raster_groups': len(groups), 'blocking': False}

def pdf_info(path: Path) -> dict:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise RuntimeError('--pdf requires pypdf') from exc
    reader = PdfReader(path)
    require(len(reader.pages) == 3, 'PDF must have three pages')
    for page, heading in zip(reader.pages, HEADINGS):
        require(abs(float(page.mediabox.width) - 720) < .01 and
                abs(float(page.mediabox.height) - 500) < .01, 'wrong PDF page size')
        require(heading in (page.extract_text() or ''), 'missing native PDF heading')
    return {'pages': 3, 'sizes_points': [[720, 500]] * 3, 'heading_extraction': 'passed'}

def inspect(prefix: Path, pdf: bool) -> dict:
    def f(suffix: str) -> Path:
        return Path(str(prefix) + suffix)
    result = {'svg': {}, 'audits': {}}
    for name in PANELS:
        result['svg'][name] = svg_info(f('.' + name + '.svg').read_bytes(), name)
        result['audits'][name] = audit_info(json.loads(f('.' + name + '.audit.json').read_text()), name)
        require(png_size(f('.' + name + '.reference.png').read_bytes()) == (1440, 1000),
                'wrong independent reference size')
    result['audits']['pdf'] = audit_info(json.loads(f('.pdf.audit.json').read_text()), 'pdf')
    trace = json.loads(f('.queries.json').read_text())
    require({t['backend'] for t in trace} == {'svg', 'pdf', 'raster'}, 'incomplete query trace')
    for row in trace:
        require(row.get('far_rejected') is True, 'far rectangle was not rejected')
        require(all(isinstance(row.get(k), list) and len(row[k]) == 4 for k in ('local', 'device')),
                'missing query rectangle')
    result['queries'] = trace
    review = f('.review.html').read_text()
    require(review.count('<img ') == 6 and 'independent raster reference' in review.lower(), 'incomplete review page')
    result['pdf'] = pdf_info(f('.pdf')) if pdf else 'NOT CHECKED (use --pdf)'
    result['visual_review'] = 'NOT PERFORMED by structural inspector'
    return result

# Compact in-memory fixtures exercise the inspector, not Skia.
def chunk(t: bytes, d: bytes) -> bytes:
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', binascii.crc32(t+d) & 0xffffffff)
def png(w=600, h=224) -> bytes:
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress((b'\0' + bytes(4*w))*h)) + chunk(b'IEND', b''))
def svg(name='geometry') -> bytes:
    images = ''.join(f'<image width="300" height="112" href="data:image/png;base64,{base64.b64encode(png()).decode()}"/>'
                     for _ in range(PANELS[name]))
    clip = '<clipPath id="c"><path d="M0 0L1 1Z"/></clipPath>' if name == 'clips' else ''
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="720pt" height="500pt" viewBox="0 0 720 500">{clip}<path d="M0 0L1 1"/>{images}</svg>'.encode()
def report(name='geometry') -> dict:
    events = [{'feature': 'geometry', 'status': 'vector'}]
    for _ in range(PANELS[name]):
        events.append({'feature': 'raster-group', 'status': 'rasterized', 'details': {'pixel_width':600,'pixel_height':224}})
    if name == 'geometry': events.append({'feature':'point-sprites','status':'rasterized'})
    if name == 'layers': events.append({'feature':'layer','status':'rasterized'})
    return {'backend':'svg','mode':'export','blocking':False,'vector_only':name=='clips','events':events}
class Checks(unittest.TestCase):
    def test_valid(self):
        for n in PANELS: svg_info(svg(n), n); audit_info(report(n), n)
    def test_crc(self):
        raw=bytearray(png());raw[-1] ^= 1
        with self.assertRaises(ValueError): png_size(raw)
    def test_truncated(self):
        with self.assertRaises(ValueError): png_size(png()[:-5])
    def test_size(self):
        with self.assertRaises(ValueError): svg_info(svg().replace(b'720pt', b'719pt'), 'geometry')
    def test_viewbox(self):
        with self.assertRaises(ValueError): svg_info(svg().replace(b'0 0 720 500', b'0 0 700 500'), 'geometry')
    def test_native_text(self):
        with self.assertRaises(ValueError): svg_info(svg().replace(b'</svg>', b'<text>x</text></svg>'), 'geometry')
    def test_external_image(self):
        raw=b'<svg xmlns="http://www.w3.org/2000/svg" width="720pt" height="500pt" viewBox="0 0 720 500"><path/><image href="external.png"/></svg>'
        with self.assertRaises(ValueError): svg_info(raw, 'geometry')
    def test_duplicate_id(self):
        with self.assertRaises(ValueError): svg_info(svg().replace(b'<path ', b'<path id="same"/><path id="same" '), 'geometry')
    def test_dangling_reference(self):
        with self.assertRaises(ValueError): svg_info(svg().replace(b'</svg>',b'<use href="#missing"/></svg>'),'geometry')
    def test_missing_panel(self):
        with self.assertRaises(ValueError): svg_info(svg('clips'),'layers')
    def test_blocking_report(self):
        r=report();r['blocking']=True
        with self.assertRaises(ValueError): audit_info(r,'geometry')
    def test_report_pixels(self):
        r=report();r['events'][1]['details']['pixel_width']=500
        with self.assertRaises(ValueError): audit_info(r,'geometry')
    def test_missing_layer(self):
        r=report('layers');r['events'].pop()
        with self.assertRaises(ValueError): audit_info(r,'layers')
    def test_negative_extent(self):
        with self.assertRaises(ValueError): svg_info(svg().replace(b'width="300"',b'width="-3"'),'geometry')

def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test',action='store_true')
    parser.add_argument('--probe-prefix',type=Path)
    parser.add_argument('--pdf',action='store_true')
    args=parser.parse_args()
    if args.self_test:
        result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks))
        if not result.wasSuccessful(): raise SystemExit(1)
    elif args.probe_prefix:
        print(json.dumps(inspect(args.probe_prefix,args.pdf),indent=2))
    else:
        parser.error('choose --self-test or --probe-prefix')
if __name__=='__main__': main()
