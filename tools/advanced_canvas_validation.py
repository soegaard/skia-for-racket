"""0.74 acceptance inspectors and runner; source declarations are not receipts.

Pixel oracles below are independent of the Racket drawing implementation. All
file reads are bounded, local, and reject ambiguous or stale evidence.
"""
from __future__ import annotations
from validation_regressions import RegressionGate, add_regression_argument, checked_mode, global_compile_targets

import argparse
import base64
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
STAGE = '0.74'
SIZE = (64, 48)
GPU_CASES = 11
PURE_CASES = 28
NATIVE_CASES = 33
URL = 'https://example.invalid/advanced-canvases'
SCENES = ('layer', 'initialization', 'backdrop', 'drawable', 'nway-a', 'nway-b')
DOCUMENTS = tuple((mode, kind) for mode in ('vector', 'layer') for kind in ('pdf', 'svg'))
BACKENDS = {'egl': ('opengl', 0), 'metal': ('metal', 2), 'direct3d': ('direct3d', 3)}
MAX_FILE = 32 * 1024 * 1024


def need(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def exact(value, expected: int) -> bool:
    return type(value) is int and value == expected


def safe_file(directory: Path, name: str) -> Path:
    need(type(name) is str and bool(name) and name not in ('.', '..')
         and not any(c in name for c in '/\\:') and not any(ord(c) < 32 for c in name),
         'unsafe evidence filename')
    path = directory / name
    need(path.is_file() and not path.is_symlink(), 'missing/symlink evidence: ' + name)
    need(path.stat().st_size <= MAX_FILE, 'oversized evidence: ' + name)
    return path


def read_json(path: Path):
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= MAX_FILE,
         'missing/unsafe JSON report')
    def pairs(values):
        result = {}
        for key, value in values:
            need(key not in result, 'duplicate JSON key: ' + key)
            result[key] = value
        return result
    def invalid(value):
        raise ValueError('nonfinite JSON value: ' + value)
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=pairs, parse_constant=invalid)


def receipt_header(data, token: str) -> None:
    need(type(data) is dict and exact(data.get('schema'), 1) and data.get('stage') == STAGE,
         'wrong receipt schema/stage')
    need(bool(token) and data.get('run_token') == token and data.get('status') == 'passed',
         'stale or failed receipt')


def expected_rgba(scene: str, *, document: bool = False) -> bytes:
    need(scene in (*SCENES, 'vector'), 'unknown oracle scene')
    out = bytearray()
    for y in range(SIZE[1]):
        for x in range(SIZE[0]):
            pixel = (255, 255, 255, 255)
            left, right = (12, 36) if scene == 'backdrop' else (8, 32)
            if left <= x < right and 8 <= y < 32:
                pixel = (255, 127, 127, 255) if scene == 'layer' else (255, 0, 0, 255)
            if 36 <= x < 56 and 16 <= y < 32:
                pixel = (0, 0, 255, 255)
            if document and 2 <= x < 6 and 2 <= y < 6:
                pixel = (0, 255, 0, 255)
            out.extend(pixel)
    return bytes(out)


def check_rgba(data: bytes, scene: str, *, document: bool = False) -> dict:
    expected = expected_rgba(scene, document=document)
    need(len(data) == len(expected), 'wrong RGBA capture dimensions')
    # Independent renderers can antialias path boundaries differently. Probe
    # every interior pixel, excluding a one-pixel belt around authored edges.
    edges_x = {2, 6, 8, 12, 32, 36, 56}
    edges_y = {2, 6, 8, 16, 32}
    checked = 0
    for y in range(SIZE[1]):
        for x in range(SIZE[0]):
            if document and (any(abs(x + .5 - e) <= 1 for e in edges_x)
                             or any(abs(y + .5 - e) <= 1 for e in edges_y)):
                continue
            offset = (y * SIZE[0] + x) * 4
            a, b = data[offset:offset+4], expected[offset:offset+4]
            need(all(abs(u-v) <= 1 for u, v in zip(a, b)),
                 f'{scene}: pixels differ at ({x},{y}): {tuple(a)} != {tuple(b)}')
            checked += 1
    need(checked > 1000, 'pixel oracle checked too few samples')
    return {'pixels_checked': checked, 'sha256': hashlib.sha256(data).hexdigest()}


