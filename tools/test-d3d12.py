#!/usr/bin/env python3
"""Synthetic D3D12 inspector/orchestration tests. No Windows/GPU execution claim."""
from __future__ import annotations
import copy
import ast
import importlib.util
import sys
import types
import ctypes
import json
from pathlib import Path
import re
import struct
import tempfile
import unittest
import uuid
import zlib
from unittest.mock import patch
import d3d12_validation as d

HERE = Path(__file__).resolve().parent


def png(pixels=None):
    pixels = d.pattern() if pixels is None else pixels
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 8, 8, 8, 6, 0, 0, 0)) + chunk(
        b'IDAT', zlib.compress(b''.join(b'\0' + pixels[y*32:(y+1)*32] for y in range(8)))) + chunk(b'IEND', b'')


def fixture(directory, selection='warp'):
    directory.mkdir(parents=True, exist_ok=True)
    counts = {**d.COUNTS, **{name + '_failures': 0 for name in d.COUNTS}}
    cycles = []
    for i in range(3):
        def context(generation, state):
            return dict(backend='direct3d', native_backend=3, generation=generation, state=state,
                        adapter_selection=selection, adapter_flags=2 if selection == 'warp' else 0,
                        api='D3D12', minimum_feature_level=0xb000, adapter_index=False if selection == 'warp' else 0,
                        adapter_name='synthetic adapter', adapter_vendor_id=0x1414, adapter_device_id=0x8c,
                        adapter_luid_low=42, adapter_luid_high=0,
                        d3d12_warp=selection == 'warp', renderer_class='software' if selection == 'warp' else 'hardware-reported',
                        command_queue_owned=True, command_queue_type='direct', window_created=False, requires_gui=False,
                        hardware_acceleration_verified=False, live_children=0, pending_releases=0, failed_releases=0)
        io = [dict(kind='upload')]
        for frame in range(180):
            io += [dict(kind='flush'), dict(kind='submit', wait_requested=False)]
            if (frame + 1) % 30 == 0:
                io += [dict(kind='gpu-snapshot'), dict(kind='gpu-subset'), dict(kind='readback'),
                       dict(kind='flush'), dict(kind='submit', wait_requested=True)]
        io += [dict(kind='readback'), dict(kind='flush'), dict(kind='submit', wait_requested=True)] * 2
        row = dict(cycle=i, frames=180, initial=context(2*i+1, 'ready'), final=context(2*i+1, 'closed'),
                   other_initial=context(2*i+2, 'ready'), other_final=context(2*i+2, 'closed'),
                   target=dict(backend='direct3d', native_backend=3, context_matches=True, context_generation=2*i+1, width=8, height=8),
                   image=dict(backend='direct3d', context_matches=True, context_generation=2*i+1, texture_backed=True),
                   detached_encoded_after_teardown=True, io=io)
        for role in ('cpu', 'gpu', 'detached'):
            name = f'cycle-{i}-{role}.png'; (directory / name).write_bytes(png()); row[role+'_png'] = name
        cycles.append(row)
    report = dict(schema=1, stage='0.48', status='passed', validation_run=directory.name,
                  adapter_selection=selection, os='windows', architecture='x86_64', test_counts=counts, cycles=cycles,
                  window_created=False, presentation_verified=False, hardware_acceleration_verified=False, performance_measured=False)
    (directory / 'd3d12.diagnostic.json').write_text(json.dumps(report))
    return report


