#!/usr/bin/env python3
"""Synthetic DXGI inspector/orchestration tests. They do not execute Windows/GPU code."""
from __future__ import annotations
import ast
import copy
import importlib.util
import json
from pathlib import Path
import re
import struct
import sys
import tempfile
import types
import unittest
import uuid
import zlib
from unittest.mock import patch
import dxgi_validation as d

HERE = Path(__file__).resolve().parent
EXTENTS = ((37, 29), (67, 41), (53, 35))


def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)


def png(w, h, pixels=None, *, mode=0, rgb=False):
    pixels = d.pattern(w, h) if pixels is None else pixels
    bpp = 3 if rgb else 4
    if rgb:
        pixels = b''.join(pixels[i:i+3] for i in range(0, len(pixels), 4))
    previous = bytes(w * bpp); rows = []
    for y in range(h):
        row = pixels[y*w*bpp:(y+1)*w*bpp]
        encoded = bytearray()
        for x, v in enumerate(row):
            a, b, c = (row[x-bpp] if x >= bpp else 0), previous[x], (previous[x-bpp] if x >= bpp else 0)
            if mode == 0: predictor = 0
            elif mode == 1: predictor = a
            elif mode == 2: predictor = b
            elif mode == 3: predictor = (a + b) // 2
            else:
                p = a + b - c
                distances = (abs(p - a), abs(p - b), abs(p - c))
                predictor = (a, b, c)[distances.index(min(distances))]
            encoded.append((v - predictor) & 255)
        rows.append(bytes([mode]) + encoded); previous = row
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2 if rgb else 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(b''.join(rows))) + chunk(b'IEND', b''))


