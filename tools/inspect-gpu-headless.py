#!/usr/bin/env python3
"""Validate raw EGL/GL-interop reports and actual PNGs; self-tests are synthetic.

A successful native EGL context alone is not a Ganesh pass. Combined headless
acceptance additionally rechecks the 33-case surface and 42-case image reports.
No display/window, zero-copy, hardware, or performance conclusion is inferred.
"""
from __future__ import annotations
import argparse
import copy
import html
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent

def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE/filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

shared = module('headless_offscreen', 'inspect-gpu-offscreen.py')
images = module('headless_images', 'inspect-gpu-images.py')
require = shared.require
EGL_NATIVE_CASES = 10
INTEROP_NATIVE_CASES = 32
INTEROP_SYMBOLS = {'gr_backendtexture_new_gl', 'gr_backendtexture_delete', 'sk_image_new_from_texture'}


def exact(value, expected):
    return type(value) is int and value == expected


def envelope(data, kind, cases):
    require(isinstance(data, dict) and exact(data.get('schema_version'), 1) and
            data.get('stage') == '0.43' and data.get('kind') == kind,
            'wrong diagnostic schema/stage/kind')
    require(data.get('status') == 'passed' and data.get('backend') == 'opengl', 'native probe did not pass')
    require(isinstance(data.get('validation_run'), str) and data['validation_run'], 'missing run identity')
    require(isinstance(data.get('architecture'), str) and data['architecture'] and
            isinstance(data.get('racket_version'), str) and data['racket_version'], 'missing execution identity')
    require(data.get('performance_measured') is False, 'performance was not measured')
    require(exact(data.get('native_test_cases'), cases) and exact(data.get('native_test_failures'), 0),
            'native tests missing/failed or coverage differs')


def context(info, *, closed=False, hardware=False):
    shared.context(info, closed=closed)
    if hardware:
        require(info['renderer_class'] == 'hardware-reported', 'hardware string requirement not met')


def egl_context(info, *, closed=False, hardware=False):
    context(info, closed=closed, hardware=hardware)
    require(info.get('provider') == 'egl-owned' and info.get('interface_factory') == 'assembled-desktop-gl',
            'not an owned EGL procedure-table context')
    for field in ('headless', 'display_server_free', 'owns_egl_context', 'owns_egl_display_initialization'):
        require(info.get(field) is True, f'missing EGL ownership/headless field: {field}')
    for field in ('window_created', 'requires_window', 'requires_glx', 'context_sharing'):
        require(info.get(field) is False, f'unexpected window/GLX/sharing claim: {field}')
    require(info.get('egl_platform') in ('surfaceless', 'device') and
            info.get('egl_surface') in ('surfaceless', 'pbuffer'), 'unsupported EGL platform/surface')
    require(isinstance(info.get('egl_version'), str) and info['egl_version'] and
            isinstance(info.get('egl_vendor'), str) and info['egl_vendor'], 'missing native EGL identity')
    require(info.get('egl_place_policy') == 'one-instance/place-per-process', 'missing process initialization policy')
    if info['egl_platform'] == 'device':
        require(shared.integer(info.get('egl_device_index')), 'invalid selected EGL device')
    else:
        require(info.get('egl_device_index') is False, 'surfaceless platform has no device enumeration index')


def profile(info):
    return tuple(info.get(k) for k in ('egl_platform', 'egl_surface', 'egl_device_index', 'egl_vendor', 'egl_version'))


def read_json(path):
    require(path.stat().st_size <= 16*1024*1024, 'oversized diagnostic')
    data = json.loads(path.read_text())
    require(isinstance(data, dict), 'expected diagnostic object')
    return data


def png(directory, name, expected):
    path = shared.image_path(directory, name)
    require(path.resolve().parent == directory.resolve(), 'PNG escaped its report directory')
    require(shared.png(path.read_bytes(), (8,8)) == expected, f'wrong exact pixels: {name}')


def source_pattern():
    return b''.join(bytes(((255,0,0,255) if x < 4 else (0,255,0,255)) if y < 4 else
                         ((0,0,255,255) if x < 4 else (255,255,0,255)))
                    for y in range(8) for x in range(8))