class Inspector(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name) / 'gpu-d3d12-test'
        self.report = fixture(self.directory)
    def bad(self, change):
        change(self.report)
        (self.directory / 'd3d12.diagnostic.json').write_text(json.dumps(self.report))
        with self.assertRaises((ValueError, KeyError, TypeError)): d.inspect(self.directory)
    def test_valid(self):
        result = d.inspect(self.directory)
        self.assertEqual((result['native_cases'], result['contexts'], result['stress_frames']), (95, 6, 540))
        self.assertFalse(result['hardware_acceleration_verified'])
    def test_hardware_separate(self):
        fixture(self.directory, 'hardware')
        self.assertEqual(d.inspect(self.directory, 'hardware')['renderer_class'], 'hardware-reported')
        with self.assertRaises(ValueError): d.inspect(self.directory, 'warp')
    def test_schema_bool(self): self.bad(lambda r: r.update(schema=True))
    def test_adapter_name_missing(self): self.bad(lambda r: r['cycles'][0]['initial'].update(adapter_name=''))
    def test_warp_index(self): self.bad(lambda r: r['cycles'][0]['initial'].update(adapter_index=0))
    def test_luid_changed(self): self.bad(lambda r: r['cycles'][0]['final'].update(adapter_luid_low=1))
    def test_generation_bool(self): self.bad(lambda r: r['cycles'][0]['target'].update(context_generation=True))
    def test_hardware_index_changed(self):
        fixture(self.directory, 'hardware')
        with self.assertRaises(ValueError): d.inspect(self.directory, 'hardware', 1)
    def test_failed(self): self.bad(lambda r: r.update(status='failed'))
    def test_foreign_run(self): self.bad(lambda r: r.update(validation_run='old'))
    def test_wrong_platform(self): self.bad(lambda r: r.update(os='macosx'))
    def test_missing_cycle(self): self.bad(lambda r: r['cycles'].pop())
    def test_shortened_stress(self): self.bad(lambda r: r['cycles'][0].update(frames=1))
    def test_bool_not_failure_count(self): self.bad(lambda r: r['test_counts'].update(surface_failures=False))
    def test_native_failure(self): self.bad(lambda r: r['test_counts'].update(image_failures=1))
    def test_missing_native_suite(self): self.bad(lambda r: r['test_counts'].update(cache=0))
    def test_wrong_backend(self): self.bad(lambda r: r['cycles'][0]['initial'].update(native_backend=0))
    def test_wrong_flag(self): self.bad(lambda r: r['cycles'][0]['initial'].update(adapter_flags=0))
    def test_flag_bool(self): self.bad(lambda r: r['cycles'][0]['initial'].update(adapter_flags=True))
    def test_wrong_renderer_class(self): self.bad(lambda r: r['cycles'][0]['initial'].update(renderer_class='hardware-reported'))
    def test_queue_not_owned(self): self.bad(lambda r: r['cycles'][0]['initial'].update(command_queue_owned=False))
    def test_gui(self): self.bad(lambda r: r['cycles'][0]['initial'].update(requires_gui=True))
    def test_live_resource(self): self.bad(lambda r: r['cycles'][0]['final'].update(live_children=1))
    def test_pending_release(self): self.bad(lambda r: r['cycles'][0]['final'].update(pending_releases=1))
    def test_failed_release(self): self.bad(lambda r: r['cycles'][0]['final'].update(failed_releases=1))
    def test_not_closed(self): self.bad(lambda r: r['cycles'][0]['final'].update(state='ready'))
    def test_reused_generation(self): self.bad(lambda r: r['cycles'][1]['initial'].update(generation=1))
    def test_foreign_target(self): self.bad(lambda r: r['cycles'][0]['target'].update(context_generation=2))
    def test_cpu_image(self): self.bad(lambda r: r['cycles'][0]['image'].update(texture_backed=False))
    def test_early_serialization(self): self.bad(lambda r: r['cycles'][0].update(detached_encoded_after_teardown=False))
    def test_missing_submit(self): self.bad(lambda r: r['cycles'][0]['io'].pop(2))
    def test_missing_readback(self): self.bad(lambda r: r['cycles'][0].update(io=[]))
    def test_normal_frame_wait(self): self.bad(lambda r: r['cycles'][0]['io'][2].update(wait_requested=True))
    def test_unsafe_path(self): self.bad(lambda r: r['cycles'][0].update(cpu_png='../outside.png'))
    def test_hardware_claim(self): self.bad(lambda r: r.update(hardware_acceleration_verified=True))
    def test_presentation_claim(self): self.bad(lambda r: r.update(presentation_verified=True))
    def test_wrong_pixels(self):
        (self.directory / 'cycle-0-gpu.png').write_bytes(png(bytes(256)))
        with self.assertRaises(ValueError): d.inspect(self.directory)
    def test_shared_wrong_reference(self):
        for f in self.directory.glob('*.png'): f.write_bytes(png(bytes(256)))
        with self.assertRaises(ValueError): d.inspect(self.directory)
    def test_png_crc(self):
        p = self.directory / 'cycle-0-cpu.png'; data = bytearray(p.read_bytes()); data[-1] ^= 1; p.write_bytes(data)
        with self.assertRaises(ValueError): d.inspect(self.directory)
    def test_png_truncated(self):
        p = self.directory / 'cycle-0-cpu.png'; p.write_bytes(p.read_bytes()[:-3])
        with self.assertRaises(ValueError): d.inspect(self.directory)
    def test_png_trailing(self):
        p = self.directory / 'cycle-0-cpu.png'; p.write_bytes(p.read_bytes() + b'bad')
        with self.assertRaises(ValueError): d.inspect(self.directory)


