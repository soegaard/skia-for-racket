#!/usr/bin/env python3
"""Inspect 0.39 live files; synthetic self-tests do not exercise Racket or a GPU.

Only the standard library is required. PNG checks compare decoded samples, not
compressed streams. Tolerances are deliberately explicit initial acceptance
bounds, not a claim that all backends render identically.
"""
from __future__ import annotations
import argparse
import copy
import html
import json
import math
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

SIZE = (420, 260)
NAMES = ('paths', 'gradients', 'images', 'filters', 'runtime', 'text', 'mesh', 'perspective')
# (mean absolute channel error, fraction of ROI pixels with any error > 24)
TOLERANCES = {'paths': (2.5, .04), 'gradients': (1.2, .015), 'images': (1.5, .02),
              'filters': (3.0, .06), 'runtime': (2.0, .03), 'text': (3.0, .075),
              'mesh': (2.5, .05), 'perspective': (3.0, .06)}
SURFACE_SYMBOLS = {'gr_direct_context_submit', 'gr_direct_context_flush',
                   'sk_surface_read_pixels', 'sk_canvas_get_save_count'}
WINDOW_SYMBOLS = SURFACE_SYMBOLS | {'gr_backendrendertarget_new_gl',
    'gr_backendrendertarget_delete', 'gr_backendrendertarget_is_valid',
    'sk_surface_new_backend_render_target', 'sk_surface_draw'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def png(data: bytes, expected: tuple[int, int]) -> bytes:
    require(len(data) <= 32*1024*1024, 'PNG file exceeds inspection limit')
    require(data.startswith(b'\x89PNG\r\n\x1a\n'), 'not a PNG')
    pos, header, ended = 8, None, False
    compressed = bytearray()
    while pos < len(data):
        require(pos + 12 <= len(data), 'truncated PNG chunk')
        n, kind = struct.unpack_from('>I4s', data, pos)
        require(n <= 16*1024*1024 and pos+n+12 <= len(data), 'invalid PNG chunk extent')
        payload = data[pos+8:pos+8+n]
        require((zlib.crc32(kind+payload) & 0xffffffff) == struct.unpack_from('>I', data, pos+8+n)[0],
                'PNG CRC mismatch')
        if kind == b'IHDR':
            require(header is None and pos == 8 and n == 13, 'invalid PNG header')
            header = struct.unpack('>IIBBBBB', payload)
        elif kind == b'IDAT':
            require(header is not None, 'PNG data before header')
            compressed.extend(payload)
        elif kind == b'tRNS':
            raise ValueError('unexpected PNG color-key transparency')
        elif kind == b'IEND':
            require(n == 0 and pos+12 == len(data), 'invalid PNG end')
            ended = True
            break
        elif not (kind[0] & 32) and kind != b'PLTE':
            raise ValueError('unsupported critical PNG chunk')
        pos += n+12
    require(ended and header is not None, 'incomplete PNG')
    w, h, depth, color, method, filters, interlace = header
    require((w,h) == expected and (depth,method,filters,interlace) == (8,0,0,0),
            f'expected noninterlaced 8-bit PNG of size {expected}')
    require(color in (2,6), 'expected RGB/RGBA PNG')
    bpp = 4 if color == 6 else 3
    stride, limit = w*bpp, h*(w*bpp+1)
    decoder = zlib.decompressobj()
    raw = decoder.decompress(bytes(compressed), limit+1)
    require(len(raw) == limit and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail,
            'truncated, excessive, or concatenated PNG pixel stream')
    previous = bytearray(stride)
    result = bytearray()
    for y in range(h):
        offset = y*(stride+1)
        mode = raw[offset]
        require(mode in range(5), 'unknown PNG row filter')
        row = bytearray(raw[offset+1:offset+1+stride])
        for x in range(stride):
            a = row[x-bpp] if x >= bpp else 0
            b = previous[x]
            c = previous[x-bpp] if x >= bpp else 0
            if mode == 0: predictor = 0
            elif mode == 1: predictor = a
            elif mode == 2: predictor = b
            elif mode == 3: predictor = (a+b)//2
            else:
                p = a+b-c
                pa,pb,pc = abs(p-a),abs(p-b),abs(p-c)
                predictor = a if pa <= pb and pa <= pc else b if pb <= pc else c
            row[x] = (row[x]+predictor) & 255
        if bpp == 4: result.extend(row)
        else:
            for x in range(0,stride,3): result.extend((*row[x:x+3],255))
        previous = row
    return bytes(result)


def image_path(directory: Path, name):
    require(isinstance(name,str) and name not in ('','.', '..') and
            '/' not in name and '\\' not in name and ':' not in name and name.endswith('.png'),
            'unsafe or invalid image filename')
    return directory/name


def load_image(directory, name, expected):
    return png(image_path(directory,name).read_bytes(),expected)


def px(data, x, y, width=420):
    i = 4*(x+y*width)
    return data[i:i+4]


def anchors(data):
    for point, expected in [((0,0),(255,0,0,255)), ((419,0),(0,255,0,255)),
                            ((0,259),(0,0,255,255)), ((419,259),(255,255,0,255)),
                            ((10,10),(0,0,0,0)), ((410,249),(0,0,0,0))]:
        require(px(data,*point) == bytes(expected), f'orientation/alpha marker mismatch at {point}')


def comparison(cpu, gpu, name):
    require(len(cpu) == len(gpu) == 420*260*4, 'wrong decoded pixel count')
    anchors(cpu); anchors(gpu)
    error_sum = maximum = large = total = cpu_ink = gpu_ink = 0
    # Content ROI avoids diluting differences with the large white frame and
    # footer. The orientation and transparent margins are checked separately.
    for y in range(52,234):
        for x in range(24,396):
            a,b = px(cpu,x,y),px(gpu,x,y)
            diffs = [abs(u-v) for u,v in zip(a,b)]
            error_sum += sum(diffs)
            peak = max(diffs)
            maximum = max(maximum,peak)
            large += peak > 24
            total += 1
            cpu_ink += a[3] > 0 and min(a[:3]) < 225
            gpu_ink += b[3] > 0 and min(b[:3]) < 225
    mean = error_sum/(4*total)
    fraction = large/total
    mean_limit, fraction_limit = TOLERANCES[name]
    require(cpu_ink >= 50, f'{name}: CPU reference contains no meaningful artwork')
    ratio = gpu_ink/cpu_ink
    require(.8 <= ratio <= 1.2, f'{name}: lost or extra GPU foreground ({ratio:.4f})')
    require(mean <= mean_limit and fraction <= fraction_limit,
            f'{name}: CPU/GPU difference exceeds initial tolerance: mean={mean:.4f}, large_fraction={fraction:.5f}, max={maximum}')
    return {'mean_absolute_channel_error':round(mean,6), 'max_channel_error':maximum,
            'large_error_threshold':24, 'large_error_pixel_fraction':round(fraction,6),
            'foreground_ratio':round(ratio,6), 'mean_limit':mean_limit,
            'large_fraction_limit':fraction_limit, 'roi':[24,52,372,182],
            'exact_orientation_alpha_markers':True}


def context(info, *, closed=False):
    require(isinstance(info,dict), 'missing context snapshot')
    require(info.get('backend') == 'opengl' and info.get('native_backend') == 0,
            'context is not native OpenGL')
    require(info.get('state') == ('closed' if closed else 'ready'), 'incorrect context lifecycle state')
    require(integer(info.get('generation'),1), 'invalid context generation')
    for field in ('live_children','pending_releases','failed_releases'):
        require(type(info.get(field)) is int and info[field] == 0, f'nonzero or missing {field}')
    require(info.get('binding_package') == '3.119.1' and info.get('native_version') == '119.0',
            'unexpected native version')
    require(isinstance(info.get('renderer'),str) and info['renderer'], 'missing actual renderer')
    require(info.get('renderer_class') in ('hardware-reported','software','unclassified'), 'invalid renderer class')


def inventory(data, names):
    require(isinstance(data,list), 'missing surface symbol inventory')
    require(len(data) == len(names) and {x.get('name') for x in data} == names,
            'wrong or duplicate surface symbol inventory')
    require(all(x.get('available') is True for x in data), 'unresolved native surface symbol')


def common(data):
    require(data.get('schema_version') == 1 and data.get('stage') == '0.39', 'wrong diagnostic schema/stage')
    require(data.get('status') == 'passed' and data.get('backend') == 'opengl', 'diagnostic did not pass OpenGL')
    require(data.get('performance_measured') is False, 'this diagnostic does not measure performance')
    context(data.get('initial_context'))
    context(data.get('closed_context'),closed=True)
    require(data['closed_context']['generation'] == data['initial_context']['generation'],
            'teardown refers to a different context')
    if data.get('require_hardware'):
        require(data['initial_context']['renderer_class'] == 'hardware-reported',
                'required hardware renderer not reported')


def offscreen(data, directory):
    common(data)
    require(data.get('kind') == 'offscreen', 'wrong diagnostic kind')
    inventory(data.get('surface_symbol_inventory'),SURFACE_SYMBOLS)
    require(type(data.get('native_test_failures')) is int and data['native_test_failures'] == 0,
            'live native test suite did not pass')
    context(data.get('other_closed_context'),closed=True)
    require(data['other_closed_context']['generation'] != data['closed_context']['generation'],
            'cross-context tests need two distinct domains')
    require(data.get('detached_survived_teardown') is True, 'no detached-image teardown check')
    detached = load_image(directory,data.get('detached_image'),(8,8))
    require(detached == bytes([0,0,255,255])*64, 'detached image does not match its post-teardown samples')
    scenes = data.get('scenes')
    require(isinstance(scenes,list) and tuple(s.get('name') for s in scenes) == NAMES,
            'missing, duplicate, or reordered scene coverage')
    results = []
    seen = set()
    for scene in scenes:
        name = scene['name']
        require((scene.get('width'),scene.get('height')) == SIZE, 'wrong scene dimensions')
        require(scene.get('explicit_readback') is True and scene.get('intermediate_cpu_panels') == 0,
                'hidden transfer/panel fallback')
        target = scene.get('target',{})
        require(target.get('storage') == 'gpu' and target.get('target_kind') == 'offscreen' and
                target.get('backend') == 'opengl' and target.get('native_backend') == 0 and
                target.get('context_matches') is True and target.get('render_path') == 'sk_surface_new_render_target',
                'scene was not drawn into its actual Ganesh target')
        require(target.get('context_generation') == data['initial_context']['generation'], 'foreign scene context')
        require((target.get('width'),target.get('height')) == SIZE and target.get('origin') == 'top-left',
                'wrong target dimensions/origin')
        require(target.get('color_type') == 'RGBA8888' and target.get('alpha_type') == 'premultiplied',
                'unexpected offscreen format')
        require(target.get('actual_sample_count') is False and target.get('requested_sample_count') == 0,
                'invented actual offscreen sample count or unexpected request')
        events = scene.get('io_events',[])
        reads = [e for e in events if e.get('kind') == 'readback']
        submits = [e for e in events if e.get('kind') == 'submit']
        require(len(events) == 3 and len(reads) == len(submits) == 1 and
                [e.get('kind') for e in events] == ['readback','flush','submit'] and
                submits[0].get('wait_requested') is True, 'readback/submission trace is not explicit')
        require((reads[0].get('width'),reads[0].get('height'),reads[0].get('row_bytes')) == (420,260,1680),
                'wrong readback descriptor')
        a,b = scene.get('cpu_image'),scene.get('gpu_image')
        require(a != b and a not in seen and b not in seen, 'reused CPU/GPU artifact paths')
        seen.update((a,b))
        cpu,gpu = load_image(directory,a,SIZE),load_image(directory,b,SIZE)
        stats = comparison(cpu,gpu,name)
        results.append({'name':name,'cpu_image':a,'gpu_image':b,**stats})
    return {'schema_version':1,'stage':'0.39','status':'passed','kind':'offscreen','backend':'opengl',
            'scenes_checked':len(results),'scenes':results,'rendering_verified':True,
            'exact_orientation_alpha_markers':True,'detached_image_survived_teardown':True,
            'renderer':data['initial_context']['renderer'],
            'renderer_class':data['initial_context']['renderer_class'],
            'universal_pixel_identity_claimed':False,'performance_measured':False}


def window(data):
    common(data)
    require(data.get('kind') == 'window', 'wrong diagnostic kind')
    inventory(data.get('surface_symbol_inventory'),WINDOW_SYMBOLS)
    require(data.get('visible_pixels_verified') is False and data.get('manual_review_required') is True,
            'automated swap checks cannot certify visible pixels')
    require(type(data.get('frame_readbacks')) is int and data['frame_readbacks'] == 0 and
            type(data.get('frame_explicit_cpu_waits')) is int and data['frame_explicit_cpu_waits'] == 0,
            'normal frames performed a CPU wait/readback')
    frames = data.get('frames')
    require(isinstance(frames,list) and len(frames) >= 3, 'missing window frames')
    io = data.get('io_events',[])
    require(len(io) == 2*len(frames) and
            [x.get('kind') for x in io] == ['flush','submit']*len(frames) and
            all(x.get('wait_requested') is False for x in io if x.get('kind') == 'submit'),
            'frame submission trace includes a wait/readback or is missing submissions')
    sizes = set()
    for index,f in enumerate(frames):
        require(f.get('index') == index and f.get('swap_requested') is True and f.get('expired_canvas') is True,
                'missing/invalid frame swap or expiration')
        require(f.get('live_children') == 0 and f.get('pending_releases') == 0, 'frame leaked handles')
        w,h = f.get('pixel_width'),f.get('pixel_height')
        lw,lh = f.get('logical_width'),f.get('logical_height')
        require(all(integer(x,1) for x in (w,h,lw,lh)), 'invalid actual drawable dimensions')
        require(math.isclose(f.get('scale_x',0),w/lw) and math.isclose(f.get('scale_y',0),h/lh),
                'HiDPI scaling does not match actual pixels')
        sizes.add((w,h))
        t = f.get('target',{})
        require((t.get('width'),t.get('height')) == (w,h) and t.get('origin') == 'bottom-left',
                'wrong window target size/origin')
        require(t.get('context_matches') is True and t.get('native_backend') == 0 and
                t.get('target_kind') == 'host-framebuffer' and t.get('storage') == 'gpu',
                'window target is not GPU backed')
        require(t.get('backend') == 'opengl' and
                t.get('context_generation') == data['initial_context']['generation'] and
                t.get('render_path') == 'sk_surface_new_backend_render_target',
                'foreign or unidentified window target')
        require(integer(t.get('framebuffer_id')) and integer(t.get('actual_sample_count')) and
                integer(t.get('stencil_bits')) and t.get('double_buffered') is True,
                'missing actual host framebuffer properties')
        bits = t.get('color_bits')
        require(bits in ([8,8,8,0],[8,8,8,8]) and t.get('component_type') == 0x8c17,
                'unsupported window component layout')
        enc = t.get('color_encoding')
        require(enc in (0x2601,0x8c40), 'unknown window color encoding')
        fmt = (0x8051 if bits[3] == 0 else 0x8058) if enc == 0x2601 else (0x8c41 if bits[3] == 0 else 0x8c43)
        require(t.get('format') == fmt, 'window format contradicts queried channels/encoding')
    require(len(sizes) >= 2, 'resize did not exercise different actual drawable dimensions')
    return {'schema_version':1,'stage':'0.39','status':'passed','kind':'window','backend':'opengl',
            'frames_checked':len(frames),'distinct_pixel_sizes':sorted([list(s) for s in sizes]),
            'frame_readbacks':0,'frame_explicit_cpu_waits':0,'swaps_requested':len(frames),
            'visible_pixels_verified':False,'manual_review_required':True,'performance_measured':False}


def atomic_text(path, text):
    path.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=path.parent,delete=False) as out:
        temporary = Path(out.name)
        out.write(text)
    try: temporary.replace(path)
    finally:
        if temporary.exists(): temporary.unlink()


