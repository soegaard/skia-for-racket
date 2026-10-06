#!/usr/bin/env python3
"""Synthetic inspector/runner and production-source contracts; not Windows/GPU execution."""
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
from unittest.mock import patch
import zlib
import d3d12_interop_validation as v

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def png(w, h, pixels):
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag+data) & 0xffffffff)
    rows = b''.join(b'\0'+pixels[y*w*4:(y+1)*w*4] for y in range(h))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))+chunk(b'IDAT', zlib.compress(rows))+chunk(b'IEND', b'')


def ctx(gen, selection='warp', index=0, closed=False):
    return dict(backend='direct3d', native_backend=3, api='D3D12', command_queue_owned=True,
                command_queue_type='direct', adapter_selection=selection,
                adapter_index=False if selection == 'warp' else index, adapter_flags=2 if selection == 'warp' else 0,
                d3d12_warp=selection == 'warp', renderer_class='software' if selection == 'warp' else 'hardware-reported',
                adapter_name='Synthetic fixture; not a real device', adapter_vendor_id=0x1414, adapter_device_id=0x8c,
                adapter_luid_low=91, adapter_luid_high=0, binding_package='3.119.1', native_version='119.0',
                hardware_acceleration_verified=False, generation=gen, state='closed' if closed else 'ready',
                shutdown_requested=False, live_children=0, pending_releases=0, failed_releases=0)


def native(mode='copy'):
    return dict(state='closed', same_device_verified=True, state_declaration_verified_by_runtime=False,
                cpu_pixel_readbacks=0, fence_waits=2, incoming_state='pixel-shader-resource', outgoing_state='copy-source',
                quarantined=False, error=False, producer_completion_verified=True, external_state_returned=True,
                queue_submissions=1 if mode == 'copy' else 2, native_gpu_copies=1 if mode == 'copy' else 0)


def io(mode, w, h):
    flush = dict(kind='flush'); submit = dict(kind='submit', wait_requested=False)
    snapshot = dict(kind='gpu-snapshot', width=w, height=h)
    completed = dict(kind='external-d3d12-completion', wait_requested=True, cpu_pixel_readback=False)
    returned = dict(kind='external-resource-return', backend='direct3d', completion_verified=True,
                    outgoing_state='copy-source', cpu_readback=False)
    if mode == 'copy':
        rows = [flush, submit, snapshot, flush, submit, completed,
                dict(kind='external-image-copy', backend='direct3d', aliases_source=False, cpu_readback=False,
                     native_bridge_copies=1, skia_copy_draws=1), flush, submit, completed, returned]
    else:
        rows = [flush, submit, dict(kind='external-surface-borrow', backend='direct3d', contents_preserved=True), snapshot,
                dict(kind='external-target-normalization', backend='direct3d', gpu_snapshot_copies=1,
                     gpu_copy_draws=1, cpu_readback=False), flush, submit, completed, returned]
    return copy.deepcopy(rows)