class Runner(unittest.TestCase):
    def simulate(self, fail=None, identity=None, abi=None, change=None):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t); output = root / 'probe'; output.mkdir()
            calls = []
            def run(args):
                args = [str(x) for x in args]; calls.append(args)
                if fail and any(fail in a for a in args): raise RuntimeError('synthetic command failure')
                if args[1].endswith('ci-identity.rkt'):
                    return json.dumps(identity or dict(os='windows', architecture='x86_64', pointer_bytes=8))
                if args[1].endswith('check-d3d12-call.rkt'):
                    return json.dumps(abi if abi is not None else dict(status='passed', by_value_call_verified=True))
                if args[1].endswith('gpu-d3d12-doctor.rkt'):
                    report = fixture(output)
                    if change:
                        change(report); (output / 'd3d12.diagnostic.json').write_text(json.dumps(report))
                return ''
            result = d.execute(root, '/selected Racket/racket.exe', output, run)
            return calls, result
    def test_order_and_selected_racket(self):
        calls, result = self.simulate()
        self.assertTrue(result['by_value_call_verified'])
        self.assertEqual(calls[1][-2:], ['-A', 'x64'])
        for c in calls:
            if len(c) > 1 and (c[1].endswith('.rkt') or 'raco' in c):
                self.assertEqual(c[0], '/selected Racket/racket.exe')
        self.assertTrue(calls[-1][1].endswith('gpu-d3d12-doctor.rkt'))
        self.assertIn('warp', calls[-1])
    def test_compile_failure(self):
        with self.assertRaises(RuntimeError): self.simulate(fail='--build')
    def test_abi_failure(self):
        with self.assertRaises(ValueError): self.simulate(abi=dict(status='failed'))
    def test_doctor_failure(self):
        with self.assertRaises(RuntimeError): self.simulate(fail='gpu-d3d12-doctor.rkt')
    def test_inspector_failure(self):
        with self.assertRaises(ValueError): self.simulate(change=lambda r: r.update(status='failed'))
    def test_non_windows(self):
        with self.assertRaises(ValueError): self.simulate(identity=dict(os='unix', architecture='x86_64', pointer_bytes=8))
    def test_no_stale_directory(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t); (p/'old').touch()
            with self.assertRaises(ValueError): d.execute(p, 'racket', p, lambda a: '')


class Source(unittest.TestCase):
    def test_guid_bytes(self):
        source = (HERE.parent / 'private/gpu-d3d12-types.rkt').read_text()
        ids = dict(factory4='1bc6ea02-ef36-464f-bf0c-21ca39e5168a', adapter1='29038f61-3839-4626-91fd-086879011a05',
                   device='189819f1-1db6-4b57-be54-1821339b85f7', queue='0ec870a6-5d7e-4c22-8cfc-5baae07616ed')
        for name, expected in ids.items():
            text = re.search(r'\(define iid-' + name + r' #"([^"]+)"\)', source)[1]
            observed = text.encode().decode('unicode_escape').encode('latin1')
            self.assertEqual(observed, uuid.UUID(expected).bytes_le, name)
    def test_byvalue_signature(self):
        source = (HERE.parent / 'private/gpu-native.rkt').read_text()
        self.assertIn('(_fun _gr-d3d-backend-context -> _pointer)', source)
        self.assertNotIn('(_fun _gr-d3d-backend-context-pointer -> _pointer)', source)
    def test_sdk_slots_not_just_mirrors(self):
        source = (HERE / 'd3d12-abi/check.c').read_text()
        for term in ('IDXGIFactory4Vtbl', 'EnumWarpAdapter', 'ID3D12DeviceVtbl', 'GetDeviceRemovedReason', 'DXGI_ADAPTER_DESC1'):
            self.assertIn(term, source)
    def test_no_default_migration(self):
        self.assertEqual((HERE.parent / 'private/native-default-version.txt').read_text().strip(), '3.119.1')
    def test_shared_suites_are_called(self):
        source = (HERE / 'gpu-d3d12-doctor.rkt').read_text()
        for name in ('surface', 'image', 'cache'):
            self.assertIn('(run-tests (make-gpu-' + name + '-native-tests gpu other))', source)
    def test_no_optional_skip(self):
        for name in ('ci-d3d12.py', 'validate-d3d12.py'):
            self.assertNotIn('GPU_MODE', (HERE/name).read_text())



