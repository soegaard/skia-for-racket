"""0.68b evidence checks. Imports are stdlib-only; document libraries load on use.

Synthetic receipts/pixels exercise these checks, never establish native coverage.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

WIDTH, HEIGHT = 160, 100
SCENES = ('snapshot', 'mutated', 'batch')
BLACK, WHITE = (0, 0, 0, 255), (255, 255, 255, 255)
PROBES = {
    'snapshot': ((25,40,BLACK),(50,36,BLACK),(41,40,WHITE),(70,40,WHITE),(5,5,WHITE)),
    'mutated': ((25,40,BLACK),(41,40,BLACK),(61,36,BLACK),(85,40,WHITE),(5,5,WHITE)),
    'batch': ((25,40,BLACK),(36,40,BLACK),(60,36,BLACK),(44,40,WHITE),(85,40,WHITE),(5,5,WHITE)),
}
MAX_FILE = 16 * 1024 * 1024


def require(ok, message):
    if not ok:
        raise ValueError(message)


def integer(value, expected, name):
    require(type(value) is int and value == expected, 'invalid ' + name)


def checked_file(directory: Path, name: str) -> Path:
    require(type(name) is str and re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]*', name) is not None,
            'unsafe evidence filename')
    path = directory / name
    require(not path.is_symlink() and path.is_file(), 'missing/symlink evidence: ' + name)
    require(path.stat().st_size <= MAX_FILE, 'oversized evidence: ' + name)
    return path


def read_json(path: Path):
    def pairs(items):
        out = {}
        for key, value in items:
            require(key not in out, 'duplicate JSON key')
            out[key] = value
        return out
    require(not path.is_symlink() and path.is_file() and path.stat().st_size <= MAX_FILE,
            'missing/symlink/oversized JSON')
    result = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=pairs,
                        parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite JSON')))
    require(type(result) is dict, 'JSON object required')
    return result


def pixel_checks(data: bytes, scene: str):
    require(scene in SCENES, 'unknown scene')
    require(len(data) == WIDTH * HEIGHT * 4, 'wrong pixel dimensions')
    for x, y, color in PROBES[scene]:
        offset = 4 * (y * WIDTH + x)
        require(tuple(data[offset:offset+4]) == color, f'{scene}: wrong pixel at {x},{y}')
    require(all(data[i] == 255 for i in range(3, len(data), 4)), 'nonopaque document pixels')


def document_receipts(data: dict, token: str):
    integer(data.get('schema'), 1, 'schema')
    require(data.get('stage') == '0.68b' and data.get('status') == 'passed', 'wrong/failed stage')
    require(type(token) is str and bool(token) and data.get('run_token') == token, 'stale run token')
    integer(data.get('width'), WIDTH, 'width'); integer(data.get('height'), HEIGHT, 'height')
    require(data.get('rendering_executed') is True and data.get('gui_executed') is False
            and data.get('gpu_executed') is False, 'incorrect execution scope')
    rows = data.get('documents')
    require(type(rows) is list and len(rows) == 6, 'six document receipts required')
    seen = set()
    for row in rows:
        require(type(row) is dict, 'document object required')
        scene, fmt = row.get('scene'), row.get('format')
        require(scene in SCENES and fmt in ('pdf', 'svg'), 'unknown scene/format')
        require((scene, fmt) not in seen, 'duplicate document'); seen.add((scene, fmt))
        integer(row.get('callback_count'), 1, 'callback count')
        require(row.get('file') == f'{scene}-{fmt}.{fmt}' and row.get('rgba') == f'{scene}-{fmt}.rgba',
                'foreign document filenames')
        require(row.get('text_mode') == ('native' if fmt == 'pdf' else 'outline'), 'wrong text mode')
        require(row.get('audit_policy') == 'vector-only', 'weakened export policy')
        audit = row.get('audit')
        require(type(audit) is dict and audit.get('mode') == 'export' and audit.get('backend') == fmt,
                'preflight/foreign audit')
        require(audit.get('blocking') is False and audit.get('vector_only') is True, 'nonvector audit')
        events = audit.get('events')
        require(type(events) is list and bool(events), 'empty audit events')
        require(all(type(e) is dict and e.get('status') == 'vector' for e in events),
                'nonvector event in document receipt')
        features = {e.get('feature') for e in events}
        native_text = fmt == 'pdf' and scene != 'batch'
        require(('native-text' in features) == native_text, 'incorrect text audit provenance')
        require(native_text or 'geometry' in features, 'missing outline geometry provenance')
    require(seen == {(s, f) for s in SCENES for f in ('pdf', 'svg')}, 'missing document')
    return rows


def inspect_svg(path: Path):
    raw = path.read_bytes()
    require(b'<!DOCTYPE' not in raw.upper() and b'<!ENTITY' not in raw.upper(), 'SVG entities forbidden')
    root = ET.fromstring(raw)
    require(root.tag.rsplit('}', 1)[-1] == 'svg', 'not SVG')
    shapes = 0
    for node in root.iter():
        name = node.tag.rsplit('}', 1)[-1]
        require(name not in ('image', 'text', 'foreignObject', 'script'), 'SVG is not outlined vector output')
        if name in ('path', 'polygon', 'rect'): shapes += 1
        for key, value in node.attrib.items():
            if key.rsplit('}', 1)[-1] == 'href':
                require(value.startswith('#'), 'external SVG reference')
    def points(value):
        match = re.fullmatch(r'(\d+(?:\.\d+)?)(pt|px)?', value or '')
        require(match is not None, 'nonabsolute SVG size')
        return float(match[1]) * (1 if match[2] == 'pt' else 0.75)
    require(abs(points(root.get('width')) - WIDTH) < 0.01
            and abs(points(root.get('height')) - HEIGHT) < 0.01, 'wrong SVG physical size')
    require(shapes >= 2, 'missing SVG glyph geometry')
    return dict(vector_shapes=shapes, text_nodes=0, raster_images=0)


def inspect_pdf(path: Path, scene: str):
    from pypdf import PdfReader
    from pypdf.generic import ContentStream
    reader = PdfReader(path, strict=True)
    require(not reader.is_encrypted and len(reader.pages) == 1, 'expected one unencrypted PDF page')
    page = reader.pages[0]
    require(abs(float(page.mediabox.width)-WIDTH) < 0.01
            and abs(float(page.mediabox.height)-HEIGHT) < 0.01, 'wrong PDF page dimensions')
    operators, fonts = [], []
    visited = set()
    def walk(contents, resources, depth=0):
        require(depth < 24, 'excessive PDF form depth')
        resources = resources.get_object() if hasattr(resources, 'get_object') else resources
        font_resources = resources.get('/Font', {})
        if hasattr(font_resources, 'get_object'): font_resources = font_resources.get_object()
        for font in font_resources.values(): fonts.append(font.get_object())
        objects = resources.get('/XObject', {})
        if hasattr(objects, 'get_object'): objects = objects.get_object()
        require(all(o.get_object().get('/Subtype') != '/Image' for o in objects.values()),
                'raster resource in vector PDF')
        for operands, op in ContentStream(contents, reader).operations:
            require(op not in (b'INLINE IMAGE', b'BI', b'ID'), 'inline image in vector PDF')
            operators.append(op)
            if op == b'Do':
                require(bool(operands), 'missing XObject operand')
                obj = resources['/XObject'][operands[0]].get_object()
                require(obj.get('/Subtype') != '/Image', 'raster XObject in vector PDF')
                if obj.get('/Subtype') == '/Form':
                    identity = id(obj)
                    require(identity not in visited, 'recursive PDF form')
                    visited.add(identity)
                    walk(obj, obj.get('/Resources', resources), depth+1)
                    visited.remove(identity)
    contents = page.get_contents()
    require(contents is not None, 'empty PDF page')
    walk(contents, page.get('/Resources', {}))
    require(any(op in (b'f', b'f*', b'B', b'B*', b'Tj', b'TJ') for op in operators), 'no PDF ink')
    text_ops = sum(op in (b'Tj', b'TJ', b"'", b'"') for op in operators)
    if scene in ('snapshot', 'mutated'):
        require(text_ops > 0 and bool(fonts), 'native PDF text unexpectedly outlined')
        embedded = False
        for font in fonts:
            for f in [font, *[v.get_object() for v in font.get('/DescendantFonts', [])]]:
                descriptor = f.get('/FontDescriptor')
                if descriptor is not None:
                    descriptor = descriptor.get_object()
                    embedded |= any(k in descriptor and len(descriptor[k].get_object().get_data()) > 0
                                    for k in ('/FontFile', '/FontFile2', '/FontFile3'))
        require(embedded, 'native PDF text has no embedded font program')
        text = ''.join(page.extract_text().split())
        require(text == 'AV', 'native PDF text extraction did not preserve AV')
    else:
        require(text_ops == 0, 'batch outline document unexpectedly has text operators')
    return dict(text_operations=text_ops, raster_images=0, operations=len(operators))


def inspect_documents(directory: Path, token: str, render=None):
    rows = document_receipts(read_json(checked_file(directory, 'documents.json')), token)
    result = []
    for row in rows:
        path = checked_file(directory, row['file'])
        reference = checked_file(directory, row['rgba']).read_bytes()
        pixel_checks(reference, row['scene'])
        structure = inspect_pdf(path, row['scene']) if row['format'] == 'pdf' else inspect_svg(path)
        detail = dict(scene=row['scene'], format=row['format'], file=path.name,
                      sha256=hashlib.sha256(path.read_bytes()).hexdigest(), structure=structure,
                      reference_pixels_passed=True, independent_rendering_passed=False)
        if render is not None:
            from PIL import Image
            rendered = render(path, row['format'])
            with Image.open(rendered) as image:
                require(image.size == (WIDTH, HEIGHT), 'wrong independent rendering dimensions')
                data = image.convert('RGBA').tobytes()
            pixel_checks(data, row['scene'])
            # Edges can differ across text and outline rasterizers. Broad pixel
            # agreement plus exact interior/exterior probes catches misplaced,
            # missing, substituted and silently rasterized text separately.
            error = sum(abs(a-b) for a,b in zip(reference,data)) / len(data)
            require(error <= 6.0, 'independent rendering differs beyond edge tolerance')
            detail.update(independent_rendering_passed=True, rgba_mean_absolute_error=error)
        result.append(detail)
    return dict(stage='0.68b', status='passed', documents=result,
                independent_renderers_executed=render is not None)


def gpu_receipt(path: Path, token: str, backend: str, adapter: str):
    data = read_json(path)
    integer(data.get('schema'), 1, 'schema')
    require(data.get('stage') == '0.68b' and data.get('status') == 'passed', 'failed/foreign GPU result')
    require(data.get('run_token') == token and bool(token), 'stale GPU token')
    require(data.get('backend') == backend and data.get('adapter') == adapter, 'wrong GPU backend/adapter')
    for key, value in (('failures',0), ('frames',3), ('drawing_readbacks',0), ('inspection_readbacks',3)):
        integer(data.get(key), value, key)
    require(data.get('scenes') == list(SCENES), 'wrong/missing/duplicate GPU scenes')
    require(data.get('contexts_closed') is True and data.get('gui_executed') is False
            and data.get('physical_display_verified') is False, 'incorrect GPU cleanup/display claim')
    return data