def inspect(prefix):
    prefix = Path(prefix)
    data = json.loads(Path(str(prefix)+'.diagnostic.json').read_text())
    result = offscreen(data,prefix.parent) if data.get('kind') == 'offscreen' else window(data)
    parts = ['<!doctype html><meta charset="utf-8"><title>Skia 0.39 GPU review</title>',
             '<style>body{font:16px system-ui;max-width:1100px;margin:2em auto;padding:0 1em;color:#172c3b}',
             'article{border-top:1px solid #ccd5dc;margin-top:2em;padding-top:1em}.pair{display:flex;gap:1em;flex-wrap:wrap}',
             'figure{margin:0}img{max-width:100%;background:repeating-conic-gradient(#ddd 0% 25%,white 0% 50%) 0/16px 16px}',
             'pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}figcaption{padding:.5em 0}</style>',
             '<h1>GPU surfaces — executed validation</h1>',
             '<p>OpenGL target identity is checked by the native probe. CPU/GPU scene comparisons use direct independent draws of the same registry. ',
             'Initial numerical tolerances are not universal pixel-identity or performance guarantees.</p>']
    if result['kind'] == 'offscreen':
        parts.append('<p>Review crop edges, alpha, glyphs, shadows, meshes and perspective in both images. Transparent borders and four unequal corner colors check orientation.</p>')
        for s in result['scenes']:
            parts.append('<article><h2>'+html.escape(s['name'])+'</h2><div class="pair">')
            for key,label in [('cpu_image','CPU reference'),('gpu_image','OpenGL readback')]:
                parts.append(f'<figure><img width="420" height="260" src="{html.escape(s[key],quote=True)}" alt="{label}"><figcaption>{label}</figcaption></figure>')
            parts.append('</div><pre>'+html.escape(json.dumps(s,indent=2))+'</pre></article>')
    else:
        parts.append('<p><strong>No screenshot or monitor-pixel check was performed.</strong> This report checks framebuffer queries, resize, submission, swaps, expired canvases and zero explicit frame waits/readbacks. Run the interactive window example to inspect the visible result.</p>')
        parts.append('<pre>'+html.escape(json.dumps(data['frames'],indent=2))+'</pre>')
    parts.append('<h2>Inspection</h2><pre>'+html.escape(json.dumps(result,indent=2))+'</pre>')
    parts.append('<h2>Native diagnostic</h2><pre>'+html.escape(json.dumps(data,indent=2))+'</pre>')
    # Publish the success JSON last. A failed comparison produces neither a
    # fresh success marker nor an HTML review that pretends that it passed.
    atomic_text(Path(str(prefix)+'.review.html'),''.join(parts))
    atomic_text(Path(str(prefix)+'.inspection.json'),json.dumps(result,indent=2)+'\n')
    return result


