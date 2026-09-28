#!/usr/bin/env python3
"""Inspect presenter submission/lifetime reports, not physical display pixels.

All self-test data is synthetic. A successful native report establishes that the
selected backend wrapped a real target, submitted rendering, and requested
presentation in order. It does not establish monitor contents or a frame rate.
"""
from __future__ import annotations
import argparse
import copy
import html
import json
import math
from pathlib import Path
import tempfile
import unittest

NATIVE_TEST_CASES = 28
BACKENDS = {'opengl': 0, 'metal': 2}
MAX_REPORT_BYTES = 8 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(value, minimum=0):
    return type(value) is int and minimum <= value <= 0x7fffffff


def number(value, positive=False):
    return type(value) in (int, float) and math.isfinite(value) and (value > 0 if positive else value >= 0)


def load(path):
    require(path.stat().st_size <= MAX_REPORT_BYTES, 'diagnostic exceeds size limit')
    value = json.loads(path.read_text(encoding='utf-8'))
    require(isinstance(value, dict), 'diagnostic must be an object')
    return value


def context(info, backend, *, closed=False, generation=None):
    require(isinstance(info, dict), 'missing native context')
    require(info.get('backend') == backend, 'context backend differs')
    require(type(info.get('native_backend')) is int and info['native_backend'] == BACKENDS[backend],
            'context native backend differs')
    require(integer(info.get('generation'), 1), 'invalid context generation')
    if generation is not None:
        require(info['generation'] == generation, 'context generation changed')
    require(info.get('state') == ('closed' if closed else 'ready'), 'context state differs')
    for key in ('live_children', 'pending_releases', 'failed_releases'):
        require(type(info.get(key)) is int and info[key] == 0, f'context has nonzero/invalid {key}')
    require(info.get('binding_package') == '3.119.1' and info.get('native_version') == '119.0',
            'native version differs from pinned ABI')
    require(isinstance(info.get('renderer'), str) and info['renderer'].strip(), 'missing renderer identity')
    require(info.get('renderer_class') in ('hardware-reported', 'software', 'unclassified'),
            'missing renderer classification')
    if backend == 'metal':
        require(info.get('provider') == 'metal-owned' and info.get('owns_command_queue') is True,
                'Metal must own its Ganesh command queue')
        require(info.get('requires_gl_context') is False, 'Metal incorrectly uses a GL context')
    return info['generation']


def presenter(info, backend, generation, *, closed=False):
    require(isinstance(info, dict), 'missing presenter state')
    require(info.get('backend') == backend and info.get('state') == ('closed' if closed else 'ready'),
            'presenter did not become ready/closed')
    require(info.get('visible_pixels_verified') is False and info.get('performance_measured') is False,
            'unsupported visible-pixel or performance claim')
    require(info.get('redraw_queued') is False, 'unconsumed redraw request')
    require(info.get('shutdown_requested') is closed, 'presenter shutdown state differs')
    require(info.get('last_error') is False, 'unexpected presenter error')
    for key in ('target_generation', 'frames_acquired', 'presents_requested', 'frames_skipped', 'frames_cancelled'):
        require(integer(info.get(key)), f'invalid presenter count {key}')
    require(info['frames_cancelled'] == 0, 'normal diagnostic unexpectedly cancelled a frame')
    adapter = info.get('adapter')
    require(isinstance(adapter, dict), 'missing adapter report')
    context(adapter.get('context'), backend, closed=closed, generation=generation)
    require(type(adapter.get('live_drawables')) is int and adapter['live_drawables'] == 0,
            'drawable references leaked')
    if backend == 'metal':
        require(adapter.get('presentation_path') == 'CAMetalLayer/same-Ganesh-queue',
                'Metal does not present on the Ganesh queue')
        require(type(adapter.get('quarantined_frames')) is int and adapter['quarantined_frames'] == 0,
                'quarantined native frame')
        require(adapter.get('layer_closed') is closed, 'Metal layer teardown differs')
        require(type(adapter.get('pending_presentation_buffers')) is int
                and adapter['pending_presentation_buffers'] == (0 if closed else 1),
                'Metal completion references are not bounded/retired')
        require(adapter.get('acquisition_may_block') is True, 'drawable acquisition blocking hidden')
        require(adapter.get('presents_requested') == info['presents_requested'], 'native present count differs')
    else:
        require(adapter.get('presentation_path') == 'host-framebuffer/swap-buffers', 'wrong GL presentation path')
        require(adapter.get('owns_host_framebuffer') is False, 'host framebuffer ownership was adopted')