def lifecycle(data, directory):
    envelope(data, 'egl-lifecycle', EGL_NATIVE_CASES)
    require(data.get('os') == 'unix' and data.get('headless') is True and
            data.get('window_created') is False and data.get('display_environment_unset') is True,
            'EGL acceptance requires Linux/no DISPLAY/no WAYLAND_DISPLAY and no window')
    cycles = data.get('cycles')
    require(isinstance(cycles, list) and len(cycles) == 3, 'three EGL cycles required')
    generations = set(); names = set(); profiles = set(); renderers = set()
    for index, cycle in enumerate(cycles):
        require(isinstance(cycle, dict) and exact(cycle.get('index'), index), 'wrong lifecycle index')
        initial, closed = cycle.get('initial_context'), cycle.get('closed_context')
        egl_context(initial, hardware=data.get('require_hardware', False))
        egl_context(closed, closed=True)
        require(initial['generation'] == closed['generation'], 'teardown belongs to another context')
        require(initial['generation'] not in generations, 'context generation reused')
        require(profile(initial) == profile(closed), 'context profile changed during teardown')
        generations.add(initial['generation']); profiles.add(profile(initial)); renderers.add(initial['renderer'])
        t = cycle.get('target', {})
        require(t.get('exact_pixels') is True and t.get('context_matches') is True and
                exact(t.get('native_backend'), 0) and t.get('render_path') == 'sk_surface_new_render_target' and
                t.get('origin') == 'top-left' and exact(t.get('width'),8) and exact(t.get('height'),8) and
                exact(t.get('row_bytes'),32), 'missing actual Ganesh target/readback proof')
        require(cycle.get('encoded_after_teardown') is True, 'CPU image did not survive teardown')
        name = cycle.get('image')
        require(name not in names, 'duplicate lifecycle image')
        png(directory, name, images.pattern()); names.add(name)
    require(len(profiles) == len(renderers) == 1, 'mixed EGL configurations/devices')
    initial = cycles[0]['initial_context']
    return {'schema_version':1, 'stage':'0.43', 'kind':'egl-lifecycle', 'status':'passed',
            'validation_run':data['validation_run'], 'cycles_checked':3, 'native_test_cases':EGL_NATIVE_CASES,
            'ganesh_rendering_verified':True, 'display_environment_unset':True, 'window_created':False,
            'egl_platform':initial['egl_platform'], 'egl_surface':initial['egl_surface'],
            'renderer':initial['renderer'], 'renderer_class':initial['renderer_class'],
            'performance_measured':False}