# Synthetic fixtures exercise the inspector only, never native rendering.
def png_bytes(pixels, size=SIZE, channels=4):
    w,h = size
    def chunk(kind,payload):
        return struct.pack('>I',len(payload))+kind+payload+struct.pack('>I',zlib.crc32(kind+payload)&0xffffffff)
    raw = b''.join(b'\0'+pixels[y*w*channels:(y+1)*w*channels] for y in range(h))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6 if channels == 4 else 2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')


def fixture_pixels():
    out = bytearray(420*260*4)
    for y in range(16,244):
        for x in range(16,404): out[4*(y*420+x):4*(y*420+x+1)] = bytes([255,255,255,255])
    for y in range(65,222):
        for x in range(35,385): out[4*(y*420+x):4*(y*420+x+1)] = bytes([40,130,170,255])
    for xs,ys,color in [(range(8),range(8),(255,0,0,255)),(range(412,420),range(8),(0,255,0,255)),
                         (range(8),range(252,260),(0,0,255,255)),(range(412,420),range(252,260),(255,255,0,255))]:
        for y in ys:
            for x in xs: out[4*(y*420+x):4*(y*420+x+1)] = bytes(color)
    return bytes(out)


def fixture_context(closed=False, generation=1):
    return {'backend':'opengl','native_backend':0,'state':'closed' if closed else 'ready',
            'generation':generation,'live_children':0,'pending_releases':0,'failed_releases':0,
            'binding_package':'3.119.1','native_version':'119.0','renderer':'SYNTHETIC',
            'renderer_class':'hardware-reported'}


