#!/usr/bin/env python3
"""Verify actual GPU doctor artifacts; self-tests use synthetic files, not a GPU."""
from __future__ import annotations
import argparse
import copy
import html
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
import zlib


def require(condition, message):
    if not condition:
        raise ValueError(message)


def expected_rgba() -> bytes:
    return bytes(channel for y in range(8) for x in range(8)
                 for channel in ((0, 0, 0, 0) if x == 3 else
                                 ((255, 0, 0, 255) if x < 3 else (0, 255, 0, 255)) if y < 4 else
                                 ((0, 0, 255, 255) if x < 3 else (255, 255, 0, 255))))


def png_rgba(data: bytes) -> bytes:
    require(data.startswith(b'\x89PNG\r\n\x1a\n'), 'not a PNG')
    position = 8
    header = None
    compressed = bytearray()
    ended = False
    while position < len(data):
        require(len(data) - position >= 12, 'truncated PNG chunk')
        size, kind = struct.unpack_from('>I4s', data, position)
        require(size <= 1024 * 1024 and position + size + 12 <= len(data), 'invalid PNG chunk size')
        payload = data[position+8:position+8+size]
        crc = struct.unpack_from('>I', data, position+8+size)[0]
        require(zlib.crc32(kind + payload) & 0xffffffff == crc, 'PNG CRC mismatch')
        if kind == b'IHDR':
            require(header is None and position == 8 and size == 13, 'invalid PNG header')
            header = struct.unpack('>IIBBBBB', payload)
        elif kind == b'IDAT':
            require(header is not None, 'PNG data before header')
            compressed.extend(payload)
        elif kind == b'IEND':
            require(size == 0 and position+12 == len(data), 'invalid PNG end')
            ended = True
            break
        position += size + 12
    require(ended and header is not None, 'incomplete PNG')
    w, h, depth, color, compression, filter_method, interlace = header
    require((w, h, depth, compression, filter_method, interlace) == (8, 8, 8, 0, 0, 0),
            'expected noninterlaced 8x8, 8-bit PNG')
    require(color in (2, 6), 'expected RGB or RGBA PNG')
    bpp = 4 if color == 6 else 3
    stride = w*bpp
    decoder = zlib.decompressobj()
    raw = decoder.decompress(bytes(compressed), 1 + h*(stride+1))
    require(len(raw) == h*(stride+1) and decoder.eof and not decoder.unused_data,
            'invalid or oversized PNG pixel stream')
    previous = bytearray(stride)
    output = bytearray()
    for y in range(h):
        base = y*(stride+1)
        method = raw[base]
        require(method in range(5), 'unknown PNG row filter')
        row = bytearray(raw[base+1:base+1+stride])
        for x in range(stride):
            left = row[x-bpp] if x >= bpp else 0
            up = previous[x]
            ul = previous[x-bpp] if x >= bpp else 0
            if method == 0: predictor = 0
            elif method == 1: predictor = left
            elif method == 2: predictor = up
            elif method == 3: predictor = (left+up)//2
            else:
                p = left+up-ul
                a, b, c = abs(p-left), abs(p-up), abs(p-ul)
                predictor = left if a <= b and a <= c else up if b <= c else ul
            row[x] = (row[x] + predictor) & 255
        if bpp == 4:
            output.extend(row)
        else:
            for x in range(0, stride, 3): output.extend((*row[x:x+3], 255))
        previous = row
    return bytes(output)


def closed(info: dict):
    require(info.get('state') == 'closed', 'native context was not closed')
    for name in ('live_children', 'pending_releases', 'failed_releases'):
        require(info.get(name) == 0, f'incomplete cleanup: {name}')