def check_f16(data: bytes, order: str) -> dict:
    need(order in ('little', 'big'), 'unknown float byte order')
    need(len(data) == 8*6*8, 'wrong F16 capture dimensions/stride')
    prefix = '<' if order == 'little' else '>'
    expected = (.25, .5, .75, 1.)
    for y in range(6):
        for x in range(8):
            actual = struct.unpack_from(prefix + '4e', data, (y*8+x)*8)
            need(all(math.isfinite(a) and abs(a-b) <= 0.0021 for a, b in zip(actual, expected)),
                 'F16 typed target/composite differs from the bounded reference')
    return {'samples_checked': 48, 'storage': 'rgba-f16',
            'typed_target_verified': True, 'intermediate_precision_inferred': False,
            'sha256': hashlib.sha256(data).hexdigest()}


def expected_overdraw() -> bytes:
    return bytes(int(2 <= x < 8 and 2 <= y < 8) + int(4 <= x < 10 and 2 <= y < 8)
                 for y in range(10) for x in range(12))


def check_io(events) -> None:
    need(type(events) is list and len(events) == 3 and all(type(e) is dict for e in events),
         'missing/extra I/O events')
    need([e.get('kind') for e in events] == ['readback', 'flush', 'submit'],
         'wrong readback/completion event order')
    need(events[2].get('wait_requested') is True, 'readback lacks synchronous completion')
    for key, value in (('width', 64), ('height', 48), ('row_bytes', 256)):
        need(exact(events[0].get(key), value), 'wrong readback descriptor: ' + key)


def inspect_gpu(directory: Path, token: str, backend: str, adapter: str) -> dict:
    data = read_json(directory/'gpu.json')
    receipt_header(data, token)
    need(data.get('backend') == backend and data.get('adapter') == adapter, 'foreign backend/adapter')
    need(exact(data.get('cases'), GPU_CASES) and exact(data.get('failures'), 0), 'incomplete GPU tests')
    need(data.get('contexts_closed') is True, 'GPU contexts did not close')
    for flag in ('hdr_verified', 'physical_display_verified'):
        need(data.get(flag) is False, 'unsupported claim: ' + flag)
    checks = data.get('checks')
    need(type(checks) is dict, 'missing GPU ownership checks')
    for flag in ('nway_authoring_once', 'f16_layer', 'foreign_drawable_rejected',
                 'foreign_backdrop_rejected', 'layer_exception_cleanup', 'nway_exception_cleanup',
                 'overdraw_capability_checked'):
        need(checks.get(flag) is True, 'missing required GPU check: ' + flag)
    need(type(checks.get('overdraw_supported')) is bool, 'missing overdraw capability result')
    rows = data.get('captures')
    need(type(rows) is list and len(rows) == len(SCENES) and all(type(r) is dict for r in rows),
         'incomplete capture list')
    lookup = {r.get('name'): r for r in rows}
    need(set(lookup) == set(SCENES), 'duplicate/foreign capture')
    real_backend, native_id = BACKENDS[backend]
    generation = None
    results = []
    for name in SCENES:
        row = lookup[name]
        need(row.get('file') == name+'.rgba', 'wrong capture filename')
        need(exact(row.get('drawing_readbacks'), 0) and exact(row.get('inspection_readbacks'), 1),
             'hidden/missing readback')
        target = row.get('target')
        need(type(target) is dict and target.get('backend') == real_backend
             and exact(target.get('native_backend'), native_id) and target.get('context_matches') is True
             and target.get('storage') == 'gpu' and target.get('render_path') == 'sk_surface_new_render_target',
             'capture was not produced by the selected GPU target')
        for key, value in (('width', 64), ('height', 48), ('requested_sample_count', 0)):
            need(exact(target.get(key), value), 'wrong GPU target ' + key)
        need(target.get('color_type') == 'RGBA8888' and target.get('alpha_type') == 'premultiplied'
             and target.get('actual_sample_count') is False, 'wrong/invented GPU format/sample metadata')
        current = target.get('context_generation')
        need(type(current) is int and current > 0 and (generation is None or generation == current),
             'foreign capture context')
        generation = current
        check_io(row.get('io'))
        results.append({'scene': name, **check_rgba(safe_file(directory, row['file']).read_bytes(), name)})
    float_result = check_f16(safe_file(directory, 'layer-f16.pixels').read_bytes(), data.get('float_order'))
    capability = checks.get('overdraw_capability')
    need(type(capability) is dict and capability.get('backend') == real_backend
         and capability.get('color_type_name') == 'alpha-8'
         and type(capability.get('max_sample_count')) is int
         and capability['max_sample_count'] >= 0
         and capability.get('renderable') is (capability['max_sample_count'] > 0)
         and capability.get('renderable') is checks['overdraw_supported']
         and capability.get('allocation_verified') is False,
         'overdraw skip is not justified by native format capability')
    if checks['overdraw_supported']:
        need(safe_file(directory, 'overdraw.alpha').read_bytes() == expected_overdraw(),
             'overdraw Alpha8 values differ')
    else:
        need(not (directory/'overdraw.alpha').exists(), 'unsupported overdraw has a fabricated capture')
    return {'status': 'passed', 'backend': backend, 'cases': GPU_CASES, 'captures': results,
            'float': float_result, 'overdraw_executed': checks['overdraw_supported'], 'contexts_closed': True}


