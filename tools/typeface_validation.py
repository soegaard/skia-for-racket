"""0.68a: inspect actual controlled typeface output, not installed-font guesses."""
from __future__ import annotations
import re
from pathlib import Path
import xml.etree.ElementTree as ET
from effects_validation import need, read_json, evidence_file

SPECS = tuple((face, fmt, mode) for face in ('regular', 'bold')
              for fmt, mode in (('pdf', 'native'), ('pdf', 'outline'), ('svg', 'outline')))
BLUE = (24, 64, 192, 255)
WHITE = (255, 255, 255, 255)


def receipt(row, spec):
    face, fmt, mode = spec
    need(isinstance(row, dict) and (row.get('face'), row.get('format'), row.get('text_mode')) == spec,
         'foreign typeface document')
    need(type(row.get('callback_count')) is int and row['callback_count'] == 1, 'authoring count')
    need(row.get('audit_policy') == 'vector-only', 'vector-only policy not selected')
    a = row.get('audit', {})
    need(isinstance(a, dict) and a.get('mode') == 'export' and a.get('backend') == fmt
         and a.get('blocking') is False and a.get('vector_only') is True, 'incomplete vector export')
    events = a.get('events', [])
    need(isinstance(events, list) and events and all(isinstance(e, dict) and e.get('status') == 'vector'
                                                   for e in events), 'nonvector audit event')
    features = {e.get('feature') for e in events}
    need('geometry' in features and 'annotation' in features, 'marker/link audit not observed')
    if mode == 'native':
        need('native-text' in features, 'native text event absent')
    else:
        need('native-text' not in features, 'outlined output still reports native text')


def metadata(rows):
    need(isinstance(rows, list) and len(rows) == 2, 'missing typeface metadata')
    seen = set()
    for row in rows:
        need(isinstance(row, dict), 'invalid metadata row')
        face = row.get('face')
        need(face in ('regular', 'bold') and face not in seen, 'duplicate/foreign metadata')
        seen.add(face)
        need(row.get('postscript_name') == 'SkiaRacketFixture-' + face.title(), 'wrong collection/face identity')
        for key, expected in (('glyph_count', 4), ('units_per_em', 1000)):
            need(type(row.get(key)) is int and row[key] == expected, 'wrong fixture ' + key)
        need(row.get('fixed_pitch') is True, 'fixed-pitch flag missing')
        need(type(row.get('font_data_bytes')) is int and row['font_data_bytes'] > 0, 'font data not copied')
        need(type(row.get('font_data_index')) is int and row['font_data_index'] >= 0, 'invalid returned font index')
        tags = row.get('table_tags')
        need(isinstance(tags, list) and all(type(v) is int and 0 <= v <= 0xffffffff for v in tags), 'invalid tag list')
        need(len(tags) == len(set(tags)) and {0x6e616d65, 0x6d617870, 0x636d6170} <= set(tags), 'fixture tables absent')
        need(type(row.get('kerning_available')) is bool, 'kerning availability must be explicit')
        need(row.get('kerning') == [-80] if row['kerning_available'] else row.get('kerning') is False,
             'undefined/incorrect pair kerning')


def pixel_checks(data: bytes, face: str, tolerance: int = 2):
    need(face in ('regular', 'bold') and len(data) == 160 * 100 * 4, 'pixel shape/identity mismatch')
    need(all(data[i] == 255 for i in range(3, len(data), 4)), 'nonopaque fixture background')
    # All text probes are several pixels from a contour; no corner-coverage oracle.
    probes = ((4, 4, (0, 255, 0, 255)), (20, 50, BLUE),
              (68 if face == 'bold' else 54, 54, BLUE),
              (12, 50, WHITE), (100, 50, WHITE), (20, 80, WHITE))
    for x, y, expected in probes:
        at = 4 * (160*y + x)
        need(all(abs(a-b) <= tolerance for a, b in zip(data[at:at+4], expected)),
             f'{face}: incorrect semantic pixel at {x},{y}')


def inspect_svg(path: Path, face: str):
    raw = path.read_bytes()
    need(b'<!DOCTYPE' not in raw.upper() and b'<!ENTITY' not in raw.upper(), 'DTD/entity outside fixture scope')
    root = ET.fromstring(raw)
    local = lambda e: e.tag.rsplit('}', 1)[-1]
    need(local(root) == 'svg', 'not SVG')
    def points(value):
        m = re.fullmatch(r'(\d+(?:\.\d+)?)(pt|px)?', value or '')
        need(m is not None, 'nonabsolute SVG size')
        return float(m[1]) * (1 if m[2] == 'pt' else 0.75)
    need(abs(points(root.get('width')) - 160) < 1e-6 and abs(points(root.get('height')) - 100) < 1e-6,
         'SVG physical size changed')
    need(not any(local(e) in ('image', 'foreignObject', 'text') for e in root.iter()), 'outlined SVG uses raster/text fallback')
    shapes = [e for e in root.iter() if local(e) in ('path', 'rect', 'polygon')]
    need(len(shapes) >= 3, 'SVG geometry missing')
    link = 'https://example.invalid/typeface/' + face
    need(any(local(e) == 'a' and (e.get('href') or e.get('{http://www.w3.org/1999/xlink}href')) == link
             for e in root.iter()), 'SVG link missing')
    return dict(embedded_images=0, native_text=False, shapes=len(shapes), link_verified=True)