def interop(data, directory):
    envelope(data, 'gl-interop', INTEROP_NATIVE_CASES)
    initial = data.get('initial_context'); closed = data.get('closed_context'); other = data.get('other_closed_context')
    context(initial, hardware=data.get('require_hardware', False))
    context(closed, closed=True); context(other, closed=True)
    require(initial['generation'] == closed['generation'] and other['generation'] != initial['generation'],
            'missing independent native context tests or wrong teardown')
    shared.inventory(data.get('interop_symbol_inventory'), INTEROP_SYMBOLS)
    w = data.get('workflow')
    require(isinstance(w, dict), 'missing external GL workflow')
    for field in ('host_names_survived_borrow', 'source_deleted_before_copy_readback', 'framebuffer_read_by_host'):
        require(w.get(field) is True, f'missing host ownership check: {field}')
    require(exact(w.get('cpu_validation_readbacks'), 3), 'validation transfer count differs')
    im = w.get('image', {})
    require(im.get('storage') == 'gpu' and im.get('backend') == 'opengl' and
            im.get('texture_backed') is True and im.get('context_matches') is True and
            exact(im.get('context_generation'), initial['generation']) and
            exact(im.get('width'),8) and exact(im.get('height'),8), 'copy is not a valid same-context GPU image')
    files = [w.get(k) for k in ('source_image','framebuffer_image','copy_image')]
    require(all(isinstance(n,str) for n in files) and len(set(files)) == 3, 'missing/duplicate validation images')
    for name, pixels in zip(files, (source_pattern(), bytes((0,0,255,255))*64, source_pattern())):
        png(directory, name, pixels)
    events = data.get('resident_events')
    require(isinstance(events, list) and all(isinstance(e,dict) for e in events), 'missing operation ledger')
    kinds = [e.get('kind') for e in events]
    require(set(kinds) <= {'flush','submit','external-texture-copy','gpu-snapshot',
                          'external-texture-return','external-framebuffer-borrow','external-framebuffer-return'},
            'unexpected operation or hidden CPU readback in resident workflow')
    for kind in ('external-texture-copy','gpu-snapshot','external-texture-return',
                 'external-framebuffer-borrow','external-framebuffer-return'):
        require(kinds.count(kind) == 1, f'missing/duplicate {kind}')
    copy_at, snap_at, returned, borrow_at, last = [kinds.index(k) for k in
        ('external-texture-copy','gpu-snapshot','external-texture-return','external-framebuffer-borrow','external-framebuffer-return')]
    require(copy_at < snap_at < returned < borrow_at < last, 'incorrect borrow/copy order')
    c, b = events[copy_at], events[borrow_at]
    require(c.get('context_verified') is True and c.get('cpu_readback') is False and
            c.get('aliases_source') is False and c.get('owns_external_texture') is False,
            'copy must not adopt/alias/read back the external texture')
    require(b.get('context_verified') is True and b.get('owns_host_framebuffer') is False and
            b.get('owns_external_texture') is False and exact(b.get('stencil_bits'),8) and
            exact(b.get('actual_sample_count'),0), 'external framebuffer contract is not verified')
    require(exact(b.get('color_type'),4), 'wrong external color type')
    for e in (c,b):
        require(exact(e.get('width'),8) and exact(e.get('height'),8) and exact(e.get('format'),0x8058) and
                e.get('origin') == 'top-left', 'wrong external extent/format/origin')
    require(shared.integer(b.get('framebuffer_id'),1) and shared.integer(c.get('texture_id'),1), 'invalid GL name')
    require(events[last].get('attachments_preserved') is True and events[last].get('owns_host_framebuffer') is False,
            'framebuffer attachments not preserved')
    require(events[returned].get('owns_external_texture') is False, 'texture ownership changed')
    # This doctor selects the safe default completion policy at both external
    # return boundaries. That wait is intentional, not a frame/presenter wait.
    for start, end in ((snap_at,returned),(borrow_at,last)):
        submit = [e for e in events[start+1:end] if e.get('kind') == 'submit']
        require(len(submit) == 1 and submit[0].get('wait_requested') is True and
                events[end].get('wait_requested') is True, 'uncompleted external-storage handoff')
    for i,e in enumerate(events):
        if e['kind'] == 'submit':
            require(type(e.get('wait_requested')) is bool and i > 0 and events[i-1]['kind'] == 'flush',
                    'submission must follow flush with an explicit wait choice')
    return {'schema_version':1,'stage':'0.43','kind':'gl-interop','status':'passed',
            'validation_run':data['validation_run'],'native_test_cases':INTEROP_NATIVE_CASES,
            'host_objects_preserved':True,'owned_copy_survived_source_deletion':True,
            'resident_readbacks':0,'explicit_borrow_completion_waits':2,'cpu_validation_readbacks':3,
            'images':files,'renderer':initial['renderer'],'renderer_class':initial['renderer_class'],
            'performance_measured':False,'zero_copy_claimed':False}


def inspect_prefix(prefix):
    data = read_json(Path(str(prefix)+'.diagnostic.json'))
    if data.get('kind') == 'egl-lifecycle': return lifecycle(data,prefix.parent)
    if data.get('kind') == 'gl-interop': return interop(data,prefix.parent)
    raise ValueError('not an EGL or interoperability diagnostic')