def target(info, backend, generation, pw, ph):
    require(isinstance(info, dict), 'missing actual target description')
    require(info.get('backend') == backend and type(info.get('native_backend')) is int
            and info['native_backend'] == BACKENDS[backend], 'target backend differs')
    require(info.get('storage') == 'gpu' and info.get('context_matches') is True,
            'target is not same-context GPU storage')
    require(type(info.get('context_generation')) is int and info['context_generation'] == generation, 'foreign target context')
    require(info.get('width') == pw and info.get('height') == ph, 'target size differs from frame')
    require(info.get('render_path') == 'sk_surface_new_backend_render_target', 'not a wrapped presentation target')
    samples = info.get('actual_sample_count')
    require(integer(samples) and samples <= 64, 'invalid actual sample count')
    if backend == 'metal':
        require(info.get('target_kind') == 'metal-drawable' and info.get('origin') == 'top-left',
                'wrong Metal target kind/origin')
        require(info.get('metal_pixel_format') == 80 and info.get('pixel_format') == 'BGRA8Unorm'
                and info.get('color_type') == 'BGRA8888', 'wrong Metal drawable format')
        require(info.get('framebuffer_only') is True and info.get('color_space') == 'sRGB',
                'Metal framebuffer/color-space contract differs')
        require(samples == 1 and type(info.get('texture_sample_count')) is int
                and info['texture_sample_count'] == 1, 'unexpected drawable multisampling')
        require(info.get('presentation_path') == 'CAMetalLayer/same-Ganesh-queue', 'wrong Metal presentation path')
        require(isinstance(info.get('target_identity'), str) and info['target_identity'], 'missing layer identity')
    else:
        require(info.get('target_kind') == 'host-framebuffer' and info.get('origin') == 'bottom-left',
                'wrong GL target kind/origin')
        require(info.get('double_buffered') is True, 'GL host is not double buffered')
        fbo = info.get('framebuffer_id')
        require(integer(fbo) and type(info.get('target_identity')) is int and info['target_identity'] == fbo,
                'host FBO identity missing or fabricated')
        bits = info.get('color_bits')
        require(bits in ([8, 8, 8, 0], [8, 8, 8, 8]) and info.get('component_type') == 0x8c17,
                'unsupported actual GL component format')
        encoding = info.get('color_encoding')
        require(encoding in (0x2601, 0x8c40), 'unsupported actual GL color encoding')
        expected = {(0x2601, 0): 0x8051, (0x2601, 8): 0x8058,
                    (0x8c40, 0): 0x8c41, (0x8c40, 8): 0x8c43}[encoding, bits[3]]
        require(info.get('format') == expected and info.get('color_type') == (5 if bits[3] == 0 else 4),
                'GL format does not match its queried components')
        require(integer(info.get('stencil_bits')), 'invalid stencil count')
        require(info.get('draw_buffer') in (0x0405, 0x0402) if fbo == 0 else
                integer(info.get('draw_buffer')) and 0x8ce0 <= info['draw_buffer'] <= 0x8cff,
                'wrong actual host draw buffer')
        require(info.get('presentation_path') == 'host-framebuffer/swap-buffers', 'wrong GL presentation path')