def check_document_row(row: dict) -> None:
    need(type(row) is dict, 'document row must be an object')
    mode, kind = row.get('mode'), row.get('format')
    need((mode, kind) in DOCUMENTS and row.get('file') == f'{mode}.{kind}', 'unknown document')
    need(row.get('boundary') == ('native-drawable' if mode == 'vector' else 'explicit-integer-snapshot'),
         'implicit document boundary')
    audit = row.get('audit')
    need(type(audit) is dict and audit.get('backend') == kind and audit.get('mode') == 'export'
         and exact(audit.get('pages'), 1) and audit.get('blocking') is False,
         'invalid document audit')
    events = audit.get('events')
    need(type(events) is list and bool(events) and all(type(e) is dict for e in events),
         'missing audit events')
    need(all(exact(e.get('page'), 1) for e in events), 'wrong event page')
    need(any(e.get('feature') == 'annotation' for e in events), 'missing document annotation')
    need(any(e.get('feature') == 'geometry' for e in events), 'missing vector geometry')
    images = [e for e in events if e.get('feature') == 'image']
    need(len(images) == (0 if mode == 'vector' else 1), 'wrong embedded image count')
    allowed = {'geometry', 'annotation', 'drawable', 'picture', 'source-replace', 'transform', 'clip-intersect', 'image'}
    need(all(e.get('feature') in allowed for e in events), 'unexpected or laundered document feature')
    for event in events:
        need(event.get('status') == ('embedded-raster' if event.get('feature') == 'image' else 'vector'),
             'hidden fallback or incorrectly classified document content')
    need(audit.get('vector_only') is (mode == 'vector'), 'wrong vector-only audit claim')
    if mode == 'vector':
        need(any(e.get('feature') == 'drawable' for e in events), 'missing drawable provenance')