def inspect_report(report: dict, directory: Path) -> dict:
    require(report.get('schema_version') == 1 and report.get('stage') == '0.38', 'wrong diagnostic schema')
    require(report.get('status') == 'passed', 'an unavailable/error report is not a passed GPU probe')
    backend = report.get('backend')
    require(backend in ('opengl', 'metal'), 'unknown backend')
    cycles = report.get('cycles')
    require(isinstance(cycles, list) and len(cycles) > 0, 'missing executed cycles')
    generations = set()
    images = []
    renderer_classes = set()
    for index, row in enumerate(cycles, 1):
        require(row.get('index') == index, 'wrong cycle index')
        if backend == 'metal':
            info = row['context']
            require(row.get('construction_only') is True and info.get('construction_only') is True,
                    'Metal probe must remain construction-only')
            require(info.get('rendering_verified') is False, 'Metal construction misreported as rendering')
            require(info.get('native_backend') == 2 and info.get('backend') == 'metal', 'not a Metal context')
            closed(info)
        else:
            info = row['initial_context']
            end = row['closed_context']
            closed(end)
            require(info.get('state') == 'ready', 'GL context never became ready')
            require(end.get('generation') == info.get('generation'), 'context identity changed during probe')
            require(info.get('native_backend') == 0 and info.get('backend') == 'opengl', 'not a GL context')
            category = info.get('renderer_class')
            require(category in ('software', 'hardware-reported', 'unclassified'), 'missing renderer classification')
            renderer_classes.add(category)
            require(bool(info.get('renderer')) and bool(info.get('api_version')), 'missing real driver identity')
            if report.get('require_hardware'):
                require(category == 'hardware-reported', 'hardware requirement did not pass')
            smoke = row['smoke']
            require(smoke.get('render_path') == 'sk_surface_new_render_target', 'CPU substitution in GPU probe')
            require(smoke.get('context_matches') is True and smoke.get('native_backend') == 0,
                    'target does not belong to the Ganesh context')
            require((smoke.get('width'), smoke.get('height'), smoke.get('row_bytes')) == (8, 8, 32),
                    'wrong target or stride')
            require(smoke.get('origin') == 'top-left', 'wrong public origin')
            rgba = smoke.get('rgba')
            require(isinstance(rgba, list) and all(type(v) is int and 0 <= v <= 255 for v in rgba),
                    'invalid RGBA samples')
            require(bytes(rgba) == expected_rgba(), 'readback does not match the exact asymmetric RGBA pattern')
            name = row.get('image_file', '')
            require(bool(name) and Path(name).name == name and '/' not in name and '\\' not in name,
                    'unsafe image filename in diagnostic')
            require(png_rgba((directory / name).read_bytes()) == expected_rgba(), 'published PNG differs from GPU readback')
            images.append(name)
        generation = info.get('generation')
        require(type(generation) is int and generation > 0 and generation not in generations,
                'reused or invalid context generation')
        generations.add(generation)
    return {'schema_version': 1, 'status': 'passed', 'backend': backend,
            'cycles_checked': len(cycles), 'rendering_verified': backend == 'opengl',
            'construction_only': backend == 'metal', 'images': images,
            'renderer_classes': sorted(renderer_classes), 'performance_measured': False}


def publish(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as out: out.write(text)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def review_html(report, result):
    images = ''.join(f'<figure><img src="{html.escape(name, quote=True)}" alt="Exact GPU readback"><figcaption>{html.escape(name)}</figcaption></figure>'
                     for name in result['images'])
    return ('<!doctype html><meta charset="utf-8"><title>Skia 0.38 GPU review</title>'
            '<style>body{font:17px system-ui;max-width:1000px;margin:3em auto;padding:0 1em}'
            'img{width:256px;height:256px;image-rendering:pixelated;background:repeating-conic-gradient(#ddd 0% 25%,white 0% 50%) 0/32px 32px}'
            'figure{display:inline-block;margin:1em}pre{white-space:pre-wrap;overflow-wrap:anywhere}</style>'
            '<h1>GPU foundation: executed diagnostic</h1>'
            '<p>OpenGL images are CPU-detached copies of a real Ganesh target readback. '
            'The transparent column and unequal left/right regions expose alpha and orientation mistakes. '
            'Metal output, when selected, establishes construction/teardown only. '
            'Renderer classification is based on driver strings; no performance or hardware attestation is implied.</p>'
            + images + '<h2>Inspection</h2><pre>' + html.escape(json.dumps(result, indent=2))
            + '</pre><h2>Native diagnostic</h2><pre>' + html.escape(json.dumps(report, indent=2)) + '</pre>')


def png_fixture(pixels=None):
    pixels = expected_rgba() if pixels is None else pixels
    def chunk(kind, payload):
        return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind+payload) & 0xffffffff)
    rows = b''.join(b'\0' + pixels[y*32:(y+1)*32] for y in range(8))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 8, 8, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')


def report_fixture():
    info = {'state':'ready', 'generation':1, 'backend':'opengl', 'native_backend':0,
            'renderer':'llvmpipe', 'renderer_class':'software', 'api_version':'4.5',
            'live_children':0, 'pending_releases':0, 'failed_releases':0}
    smoke = {'width':8, 'height':8, 'row_bytes':32, 'origin':'top-left', 'native_backend':0,
             'context_matches':True, 'render_path':'sk_surface_new_render_target', 'rgba':list(expected_rgba())}
    return {'stage':'0.38','schema_version':1,'status':'passed','backend':'opengl','require_hardware':False,
            'cycles':[{'index':1,'initial_context':info,'closed_context':dict(info,state='closed'),
                       'smoke':smoke,'image_file':'cycle.png'}]}