class CIEntry(unittest.TestCase):
    def setUp(self):
        self.ci = types.ModuleType('ci')
        self.matrix = types.ModuleType('ci_matrix')
        self.matrix.load_matrix = lambda: {'cpu': [{'id': 'windows-x64'}]}
        spec = importlib.util.spec_from_file_location('test_ci_d3d12_entry', HERE / 'ci-d3d12.py')
        self.module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, ci=self.ci, ci_matrix=self.matrix):
            spec.loader.exec_module(self.module)
    def test_warp_hook_uses_installed_copy(self):
        with tempfile.TemporaryDirectory() as t:
            installed = Path(t) / 'installed'; installed.mkdir()
            away = Path(t) / 'outside'; away.mkdir()
            calls = []
            runner = types.SimpleNamespace(run=lambda argv, **kw: calls.append((argv, kw)))
            report = {'racket_executable': 'selected racket', 'checks': {}}
            env = {'GPU_MODE': 'off'}  # not consumed as a skip by this gate
            def execute(root, racket, directory, run, **kwargs):
                self.assertEqual(root, installed); self.assertEqual(racket, 'selected racket')
                self.assertEqual(directory.parent, installed / 'output')
                self.assertEqual(kwargs, {'selection': 'warp'})
                run(['native-test']); return {'status': 'passed'}
            with patch.object(self.module, 'execute', side_effect=execute):
                self.module.warp_checks(runner, installed, away, env, report)
            self.assertEqual(calls[0][1], {'cwd': away, 'env': env})
            self.assertTrue(report['checks']['required_d3d12_warp'])
            self.assertEqual(report['gpu']['renderer_class'], 'software')
    def test_warp_failure_cannot_set_pass_flag(self):
        with tempfile.TemporaryDirectory() as t:
            report = {'racket_executable': 'racket', 'checks': {}}
            with patch.object(self.module, 'execute', side_effect=RuntimeError('failure')):
                with self.assertRaises(RuntimeError):
                    self.module.warp_checks(None, Path(t), Path(t), {}, report)
            self.assertNotIn('required_d3d12_warp', report['checks'])
    def test_ci_entry_reuses_full_package_path(self):
        source = (HERE / 'ci-d3d12.py').read_text()
        self.assertIn("ci.package_checks(runner, root, row, 'cpu', report, extra_checks=warp_and_parity_checks)", source)
        self.assertIn("ci.require(report['checks'].get('required_d3d12_warp') is True", source)


class Integration(unittest.TestCase):
    """Must run in the complete checkout/installed package; no partial-tree skips."""
    def test_required_job_and_aggregate(self):
        workflow = (HERE.parent / '.github/workflows/ci.yml').read_text()
        self.assertIn('needs: [source, cpu, egl, d3d12, dxgi, canvas]', workflow)
        self.assertIn('D3D12_RESULT: ${{ needs.d3d12.result }}', workflow)
        self.assertIn('test "$D3D12_RESULT" = success', workflow)
        self.assertIn('run: python tools/ci-d3d12.py', workflow)
        self.assertNotIn('continue-on-error:', workflow)
    def test_hook_precedes_source_check_and_cleanup(self):
        source = (HERE / 'ci.py').read_text()
        tree = ast.parse(source)
        f = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'package_checks')
        self.assertIn('extra_checks', [a.arg for a in f.args.kwonlyargs])
        calls = [n for n in ast.walk(f) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)]
        hook = [n for n in calls if n.func.id == 'extra_checks']
        self.assertEqual(len(hook), 1)
        verifies = sorted(n.lineno for n in calls if n.func.id == 'verify_install')
        copy_line = next(n.lineno for n in calls if n.func.id == 'copy_artifacts')
        self.assertLess(verifies[0], hook[0].lineno)
        self.assertLess(hook[0].lineno, verifies[-1]); self.assertLess(verifies[-1], copy_line)
    def test_all_shared_source_cases_match_report_counts(self):
        for name, count in d.COUNTS.items():
            source = (HERE.parent / 'tests' / ('gpu-' + name + '-native-test.rkt')).read_text()
            self.assertEqual(len(re.findall(r'\(test-case\s', source)), count)
    def test_pure_suite_is_wired(self):
        source = (HERE.parent / 'run-tests.rkt').read_text()
        self.assertIn('"tests/gpu-d3d12-pure-test.rkt"', source)
        self.assertIn('(run-tests gpu-d3d12-pure-tests)', source)
    def test_source_ci_runs_this_suite(self):
        self.assertIn("'test-d3d12.py'", (HERE / 'ci.py').read_text())

if __name__ == '__main__':
    unittest.main(verbosity=2)
