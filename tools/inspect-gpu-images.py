#!/usr/bin/env python3
"""Inspect executed GPU-image workflows. Self-tests use synthetic data only."""
from __future__ import annotations
import argparse
import html
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location(
    'skia_gpu_offscreen_inspection', Path(__file__).with_name('inspect-gpu-offscreen.py'))
shared = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(shared)
require = shared.require
NAMES = ('upload-reuse', 'snapshot-graph')
IMAGE_SYMBOLS = {'sk_image_make_texture_image', 'sk_surface_new_image_snapshot',
                 'sk_image_make_subset', 'sk_image_is_texture_backed', 'sk_image_is_valid',
                 'sk_image_get_unique_id', 'sk_image_unref', 'sk_image_make_with_filter'}
NATIVE_TEST_CASES = 42


def exact_int(value, expected):
    return type(value) is int and value == expected


def pattern():
    out = bytearray()
    for y in range(8):
        for x in range(8):
            out.extend((0, 0, 0, 0) if x == 3 else
                       ((255, 0, 0, 255) if x < 3 else (0, 255, 0, 255)) if y < 4 else
                       ((0, 0, 255, 255) if x < 3 else (255, 255, 0, 255)))
    return bytes(out)


def context(info, *, closed=False, backend="opengl"):
    require(isinstance(info, dict) and exact_int(info.get('native_backend'), shared.BACKEND_IDS.get(backend)),
            'invalid native context backend')
    shared.context(info, closed=closed, backend=backend)


def inventory(value, expected):
    require(isinstance(value, list) and all(isinstance(e, dict) for e in value), 'missing symbol inventory')
    shared.inventory(value, expected)


def load(directory, name, size):
    path = shared.image_path(directory, name)
    require(path.resolve().parent == directory.resolve(), 'image path escapes the report directory')
    require(path.stat().st_size <= 32*1024*1024, 'oversized image')
    return shared.png(path.read_bytes(), size)


def samples(pixels):
    # Exact interior samples, independent of the Racket source constructors and
    # of the CPU/GPU similarity statistic. A blank/incorrect common reference
    # must not pass just because both sides have the same defect.
    points = [((37,73),(255,0,0,255)), ((109,73),(0,255,0,255)),
              ((37,145),(0,0,255,255)), ((109,145),(255,255,0,255)),
              ((91,73),(255,255,255,255)), ((220,100),(0,0,255,255)),
              ((208,174),(255,0,0,255)), ((304,174),(0,255,0,255)),
              ((208,211),(0,0,255,255)), ((304,211),(255,255,0,255)),
              ((280,174),(255,255,255,255))]
    for point, expected in points:
        require(shared.px(pixels,*point) == bytes(expected), f'wrong image/subset/filter sample at {point}')