def fixture(directory: Path, selection='warp', index=0):
    """Only fake reports/pixels in temporary test directories. Not retained native evidence."""
    directory.mkdir(parents=True, exist_ok=True)
    def context(generation, state, children):
        return dict(backend='direct3d', native_backend=3, generation=generation, state=state,
                    adapter_selection=selection, adapter_index=False if selection == 'warp' else index,
                    api='D3D12', d3d12_warp=selection == 'warp', adapter_flags=2 if selection == 'warp' else 0,
                    renderer_class='software' if selection == 'warp' else 'hardware-reported',
                    adapter_name='synthetic WARP/hardware fixture', adapter_vendor_id=0x1414, adapter_device_id=0x8c,
                    adapter_luid_low=42, adapter_luid_high=0, command_queue_owned=True, command_queue_type='direct',
                    hardware_acceleration_verified=False, live_children=children, pending_releases=0, failed_releases=0)
    def presenter(generation, state):
        host = dict(state=state, quarantined=False, quarantined_frames=0,
                    context=context(generation, state, 1 if state == 'ready' else 0),
                    backend='direct3d', window_system='win32-hwnd', hwnd_ownership='borrowed-racket-gui',
                    queue_ownership='context-driver', swap_chain_ownership='presenter', window_created=True,
                    visible_pixels_verified=False, performance_measured=False,
                    presentation_context_children=1 if state == 'ready' else 0,
                    live_drawables=0, live_back_buffers=2 if state == 'ready' else 0,
                    buffer_count=2, format='RGBA8888', swap_effect='flip-discard', sync_interval=1,
                    resize_count=2, swap_chain_generation=3, presents_submitted=186, validation_readbacks=3,
                    frames_acquired=186, presents_occluded=0, frames_cancelled=0, fence_value=186,
                    blocking_fence_waits=8, width=EXTENTS[-1][0], height=EXTENTS[-1][1])
        return dict(backend='direct3d', state=state, visible_pixels_verified=False, performance_measured=False,
                    adapter=host, presents_requested=186)
    cycles = []
    for ci in range(3):
        windows = []
        for wi in range(2):
            generation = 2 * ci + wi + 1
            captures = []
            for si, (width, height) in enumerate(EXTENTS):
                record = dict(result='submitted', hresult=0, same_queue=True, skia_wrappers_retired_before_transition=True,
                              state_before_transition='render-target', state_at_present='present', validation_readback=True,
                              visible_pixels_verified=False, width=width, height=height,
                              readback_row_pitch=((4*width+255)//256)*256, format='RGBA8888', sample_count=1,
                              buffer_count=2, swap_effect='flip-discard', buffer_index=0, swap_chain_generation=si+1,
                              fence_value=2*si+1)
                target = dict(backend='direct3d', native_backend=3, context_matches=True, context_generation=generation,
                              target_kind='dxgi-back-buffer', target_identity=f'dxgi-{generation}-{si+1}',
                              width=width, height=height, buffer_index=0, swap_chain_generation=si+1,
                              actual_sample_count=1, render_path='sk_surface_new_backend_render_target')
                frame = dict(backend='direct3d', result='present-requested', frame_index=2*si+1,
                             target_generation=si+1, pixel_width=width, pixel_height=height, target=target)
                name = f'cycle-{ci}-window-{wi}-size-{si}.png'
                (directory / name).write_bytes(png(width, height))
                captures.append(dict(ordinal=si, png=name, submission=record, frame=frame, encoded_after_context_teardown=True))
            rows = []
            for i in range(d.NORMAL_FRAMES):
                rows += [dict(kind='flush'), dict(kind='submit', wait_requested=False),
                         dict(kind='present-request', wait_requested=False, backend='direct3d', method='dxgi-same-queue',
                              buffer_index=1 if i < 3 else (i-3)%2, swap_chain_generation=min(i+1, 3),
                              fence_value=2*(i+1) if i < 3 else i+4,
                              hresult=0, result='submitted')]
            windows.append(dict(window=wi, initial=context(generation, 'ready', 1),
                                before_close=presenter(generation, 'ready'), final=presenter(generation, 'closed'),
                                stress_frames=180, normal_frames=183, normal_io=rows, captures=captures))
        cycles.append(dict(cycle=ci, windows=windows))
    result = dict(schema=1, stage='0.49', status='passed', validation_run=directory.name,
                  os='windows', architecture='x86_64', adapter_selection=selection,
                  adapter_index=False if selection == 'warp' else index,
                  visible_pixels_verified=False, hardware_acceleration_verified=False, performance_measured=False,
                  window_created=True, presentation_submission_verified=True,
                  test_counts=dict(presenter=28, presenter_failures=0), cycles=cycles)
    (directory / 'dxgi.diagnostic.json').write_text(json.dumps(result), encoding='utf-8')
    return result


class Inspector(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name) / 'gpu-dxgi-fixture'
        self.data = fixture(self.directory)
        self.w = self.data['cycles'][0]['windows'][0]
    def bad(self, change):
        change(self.data)
        (self.directory / 'dxgi.diagnostic.json').write_text(json.dumps(self.data), encoding='utf-8')
        with self.assertRaises((ValueError, KeyError, TypeError)): d.inspect(self.directory)
    def test_valid(self):
        r = d.inspect(self.directory)
        self.assertEqual((r['native_presenter_cases'], r['contexts'], r['stress_frames'], r['captures']), (28, 6, 1080, 18))
        self.assertTrue(r['back_buffer_pixels_verified']); self.assertFalse(r['visible_pixels_verified'])
    def test_hardware_is_separate(self):
        fixture(self.directory, 'hardware', 2)
        self.assertEqual(d.inspect(self.directory, 'hardware', 2)['renderer_class'], 'hardware-reported')
        with self.assertRaises(ValueError): d.inspect(self.directory, 'warp')
    def test_hardware_wrong_index(self):
        fixture(self.directory, 'hardware', 2)
        with self.assertRaises(ValueError): d.inspect(self.directory, 'hardware', 0)
    def test_schema_bool(self): self.bad(lambda r: r.update(schema=True))
    def test_stage(self): self.bad(lambda r: r.update(stage='0.48'))
    def test_failed(self): self.bad(lambda r: r.update(status='failed'))
    def test_foreign(self): self.bad(lambda r: r.update(validation_run='other'))
    def test_platform(self): self.bad(lambda r: r.update(os='macosx'))
    def test_missing_window(self): self.bad(lambda r: r.update(window_created=False))
    def test_no_presents(self): self.bad(lambda r: r.update(presentation_submission_verified=False))
    def test_screen_claim(self): self.bad(lambda r: r.update(visible_pixels_verified=True))
    def test_hardware_claim(self): self.bad(lambda r: r.update(hardware_acceleration_verified=True))
    def test_performance_claim(self): self.bad(lambda r: r.update(performance_measured=True))
    def test_wrong_count(self): self.bad(lambda r: r['test_counts'].update(presenter=27))
    def test_bool_failures(self): self.bad(lambda r: r['test_counts'].update(presenter_failures=False))
    def test_live_failures(self): self.bad(lambda r: r['test_counts'].update(presenter_failures=1))
    def test_missing_cycle(self): self.bad(lambda r: r['cycles'].pop())
    def test_one_window(self): self.bad(lambda r: r['cycles'][0]['windows'].pop())
    def test_reused_generation(self): self.bad(lambda r: r['cycles'][1]['windows'][0]['initial'].update(generation=1))
    def test_shortened_stress(self): self.bad(lambda r: self.w.update(stress_frames=1))
    def test_wrong_native_backend(self): self.bad(lambda r: self.w['initial'].update(native_backend=0))
    def test_missing_pin(self): self.bad(lambda r: self.w['initial'].update(live_children=0))
    def test_final_reference(self): self.bad(lambda r: self.w['final']['adapter']['context'].update(live_children=1))
    def test_pending_reference(self): self.bad(lambda r: self.w['final']['adapter']['context'].update(pending_releases=1))
    def test_failed_release(self): self.bad(lambda r: self.w['final']['adapter']['context'].update(failed_releases=1))
    def test_wrong_adapter(self): self.bad(lambda r: self.w['initial'].update(adapter_flags=0))
    def test_bad_luid(self): self.bad(lambda r: self.w['initial'].update(adapter_luid_low=True))
    def test_luid_changed(self): self.bad(lambda r: self.w['final']['adapter']['context'].update(adapter_luid_low=9))
    def test_queue_not_owned(self): self.bad(lambda r: self.w['initial'].update(command_queue_owned=False))
    def test_foreign_queue(self): self.bad(lambda r: self.w['before_close']['adapter'].update(queue_ownership='other'))
    def test_quarantined(self): self.bad(lambda r: self.w['final']['adapter'].update(quarantined=True))
    def test_live_buffer(self): self.bad(lambda r: self.w['final']['adapter'].update(live_back_buffers=1))
    def test_live_frame(self): self.bad(lambda r: self.w['before_close']['adapter'].update(live_drawables=1))
    def test_old_generation(self): self.bad(lambda r: self.w['before_close']['adapter'].update(swap_chain_generation=1))
    def test_missing_resize(self): self.bad(lambda r: self.w['before_close']['adapter'].update(resize_count=0))
    def test_changed_format(self): self.bad(lambda r: self.w['before_close']['adapter'].update(format='BGRA8888'))
    def test_changed_effect(self): self.bad(lambda r: self.w['before_close']['adapter'].update(swap_effect='discard'))
    def test_changed_samples(self): self.bad(lambda r: self.w['captures'][0]['submission'].update(sample_count=4))
    def test_hidden_wait(self): self.bad(lambda r: self.w['normal_io'][1].update(wait_requested=True))
    def test_hidden_readback(self): self.bad(lambda r: self.w['normal_io'][1].update(kind='readback'))
    def test_flush_wait_is_not_hidden(self): self.bad(lambda r: self.w['normal_io'][0].update(wait_requested=True))
    def test_reused_normal_fence(self): self.bad(lambda r: self.w['normal_io'][5].update(fence_value=2))
    def test_bool_target_sample(self): self.bad(lambda r: self.w['captures'][0]['frame']['target'].update(actual_sample_count=True))
    def test_real_occlusion_is_counted_but_not_passed(self):
        rows=self.w['normal_io']
        occluded=copy.deepcopy(rows[:3]); occluded[-1].update(result='occluded', hresult=0x087a0001)
        for row in rows:
            if row['kind']=='present-request': row['fence_value']+=1
        rows[:0]=occluded
        for capture in self.w['captures'][1:]:
            capture['submission']['fence_value']+=1; capture['frame']['frame_index']+=1
        for key in ('before_close','final'):
            self.w[key]['adapter'].update(frames_acquired=187, presents_occluded=1, fence_value=187)
        (self.directory/'dxgi.diagnostic.json').write_text(json.dumps(self.data))
        self.assertEqual(d.inspect(self.directory)['stress_frames'],1080)
    def test_no_rotation(self):
        self.bad(lambda r: [row.update(buffer_index=0) for row in self.w['normal_io'] if row['kind'] == 'present-request'])
    def test_occlusion_counted_as_success(self): self.bad(lambda r: self.w['normal_io'][2].update(hresult=0x087a0001))
    def test_present_before_submit(self): self.bad(lambda r: self.w['normal_io'].reverse())
    def test_one_less_frame(self): self.bad(lambda r: self.w['normal_io'].__delitem__(slice(0, 3)))
    def test_unreported_waits(self): self.bad(lambda r: self.w['final']['adapter'].pop('blocking_fence_waits'))
    def test_missing_fence(self): self.bad(lambda r: self.w['before_close']['adapter'].update(fence_value=0))
    def test_no_capture(self): self.bad(lambda r: self.w['captures'].pop())
    def test_early_encoding(self): self.bad(lambda r: self.w['captures'][0].update(encoded_after_context_teardown=False))
    def test_foreign_target(self): self.bad(lambda r: self.w['captures'][0]['frame']['target'].update(context_generation=9))
    def test_stale_target(self): self.bad(lambda r: self.w['captures'][1]['frame']['target'].update(swap_chain_generation=1))
    def test_no_present_state(self): self.bad(lambda r: self.w['captures'][0]['submission'].update(state_at_present='render-target'))
    def test_no_retirement(self): self.bad(lambda r: self.w['captures'][0]['submission'].update(skia_wrappers_retired_before_transition=False))
    def test_wrong_pitch(self): self.bad(lambda r: self.w['captures'][0]['submission'].update(readback_row_pitch=148))
    def test_wrong_present_hresult(self): self.bad(lambda r: self.w['captures'][0]['submission'].update(hresult=1))
    def test_wrong_frame_extent(self): self.bad(lambda r: self.w['captures'][0]['frame'].update(pixel_width=9))
    def test_unsafe_path(self): self.bad(lambda r: self.w['captures'][0].update(png='../a.png'))
    def test_shared_wrong_pixels(self):
        for c in self.data['cycles']:
            for w in c['windows']:
                for item in w['captures']:
                    s = item['submission']; (self.directory/item['png']).write_bytes(png(s['width'], s['height'], bytes(s['width']*s['height']*4)))
        with self.assertRaises(ValueError): d.inspect(self.directory)
    def test_png_crc(self):
        path = self.directory / self.w['captures'][0]['png']; b=bytearray(path.read_bytes()); b[-1]^=1; path.write_bytes(b)
        with self.assertRaises(ValueError): d.inspect(self.directory)
    def test_png_truncated(self):
        p=self.directory/self.w['captures'][0]['png']; p.write_bytes(p.read_bytes()[:-3])
        with self.assertRaises(ValueError): d.inspect(self.directory)
    def test_png_trailing(self):
        p=self.directory/self.w['captures'][0]['png']; p.write_bytes(p.read_bytes()+b'extra')
        with self.assertRaises(ValueError): d.inspect(self.directory)
    def test_duplicate_json(self):
        p=self.directory/'dxgi.diagnostic.json'; p.write_text('{"schema":1,"schema":1}')
        with self.assertRaisesRegex(ValueError, 'duplicate'): d.inspect(self.directory)
    def test_nonfinite_json(self):
        p=self.directory/'dxgi.diagnostic.json'; p.write_text('{"x":NaN}')
        with self.assertRaisesRegex(ValueError, 'non-finite'): d.inspect(self.directory)
    def test_png_rgb_and_all_filters(self):
        p=self.directory/'filter.png'
        for rgb in (False, True):
            for mode in range(5):
                p.write_bytes(png(37, 29, mode=mode, rgb=rgb))
                self.assertEqual(d.png_rgba(p), (37, 29, d.pattern(37, 29)))


class Runner(unittest.TestCase):
    def simulate(self, fail=None, identity=None, sdk_change=None, layout_change=None, change=None):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t); directory=root/'probe'; directory.mkdir(); calls=[]
            def run(args):
                a=[str(v) for v in args]; calls.append(a)
                if fail and any(fail in v for v in a): raise RuntimeError('synthetic subprocess failure')
                if len(a)>1 and a[1].endswith('ci-identity.rkt'):
                    return json.dumps(identity or dict(os='windows', architecture='x86_64', pointer_bytes=8))
                if a[0].endswith('check-dxgi.exe'):
                    sdk=dict(kind='windows-sdk', status='passed', slots_verified=22, guids_verified=5, sizes=d.SIZES.copy())
                    if sdk_change: sdk_change(sdk)
                    return json.dumps(sdk)
                if len(a)>1 and a[1].endswith('check-dxgi-layouts.rkt'):
                    r=dict(kind='racket-ffi-layouts', status='passed', sizes=d.SIZES.copy())
                    if layout_change: layout_change(r)
                    return json.dumps(r)
                if len(a)>1 and a[1].endswith('gpu-dxgi-doctor.rkt'):
                    data=fixture(directory)
                    if change:
                        change(data); (directory/'dxgi.diagnostic.json').write_text(json.dumps(data))
                return ''
            try:
                result=d.execute(root, '/selected Racket/racket.exe', directory, run)
            except Exception:
                self.assertFalse((directory/'dxgi.inspection.json').exists())
                self.assertFalse((directory/'dxgi.review.html').exists())
                self.assertTrue((directory/'dxgi.validation.failed.json').exists())
                raise
            self.assertTrue((directory/'dxgi.inspection.json').exists())
            self.assertTrue((directory/'dxgi.review.html').exists())
            return calls,result
    def test_order_and_selected_interpreter(self):
        calls,r=self.simulate(); self.assertEqual(len(calls),8)
        self.assertEqual(calls[1][-2:], ['-A','x64'])
        for a in calls:
            if len(a)>1 and (a[1].endswith('.rkt') or 'raco' in a): self.assertEqual(a[0],'/selected Racket/racket.exe')
        self.assertTrue(r['windows_sdk_abi_verified']); self.assertTrue(r['racket_layouts_verified'])
        self.assertIn('warp',calls[-1]); self.assertEqual(r['captures'],18)
    def test_non_windows(self):
        with self.assertRaises(ValueError): self.simulate(identity=dict(os='unix',architecture='x86_64',pointer_bytes=8))
    def test_pointer_bool(self):
        with self.assertRaises(ValueError): self.simulate(identity=dict(os='windows',architecture='x86_64',pointer_bytes=True))
    def test_cmake_failure(self):
        with self.assertRaises(RuntimeError): self.simulate(fail='--build')
    def test_ctest_failure(self):
        with self.assertRaises(RuntimeError): self.simulate(fail='ctest')
    def test_doctor_failure(self):
        with self.assertRaises(RuntimeError): self.simulate(fail='gpu-dxgi-doctor.rkt')
    def test_host_mirror_not_sdk(self):
        with self.assertRaises(ValueError): self.simulate(sdk_change=lambda r:r.update(kind='host-mirror'))
    def test_sdk_count(self):
        with self.assertRaises(ValueError): self.simulate(sdk_change=lambda r:r.update(slots_verified=21))
    def test_guids(self):
        with self.assertRaises(ValueError): self.simulate(sdk_change=lambda r:r.update(guids_verified=0))
    def test_racket_sizes(self):
        with self.assertRaises(ValueError): self.simulate(layout_change=lambda r:r['sizes'].update(transition=24))
    def test_rendering_failure(self):
        with self.assertRaises(ValueError): self.simulate(change=lambda r:r.update(status='failed'))
    def test_no_stale_directory(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t); (p/'old').touch()
            with self.assertRaises(ValueError): d.execute(p,'racket',p,lambda _:self.fail('must not run'))
    def test_invalid_adapter(self):
        for selection,index in [('auto',0),('warp',1),('hardware',True),('hardware',-1)]:
            with self.assertRaises(ValueError): d.select(selection,index)