def inspect_pdf(path: Path, face: str, mode: str):
    from pypdf import PdfReader
    from pypdf.generic import ContentStream
    reader = PdfReader(path, strict=True)
    need(not reader.is_encrypted and len(reader.pages) == 1, 'unexpected PDF encryption/page count')
    page = reader.pages[0]
    need([float(v) for v in page.mediabox] == [0, 0, 160, 100], 'wrong PDF size')
    text_ops = 0
    paint_ops = 0
    fonts = []
    def resources(res, seen=None, depth=0):
        seen = set() if seen is None else seen
        need(depth < 16, 'resource depth exceeded')
        for ref in res.get('/Font', {}).get_object().values() if '/Font' in res else ():
            fonts.append(ref.get_object())
        xo = res.get('/XObject', {})
        if hasattr(xo, 'get_object'): xo = xo.get_object()
        for ref in xo.values():
            obj = ref.get_object()
            need(obj.get('/Subtype') != '/Image', 'PDF raster resource')
            if obj.get('/Subtype') == '/Form' and id(obj) not in seen:
                seen.add(id(obj))
                resources(obj.get('/Resources', res).get_object(), seen, depth+1)
    def walk(stream, res, active=None, depth=0):
        nonlocal text_ops, paint_ops
        active = set() if active is None else active
        need(depth < 16, 'form depth exceeded')
        for values, op in ContentStream(stream, reader).operations:
            need(op != b'INLINE IMAGE', 'inline PDF raster fallback')
            if op in (b'Tj', b'TJ', b"'", b'"'): text_ops += 1
            if op in (b'f', b'f*', b'F', b'S', b's', b'B', b'B*'): paint_ops += 1
            if op == b'Do':
                obj = res['/XObject'].get_object()[values[0]].get_object()
                need(obj.get('/Subtype') == '/Form' and id(obj) not in active, 'nonvector/cyclic form')
                walk(obj, obj.get('/Resources', res).get_object(), active | {id(obj)}, depth+1)
    res = page['/Resources'].get_object()
    resources(res)
    walk(page.get_contents(), res)
    need(paint_ops >= 2, 'background/vector marker missing')
    extracted = ''.join(page.extract_text().split())
    if mode == 'native':
        need(text_ops > 0 and extracted == 'AV', 'native PDF text not preserved/extractable')
        def embedded(font):
            descriptor = font.get('/FontDescriptor')
            if descriptor:
                d = descriptor.get_object()
                if any(key in d and len(d[key].get_object().get_data()) > 0
                       for key in ('/FontFile', '/FontFile2', '/FontFile3')): return True
            return any(embedded(ref.get_object()) for ref in font.get('/DescendantFonts', []))
        need(fonts and any(embedded(font) for font in fonts), 'controlled native font not embedded')
    else:
        need(text_ops == 0 and not extracted and paint_ops >= 3, 'PDF text not outlined')
    link = 'https://example.invalid/typeface/' + face
    need(any(a.get_object().get('/A') and a.get_object()['/A'].get_object().get('/URI') == link
             for a in page.get('/Annots', [])), 'PDF link missing')
    return dict(embedded_images=0, native_text=(mode == 'native'), text_operations=text_ops,
                extracted=extracted, painted_paths=paint_ops, link_verified=True)


def inspect_render(path: Path, face: str, reference: bytes):
    from PIL import Image
    with Image.open(path) as image:
        need(image.size == (160, 100), 'wrong viewer size')
        pixels = image.convert('RGBA').tobytes()
    pixel_checks(pixels, face, tolerance=24)
    errors = [abs(a-b) for i, (a, b) in enumerate(zip(pixels, reference)) if i % 4 != 3]
    mean = sum(errors)/len(errors)
    fraction = sum(v > 32 for v in errors)/len(errors)
    need(mean <= 5 and fraction <= 0.06, f'viewer divergence mean={mean:.3f}, fraction={fraction:.3f}')
    return dict(mean_rgb_error=mean, large_error_fraction=fraction)


def inspect_documents(directory: Path, token: str, *, render=None):
    value = read_json(directory / 'documents.json')
    need(type(value.get('schema')) is int and value['schema'] == 1 and value.get('stage') == '0.68a'
         and value.get('run_token') == token and value.get('status') == 'passed'
         and value.get('rendering_executed') is True, 'stale/incomplete typeface receipt')
    need(value.get('gui_executed') is False and value.get('gpu_executed') is False, 'unsupported execution claim')
    metadata(value.get('typefaces'))
    rows = value.get('documents')
    need(isinstance(rows, list) and len(rows) == len(SPECS), 'incomplete document matrix')
    by_key = {(r.get('face'), r.get('format'), r.get('text_mode')): r for r in rows if isinstance(r, dict)}
    need(set(by_key) == set(SPECS), 'duplicate/foreign documents')
    reports = []
    for spec in SPECS:
        face, fmt, mode = spec
        row = by_key[spec]
        receipt(row, spec)
        stem = '-'.join(spec)
        need(row.get('file') == stem + '.' + fmt and row.get('rgba') == stem + '.rgba', 'foreign filenames')
        path = evidence_file(directory, row['file'])
        reference = evidence_file(directory, row['rgba']).read_bytes()
        pixel_checks(reference, face)
        report = inspect_pdf(path, face, mode) if fmt == 'pdf' else inspect_svg(path, face)
        report.update(face=face, format=fmt, text_mode=mode)
        if render: report['viewer'] = inspect_render(render(path, fmt), face, reference)
        reports.append(report)
    return dict(schema=1, stage='0.68a', status='passed', documents=reports,
                typefaces=value['typefaces'], independent_renderers_executed=(render is not None))