class Checks(unittest.TestCase):
    def check_report(self, report, pixels=None):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp); (folder/'cycle.png').write_bytes(png_fixture(pixels))
            return inspect_report(report,folder)
    def test_pattern(self): self.assertEqual(len(expected_rgba()),256)
    def test_png(self): self.assertEqual(png_rgba(png_fixture()),expected_rgba())
    def test_png_crc(self):
        data=bytearray(png_fixture()); data[-1]^=1
        with self.assertRaises(ValueError): png_rgba(bytes(data))
    def test_png_truncation(self):
        with self.assertRaises(ValueError): png_rgba(png_fixture()[:-5])
    def test_valid(self): self.assertTrue(self.check_report(report_fixture())['rendering_verified'])
    def test_unavailable(self):
        r=report_fixture(); r['status']='unavailable'
        with self.assertRaises(ValueError): self.check_report(r)
    def test_error(self):
        r=report_fixture(); r['status']='error'
        with self.assertRaises(ValueError): self.check_report(r)
    def test_no_cycles(self):
        r=report_fixture(); r['cycles']=[]
        with self.assertRaises(ValueError): self.check_report(r)
    def test_cpu_target(self):
        r=report_fixture(); r['cycles'][0]['smoke']['render_path']='sk_surface_new_raster'
        with self.assertRaises(ValueError): self.check_report(r)
    def test_wrong_context(self):
        r=report_fixture(); r['cycles'][0]['smoke']['context_matches']=False
        with self.assertRaises(ValueError): self.check_report(r)
    def test_wrong_samples(self):
        r=report_fixture(); r['cycles'][0]['smoke']['rgba'][0]=0
        with self.assertRaises(ValueError): self.check_report(r)
    def test_wrong_png(self):
        with self.assertRaises(ValueError): self.check_report(report_fixture(),bytes(256))
    def test_origin(self):
        r=report_fixture(); r['cycles'][0]['smoke']['origin']='bottom-left'
        with self.assertRaises(ValueError): self.check_report(r)
    def test_live_children(self):
        r=report_fixture(); r['cycles'][0]['closed_context']['live_children']=1
        with self.assertRaises(ValueError): self.check_report(r)
    def test_queued_release(self):
        r=report_fixture(); r['cycles'][0]['closed_context']['pending_releases']=1
        with self.assertRaises(ValueError): self.check_report(r)
    def test_reused_generation(self):
        r=report_fixture(); second=copy.deepcopy(r['cycles'][0]); second['index']=2; r['cycles'].append(second)
        with self.assertRaises(ValueError): self.check_report(r)
    def test_require_hardware(self):
        r=report_fixture(); r['require_hardware']=True
        with self.assertRaises(ValueError): self.check_report(r)
    def test_unsafe_path(self):
        r=report_fixture(); r['cycles'][0]['image_file']='../cycle.png'
        with self.assertRaises(ValueError): self.check_report(r)
    def test_metal_construction(self):
        info={'generation':1,'state':'closed','backend':'metal','native_backend':2,'live_children':0,
              'pending_releases':0,'failed_releases':0,'construction_only':True,'rendering_verified':False}
        r={'schema_version':1,'stage':'0.38','status':'passed','backend':'metal',
           'cycles':[{'index':1,'context':info,'construction_only':True}]}
        self.assertFalse(inspect_report(r,Path('.'))['rendering_verified'])
        info['rendering_verified']=True
        with self.assertRaises(ValueError): inspect_report(r,Path('.'))
    def test_atomic_publication(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'report.json'; publish(p,'first'); publish(p,'second')
            self.assertEqual(p.read_text(),'second')
            self.assertEqual([x.name for x in p.parent.iterdir()],['report.json'])


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test',action='store_true')
    parser.add_argument('--probe-prefix',type=Path)
    args=parser.parse_args()
    if args.self_test:
        result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks))
        if not result.wasSuccessful(): raise SystemExit(1)
    if args.probe_prefix:
        prefix=args.probe_prefix
        report=json.loads(Path(str(prefix)+'.diagnostic.json').read_text())
        result=inspect_report(report,prefix.parent)
        publish(Path(str(prefix)+'.review.html'),review_html(report,result))
        publish(Path(str(prefix)+'.inspection.json'),json.dumps(result,indent=2)+'\n')
        print(json.dumps(result,indent=2))
    if not args.self_test and not args.probe_prefix: parser.error('supply --self-test or --probe-prefix')