def images(data, directory):
    require(isinstance(data, dict) and exact_int(data.get('schema_version'), 1) and
            data.get('stage') in ('0.40', '0.41') and data.get('kind') == 'images', 'wrong image workflow schema')
    backend = data.get('backend')
    shared.check_backend_host(data, backend)
    require(data.get('status') == 'passed' and backend in shared.BACKEND_IDS, 'GPU image diagnostic did not pass')
    require(backend == 'opengl' or data['stage'] == '0.41', 'legacy report cannot establish Metal rendering')
    if backend == 'metal':
        require(data.get('os') == 'macosx' and data.get('host', {}).get('headless') is True,
                'Metal image report did not use the headless macOS host')
    require(data.get('performance_measured') is False, 'performance was not measured')
    context(data.get('initial_context'), backend=backend)
    context(data.get('closed_context'), closed=True, backend=backend)
    context(data.get('other_closed_context'), closed=True, backend=backend)
    generation = data['initial_context']['generation']
    require(data['closed_context']['generation'] == generation, 'wrong teardown context')
    require(data['other_closed_context']['generation'] != generation, 'missing independent cross-context validation')
    if data.get('require_hardware'):
        require(data['initial_context']['renderer_class'] == 'hardware-reported', 'hardware string requirement not met')
    inventory(data.get('image_symbol_inventory'), IMAGE_SYMBOLS)
    inventory(data.get('surface_symbol_inventory'), shared.SURFACE_SYMBOLS)
    require(exact_int(data.get('native_test_failures'), 0), 'native image suite failed or was not executed')
    require(exact_int(data.get('native_test_cases'), NATIVE_TEST_CASES), 'incorrect native image suite coverage')
    require(data.get('detached_survived_teardown') is True, 'detachment teardown check missing')
    detached_name = data.get('detached_image')
    require(load(directory, detached_name, (8,8)) == pattern(), 'wrong CPU-detached pixels after teardown')
    scenes = data.get('scenes')
    require(isinstance(scenes,list) and all(isinstance(s,dict) for s in scenes) and
            tuple(s.get('name') for s in scenes) == NAMES, 'missing/duplicate/reordered GPU image workflows')
    seen = {detached_name}
    results = []
    for scene in scenes:
        name = scene['name']
        require(exact_int(scene.get('width'),420) and exact_int(scene.get('height'),260), 'wrong scene dimensions')
        require(exact_int(scene.get('intermediate_cpu_panels'),0), 'hidden intermediate CPU panel')
        require(exact_int(scene.get('replay_count'),2) and
                scene.get('original_wrappers_closed_before_replay') is True,
                'resident graph was not replayed after original wrapper closure')
        image = scene.get('image',{})
        require(image.get('storage') == 'gpu' and image.get('backend') == backend and
                image.get('texture_backed') is True and image.get('context_matches') is True and
                exact_int(image.get('context_generation'),generation), 'invalid/foreign GPU image')
        require(exact_int(image.get('width'),8) and exact_int(image.get('height'),8) and
                shared.integer(image.get('unique_id'),1), 'invalid GPU image metadata')
        target = scene.get('target',{})
        require(target.get('storage') == 'gpu' and target.get('backend') == backend and
                exact_int(target.get('native_backend'),shared.BACKEND_IDS[backend]) and target.get('context_matches') is True and
                exact_int(target.get('context_generation'),generation), 'incorrect GPU drawing target')
        require(target.get('target_kind') == 'offscreen' and target.get('origin') == 'top-left' and
                target.get('render_path') == 'sk_surface_new_render_target' and
                exact_int(target.get('width'),420) and exact_int(target.get('height'),260), 'wrong target descriptor')
        require(target.get('color_type') == 'RGBA8888' and target.get('alpha_type') == 'premultiplied' and
                target.get('actual_sample_count') is False and exact_int(target.get('requested_sample_count'),0),
                'wrong format or unverified sample-count claim')
        events = scene.get('reuse_events')
        first = 'upload' if name == 'upload-reuse' else 'gpu-snapshot'
        require(isinstance(events,list) and all(isinstance(e,dict) for e in events) and
                [e.get('kind') for e in events] == [first,'gpu-subset','flush','submit'],
                'resident reuse contains readback/extra transfer or misses its explicit source creation')
        require(exact_int(events[0].get('width'),8) and exact_int(events[0].get('height'),8), 'wrong source size')
        if first == 'upload':
            require(events[0].get('mipmapped_requested') is False and
                    events[0].get('budgeted_requested') is True, 'unexpected upload flags')
        require(all(exact_int(events[1].get(k),v) for k,v in {'x':0,'y':4,'width':3,'height':4}.items()),
                'wrong GPU subset descriptor')
        require(events[-1].get('wait_requested') is False and
                all(not e.get('wait_requested',False) for e in events), 'CPU wait during resident reuse')
        download = scene.get('download_events')
        require(isinstance(download,list) and all(isinstance(e,dict) for e in download) and
                [e.get('kind') for e in download] == ['readback','flush','submit'] and
                download[-1].get('wait_requested') is True, 'output transfer is not an explicit completed readback')
        require(all(exact_int(download[0].get(k),v) for k,v in {'width':420,'height':260,'row_bytes':1680}.items()),
                'incorrect readback layout')
        a,b = scene.get('cpu_image'),scene.get('gpu_image')
        require(isinstance(a,str) and isinstance(b,str) and a != b and a not in seen and b not in seen,
                'reused artifact filenames')
        seen.update((a,b))
        cpu,gpu = load(directory,a,(420,260)),load(directory,b,(420,260))
        samples(cpu); samples(gpu)
        # Same bounded content ROI and image-sampling tolerances as 0.39.
        stats = shared.comparison(cpu,gpu,'images')
        results.append({'name':name,'cpu_image':a,'gpu_image':b,**stats,
                        'known_source_subset_filter_samples':True,
                        'original_wrappers_closed_before_replay':True,'replay_count':2})
    return {'schema_version':1,'stage':data['stage'],'status':'passed','kind':'images','backend':backend,
            'scenes_checked':len(results),'native_test_cases':NATIVE_TEST_CASES,'scenes':results,
            'rendering_verified':True,'resident_replay_readbacks':0,'resident_replay_explicit_cpu_waits':0,
            'detached_image_survived_teardown':True,'renderer':data['initial_context']['renderer'],
            'renderer_class':data['initial_context']['renderer_class'],
            'performance_measured':False,'universal_pixel_identity_claimed':False}