def combined(directory):
    names = ('egl-lifecycle','offscreen-egl','images-egl','interop-egl')
    reports = [read_json(directory/(n+'.diagnostic.json')) for n in names]
    identity = lambda d: tuple(d.get(k) for k in ('validation_run','os','architecture','racket_version'))
    require(len({identity(d) for d in reports}) == 1 and reports[0].get('validation_run') == directory.name,
            'headless reports have mixed execution/run identity')
    first_context = reports[0]['cycles'][0]['initial_context']
    for report in reports[1:]:
        require(report.get('host',{}).get('headless') is True and
                report['host'].get('window_created') is False and
                report['host'].get('display_server_free') is True, 'hidden GUI/native-window host')
        for key in ('initial_context','closed_context','other_closed_context'):
            egl_context(report.get(key), closed=key != 'initial_context')
            require(profile(report[key]) == profile(first_context) and
                    report[key]['renderer'] == first_context['renderer'], 'mixed EGL configuration/renderer')
    results = [lifecycle(reports[0],directory), shared.offscreen(reports[1],directory),
               images.images(reports[2],directory), interop(reports[3],directory)]
    return {'schema_version':1,'stage':'0.43','kind':'headless-summary','status':'passed',
            'validation_run':directory.name,'headless_rendering_verified':True,'window_created':False,
            'display_environment_unset':True,'shared_surface_cases':33,'shared_image_cases':42,
            'egl_native_cases':EGL_NATIVE_CASES,'interop_native_cases':INTEROP_NATIVE_CASES,
            'scenes_checked':10,'results':results,'performance_measured':False,
            'presentation_verified':False,'zero_copy_claimed':False}


def publish(prefix, compute):
    paths = [Path(str(prefix)+s) for s in ('.inspection.json','.review.html')]
    for path in paths: path.unlink(missing_ok=True)
    result = compute()
    body = '<!doctype html><meta charset="utf-8"><title>EGL / GL interop validation</title>'
    body += '<style>body{font:16px system-ui;max-width:1100px;margin:2em auto}pre{white-space:pre-wrap}img{image-rendering:pixelated;width:160px}</style>'
    body += '<h1>EGL and external OpenGL — executed validation</h1>'
    body += '<p>External framebuffers are borrowed; texture import makes a GPU-side copy. No ownership adoption or zero-copy promise. CPU validation transfers are explicit; no display pixels or performance are certified.</p>'
    results = result.get('results', [result])
    for item in results:
        for name in item.get('images', []):
            shared.image_path(prefix.parent, name)
            body += '<figure><img src="'+html.escape(name,quote=True)+'"><figcaption>'+html.escape(name)+'</figcaption></figure>'
    if result.get('kind') == 'headless-summary':
        body += '<p>Also review <a href="offscreen-egl.review.html">eight offscreen scenes</a> and <a href="images-egl.review.html">retained-image workflows</a>.</p>'
    body += '<pre>'+html.escape(json.dumps(result,indent=2))+'</pre>'
    shared.atomic_text(paths[1],body)
    shared.atomic_text(paths[0],json.dumps(result,indent=2)+'\n')
    return result


def fixture_context(closed=False, generation=1, egl=True):
    c = shared.fixture_context(closed,generation)
    if egl:
        c.update(provider='egl-owned', interface_factory='assembled-desktop-gl',headless=True,
          display_server_free=True,owns_egl_context=True,owns_egl_display_initialization=True,
          window_created=False,requires_window=False,requires_glx=False,context_sharing=False,
          egl_platform='surfaceless',egl_surface='surfaceless',egl_device_index=False,
          egl_version='1.5',egl_vendor='SYNTHETIC',egl_place_policy='one-instance/place-per-process')
    return c


def base(kind,cases):
    return dict(schema_version=1,stage='0.43',kind=kind,status='passed',backend='opengl',
                validation_run='fixture',os='unix',architecture='x86_64',racket_version='test',
                native_test_cases=cases,native_test_failures=0,performance_measured=False,require_hardware=False)


def fixture_lifecycle(directory):
    data = base('egl-lifecycle',EGL_NATIVE_CASES)
    data.update(headless=True,window_created=False,display_environment_unset=True,cycles=[])
    for i in range(3):
        name=f'egl-{i}.png'; (directory/name).write_bytes(shared.png_bytes(images.pattern(),(8,8)))
        data['cycles'].append(dict(index=i,initial_context=fixture_context(generation=i+1),
            closed_context=fixture_context(True,i+1),encoded_after_teardown=True,image=name,
            target=dict(exact_pixels=True,context_matches=True,native_backend=0,
                        render_path='sk_surface_new_render_target',origin='top-left',width=8,height=8,row_bytes=32)))
    return data