def fixture(directory, selection='warp', index=0):
    directory.mkdir(parents=True, exist_ok=True)
    raw = dict(schema=1, stage='0.51', validation_run=directory.name, os='windows', architecture='x86_64',
               racket_version='9.3', vm='chez-scheme', backend='direct3d', adapter_selection=selection,
               adapter_index=False if selection == 'warp' else index, status='passed', error=False,
               hardware_acceleration_verified=False, presentation_verified=False, performance_measured=False,
               resource_state_declarations_verified=False, zero_copy_claimed=False,
               native_cases=v.NATIVE_CASES, native_failures=0, sdk_getdesc_call_verified=True,
               producer='independent-d3d12-sdk-fixture', consumer='independent-direct-command-queue',
               suite_contexts=[ctx(1, selection, index, True), ctx(2, selection, index, True)], cycles=[], captures=[])
    for ci in range(3):
        contexts = []
        for slot in range(2):
            gen = ci*2+slot+3; w, h = (37, 29) if slot == 0 else (67, 41)
            rows = []
            for ordinal in range(24):
                mode = 'copy' if ordinal % 2 == 0 else 'surface'
                handoff = dict(backend='direct3d', context_generation=gen, handoff_state='consumed', raw_handles_exposed=False,
                               ownership='retained-single-handoff', completion='bounded-synchronous', state_query_available=False,
                               format_name='RGBA8888', width=w, height=h, dimension=3, depth=1, levels=1,
                               format=28, samples=1, quality=0, layout=0, heap_type=1, flags=1, heap_flags=0, native=native(mode))
                image = dict(texture_backed=True, storage='gpu', context_matches=True, backend='direct3d',
                             context_generation=gen, width=w, height=h) if mode == 'copy' else False
                rows.append(dict(ordinal=ordinal, mode=mode, width=w, height=h, handoff=handoff,
                                 pixels_verified=True, producer_closed_before_skia_readback=mode == 'copy',
                                 independent_consumer_readback=mode == 'surface', image=image, io_events=io(mode, w, h)))
                if ordinal < 2:
                    name = f'cycle-{ci}-context-{slot}-{mode}.png'
                    (directory/name).write_bytes(png(w, h, v.pattern(w, h, mode == 'surface')))
                    raw['captures'].append(dict(cycle=ci, context=slot, ordinal=ordinal, mode=mode,
                                                width=w, height=h, png=name, encoded_after_context_teardown=True))
            contexts.append(dict(context=slot, initial=ctx(gen, selection, index), final=ctx(gen, selection, index, True), handoffs=rows))
        raw['cycles'].append(dict(cycle=ci, contexts=contexts))
    timeout = {k: copy.deepcopy(raw[k]) for k in ('schema', 'stage', 'validation_run', 'os', 'architecture',
        'racket_version', 'vm', 'backend', 'adapter_selection', 'adapter_index', 'hardware_acceleration_verified',
        'presentation_verified', 'performance_measured', 'resource_state_declarations_verified', 'zero_copy_claimed')}
    n = native(); n.update(state='quarantined', quarantined=True, error='fence timeout', producer_completion_verified=False,
                          external_state_returned=False, queue_submissions=0, native_gpu_copies=0)
    c = ctx(1, selection, index); c.update(shutdown_requested=True, live_children=1)
    timeout.update(status='expected-timeout-quarantined', normal_process_exit=True, intentional_retention_until_process_exit=True,
                   graphics_handoff_submitted=False, error='fence timeout', native=n, context=c)
    v.write(directory/'interop.diagnostic.json', raw); v.write(directory/'interop.timeout.json', timeout)
    return raw, timeout