def fixture(directory):
    data = {'schema_version':1,'stage':'0.39','status':'passed','kind':'offscreen','backend':'opengl',
            'initial_context':fixture_context(),'closed_context':fixture_context(True),
            'other_closed_context':fixture_context(True,2),'performance_measured':False,
            'native_test_failures':0,'detached_survived_teardown':True,'detached_image':'detached.png',
            'surface_symbol_inventory':[{'name':n,'available':True} for n in sorted(SURFACE_SYMBOLS)],'scenes':[]}
    (directory/'detached.png').write_bytes(png_bytes(bytes([0,0,255,255])*64,(8,8)))
    pixels = png_bytes(fixture_pixels())
    for name in NAMES:
        a,b = name+'.cpu.png',name+'.gpu.png'
        (directory/a).write_bytes(pixels); (directory/b).write_bytes(pixels)
        data['scenes'].append({'name':name,'width':420,'height':260,'explicit_readback':True,
          'intermediate_cpu_panels':0,'cpu_image':a,'gpu_image':b,
          'io_events':[{'kind':'readback','width':420,'height':260,'row_bytes':1680},
                       {'kind':'flush'},{'kind':'submit','wait_requested':True}],
          'target':{'width':420,'height':260,'storage':'gpu','target_kind':'offscreen','backend':'opengl',
                    'native_backend':0,'context_matches':True,'render_path':'sk_surface_new_render_target',
                    'context_generation':1,'origin':'top-left','color_type':'RGBA8888','alpha_type':'premultiplied',
                    'actual_sample_count':False,'requested_sample_count':0}})
    return data