def inspect(report):
    require(type(report.get('schema_version')) is int and report['schema_version'] == 1 and report.get('stage') == '0.42'
            and report.get('kind') == 'presentation' and report.get('status') == 'passed',
            'no successful 0.42 presenter diagnostic')
    backend = report.get('backend')
    require(backend in BACKENDS, 'unknown presentation backend')
    require(report.get('os') in ('macosx', 'unix', 'windows'), 'invalid host OS')
    require(isinstance(report.get('architecture'), str) and report['architecture'], 'missing architecture')
    require(isinstance(report.get('racket_version'), str) and report['racket_version'], 'missing Racket version')
    run = report.get('validation_run')
    require(isinstance(run, str) and run and len(run) < 256, 'missing validation run identity')
    require(report.get('eventspace_handler_checked') is True, 'eventspace ownership not checked')
    require(type(report.get('native_test_cases')) is int and report['native_test_cases'] == NATIVE_TEST_CASES,
            'wrong executable native suite coverage')
    require(type(report.get('native_test_failures')) is int and report['native_test_failures'] == 0,
            'native presenter suite failed')
    require(report.get('visible_pixels_verified') is False and report.get('manual_review_required') is True
            and report.get('performance_measured') is False, 'unsupported physical-display or performance claim')
    if backend == 'metal': require(report['os'] == 'macosx', 'Metal requires macOS')
    windows = report.get('windows')
    require(isinstance(windows, list) and len(windows) == 2, 'two simultaneous windows required')
    generations, rendered, total_frames = set(), [], 0
    for wi, window in enumerate(windows):
        require(type(window.get('index')) is int and window['index'] == wi, 'duplicate/out-of-order window')
        initial = window.get('initial_context')
        cg = context(initial, backend)
        require(cg not in generations, 'windows unexpectedly share a native context')
        generations.add(cg)
        if report.get('require_hardware') is True:
            require(initial['renderer_class'] == 'hardware-reported', 'hardware-reported renderer required')
        frames = window.get('frames')
        require(isinstance(frames, list) and len(frames) == 3, 'three resized frames per window required')
        extents, old_gen = set(), 0
        for fi, record in enumerate(frames, 1):
            require(record.get('result') == 'present-requested', 'a skipped/cancelled frame is not presentation')
            require(record.get('frame_expired') is True and record.get('canvas_expired') is True,
                    'borrowed frame/canvas did not expire')
            frame = record.get('frame')
            require(isinstance(frame, dict) and frame.get('backend') == backend, 'wrong frame backend')
            pw, ph = frame.get('pixel_width'), frame.get('pixel_height')
            lw, lh = frame.get('logical_width'), frame.get('logical_height')
            require(integer(pw, 1) and integer(ph, 1) and number(lw, True) and number(lh, True), 'invalid frame extent')
            require(frame.get('visible') is True and frame.get('drawable') is True, 'presented hidden/zero target')
            for axis, p, logical in (('x', pw, lw), ('y', ph, lh)):
                scale = frame.get('scale_'+axis)
                require(number(scale, True) and math.isclose(scale, p/logical, rel_tol=1e-9), 'wrong logical-to-pixel scale')
            require(type(frame.get('frame_index')) is int and frame['frame_index'] == fi, 'frame index differs')
            gen = frame.get('target_generation')
            require(integer(gen, 1) and gen > old_gen, 'resize failed to advance target generation')
            old_gen = gen
            extents.add((pw, ph))
            target(frame.get('target'), backend, cg, pw, ph)
            events = record.get('io_events')
            require(isinstance(events, list) and [x.get('kind') for x in events] == ['flush','submit','present-request'],
                    'unexpected transfer/wait or incorrect submit/present ordering')
            require(all(x.get('wait_requested', False) is False for x in events)
                    and events[1].get('wait_requested') is False and events[2].get('wait_requested') is False,
                    'normal frame requested CPU completion')
            require(events[2].get('backend') == backend and events[2].get('method') ==
                    ('swap-buffers' if backend == 'opengl' else 'same-queue-command-buffer'), 'wrong presentation request')
            after = record.get('after_frame')
            presenter(after, backend, cg)
            require(after['frames_acquired'] == fi and after['presents_requested'] == fi
                    and after['target_generation'] == gen, 'presenter counts differ from recorded frames')
            require(after.get('last_frame') == dict(frame, result='present-requested'), 'last-frame snapshot differs')
            total_frames += 1
        require(len(extents) == 3, 'resize diagnostic reused the same extent')
        closed = window.get('closed_presenter')
        presenter(closed, backend, cg, closed=True)
        require(closed['presents_requested'] == 3 and closed['frames_acquired'] == 3, 'closure lost presentation counts')
        rendered.append({'window':wi, 'context_generation':cg, 'renderer':initial['renderer'],
                         'renderer_class':initial['renderer_class'], 'pixel_extents':sorted(extents)})
    return {'schema_version':1, 'stage':'0.42', 'status':'passed', 'kind':'presentation',
            'backend':backend, 'validation_run':run, 'windows_checked':2, 'frames_checked':total_frames,
            'native_test_cases':NATIVE_TEST_CASES, 'windows':rendered,
            'submission_order_verified':True, 'frame_readbacks':0, 'frame_explicit_cpu_waits':0,
            'expired_frames_verified':True, 'teardown_verified':True,
            'visible_pixels_verified':False, 'metal_presentation_verified':False,
            'manual_review_required':True, 'performance_measured':False}