class Source(unittest.TestCase):
    def test_guids(self):
        text=(HERE.parent/'private/gpu-dxgi-types.rkt').read_text()
        ids={'swapchain3':'94d99bdb-f1f8-4ab0-b236-7da0170edab1','resource':'696442be-a72e-4059-bc79-5b5c98040fad',
             'allocator':'6102dee4-af59-4b09-b999-b44d73f09b24','command-list':'5b160d0f-ac1b-4185-8ba8-b3ae42a5a455',
             'fence':'0a753dcf-c4d8-4b91-adf6-be5a60d95a76'}
        for name,value in ids.items():
            found=re.search(r'\(define iid-'+name+r' #"([^"]+)"\)',text)[1]
            self.assertEqual(found.encode().decode('unicode_escape').encode('latin1'),uuid.UUID(value).bytes_le)
    def test_release_build_sdk_checks(self):
        text=(HERE/'dxgi-abi/check.c').read_text()
        self.assertEqual(len(re.findall(r'^SLOT\(',text,re.M)),22)
        self.assertIn('_Static_assert',text); self.assertNotRegex(text,r'\bassert\(')
        for name in ('ID3D12GraphicsCommandListVtbl','CopyTextureRegion','ResourceBarrier','IDXGISwapChain3Vtbl','GetCurrentBackBufferIndex'):
            self.assertIn(name,text)
    def test_queue_tail_transition_and_fence(self):
        text=(HERE.parent/'private/gpu-dxgi-system.rkt').read_text()
        self.assertIn('d3d12-state-render-target d3d12-state-present',text)
        self.assertIn('queue-signal-slot',text); self.assertIn('swapchain-current-buffer-slot',text)
        self.assertIn("'buffer-reuse",text); self.assertIn('release-buffers! h',text)
    def test_no_raw_target_publication(self):
        text=(HERE.parent/'private/gpu-presenter-d3d12.rkt').read_text()
        self.assertIn('(module* testing #f (provide current-dxgi-capture-hook))',text)
        self.assertIn('(retire-target!)\n                      (define-values',text)
        self.assertIn('(canvas-restore-to-count! canvas 1)',text)
    def test_production_target_metadata_names_backend(self):
        text=(HERE.parent/'private/gpu-presenter-d3d12.rkt').read_text()
        self.assertRegex(
            text,
            r'\(hasheq\s+\'backend "direct3d"\s+\'storage "gpu"\s+\'target_kind "dxgi-back-buffer"')
    def test_full_controlled_workload(self):
        text=(HERE/'gpu-dxgi-doctor.rkt').read_text()
        self.assertIn('(make-gpu-presenter-native-tests \'direct3d make-window settle)',text)
        self.assertIn('(in-range 180)',text); self.assertIn('(in-range 3)',text)
        self.assertIn("'normal_frames 183",text)
    def test_no_optional_runner_mode(self):
        for name in ('ci-dxgi.py','validate-dxgi.py'):
            self.assertNotIn('GPU_MODE',(HERE/name).read_text())