def fixture_window():
    data = {'schema_version':1,'stage':'0.39','status':'passed','kind':'window','backend':'opengl',
            'initial_context':fixture_context(),'closed_context':fixture_context(True),
            'performance_measured':False,'visible_pixels_verified':False,'manual_review_required':True,
            'frame_readbacks':0,'frame_explicit_cpu_waits':0,
            'surface_symbol_inventory':[{'name':n,'available':True} for n in sorted(WINDOW_SYMBOLS)],
            'io_events':[{'kind':'flush'},{'kind':'submit','wait_requested':False}]*3,'frames':[]}
    for i,(w,h) in enumerate([(520,350),(680,440),(560,380)]):
        data['frames'].append({'index':i,'pixel_width':w,'pixel_height':h,'logical_width':w,'logical_height':h,
          'scale_x':1.0,'scale_y':1.0,'swap_requested':True,'expired_canvas':True,'live_children':0,'pending_releases':0,
          'target':{'width':w,'height':h,'origin':'bottom-left','context_matches':True,'native_backend':0,
                    'storage':'gpu','target_kind':'host-framebuffer','framebuffer_id':0,'actual_sample_count':0,
                    'backend':'opengl','context_generation':1,'render_path':'sk_surface_new_backend_render_target',
                    'stencil_bits':8,'double_buffered':True,'color_bits':[8,8,8,8],
                    'component_type':0x8c17,'color_encoding':0x2601,'format':0x8058}})
    return data