def inspect(prefix):
    directory = prefix.parent
    diagnostic = Path(str(prefix)+'.diagnostic.json')
    output = Path(str(prefix)+'.inspection.json')
    review = Path(str(prefix)+'.review.html')
    try:
        require(diagnostic.stat().st_size <= 4*1024*1024, 'oversized diagnostic report')
        data = json.loads(diagnostic.read_text())
        result = images(data,directory)
    except (ValueError, OSError, KeyError, TypeError, AttributeError):
        # These are generated outputs for this exact prefix, not source images.
        # Avoid leaving a previous successful review beside a failed rerun.
        output.unlink(missing_ok=True); review.unlink(missing_ok=True)
        raise
    rows = []
    for scene in result['scenes']:
        rows.append('<article><h2>'+html.escape(scene['name'])+'</h2><div class="pair">'+
                    ''.join('<figure><img width="420" height="260" src="'+html.escape(scene[key],quote=True)+
                            '"><figcaption>'+title+'</figcaption></figure>'
                            for key,title in [('cpu_image','Independent CPU reference'),('gpu_image','GPU-resident graph; explicit final readback')])+
                    '</div><pre>'+html.escape(json.dumps(scene,indent=2))+'</pre></article>')
    page = ('<!doctype html><meta charset="utf-8"><title>Skia GPU images</title>'
            '<style>body{font:16px system-ui;max-width:1100px;margin:2em auto;padding:0 1em}'
            '.pair{display:flex;gap:1em;flex-wrap:wrap}figure{margin:0}img{max-width:100%;'
            'background:repeating-conic-gradient(#ddd 0% 25%,white 0% 50%) 0/16px 16px}'
            'pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}article{margin-top:2em}</style>'
            '<h1>GPU images — executed workflows</h1><p>Original image, shader, paint, filter, runtime-effect, '
            'and inner-picture wrappers are closed before replay. The retained outer picture is drawn twice '
            'without an explicit CPU wait/readback. Only final output is detached for comparison. '
            'This is not a performance benchmark or a claim of universal pixel identity.</p>'+''.join(rows)+
            '<h2>Inspection</h2><pre>'+html.escape(json.dumps(result,indent=2))+'</pre>'+
            '<h2>Native diagnostic</h2><pre>'+html.escape(json.dumps(data,indent=2))+'</pre>')
    shared.atomic_text(review,page)
    shared.atomic_text(output,json.dumps(result,indent=2)+'\n')
    return result


# Synthetic inspector fixtures below. They are never used by the live doctor.
def fixture_artwork():
    pixels = bytearray(shared.fixture_pixels())
    def rect(x,y,w,h,color):
        for j in range(y,y+h):
            for i in range(x,x+w):
                at=4*(j*420+i); pixels[at:at+4]=bytes(color)
    # Cover the ROI with white, then place a synthetic version of the known
    # source/subset/filter blocks. Similarity checks use identical fake sides.
    rect(24,52,372,182,(255,255,255,255))
    for x,y,w,h,scale_x,scale_y in [(28,64,8,8,18,18),(196,166,8,8,24,7.5)]:
        data=pattern()
        for j in range(h):
            for i in range(w):
                color=data[4*(j*8+i):4*(j*8+i)+4]
                if color[3]:
                    rect(int(x+i*scale_x),int(y+j*scale_y),int(scale_x),int(y+(j+1)*scale_y)-int(y+j*scale_y),color)
    rect(196,64,82,76,(0,0,255,255))
    return bytes(pixels)