def fixture_interop(directory):
    d=base('gl-interop',INTEROP_NATIVE_CASES)
    common=dict(width=8,height=8,format=0x8058,origin='top-left',context_verified=True,owns_external_texture=False)
    d.update(initial_context=fixture_context(),closed_context=fixture_context(True),
             other_closed_context=fixture_context(True,2),
             host=dict(headless=True,window_created=False,display_server_free=True),
             interop_symbol_inventory=[dict(name=n,available=True) for n in sorted(INTEROP_SYMBOLS)],
             workflow=dict(source_image='host-source.png',framebuffer_image='host-fbo.png',copy_image='owned-copy.png',
               host_names_survived_borrow=True,source_deleted_before_copy_readback=True,framebuffer_read_by_host=True,
               cpu_validation_readbacks=3,image=dict(storage='gpu',backend='opengl',texture_backed=True,
                                                   context_matches=True,context_generation=1,width=8,height=8)),
             resident_events=[dict(kind='flush'),dict(kind='submit',wait_requested=False),
                dict(common,kind='external-texture-copy',texture_id=1,cpu_readback=False,aliases_source=False),
                dict(kind='gpu-snapshot',width=8,height=8),dict(kind='flush'),dict(kind='submit',wait_requested=True),
                dict(kind='external-texture-return',owns_external_texture=False,wait_requested=True),
                dict(kind='flush'),dict(kind='submit',wait_requested=False),
                dict(common,kind='external-framebuffer-borrow',framebuffer_id=2,stencil_bits=8,actual_sample_count=0,color_type=4,owns_host_framebuffer=False),
                dict(kind='flush'),dict(kind='submit',wait_requested=True),
                dict(kind='external-framebuffer-return',attachments_preserved=True,owns_host_framebuffer=False,wait_requested=True)])
    for key, pixels in zip(('source_image','framebuffer_image','copy_image'),
                           (source_pattern(),bytes((0,0,255,255))*64,source_pattern())):
        (directory/d['workflow'][key]).write_bytes(shared.png_bytes(pixels,(8,8)))
    return d


def fixture_combined(directory):
    d=fixture_lifecycle(directory); inter=fixture_interop(directory)
    # The legacy fixture builders use overlapping detached.png names. Rename
    # all fixture PNGs and references before copying into the combined directory.
    def legacy(builder,prefix,kind):
        with tempfile.TemporaryDirectory() as tmp:
            source=Path(tmp); result=builder(source)
            mapping={p.name:prefix+'.'+p.name for p in source.glob('*.png')}
            def rewrite(v):
                if isinstance(v,str): return mapping.get(v,v)
                if isinstance(v,list): return [rewrite(x) for x in v]
                if isinstance(v,dict): return {k:rewrite(x) for k,x in v.items()}
                return v
            result=rewrite(result)
            for p in source.glob('*.png'): (directory/mapping[p.name]).write_bytes(p.read_bytes())
        result.update(stage='0.41',native_test_cases=33 if kind=='offscreen' else 42,
                      host=dict(headless=True,window_created=False,display_server_free=True))
        for k in ('initial_context','closed_context','other_closed_context'):
            result[k]=fixture_context(k!='initial_context',2 if k=='other_closed_context' else 1)
        return result
    off=legacy(shared.fixture,'off','offscreen'); im=legacy(images.fixture,'im','images')
    reports=[d,off,im,inter]
    for name,report in zip(('egl-lifecycle','offscreen-egl','images-egl','interop-egl'),reports):
        report.update(validation_run=directory.name,os='unix',architecture='x86_64',racket_version='test')
        (directory/(name+'.diagnostic.json')).write_text(json.dumps(report))
    return reports