def inspect_pdf(path: Path, mode: str) -> dict:
    from pypdf import PdfReader
    from pypdf.generic import ContentStream
    reader = PdfReader(str(path), strict=True)
    need(not reader.is_encrypted and len(reader.pages) == 1, 'wrong/encrypted PDF page count')
    page = reader.pages[0]
    need(abs(float(page.mediabox.width)-64) < .01 and abs(float(page.mediabox.height)-48) < .01,
         'wrong PDF dimensions')
    need(not page.get('/Rotate', 0), 'unexpected PDF rotation')
    links = []
    for obj in page.get('/Annots', []):
        annotation = obj.get_object()
        action = annotation.get('/A')
        if action:
            action = action.get_object()
            if action.get('/S') == '/URI':
                links.append(str(action.get('/URI')))
    need(URL in links, 'missing PDF URL annotation')
    images, painted, visits = [], 0, set()
    def scan(stream, resources, depth=0):
        nonlocal painted
        need(depth < 20, 'recursive PDF forms')
        if stream is not None:
            operations = ContentStream(stream, reader).operations
            need(len(operations) < 100000, 'unbounded PDF operations')
            need(not any(op == b'INLINE IMAGE' for _, op in operations), 'unexpected inline PDF image')
            painted += sum(op in (b'f', b'f*', b'B', b'B*', b'S', b'b', b'b*') for _, op in operations)
        resources = resources.get_object() if resources else {}
        objects = resources.get('/XObject', {})
        objects = objects.get_object() if objects else {}
        for ref in objects.values():
            key = (getattr(ref, 'idnum', None), getattr(ref, 'generation', None))
            obj = ref.get_object()
            if key[0] is None:
                key = id(obj)
            if key in visits:
                continue
            visits.add(key)
            need(len(visits) < 4096 and '/F' not in obj, 'unsafe PDF external resource')
            subtype = obj.get('/Subtype')
            if subtype == '/Image':
                images.append((int(obj.get('/Width', 0)), int(obj.get('/Height', 0))))
            elif subtype == '/Form':
                scan(obj, obj.get('/Resources', resources), depth+1)
    scan(page.get_contents(), page.get('/Resources'))
    need(painted > 0, 'PDF has no painted vector geometry')
    need(images == ([] if mode == 'vector' else [SIZE]), 'wrong PDF image count/dimensions')
    return {'images': len(images), 'url': True, 'vector_paints': painted}


def inspect_svg(path: Path, mode: str) -> dict:
    from PIL import Image
    text = path.read_bytes()
    need(b'<!DOCTYPE' not in text.upper() and b'<!ENTITY' not in text.upper(), 'unsafe SVG DTD/entity')
    root = ET.fromstring(text)
    def tag(node):
        return node.tag.rsplit('}', 1)[-1]
    need(tag(root) == 'svg', 'wrong SVG root')
    def dimension(value):
        need(type(value) is str and re.fullmatch(r'[0-9]+(?:\.[0-9]+)?(?:px|pt)?', value) is not None,
             'invalid SVG dimension')
        return float(re.sub(r'(?:px|pt)$', '', value))
    need(dimension(root.get('width')) == 64 and dimension(root.get('height')) == 48,
         'wrong SVG dimensions')
    nodes = list(root.iter())
    need(len(nodes) < 100000 and not any(tag(n) in ('script', 'foreignObject', 'iframe') for n in nodes),
         'unsafe SVG node')
    href = lambda n: n.get('href') or n.get('{http://www.w3.org/1999/xlink}href')
    need(any(tag(n) == 'a' and href(n) == URL for n in nodes), 'missing SVG URL link')
    images = [n for n in nodes if tag(n) == 'image']
    need(len(images) == (0 if mode == 'vector' else 1), 'wrong SVG image count')
    for node in images:
        value = href(node)
        need(type(value) is str and value.startswith('data:image/png;base64,'), 'non-embedded PNG in SVG')
        payload = base64.b64decode(''.join(value.split(',', 1)[1].split()), validate=True)
        need(len(payload) < MAX_FILE, 'oversized embedded PNG')
        with Image.open(io.BytesIO(payload)) as im:
            need(im.size == SIZE, 'wrong embedded PNG dimensions')
            check_rgba(im.convert('RGBA').tobytes(), 'layer')
    need(any(tag(n) in ('path', 'rect', 'circle', 'polygon') for n in nodes), 'missing SVG vector geometry')
    return {'images': len(images), 'url': True}