def review(report):
    return ('<!doctype html><meta charset="utf-8"><title>Skia 0.42 presenter review</title>'
            '<style>body{font:16px system-ui;max-width:1000px;margin:2em auto;padding:0 1em}'
            'pre{white-space:pre-wrap;overflow-wrap:anywhere}strong{font-weight:700}</style>'
            '<h1>Window presentation — submission and lifetime checks</h1>'
            '<p><strong>This is not a screenshot or monitor-pixel verification.</strong> '
            'The diagnostic wraps the actual host framebuffer or CAMetalDrawable texture, '
            'draws with the ordinary canvas API, submits, then requests presentation. '
            'It does not read back normal frames or wait for their completion.</p>'
            '<p>Run <code>racket examples/gpu-presenters.rkt --backend both</code> on macOS '
            '(use <code>--backend opengl</code> elsewhere). Inspect corner colors/orientation, '
            'resize, minimize/restore, move between displays, and close one window while the other stays usable. '
            'A nil drawable is a skip; drawable-pool acquisition can block. Aborted Metal frames '
            'may synchronously complete for safe cleanup; that is not the normal frame path.</p><pre>'
            + html.escape(json.dumps(report, indent=2)) + '</pre>')


def publish(prefix, producer):
    outputs = [Path(str(prefix)+'.inspection.json'), Path(str(prefix)+'.review.html')]
    # A failed reinspection must not leave stale success beside failed input.
    for p in outputs: p.unlink(missing_ok=True)
    report = producer()
    data = [json.dumps(report, indent=2)+'\n', review(report)]
    temporary = []
    try:
        prefix.parent.mkdir(parents=True, exist_ok=True)
        for dest, text in zip(outputs, data):
            with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=dest.parent, delete=False) as f:
                temporary.append(Path(f.name)); f.write(text)
        for src, dest in zip(temporary, outputs): src.replace(dest)
    except BaseException:
        for dest in outputs: dest.unlink(missing_ok=True)
        raise
    finally:
        for src in temporary: src.unlink(missing_ok=True)
    return report


def inspect_directory(directory):
    gl = load(directory/'presentation-opengl.diagnostic.json')
    selected = [gl]
    if gl.get('os') == 'macosx': selected.append(load(directory/'presentation-metal.diagnostic.json'))
    summaries = [inspect(r) for r in selected]
    for key in ('validation_run','os','architecture','racket_version'):
        require(len({r.get(key) for r in selected}) == 1, f'mixed {key} in combined reports')
    require(gl['validation_run'] == directory.name, 'directory differs from run identity')
    require([r['backend'] for r in selected] == (['opengl','metal'] if gl['os']=='macosx' else ['opengl']),
            'combined reports are mislabelled')
    return {'schema_version':1, 'stage':'0.42','status':'passed','kind':'presentation-summary',
            'validation_run':gl['validation_run'],'backends':summaries,
            'submission_order_verified':True, 'frame_readbacks':0,'frame_explicit_cpu_waits':0,
            'visible_pixels_verified':False,'metal_presentation_verified':False,
            'manual_review_required':True,'performance_measured':False}