class CIEntry(unittest.TestCase):
    def setUp(self):
        self.ci=types.ModuleType('ci'); self.matrix=types.ModuleType('ci_matrix')
        self.matrix.load_matrix=lambda:{'cpu':[{'id':'windows-x64'}]}
        spec=importlib.util.spec_from_file_location('test_ci_dxgi_entry',HERE/'ci-dxgi.py')
        self.module=importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules,ci=self.ci,ci_matrix=self.matrix): spec.loader.exec_module(self.module)
    def test_hook_inside_installed_copy(self):
        with tempfile.TemporaryDirectory() as t:
            installed=Path(t)/'installed'; installed.mkdir(); away=Path(t)/'away'; away.mkdir()
            report={'racket_executable':'selected Racket','checks':{}}; calls=[]; env={'GPU_MODE':'off'}
            runner=types.SimpleNamespace(run=lambda a,**kw:calls.append((a,kw)))
            def execute(root,racket,directory,run,**kw):
                self.assertEqual(root,installed); self.assertEqual(racket,'selected Racket')
                self.assertEqual(directory.parent,installed/'output'); self.assertEqual(kw,{'selection':'warp'})
                run(['real-command-placeholder']); return {'status':'passed'}
            with patch.object(self.module,'execute',side_effect=execute):
                self.module.dxgi_checks(runner,installed,away,env,report)
            self.assertEqual(calls[0][1],{'cwd':away,'env':env})
            self.assertTrue(report['checks']['required_dxgi_warp']); self.assertFalse(report['gpu']['visible_pixels_verified'])
    def test_failure_never_sets_pass_flag(self):
        with tempfile.TemporaryDirectory() as t:
            report={'racket_executable':'racket','checks':{}}
            with patch.object(self.module,'execute',side_effect=RuntimeError('failed')):
                with self.assertRaises(RuntimeError): self.module.dxgi_checks(None,Path(t),Path(t),{},report)
            self.assertNotIn('required_dxgi_warp',report['checks'])
    def test_full_package_hook_used(self):
        text=(HERE/'ci-dxgi.py').read_text()
        self.assertIn("ci.package_checks(runner, root, row, 'cpu', report, extra_checks=dxgi_and_parity_checks)",text)
        self.assertIn("ci.require(report['checks'].get('required_dxgi_warp') is True",text)