class Inspector(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)/'gpu-interop-synthetic'
        self.raw, self.timeout = fixture(self.directory)
        self.c = self.raw['cycles'][0]['contexts'][0]
        self.row = self.c['handoffs'][0]
    def reject(self):
        v.write(self.directory/'interop.diagnostic.json', self.raw)
        v.write(self.directory/'interop.timeout.json', self.timeout)
        with self.assertRaises((ValueError, KeyError, TypeError)): v.inspect(self.directory)
    def test_valid(self):
        r = v.inspect(self.directory)
        self.assertEqual((r['native_cases'], r['handoffs'], len(r['captures'])), (29, 144, 12))
        self.assertFalse(r['zero_copy_claimed'])
    def test_hardware_not_warp(self):
        fixture(self.directory, 'hardware', 2)
        self.assertEqual(v.inspect(self.directory, 'hardware', 2)['adapter_selection'], 'hardware')
        with self.assertRaises(ValueError): v.inspect(self.directory)
    def test_not_passed(self): self.raw['status'] = 'failed'; self.reject()
    def test_boolean_schema(self): self.raw['schema'] = True; self.reject()
    def test_wrong_stage(self): self.raw['stage'] = '0.50'; self.reject()
    def test_wrong_backend(self): self.raw['backend'] = 'opengl'; self.reject()
    def test_wrong_platform(self): self.raw['os'] = 'macosx'; self.reject()
    def test_foreign_run(self): self.raw['validation_run'] = 'other'; self.reject()
    def test_reduced_native_cases(self): self.raw['native_cases'] = 1; self.reject()
    def test_boolean_failure_count(self): self.raw['native_failures'] = False; self.reject()
    def test_no_runtime_aggregate_check(self): self.raw['sdk_getdesc_call_verified'] = False; self.reject()
    def test_wrong_producer(self): self.raw['producer'] = 'Skia'; self.reject()
    def test_missing_context(self): self.raw['cycles'][0]['contexts'].pop(); self.reject()
    def test_missing_cycle(self): self.raw['cycles'].pop(); self.reject()
    def test_missing_handoff(self): self.c['handoffs'].pop(); self.reject()
    def test_foreign_context(self): self.row['handoff']['context_generation'] = 123; self.reject()
    def test_generation_reused(self): self.c['initial']['generation'] = 1; self.reject()
    def test_device_changed(self): self.c['final']['adapter_luid_low'] += 1; self.reject()
    def test_wrong_native_backend(self): self.c['initial']['native_backend'] = 0; self.reject()
    def test_native_id_bool(self): self.c['initial']['native_backend'] = True; self.reject()
    def test_wrong_adapter_flags(self): self.c['initial']['adapter_flags'] = 0; self.reject()
    def test_resource_pin_leak(self): self.c['final']['live_children'] = 1; self.reject()
    def test_pending_release(self): self.c['final']['pending_releases'] = 1; self.reject()
    def test_failed_release(self): self.c['final']['failed_releases'] = 1; self.reject()
    def test_session_not_closed(self): self.row['handoff']['native']['state'] = 'drawing'; self.reject()
    def test_session_quarantined(self): self.row['handoff']['native']['quarantined'] = True; self.reject()
    def test_source_still_owned_by_fixture(self): self.row['producer_closed_before_skia_readback'] = False; self.reject()
    def test_consumer_not_independent(self): self.c['handoffs'][1]['independent_consumer_readback'] = False; self.reject()
    def test_cpu_result_not_gpu_image(self): self.row['image']['texture_backed'] = False; self.reject()
    def test_aliased_copy(self): self.row['io_events'][6]['aliases_source'] = True; self.reject()
    def test_missing_snapshot(self): self.row['io_events'].pop(2); self.reject()
    def test_missing_normalization(self): self.c['handoffs'][1]['io_events'].pop(4); self.reject()
    def test_cpu_staging(self): self.row['handoff']['native']['cpu_pixel_readbacks'] = 1; self.reject()
    def test_hidden_readback(self): self.row['io_events'].append(dict(kind='readback')); self.reject()
    def test_unbounded_submit_wait(self): self.row['io_events'][1]['wait_requested'] = True; self.reject()
    def test_missing_fence_completion(self): self.row['io_events'][5]['wait_requested'] = False; self.reject()
    def test_missing_state_return(self): self.row['handoff']['native']['external_state_returned'] = False; self.reject()
    def test_lied_state_query(self): self.row['handoff']['native']['state_declaration_verified_by_runtime'] = True; self.reject()
    def test_raw_pointer_publication(self): self.row['handoff']['raw_handles_exposed'] = True; self.reject()
    def test_wrong_heap_flags(self): self.row['handoff']['heap_flags'] = 1; self.reject()
    def test_wrong_format(self): self.row['handoff']['format'] = 87; self.reject()
    def test_mips(self): self.row['handoff']['levels'] = 2; self.reject()
    def test_not_consumed(self): self.row['handoff']['handoff_state'] = 'ready'; self.reject()
    def test_capture_missing(self): self.raw['captures'].pop(); self.reject()
    def test_capture_duplicate(self): self.raw['captures'][-1] = self.raw['captures'][0]; self.reject()
    def test_capture_early(self): self.raw['captures'][0]['encoded_after_context_teardown'] = False; self.reject()
    def test_unsafe_path(self): self.raw['captures'][0]['png'] = '../escape.png'; self.reject()
    def test_pixel_oracle_not_pairwise_agreement(self):
        for item in self.raw['captures']:
            w, h = item['width'], item['height']
            (self.directory/item['png']).write_bytes(png(w, h, bytes(w*h*4)))
        self.reject()
    def test_png_crc(self):
        p = self.directory/self.raw['captures'][0]['png']; data = bytearray(p.read_bytes()); data[-1] ^= 1; p.write_bytes(data)
        self.reject()
    def test_negative_result_not_arbitrary_error(self): self.timeout['error'] = 'missing DLL'; self.reject()
    def test_timeout_submitted_work(self): self.timeout['native']['queue_submissions'] = 1; self.reject()
    def test_timeout_not_quarantined(self): self.timeout['native']['quarantined'] = False; self.reject()
    def test_timeout_forged_completion(self): self.timeout['native']['producer_completion_verified'] = True; self.reject()
    def test_timeout_context_unpinned(self): self.timeout['context']['live_children'] = 0; self.reject()
    def test_timeout_foreign_interpreter(self): self.timeout['racket_version'] = '8.7'; self.reject()
    def test_timeout_abnormal_exit_claim(self): self.timeout['normal_process_exit'] = False; self.reject()
    def test_timeout_missing(self):
        (self.directory/'interop.timeout.json').unlink()
        with self.assertRaises(ValueError): v.inspect(self.directory)
    def test_duplicate_json(self):
        (self.directory/'interop.diagnostic.json').write_text('{"schema":1,"schema":1}')
        with self.assertRaisesRegex(ValueError, 'duplicate'): v.inspect(self.directory)
    def test_nonfinite_json(self):
        (self.directory/'interop.diagnostic.json').write_text('{"schema":NaN}')
        with self.assertRaisesRegex(ValueError, 'non-finite'): v.inspect(self.directory)