def inspect_documents(directory: Path, token: str, source: str, *, render: bool, runner=None) -> dict:
    data = read_json(directory/'documents.json')
    receipt_header(data, token)
    need(data.get('layer_source') == source, 'wrong document pixel source')
    rows = data.get('documents')
    need(type(rows) is list and len(rows) == len(DOCUMENTS), 'incomplete document coverage')
    for row in rows:
        check_document_row(row)
    need({(r['mode'], r['format']) for r in rows} == set(DOCUMENTS), 'duplicate/foreign documents')
    results = []
    if render:
        for executable in ('pdftoppm', 'rsvg-convert'):
            need(shutil.which(executable) is not None, 'required renderer missing: ' + executable)
    for row in rows:
        path = safe_file(directory, row['file'])
        mode, kind = row['mode'], row['format']
        detail = inspect_pdf(path, mode) if kind == 'pdf' else inspect_svg(path, mode)
        if render:
            from PIL import Image
            image_path = directory / f'{mode}-{kind}-independent.png'
            if kind == 'pdf':
                command = ['pdftoppm', '-singlefile', '-r', '72', '-png', str(path), str(image_path.with_suffix(''))]
            else:
                # Skia's SVG canvas expresses physical document sizes in points.
                # librsvg otherwise rasterizes those at its CSS 96-DPI default,
                # yielding 85x64 for a 64pt x 48pt document. Pin the acceptance
                # raster to the same 64x48 pixel reference used by the 72-DPI
                # PDF renderer.
                command = ['rsvg-convert', '--width', str(SIZE[0]), '--height', str(SIZE[1]),
                           '--output', str(image_path), str(path)]
            if runner:
                runner.run(command)
            else:
                subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
            with Image.open(image_path) as image:
                need(image.size == SIZE, 'wrong independent render dimensions')
                pixels = image.convert('RGBA').tobytes()
                detail['render'] = check_rgba(pixels, mode, document=True)
        results.append({'file': row['file'], 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), **detail})
    return {'status': 'passed', 'documents': results, 'independent_renderers_executed': render,
            'layer_source': source}


class Runner:
    def __init__(self, root: Path, directory: Path, env: dict):
        self.root, self.directory, self.env = root, directory, env
        self.index = 0
        self.failed_log = None
        (directory/'logs').mkdir()

    def run(self, command):
        command = list(map(str, command))
        self.index += 1
        log = self.directory/'logs'/f'{self.index:03d}.log'
        print('+ ' + ' '.join(command), flush=True)
        with log.open('w', encoding='utf-8') as stream:
            stream.write('$ ' + repr(command) + '\n')
            stream.flush()
            try:
                subprocess.run(command, cwd=self.root, env=self.env, stdout=stream,
                               stderr=subprocess.STDOUT, timeout=1200, check=True)
            except (OSError, subprocess.SubprocessError):
                self.failed_log = log
                stream.flush()
                raise


def arguments(argv=None):
    parser = argparse.ArgumentParser(description='0.74 real advanced canvas acceptance')
    add_regression_argument(parser)
    parser.add_argument('--racket', default='racket')
    parser.add_argument('--require-gpu', action='store_true')
    parser.add_argument('--backend', choices=('auto', *BACKENDS), default='auto')
    parser.add_argument('--adapter', choices=('hardware', 'warp'), default='hardware')
    parser.add_argument('--require-renderers', action='store_true')
    parser.add_argument('--directory', type=Path)
    args = parser.parse_args(argv)
    if not args.require_gpu and (args.backend != 'auto' or args.adapter != 'hardware'):
        parser.error('an explicit backend/adapter requires --require-gpu')
    if args.backend in ('egl', 'metal') and args.adapter == 'warp':
        parser.error('WARP requires Direct3D')
    return args