class Checks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.egl=fixture_lifecycle(self.root);self.gl=fixture_interop(self.root)
    def tearDown(self): self.temp.cleanup()
    def reject_egl(self,change):
        change(self.egl)
        with self.assertRaises((ValueError,KeyError,TypeError)): lifecycle(self.egl,self.root)
    def reject_gl(self,change):
        change(self.gl)
        with self.assertRaises((ValueError,KeyError,TypeError)): interop(self.gl,self.root)
    def test_valid_egl(self): self.assertTrue(lifecycle(self.egl,self.root)['ganesh_rendering_verified'])
    def test_valid_interop(self): self.assertTrue(interop(self.gl,self.root)['host_objects_preserved'])
    def test_wrong_stage(self): self.reject_egl(lambda d:d.update(stage='0.42'))
    def test_initialization_alone_is_insufficient(self): self.reject_egl(lambda d:d.update(cycles=[]))
    def test_live_suite_failure(self): self.reject_egl(lambda d:d.update(native_test_failures=1))
    def test_false_count(self): self.reject_gl(lambda d:d.update(native_test_failures=False))
    def test_wrong_coverage(self): self.reject_gl(lambda d:d.update(native_test_cases=29))
    def test_display_present(self): self.reject_egl(lambda d:d.update(display_environment_unset=False))
    def test_gui_fallback(self): self.reject_egl(lambda d:d['cycles'][0]['initial_context'].update(window_created=True))
    def test_glx_interface(self): self.reject_egl(lambda d:d['cycles'][0]['initial_context'].update(interface_factory='native'))
    def test_foreign_display_ownership(self): self.reject_egl(lambda d:d['cycles'][0]['initial_context'].update(owns_egl_display_initialization=False))
    def test_unsupported_profile(self): self.reject_egl(lambda d:d['cycles'][0]['initial_context'].update(egl_platform='default'))
    def test_mixed_profile(self): self.reject_egl(lambda d:d['cycles'][1]['initial_context'].update(egl_surface='pbuffer'))
    def test_wrong_place_policy(self): self.reject_egl(lambda d:d['cycles'][0]['initial_context'].update(egl_place_policy='shared'))
    def test_reused_generation(self): self.reject_egl(lambda d:d['cycles'][1]['initial_context'].update(generation=1))
    def test_teardown_leak(self): self.reject_egl(lambda d:d['cycles'][0]['closed_context'].update(pending_releases=1))
    def test_cpu_target(self): self.reject_egl(lambda d:d['cycles'][0]['target'].update(render_path='raster'))
    def test_false_native_backend(self): self.reject_egl(lambda d:d['cycles'][0]['target'].update(native_backend=False))
    def test_orientation(self): self.reject_egl(lambda d:d['cycles'][0]['target'].update(origin='bottom-left'))
    def test_encoding_before_teardown(self): self.reject_egl(lambda d:d['cycles'][0].update(encoded_after_teardown=False))
    def test_missing_run(self): self.reject_gl(lambda d:d.update(validation_run=False))
    def test_missing_symbol(self): self.reject_gl(lambda d:d['interop_symbol_inventory'].pop())
    def test_unresolved_symbol(self): self.reject_gl(lambda d:d['interop_symbol_inventory'][0].update(available=False))
    def test_host_names_deleted(self): self.reject_gl(lambda d:d['workflow'].update(host_names_survived_borrow=False))
    def test_copy_alias(self): self.reject_gl(lambda d:d['resident_events'][2].update(aliases_source=True))
    def test_adoption(self): self.reject_gl(lambda d:d['resident_events'][2].update(owns_external_texture=True))
    def test_cpu_readback(self): self.reject_gl(lambda d:d['resident_events'].append(dict(kind='readback')))
    def test_uncompleted_handoff(self): self.reject_gl(lambda d:d['resident_events'][5].update(wait_requested=False))
    def test_ordering(self): self.reject_gl(lambda d:d['resident_events'].reverse())
    def test_attachment_replaced(self): self.reject_gl(lambda d:d['resident_events'][-1].update(attachments_preserved=False))
    def test_wrong_extent(self): self.reject_gl(lambda d:d['resident_events'][2].update(width=9))
    def test_wrong_format(self): self.reject_gl(lambda d:d['resident_events'][2].update(format=0x881A))
    def test_native_sample_bool(self): self.reject_gl(lambda d:d['resident_events'][9].update(actual_sample_count=False))
    def test_foreign_image(self): self.reject_gl(lambda d:d['workflow']['image'].update(context_generation=2))
    def test_copy_not_gpu(self): self.reject_gl(lambda d:d['workflow']['image'].update(texture_backed=False))
    def test_source_not_deleted(self): self.reject_gl(lambda d:d['workflow'].update(source_deleted_before_copy_readback=False))
    def test_no_second_context(self): self.reject_gl(lambda d:d['other_closed_context'].update(generation=1))
    def test_duplicate_pngs(self): self.reject_gl(lambda d:d['workflow'].update(copy_image='host-source.png'))
    def test_unsafe_png(self): self.reject_gl(lambda d:d['workflow'].update(copy_image='../outside.png'))
    def test_corrupt_png(self):
        (self.root/'owned-copy.png').write_bytes(b'bad')
        with self.assertRaises(ValueError): interop(self.gl,self.root)
    def test_exact_source_not_just_pairwise_similarity(self):
        for p in ('owned-copy.png','host-source.png'): (self.root/p).write_bytes(shared.png_bytes(bytes(256),(8,8)))
        with self.assertRaises(ValueError): interop(self.gl,self.root)
    def test_software_is_labelled(self):
        self.gl['initial_context']['renderer_class']='software'
        self.assertEqual(interop(self.gl,self.root)['renderer_class'],'software')
    def test_hardware_is_not_inferred(self):
        self.gl['initial_context']['renderer_class']='software'
        self.reject_gl(lambda d:d.update(require_hardware=True))
    def test_failure_clears_stale_success(self):
        prefix=self.root/'test'
        for ext in ('.inspection.json','.review.html'): Path(str(prefix)+ext).write_text('stale')
        with self.assertRaises(ValueError): publish(prefix,lambda:(_ for _ in ()).throw(ValueError('bad')))
        self.assertFalse(Path(str(prefix)+'.inspection.json').exists())
        self.assertFalse(Path(str(prefix)+'.review.html').exists())
    def test_review_escapes_renderer(self):
        self.gl['initial_context']['renderer']='<script>bad</script>'
        prefix=self.root/'test';publish(prefix,lambda:interop(self.gl,self.root))
        self.assertNotIn('<script>',Path(str(prefix)+'.review.html').read_text())
    def test_combined_rechecks_native_reports_and_pngs(self):
        fixture_combined(self.root)
        self.assertEqual(combined(self.root)['scenes_checked'],10)
    def test_combined_mixed_run(self):
        fixture_combined(self.root)
        p=self.root/'images-egl.diagnostic.json';d=read_json(p);d['validation_run']='other';p.write_text(json.dumps(d))
        with self.assertRaises(ValueError): combined(self.root)
    def test_combined_ignores_forged_success(self):
        fixture_combined(self.root)
        (self.root/'offscreen-egl.inspection.json').write_text('{"status":"passed"}')
        p=self.root/'offscreen-egl.diagnostic.json';d=read_json(p);d['native_test_failures']=1;p.write_text(json.dumps(d))
        with self.assertRaises(ValueError): combined(self.root)
    def test_combined_no_hidden_gui(self):
        fixture_combined(self.root)
        p=self.root/'interop-egl.diagnostic.json';d=read_json(p);d['host']['headless']=False;p.write_text(json.dumps(d))
        with self.assertRaises(ValueError): combined(self.root)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--self-test',action='store_true');group.add_argument('--probe-prefix',type=Path);group.add_argument('--directory',type=Path)
    args=parser.parse_args()
    if args.self_test:
        return 0 if unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks)).wasSuccessful() else 1
    prefix=args.probe_prefix or args.directory/'headless'
    try:
        result=publish(prefix,lambda:inspect_prefix(prefix) if args.probe_prefix else combined(args.directory))
        print(json.dumps(result,indent=2));return 0
    except (OSError,ValueError,KeyError,TypeError) as e:
        print(f'Inspection FAILED: {e}');return 1

if __name__ == '__main__': raise SystemExit(main())