def fixture(directory):
    data = {'schema_version':1,'stage':'0.40','kind':'images','backend':'opengl','status':'passed',
            'performance_measured':False,'require_hardware':False,
            'initial_context':shared.fixture_context(), 'closed_context':shared.fixture_context(closed=True),
            'other_closed_context':shared.fixture_context(closed=True,generation=2),
            'image_symbol_inventory':[{'name':n,'available':True} for n in sorted(IMAGE_SYMBOLS)],
            'surface_symbol_inventory':[{'name':n,'available':True} for n in sorted(shared.SURFACE_SYMBOLS)],
            'native_test_failures':0,'native_test_cases':NATIVE_TEST_CASES,
            'detached_survived_teardown':True,'detached_image':'images.detached.png','scenes':[]}
    (directory/data['detached_image']).write_bytes(shared.png_bytes(pattern(),(8,8)))
    for index,name in enumerate(NAMES):
        first={'kind':'upload' if index==0 else 'gpu-snapshot','width':8,'height':8}
        if index==0: first.update(mipmapped_requested=False,budgeted_requested=True)
        scene={'name':name,'width':420,'height':260,'cpu_image':name+'.cpu.png','gpu_image':name+'.gpu.png',
               'original_wrappers_closed_before_replay':True,'intermediate_cpu_panels':0,'replay_count':2,
               'image':{'storage':'gpu','backend':'opengl','texture_backed':True,'context_matches':True,
                        'context_generation':1,'unique_id':index+1,'width':8,'height':8},
               'target':{'storage':'gpu','backend':'opengl','native_backend':0,'context_matches':True,
                         'context_generation':1,'width':420,'height':260,'origin':'top-left',
                         'target_kind':'offscreen','render_path':'sk_surface_new_render_target',
                         'color_type':'RGBA8888','alpha_type':'premultiplied',
                         'actual_sample_count':False,'requested_sample_count':0},
               'reuse_events':[first,{'kind':'gpu-subset','x':0,'y':4,'width':3,'height':4},
                               {'kind':'flush'},{'kind':'submit','wait_requested':False}],
               'download_events':[{'kind':'readback','width':420,'height':260,'row_bytes':1680},
                                  {'kind':'flush'},{'kind':'submit','wait_requested':True}]}
        for key in ('cpu_image','gpu_image'):
            (directory/scene[key]).write_bytes(shared.png_bytes(fixture_artwork()))
        data['scenes'].append(scene)
    return data


def fixture_metal(directory):
    data = fixture(directory)
    data.update(stage='0.41', backend='metal', os='macosx', host={'headless': True})
    data['initial_context'] = shared.fixture_metal_context()
    data['closed_context'] = shared.fixture_metal_context(True)
    data['other_closed_context'] = shared.fixture_metal_context(True, 2)
    for scene in data['scenes']:
        scene['target'].update(backend='metal', native_backend=2)
        scene['image'].update(backend='metal')
    return data