class Checks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.data = fixture(self.root)
    def tearDown(self): self.tmp.cleanup()
    def reject(self):
        with self.assertRaises(ValueError): offscreen(self.data,self.root)
    def test_valid(self): self.assertEqual(offscreen(self.data,self.root)['scenes_checked'],8)
    def test_failed_native(self): self.data['native_test_failures']=1; self.reject()
    def test_false_is_not_zero_native(self): self.data['native_test_failures']=False; self.reject()
    def test_unavailable(self): self.data['status']='unavailable'; self.reject()
    def test_wrong_context(self): self.data['scenes'][0]['target']['context_generation']=2; self.reject()
    def test_cpu_target(self): self.data['scenes'][0]['target']['storage']='raster'; self.reject()
    def test_wrong_origin(self): self.data['scenes'][0]['target']['origin']='bottom-left'; self.reject()
    def test_invented_samples(self): self.data['scenes'][0]['target']['actual_sample_count']=4; self.reject()
    def test_no_submit_wait(self): self.data['scenes'][0]['io_events'][-1]['wait_requested']=False; self.reject()
    def test_hidden_fallback(self): self.data['scenes'][0]['intermediate_cpu_panels']=1; self.reject()
    def test_missing_scene(self): self.data['scenes'].pop(); self.reject()
    def test_duplicate_paths(self): self.data['scenes'][0]['gpu_image']=self.data['scenes'][0]['cpu_image']; self.reject()
    def test_bad_filename(self): self.data['scenes'][0]['gpu_image']='../outside.png'; self.reject()
    def test_pending_release(self): self.data['closed_context']['pending_releases']=1; self.reject()
    def test_missing_symbol(self): self.data['surface_symbol_inventory'].pop(); self.reject()
    def test_detached_pixel(self): (self.root/'detached.png').write_bytes(png_bytes(bytes(256),(8,8))); self.reject()
    def test_png_crc(self):
        p=self.root/'paths.gpu.png'; v=bytearray(p.read_bytes()); v[-1]^=1; p.write_bytes(v); self.reject()
    def test_png_truncated(self):
        p=self.root/'paths.gpu.png'; p.write_bytes(p.read_bytes()[:-10]); self.reject()
    def test_png_wrong_size(self):
        (self.root/'paths.gpu.png').write_bytes(png_bytes(bytes(256),(8,8))); self.reject()
    def test_orientation_pixels(self):
        p=bytearray(fixture_pixels()); p[0:4]=bytes([0,0,255,255]); (self.root/'paths.gpu.png').write_bytes(png_bytes(p)); self.reject()
    def test_alpha_margin(self):
        p=bytearray(fixture_pixels()); p[4*(10+10*420)+3]=255; (self.root/'paths.gpu.png').write_bytes(png_bytes(p)); self.reject()
    def test_color_error(self):
        p=bytearray(fixture_pixels())
        for y in range(65,222):
            for x in range(35,385): p[4*(y*420+x)]=240
        (self.root/'paths.gpu.png').write_bytes(png_bytes(p)); self.reject()
    def test_hardware_requirement(self):
        self.data['require_hardware']=True;self.data['initial_context']['renderer_class']='software'; self.reject()
    def test_software_is_labelled_not_globally_rejected(self):
        self.data['initial_context']['renderer_class']='software'
        self.assertEqual(offscreen(self.data,self.root)['renderer_class'],'software')
    def test_no_publication_on_error(self):
        self.data['status']='error'; prefix=self.root/'probe'
        Path(str(prefix)+'.diagnostic.json').write_text(json.dumps(self.data))
        with self.assertRaises(ValueError): inspect(prefix)
        self.assertFalse(Path(str(prefix)+'.inspection.json').exists())
        self.assertFalse(Path(str(prefix)+'.review.html').exists())
    def test_window_valid(self): self.assertEqual(window(fixture_window())['frames_checked'],3)
    def test_window_cpu_wait(self):
        d=fixture_window();d['io_events'][-1]['wait_requested']=True
        with self.assertRaises(ValueError):window(d)
    def test_window_missing_swap(self):
        d=fixture_window();d['frames'][1]['swap_requested']=False
        with self.assertRaises(ValueError):window(d)
    def test_window_visible_claim(self):
        d=fixture_window();d['visible_pixels_verified']=True
        with self.assertRaises(ValueError):window(d)
    def test_window_format(self):
        d=fixture_window();d['frames'][1]['target']['color_bits']=[10,10,10,2]
        with self.assertRaises(ValueError):window(d)
    def test_window_hidpi(self):
        d=fixture_window();d['frames'][1]['scale_x']=2
        with self.assertRaises(ValueError):window(d)
    def test_window_leaked_frame(self):
        d=fixture_window();d['frames'][1]['live_children']=1
        with self.assertRaises(ValueError):window(d)
    def test_window_foreign_context(self):
        d=fixture_window();d['frames'][1]['target']['context_generation']=2
        with self.assertRaises(ValueError):window(d)
    def test_window_nonzero_framebuffer(self):
        d=fixture_window()
        for f in d['frames']: f['target']['framebuffer_id']=91
        self.assertEqual(window(d)['frames_checked'],3)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test',action='store_true')
    parser.add_argument('--probe-prefix',type=Path)
    args=parser.parse_args()
    if args.self_test:
        result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks))
        if not result.wasSuccessful(): raise SystemExit(1)
    if args.probe_prefix: print(json.dumps(inspect(args.probe_prefix),indent=2))
    if not args.self_test and not args.probe_prefix: parser.error('supply --self-test or --probe-prefix')