# All claims must remain explicitly false; separate test cases identify regressions.
for field in ('hardware_acceleration_verified', 'presentation_verified', 'performance_measured',
              'resource_state_declarations_verified', 'zero_copy_claimed'):
    def test(self, field=field):
        self.raw[field] = True; self.reject()
    setattr(Inspector, 'test_unsupported_claim_'+field, test)


class Runner(unittest.TestCase):
    def simulate(self, fail=None, identity=None, sdk=None, change=None, source_change=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)/'source'; root.mkdir()
            for p in v.SOURCES:
                path = root/p; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('synthetic source fingerprint only')
            directory = Path(temporary)/'probe'; directory.mkdir(); calls = []
            def run(argv):
                args = [str(x) for x in argv]; calls.append(args)
                if fail and any(fail in x for x in args): raise RuntimeError('synthetic subprocess failure')
                if args[-1].endswith('ci-identity.rkt'):
                    return json.dumps(identity or dict(os='windows', architecture='x86_64', pointer_bytes=8, version='9.3', vm='chez-scheme'))
                if args[0].endswith('interop-sdk-check.exe'):
                    return json.dumps(sdk or dict(kind='windows-sdk', status='passed', slots=6, resource_desc_bytes=56))
                if '--fixture' in args and '--timeout-case' not in args:
                    raw, timeout = fixture(directory)
                    if change:
                        change(raw, timeout); v.write(directory/'interop.diagnostic.json', raw); v.write(directory/'interop.timeout.json', timeout)
                    if source_change: (root/v.SOURCES[0]).write_text('changed')
                return ''
            try:
                result = v.execute(root, '/selected Racket/racket.exe', directory, run)
            except Exception:
                self.assertFalse((directory/'interop.inspection.json').exists())
                self.assertFalse((directory/'interop.review.html').exists())
                self.assertTrue((directory/'interop.validation.failed.json').exists())
                raise
            self.assertTrue((directory/'interop.inspection.json').is_file())
            self.assertTrue((directory/'interop.review.html').is_file())
            return calls, result
    def test_real_command_order(self):
        calls, result = self.simulate(); self.assertEqual(len(calls), 8)
        self.assertEqual(calls[1][-2:], ['-A', 'x64'])
        self.assertEqual(calls[-1][-1], '--timeout-case')
        self.assertTrue(result['windows_sdk_verified']); self.assertEqual(result['handoffs'], 144)
        for command in (calls[0], calls[5], calls[6], calls[7]): self.assertEqual(command[0], '/selected Racket/racket.exe')
    def test_non_windows(self):
        with self.assertRaises(ValueError): self.simulate(identity=dict(os='unix', architecture='x86_64', pointer_bytes=8))
    def test_sdk_not_host_mirror(self):
        with self.assertRaises(ValueError): self.simulate(sdk=dict(kind='host-mirror', status='passed', slots=6, resource_desc_bytes=56))
    def test_sdk_wrong_slots(self):
        with self.assertRaises(ValueError): self.simulate(sdk=dict(kind='windows-sdk', status='passed', slots=5, resource_desc_bytes=56))
    def test_cmake_failure(self):
        with self.assertRaises(RuntimeError): self.simulate(fail='--build')
    def test_ctest_failure(self):
        with self.assertRaises(RuntimeError): self.simulate(fail='ctest')
    def test_native_doctor_failure(self):
        with self.assertRaises(RuntimeError): self.simulate(fail='--fixture')
    def test_negative_child_crash_not_pass(self):
        with self.assertRaises(RuntimeError): self.simulate(fail='--timeout-case')
    def test_bad_pixels_or_report(self):
        with self.assertRaises(ValueError): self.simulate(change=lambda r,t:r.update(native_failures=1))
    def test_sources_changed(self):
        with self.assertRaises(ValueError): self.simulate(source_change=True)
    def test_existing_evidence_refused(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t); (p/'old').touch()
            with self.assertRaises(ValueError): v.execute(p, 'racket', p, lambda _: self.fail('must not run'))
    def test_invalid_warp_index(self):
        with self.assertRaises(ValueError): v.select('warp', 1)