def fixture(backend='metal'):
    def ctx(g, closed=False):
        return dict(backend=backend,native_backend=BACKENDS[backend],generation=g,
                    state='closed' if closed else 'ready',live_children=0,pending_releases=0,failed_releases=0,
                    binding_package='3.119.1',native_version='119.0',renderer='Synthetic device',
                    renderer_class='hardware-reported',provider='metal-owned' if backend=='metal' else 'racket-gl',
                    owns_command_queue=backend=='metal',requires_gl_context=backend=='opengl')
    def state(g, frame, fi, closed=False):
        adapter = dict(context=ctx(g,closed),live_drawables=0)
        if backend=='metal':
            adapter.update(presentation_path='CAMetalLayer/same-Ganesh-queue',quarantined_frames=0,
                           layer_closed=closed,acquisition_may_block=True,presents_requested=fi,
                           pending_presentation_buffers=0 if closed else 1)
        else: adapter.update(presentation_path='host-framebuffer/swap-buffers',owns_host_framebuffer=False)
        return dict(backend=backend,state='closed' if closed else 'ready',target_generation=fi,
                    frames_acquired=fi,presents_requested=fi,frames_skipped=0,frames_cancelled=0,
                    redraw_queued=False,shutdown_requested=closed,last_frame=dict(frame,result='present-requested'),
                    last_error=False,adapter=adapter,visible_pixels_verified=False,performance_measured=False)
    windows=[]
    for wi in range(2):
        g=wi+23; frames=[]
        for fi,(pw,ph) in enumerate(((1040,644),(1280,764),(1120,684)),1):
            t=dict(backend=backend,native_backend=BACKENDS[backend],context_matches=True,
                   context_generation=g,storage='gpu',width=pw,height=ph,
                   render_path='sk_surface_new_backend_render_target')
            if backend=='metal':
                t.update(target_kind='metal-drawable',origin='top-left',color_type='BGRA8888',
                         pixel_format='BGRA8Unorm',metal_pixel_format=80,framebuffer_only=True,
                         color_space='sRGB',actual_sample_count=1,texture_sample_count=1,
                         presentation_path='CAMetalLayer/same-Ganesh-queue',target_identity=f'layer-{wi}')
            else:
                t.update(target_kind='host-framebuffer',origin='bottom-left',color_type=4,
                         color_bits=[8,8,8,8],component_type=0x8c17,color_encoding=0x2601,
                         format=0x8058,framebuffer_id=0,target_identity=0,draw_buffer=0x0405,
                         double_buffered=True,stencil_bits=8,actual_sample_count=0,
                         presentation_path='host-framebuffer/swap-buffers')
            f=dict(backend=backend,pixel_width=pw,pixel_height=ph,logical_width=pw/2,logical_height=ph/2,
                   scale_x=2.,scale_y=2.,drawable=True,visible=True,target_generation=fi,frame_index=fi,target=t)
            frames.append(dict(result='present-requested',frame=f,frame_expired=True,canvas_expired=True,
                               after_frame=state(g,f,fi),io_events=[dict(kind='flush'),dict(kind='submit',wait_requested=False),
                                   dict(kind='present-request',backend=backend,wait_requested=False,
                                        method='swap-buffers' if backend=='opengl' else 'same-queue-command-buffer')]))
        windows.append(dict(index=wi,initial_context=ctx(g),frames=frames,closed_presenter=state(g,f,3,True)))
    return dict(schema_version=1,stage='0.42',kind='presentation',backend=backend,status='passed',
                os='macosx',architecture='aarch64',racket_version='synthetic',validation_run='synthetic-run',
                eventspace_handler_checked=True,native_test_cases=NATIVE_TEST_CASES,native_test_failures=0,
                require_hardware=False,windows=windows,visible_pixels_verified=False,
                manual_review_required=True,performance_measured=False)