class Integration(unittest.TestCase):
    """These tests require the real complete source checkout; do not silently skip."""
    def test_required_job_aggregate(self):
        text=(HERE.parent/'.github/workflows/ci.yml').read_text()
        self.assertIn('needs: [source, cpu, egl, d3d12, dxgi, canvas]',text)
        self.assertIn('DXGI_RESULT: ${{ needs.dxgi.result }}',text)
        self.assertIn('test "$DXGI_RESULT" = success',text)
        self.assertIn('run: python tools/ci-d3d12.py',text); self.assertIn('run: python tools/ci-dxgi.py',text)
        self.assertNotIn('continue-on-error:',text)
    def test_unchanged_windows_auto_and_explicit_direct3d(self):
        text=(HERE.parent/'gpu-gui.rkt').read_text()
        self.assertIn("[(auto) (if (eq? (system-type 'os) 'macosx) 'metal 'opengl)]",text)
        self.assertIn("[(opengl metal direct3d) requested]",text)
        for term in ('[adapter #f]','[adapter-index #f]','[sync-interval #f]','make-d3d12-presentation-adapter'):
            self.assertIn(term,text)
    def test_pure_suite_wired(self):
        text=(HERE.parent/'run-tests.rkt').read_text()
        self.assertIn('"tests/gpu-dxgi-pure-test.rkt"',text); self.assertIn('(run-tests gpu-dxgi-pure-tests)',text)
        self.assertEqual(len(re.findall(r'\(test-case\s',(HERE.parent/'tests/gpu-dxgi-pure-test.rkt').read_text())),34)
    def test_shared_live_cases_unchanged(self):
        text=(HERE.parent/'tests/gpu-presenter-native-test.rkt').read_text()
        self.assertEqual(len(re.findall(r'\(test-case\s',text)),d.NATIVE_CASES)
        self.assertIn('presentation_context_children',text)
    def test_source_ci_runs_test(self):
        self.assertIn("'test-dxgi.py'",(HERE/'ci.py').read_text())
    def test_default_native_and_crash_hotfix_preserved(self):
        self.assertEqual((HERE.parent/'private/native-default-version.txt').read_text().strip(),'3.119.1')
        text=(HERE/'test-native-abi.py').read_text()
        self.assertIn('test_signal_termination_is_failure',text); self.assertNotIn('def test_crash_is_failure',text)
    def test_occlusion_not_passed(self):
        text=(HERE.parent/'private/gpu-presenter.rkt').read_text()
        self.assertIn("[(eq? outcome 'occluded) (set! result 'skipped)]",text)
    def test_version_and_docs(self):
        self.assertIn('(define version "0.72")',(HERE.parent/'info.rkt').read_text())
        text=(HERE.parent/'docs/GPU-DXGI.md').read_text()
        for name in ('sync-interval','gpu-window%','gpu-canvas%','WARP','buffer-reuse','visible'):
            self.assertIn(name,text)

if __name__ == '__main__':
    unittest.main(verbosity=2)