class Source(unittest.TestCase):
    def test_generic_api_has_no_raw_handle_export(self):
        s = (ROOT/'gpu-interop.rkt').read_text()
        self.assertNotIn('make-d3d12-external-texture', s)
        self.assertNotIn('ffi-lib', s)
        self.assertIn('gpu-import-image', s)
    def test_unsafe_boundary_explicit(self):
        s = (ROOT/'unsafe/gpu-d3d12.rkt').read_text()
        self.assertIn('make-d3d12-external-texture', s)
        self.assertIn('call-with-gpu-d3d12-device', s)
    def test_driver_registers_and_forgets_actual_context(self):
        s = (ROOT/'private/gpu-driver-d3d12.rkt').read_text()
        self.assertIn('(register-d3d12-handles! context adapter device queue)', s)
        self.assertIn('(forget-d3d12-handles! p)', s)
        self.assertIn('(forget-d3d12-handles! context)', s)
    def test_native_reentry_guard(self):
        self.assertIn('(current-external-native?)', (ROOT/'private/gpu-interop-guard.rkt').read_text())
    def test_sdk_release_assertions(self):
        s = (HERE/'d3d12-interop-fixture/sdk-check.c').read_text()
        self.assertEqual(len(re.findall(r'^SLOT\(', s, re.M)), 6)
        self.assertNotRegex(s, r'\bassert\(')
        self.assertIn('c_std_11', (HERE/'d3d12-interop-fixture/CMakeLists.txt').read_text().lower().replace('cmake_c_standard 11', 'c_std_11'))
    def test_independent_fixture_has_no_skia_dependency(self):
        s = (HERE/'d3d12-interop-fixture/fixture.cpp').read_text()
        self.assertNotRegex(s, r'#include[^\n]*[Ss]kia')
        self.assertIn('CreateCommandQueue(&q,IID_PPV_ARGS(&f->producer))', s)
        self.assertIn('CreateCommandQueue(&q,IID_PPV_ARGS(&f->consumer))', s)
        self.assertIn('CopyTextureRegion', s)
    def test_normalization_not_direct_draw_image_optimization(self):
        s = (ROOT/'private/gpu-d3d12-interop.rkt').read_text()
        self.assertIn('(make-image-shader snapshot #:sampling \'nearest)', s)
        self.assertIn('(draw-rect (surface-canvas borrowed-surface) 0 0 w h paint)', s)
        self.assertIn('(call-with-canvas-state canvas', s)
    def test_only_checked_device_accessor(self):
        s = (ROOT/'private/gpu-d3d12-interop.rkt').read_text()
        self.assertIn('[current-external-native? #t]', s)
        self.assertNotIn('(proc device queue)', s)
    def test_single_use_native_session(self):
        s = (ROOT/'private/gpu-external.rkt').read_text()
        self.assertIn("'consumed", s); self.assertIn('call-with-continuation-barrier', s)
        self.assertIn('current-future', s)
    def test_native_suite_count_matches_definition(self):
        s = (ROOT/'tests/gpu-interop-native-test.rkt').read_text()
        self.assertEqual(s.count('(test-case '), v.NATIVE_CASES)
        self.assertIn(f'gpu-interop-native-test-count {v.NATIVE_CASES}', s)
    def test_translucent_native_probes(self):
        s = (ROOT/'tests/gpu-interop-native-test.rkt').read_text()
        self.assertIn('straight-alpha translucent', s)
        self.assertIn('translucent premultiplied', s)
    def test_constructor_metadata_comes_from_native_getdesc(self):
        s = (ROOT/'private/gpu-d3d12-interop-system.rkt').read_text()
        self.assertIn('(resource-description/native r)', s)
        self.assertLess(s.index('(same-device/native? r dev)'), s.index('(resource-description/native r)'))
        self.assertIn('(_fun _pointer _pointer -> _pointer)', s)
    def test_no_runtime_helper_dll(self):
        for p in (ROOT/'private').glob('gpu-d3d12-interop*.rkt'):
            self.assertNotIn('fixture.dll', p.read_text())
    def test_no_kill_or_abort_for_negative_probe(self):
        s = (HERE/'gpu-d3d12-interop-doctor.rkt').read_text()
        self.assertIn('#:timeout-ms 25', s)
        self.assertNotIn('(abort', s)
        self.assertIn('expected-timeout-quarantined', s)
    def test_new_python_files_parse(self):
        for name in ('d3d12_interop_validation.py','ci-d3d12-interop.py','validate-gpu-interop.py','test-gpu-interop.py'):
            ast.parse((HERE/name).read_text(), filename=name)