class Checks(unittest.TestCase):
    def setUp(self): self.r=fixture()
    def frame(self): return self.r['windows'][0]['frames'][0]
    def reject(self):
        with self.assertRaises((ValueError,KeyError,TypeError)): inspect(self.r)
    def test_metal_valid(self): self.assertEqual(inspect(self.r)['frames_checked'],6)
    def test_gl_valid(self): self.assertEqual(inspect(fixture('opengl'))['windows_checked'],2)
    def test_failed_diagnostic(self): self.r['status']='error'; self.reject()
    def test_old_stage(self): self.r['stage']='0.41'; self.reject()
    def test_missing_run(self): self.r['validation_run']=False; self.reject()
    def test_wrong_native_coverage(self): self.r['native_test_cases']=25; self.reject()
    def test_false_failure_count(self): self.r['native_test_failures']=False; self.reject()
    def test_failed_native_test(self): self.r['native_test_failures']=1; self.reject()
    def test_handler_not_checked(self): self.r['eventspace_handler_checked']=False; self.reject()
    def test_physical_pixel_claim(self): self.r['visible_pixels_verified']=True; self.reject()
    def test_performance_claim(self): self.r['performance_measured']=True; self.reject()
    def test_one_window_is_insufficient(self): self.r['windows'].pop(); self.reject()
    def test_same_context_is_not_independent(self): self.r['windows'][1]['initial_context']['generation']=23; self.reject()
    def test_missing_frame(self): self.r['windows'][0]['frames'].pop(); self.reject()
    def test_expired_frame(self): self.frame()['frame_expired']=False; self.reject()
    def test_expired_canvas(self): self.frame()['canvas_expired']=False; self.reject()
    def test_skipped_frame_not_pass(self): self.frame()['result']='skipped'; self.reject()
    def test_zero_extent(self): self.frame()['frame']['pixel_width']=0; self.reject()
    def test_scale(self): self.frame()['frame']['scale_x']=1.; self.reject()
    def test_non_finite_scale(self): self.frame()['frame']['scale_x']=float('nan'); self.reject()
    def test_generation_not_advanced(self): self.r['windows'][0]['frames'][1]['frame']['target_generation']=1; self.reject()
    def test_target_backend(self): self.frame()['frame']['target']['native_backend']=0; self.reject()
    def test_target_sample_bool(self): self.frame()['frame']['target']['actual_sample_count']=True; self.reject()
    def test_target_context(self): self.frame()['frame']['target']['context_generation']=99; self.reject()
    def test_target_size(self): self.frame()['frame']['target']['width']=100; self.reject()
    def test_framebuffer_only(self): self.frame()['frame']['target']['framebuffer_only']=False; self.reject()
    def test_wrong_format(self): self.frame()['frame']['target']['metal_pixel_format']=81; self.reject()
    def test_wrong_origin(self): self.frame()['frame']['target']['origin']='bottom-left'; self.reject()
    def test_hidden_readback(self): self.frame()['io_events'].insert(1,dict(kind='readback')); self.reject()
    def test_wait(self): self.frame()['io_events'][1]['wait_requested']=True; self.reject()
    def test_wait_hidden_on_flush(self): self.frame()['io_events'][0]['wait_requested']=True; self.reject()
    def test_cancelled_sync_in_success_path(self): self.frame()['io_events'].append(dict(kind='cancelled-frame-sync')); self.reject()
    def test_present_before_submit(self): self.frame()['io_events'].reverse(); self.reject()
    def test_foreign_queue(self): self.frame()['io_events'][2]['method']='other-queue'; self.reject()
    def test_drawable_leak(self): self.frame()['after_frame']['adapter']['live_drawables']=1; self.reject()
    def test_quarantine_not_pass(self): self.frame()['after_frame']['adapter']['quarantined_frames']=1; self.reject()
    def test_pending_release(self): self.frame()['after_frame']['adapter']['context']['pending_releases']=1; self.reject()
    def test_close_incomplete(self): self.r['windows'][0]['closed_presenter']['state']='closing'; self.reject()
    def test_layer_still_open(self): self.r['windows'][0]['closed_presenter']['adapter']['layer_closed']=False; self.reject()
    def test_unbounded_completion_references(self):
        self.frame()['after_frame']['adapter']['pending_presentation_buffers']=2; self.reject()
    def test_completion_reference_not_retired(self):
        self.r['windows'][0]['closed_presenter']['adapter']['pending_presentation_buffers']=1; self.reject()
    def test_gl_nonzero_host(self):
        self.r=fixture('opengl')
        for w in self.r['windows']:
            for f in w['frames']:
                t=f['frame']['target']; t.update(framebuffer_id=17,target_identity=17,draw_buffer=0x8ce0)
        self.assertTrue(inspect(self.r)['submission_order_verified'])
    def test_gl_adopts_host(self):
        self.r=fixture('opengl'); self.frame()['after_frame']['adapter']['owns_host_framebuffer']=True; self.reject()
    def test_gl_format_mismatch(self):
        self.r=fixture('opengl'); self.frame()['frame']['target']['format']=0x8c43; self.reject()
    def test_hardware_requirement(self):
        self.r['require_hardware']=True; self.r['windows'][0]['initial_context']['renderer_class']='software'; self.reject()
    def test_software_gl_is_labelled(self):
        self.r=fixture('opengl'); self.r['windows'][0]['initial_context']['renderer_class']='software'
        self.assertEqual(inspect(self.r)['windows'][0]['renderer_class'],'software')
    def directory(self, root):
        for b in ('opengl','metal'):
            r=fixture(b); r['validation_run']=root.name
            (root/f'presentation-{b}.diagnostic.json').write_text(json.dumps(r))
    def test_combined_same_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); self.directory(root)
            self.assertEqual(len(inspect_directory(root)['backends']),2)
    def test_combined_rejects_mixed_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); self.directory(root)
            p=root/'presentation-metal.diagnostic.json'; r=load(p); r['validation_run']='different'; p.write_text(json.dumps(r))
            with self.assertRaises(ValueError): inspect_directory(root)
    def test_combined_rejects_mixed_architecture(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); self.directory(root)
            p=root/'presentation-metal.diagnostic.json'; r=load(p); r['architecture']='x86_64'; p.write_text(json.dumps(r))
            with self.assertRaises(ValueError): inspect_directory(root)
    def test_atomic_publication(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefix=Path(tmp)/'presentation'; publish(prefix,lambda:inspect(self.r))
            self.assertIn('not a screenshot',Path(str(prefix)+'.review.html').read_text())
            self.assertFalse(load(Path(str(prefix)+'.inspection.json'))['visible_pixels_verified'])
    def test_failure_removes_stale_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefix=Path(tmp)/'presentation'; publish(prefix,lambda:inspect(self.r)); self.r['status']='error'
            with self.assertRaises(ValueError): publish(prefix,lambda:inspect(self.r))
            self.assertFalse(Path(str(prefix)+'.inspection.json').exists())
            self.assertFalse(Path(str(prefix)+'.review.html').exists())
    def test_review_escapes_renderer(self):
        self.r['windows'][0]['initial_context']['renderer']='<script>unsafe</script>'
        self.assertNotIn('<script>',review(inspect(self.r)))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--probe-prefix',type=Path)
    group.add_argument('--directory',type=Path)
    group.add_argument('--self-test',action='store_true')
    args=parser.parse_args()
    if args.self_test:
        suite=unittest.defaultTestLoader.loadTestsFromTestCase(Checks)
        raise SystemExit(0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1)
    try:
        if args.directory:
            r=publish(args.directory/'presentation',lambda:inspect_directory(args.directory))
        else:
            r=publish(args.probe_prefix,lambda:inspect(load(Path(str(args.probe_prefix)+'.diagnostic.json'))))
        print(json.dumps(r,indent=2))
    except (ValueError,TypeError,KeyError,OSError) as error:
        parser.exit(1,f'Presentation inspection failed: {error}\n')