class Checks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='skia-image-inspector-synthetic-')
        self.addCleanup(self.temp.cleanup)
        self.directory=Path(self.temp.name)
        self.data=fixture(self.directory)
    def reject(self,edit):
        edit(self.data)
        with self.assertRaises((ValueError,OSError)):
            images(self.data,self.directory)
    def test_valid(self):
        self.assertEqual(images(self.data,self.directory)['scenes_checked'],2)
    def test_metal_valid(self):
        self.assertEqual(images(fixture_metal(self.directory), self.directory)['backend'], 'metal')
    def test_metal_wrong_target(self):
        self.data = fixture_metal(self.directory)
        self.reject(lambda d:d['scenes'][0]['target'].update(native_backend=0))
    def test_metal_foreign_image_backend(self):
        self.data = fixture_metal(self.directory)
        self.reject(lambda d:d['scenes'][0]['image'].update(backend='opengl'))
    def test_metal_requires_owned_queue(self):
        self.data = fixture_metal(self.directory)
        self.reject(lambda d:d['initial_context'].update(owns_command_queue=False))
    def test_metal_legacy_report_is_not_parity(self):
        self.data = fixture_metal(self.directory)
        self.reject(lambda d:d.update(stage='0.40'))
    def test_metal_must_be_headless(self):
        self.data = fixture_metal(self.directory)
        self.reject(lambda d:d['host'].update(headless=False))
    def test_wrong_stage(self): self.reject(lambda d:d.update(stage='0.39'))
    def test_unavailable(self): self.reject(lambda d:d.update(status='unavailable'))
    def test_failed_native(self): self.reject(lambda d:d.update(native_test_failures=1))
    def test_false_native_count(self): self.reject(lambda d:d.update(native_test_failures=False))
    def test_wrong_coverage(self): self.reject(lambda d:d.update(native_test_cases=0))
    def test_missing_symbol(self): self.reject(lambda d:d['image_symbol_inventory'].pop())
    def test_unresolved_symbol(self): self.reject(lambda d:d['image_symbol_inventory'][0].update(available=False))
    def test_foreign_image(self): self.reject(lambda d:d['scenes'][0]['image'].update(context_generation=2))
    def test_not_texture_backed(self): self.reject(lambda d:d['scenes'][0]['image'].update(texture_backed=False))
    def test_no_affinity_proof(self): self.reject(lambda d:d['scenes'][0]['image'].update(context_matches=False))
    def test_cpu_target(self): self.reject(lambda d:d['scenes'][0]['target'].update(storage='cpu'))
    def test_false_native_backend(self): self.reject(lambda d:d['scenes'][0]['target'].update(native_backend=False))
    def test_wrong_origin(self): self.reject(lambda d:d['scenes'][0]['target'].update(origin='bottom-left'))
    def test_unverified_samples(self): self.reject(lambda d:d['scenes'][0]['target'].update(actual_sample_count=0))
    def test_missing_scene(self): self.reject(lambda d:d['scenes'].pop())
    def test_not_replayed(self): self.reject(lambda d:d['scenes'][0].update(replay_count=1))
    def test_originals_not_closed(self): self.reject(lambda d:d['scenes'][0].update(original_wrappers_closed_before_replay=False))
    def test_hidden_panel(self): self.reject(lambda d:d['scenes'][0].update(intermediate_cpu_panels=1))
    def test_hidden_readback(self): self.reject(lambda d:d['scenes'][0]['reuse_events'].append({'kind':'readback'}))
    def test_reuse_wait(self): self.reject(lambda d:d['scenes'][0]['reuse_events'][-1].update(wait_requested=True))
    def test_wrong_subset(self): self.reject(lambda d:d['scenes'][0]['reuse_events'][1].update(y=0))
    def test_uncompleted_download(self): self.reject(lambda d:d['scenes'][0]['download_events'][-1].update(wait_requested=False))
    def test_bad_stride(self): self.reject(lambda d:d['scenes'][0]['download_events'][0].update(row_bytes=4))
    def test_duplicate_paths(self): self.reject(lambda d:d['scenes'][0].update(gpu_image=d['scenes'][0]['cpu_image']))
    def test_unsafe_path(self): self.reject(lambda d:d['scenes'][0].update(gpu_image='../outside.png'))
    def test_pending_release(self): self.reject(lambda d:d['closed_context'].update(pending_releases=1))
    def test_same_context_tests(self): self.reject(lambda d:d['other_closed_context'].update(generation=1))
    def test_failed_detachment(self): self.reject(lambda d:d.update(detached_survived_teardown=False))
    def test_detached_pixels(self):
        (self.directory/self.data['detached_image']).write_bytes(shared.png_bytes(bytes(256),(8,8)))
        with self.assertRaises(ValueError): images(self.data,self.directory)
    def test_corrupt_png(self):
        path=self.directory/self.data['scenes'][0]['gpu_image'];raw=bytearray(path.read_bytes());raw[-1]^=1;path.write_bytes(raw)
        with self.assertRaises(ValueError): images(self.data,self.directory)
    def test_common_wrong_reference(self):
        p=bytearray(fixture_artwork());at=4*(73*420+37);p[at:at+4]=bytes((0,0,0,255))
        for key in ('cpu_image','gpu_image'):
            (self.directory/self.data['scenes'][0][key]).write_bytes(shared.png_bytes(p))
        with self.assertRaises(ValueError): images(self.data,self.directory)
    def test_software_label_allowed(self):
        self.data['initial_context']['renderer_class']='software'
        self.assertEqual(images(self.data,self.directory)['renderer_class'],'software')
    def test_hardware_requirement(self):
        self.data['require_hardware']=True
        self.reject(lambda d:d['initial_context'].update(renderer_class='software'))
    def test_atomic_review_and_no_stale_success(self):
        prefix=self.directory/'images'
        path=Path(str(prefix)+'.diagnostic.json');path.write_text(json.dumps(self.data))
        inspect(prefix)
        self.assertTrue(Path(str(prefix)+'.review.html').exists())
        self.data['status']='error';path.write_text(json.dumps(self.data))
        with self.assertRaises(ValueError): inspect(prefix)
        self.assertFalse(Path(str(prefix)+'.inspection.json').exists())
        self.assertFalse(Path(str(prefix)+'.review.html').exists())


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