def main(argv=None, *, root=ROOT):
    args = arguments(argv)
    root = Path(root).resolve()
    directory = (args.directory.resolve() if args.directory else
                 Path(tempfile.mkdtemp(prefix='advanced-canvases-0.74-', dir=make_output(root))))
    if args.directory:
        need(not directory.exists(), 'evidence directory must be new')
        directory.mkdir(parents=True)
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONUTF8='1')
    runner = Runner(root, directory, env)
    token = uuid.uuid4().hex
    report = {'schema': 1, 'stage': STAGE, 'run_token': token, 'status': 'failed',
              'regressions_passed': False, 'gpu_executed': False, 'documents_checked': False,
              'independent_renderers_executed': False, 'hdr_verified': False, 'physical_display_verified': False}
    regressions = RegressionGate(args.regressions, report)
    try:
        selected = shutil.which(args.racket)
        need(selected is not None, 'selected Racket executable not found')
        selected = str(Path(selected).resolve())
        if args.require_renderers:
            for executable in ('pdftoppm', 'rsvg-convert'):
                need(shutil.which(executable), 'required renderer missing: ' + executable)
        initial = (root/'SOURCE-SHA256SUMS.txt').read_bytes()
        for name, options in (('update-source-sums.py', ['--check']), ('api-inventory.py', ['--check']),
                              ('check-gpu-source.py', ['--require-integration']),
                              ('test-advanced-canvases.py', []), ('test-advanced-canvas-documents.py', [])):
            runner.run([sys.executable, root/'tools'/name, *options])
        runner.run([selected, root/'tools/check-package-version.rkt'])
        targets = [root/p for p in ('main.rkt', 'gpu.rkt', 'tests/advanced-canvas-gpu-test.rkt',
                   'tools/advanced-canvas-doctor.rkt', 'examples/advanced-canvases.rkt')]
        if args.regressions == 'full':
            targets += global_compile_targets(root)
        runner.run([selected, '-l', 'raco', '--', 'make', *targets])
        regressions.run(lambda: runner.run([selected, root/'run-tests.rkt']))
        source = 'cpu'
        capture = []
        if args.require_gpu:
            backend = args.backend
            if backend == 'auto':
                backend = 'metal' if sys.platform == 'darwin' else ('direct3d' if os.name == 'nt' else 'egl')
            need(backend == 'direct3d' or args.adapter == 'hardware', 'WARP requires Direct3D')
            gpu_dir = directory/'gpu'
            runner.run([selected, root/'tests/advanced-canvas-gpu-test.rkt', '--backend', backend,
                        '--adapter', args.adapter, '--directory', gpu_dir, '--token', token])
            report['gpu'] = inspect_gpu(gpu_dir, token, backend, args.adapter)
            report['gpu_executed'] = True
            source, capture = 'gpu-capture', ['--gpu-layer', str(gpu_dir/'layer.rgba')]
        else:
            need(args.backend == 'auto' and args.adapter == 'hardware',
                 'an explicit backend/adapter requires --require-gpu')
        documents = directory/'documents'
        runner.run([selected, root/'tools/advanced-canvas-doctor.rkt', '--directory', documents,
                    '--token', token, *capture])
        report['documents'] = inspect_documents(documents, token, source,
                                                render=args.require_renderers, runner=runner)
        report['documents_checked'] = True
        report['independent_renderers_executed'] = args.require_renderers
        need((root/'SOURCE-SHA256SUMS.txt').read_bytes() == initial, 'source manifest changed during acceptance')
        runner.run([sys.executable, root/'tools/update-source-sums.py', '--check'])
        report['status'] = 'passed'
    except Exception as error:
        report['error'] = type(error).__name__ + ': ' + str(error)
        print('Advanced canvases FAILED: ' + report['error'], file=sys.stderr)
        if runner.failed_log:
            print('Failed command log: ' + str(runner.failed_log), file=sys.stderr)
            print(runner.failed_log.read_bytes()[-24000:].decode('utf-8', errors='replace'), file=sys.stderr)
    (directory/'validation.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print('Evidence: ' + str(directory))
    if report['status'] == 'passed':
        print('Advanced canvases passed; GPU execution: ' + str(report['gpu_executed'])
              + '; independent document rendering: ' + str(report['independent_renderers_executed']))
    return 0 if report['status'] == 'passed' else 1


def make_output(root: Path) -> Path:
    out = root/'output'
    out.mkdir(exist_ok=True)
    return out