class CIEntry(unittest.TestCase):
    def setUp(self):
        ci = types.ModuleType('ci'); ci.require = v.require
        matrix = types.ModuleType('ci_matrix'); matrix.load_matrix = lambda: {}
        spec = importlib.util.spec_from_file_location('interop_ci_test', HERE/'ci-d3d12-interop.py')
        self.module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, ci=ci, ci_matrix=matrix): spec.loader.exec_module(self.module)
    def test_hook_uses_installed_root_and_away_directory(self):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t)/'installed'; root.mkdir(); away = Path(t)/'away'; away.mkdir()
            calls = []; env = {'GPU_MODE': 'off'}; report = dict(racket_executable='chosen racket', checks={})
            runner = types.SimpleNamespace(run=lambda argv, **kw: calls.append((argv, kw)))
            def execute(installed, racket, directory, run, **kw):
                self.assertEqual(installed, root); self.assertEqual(racket, 'chosen racket')
                self.assertEqual(directory.parent, root/'output'); self.assertEqual(kw, {'selection':'warp'})
                run(['selected-command']); return dict(status='passed')
            with patch.object(self.module, 'execute', side_effect=execute):
                self.module.interop_checks(runner, root, away, env, report)
            self.assertEqual(calls[0][1], dict(cwd=away, env=env))
            self.assertTrue(report['checks']['required_d3d12_interop'])
    def test_failed_hook_no_success_flag(self):
        with tempfile.TemporaryDirectory() as t:
            report = dict(racket_executable='racket', checks={})
            with patch.object(self.module, 'execute', side_effect=RuntimeError('failed')):
                with self.assertRaises(RuntimeError): self.module.interop_checks(None, Path(t), Path(t), {}, report)
            self.assertNotIn('required_d3d12_interop', report['checks'])
    def test_full_isolated_package_used(self):
        s = (HERE/'ci-d3d12-interop.py').read_text()
        self.assertIn("ci.package_checks(runner, root, row, 'cpu', report, extra_checks=interop_checks)", s)
        self.assertIn("report['checks'].get('required_d3d12_interop') is True", s)


class Integration(unittest.TestCase):
    """Requires the full applied source checkout; never silently skipped."""
    def test_new_step_is_inside_required_d3d12_job(self):
        s = (ROOT/'.github/workflows/ci.yml').read_text()
        d3d = s.split('\n  d3d12:', 1)[1].split('\n  dxgi:', 1)[0]
        self.assertIn('python tools/ci-d3d12-interop.py', d3d)
        self.assertLess(d3d.index('python tools/ci-d3d12.py'), d3d.index('python tools/ci-d3d12-interop.py'))
        self.assertNotIn('continue-on-error', d3d)
        self.assertIn('needs: [source, cpu, egl, d3d12, dxgi, canvas]', s)
    def test_failure_artifacts_retained(self):
        s = (ROOT/'.github/workflows/ci.yml').read_text()
        self.assertIn('path: output/ci-d3d12-interop/', s)
    def test_source_and_local_runner_include_tests(self):
        self.assertIn("'test-gpu-interop.py'", (HERE/'ci.py').read_text())
        self.assertIn("'tools/test-gpu-interop.py'", (HERE/'validate-gpu.py').read_text())
    def test_pure_racket_suite_is_wired(self):
        s = (ROOT/'run-tests.rkt').read_text()
        self.assertIn('"tests/gpu-interop-pure-test.rkt"', s)
        self.assertIn('(run-tests gpu-interop-pure-tests)', s)
    def test_new_public_modules_in_native_free_smoke(self):
        s = (HERE/'ci-import-smoke.rkt').read_text()
        self.assertIn('skia/gpu-interop', s); self.assertIn('skia/unsafe/gpu-d3d12', s)
    def test_stage_and_native_pin(self):
        self.assertIn('(define version "0.71")', (ROOT/'info.rkt').read_text())
        self.assertEqual((ROOT/'private/native-default-version.txt').read_text().strip(), '3.119.1')
    def test_registry_includes_completed_metal_wrapper(self):
        data = json.loads((ROOT/'private/gpu-backends.json').read_text())
        rows = {row['backend']: row for row in data['backends']}
        self.assertTrue(rows['direct3d']['features']['external_resource_interop'])
        self.assertTrue(rows['metal']['features']['external_resource_interop'])
    def test_existing_gl_interop_doctor_not_replaced(self):
        self.assertIn('gpu-gl-interop-native-test', (HERE/'gpu-interop-doctor.rkt').read_text())


if __name__ == '__main__':
    unittest.main(verbosity=2)
