#!/usr/bin/env python3
"""Pure/source and malformed-evidence regression tests, not native execution."""
import copy
import contextlib
import io
import subprocess
import sys
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import advanced_canvas_validation as v
ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'synthetic-074-unit-test'


def audit_row(mode='vector', kind='pdf'):
    events = [dict(page=1, feature=f, status='vector') for f in ('geometry', 'annotation')]
    events.append(dict(page=1, feature='drawable' if mode == 'vector' else 'image',
                       status='vector' if mode == 'vector' else 'embedded-raster'))
    return dict(mode=mode, format=kind, file=f'{mode}.{kind}',
                boundary='native-drawable' if mode == 'vector' else 'explicit-integer-snapshot',
                audit=dict(backend=kind, mode='export', pages=1, blocking=False,
                           vector_only=(mode == 'vector'), events=events))


def float_bytes(order='little'):
    return b''.join(struct.pack(('<' if order == 'little' else '>')+'4e',
                                 .25, .5, .75, 1)
                    for y in range(6) for x in range(8))


def gpu_fixture(directory):
    rows = []
    for name in v.SCENES:
        (directory/(name+'.rgba')).write_bytes(v.expected_rgba(name))
        rows.append(dict(name=name, file=name+'.rgba', drawing_readbacks=0, inspection_readbacks=1,
            target=dict(storage='gpu', backend='opengl', native_backend=0, context_matches=True,
                        width=64, height=48, context_generation=1, color_type='RGBA8888',
                        alpha_type='premultiplied', requested_sample_count=0, actual_sample_count=False,
                        render_path='sk_surface_new_render_target'),
            io=[dict(kind='readback',width=64,height=48,row_bytes=256),dict(kind='flush'),
                dict(kind='submit',wait_requested=True)]))
    (directory/'layer-f16.pixels').write_bytes(float_bytes())
    (directory/'overdraw.alpha').write_bytes(v.expected_overdraw())
    checks = {flag: True for flag in ('nway_authoring_once','f16_layer','foreign_drawable_rejected',
              'foreign_backdrop_rejected','layer_exception_cleanup','nway_exception_cleanup',
              'overdraw_capability_checked','overdraw_supported')}
    checks['overdraw_capability'] = dict(backend='opengl',color_type_name='alpha-8',renderable=True,
                                       max_sample_count=4,allocation_verified=False)
    return dict(schema=1,stage=v.STAGE,status='passed',run_token=TOKEN,backend='egl',adapter='hardware',
                cases=v.GPU_CASES,failures=0,checks=checks,contexts_closed=True,captures=rows,
                float_order='little',hdr_verified=False,physical_display_verified=False)


class Pixels(unittest.TestCase):
    def test_all_rgba_scenes(self):
        for scene in v.SCENES: v.check_rgba(v.expected_rgba(scene),scene)
    def test_opaque_black_is_not_a_reference(self):
        with self.assertRaises(ValueError): v.check_rgba(bytes([0,0,0,255])*64*48,'layer')
    def test_missing_opacity(self):
        with self.assertRaises(ValueError): v.check_rgba(v.expected_rgba('vector'),'layer')
    def test_missing_backdrop_offset(self):
        with self.assertRaises(ValueError): v.check_rgba(v.expected_rgba('vector'),'backdrop')
    def test_dimensions(self):
        with self.assertRaises(ValueError): v.check_rgba(b'','layer')
    def test_document_marker(self):
        with self.assertRaises(ValueError): v.check_rgba(v.expected_rgba('vector'),'vector',document=True)
    def test_float_both_orders(self):
        for order in ('little','big'): v.check_f16(float_bytes(order),order)
    def test_unknown_byte_order(self):
        with self.assertRaises(ValueError): v.check_f16(float_bytes(),'native')
    def test_float_truncation(self):
        with self.assertRaises(ValueError): v.check_f16(float_bytes()[:-1],'little')
    def test_float_nonfinite(self):
        data=bytearray(float_bytes());data[:2]=struct.pack('<e',float('nan'))
        with self.assertRaises(ValueError): v.check_f16(data,'little')
    def test_float_wrong_midrange(self):
        data=bytearray(float_bytes());data[:2]=struct.pack('<e',.625)
        with self.assertRaises(ValueError): v.check_f16(data,'little')
    def test_float_wrong_channels(self):
        data=bytearray(float_bytes());data[2:6]=struct.pack('<2e',0,1)
        with self.assertRaises(ValueError): v.check_f16(data,'little')
    def test_float_late_pixel_corruption(self):
        data=bytearray(float_bytes());data[4*8:4*8+2]=struct.pack('<e',.625)
        with self.assertRaises(ValueError): v.check_f16(data,'little')
    def test_alpha_count_oracle(self):
        data=v.expected_overdraw()
        self.assertEqual(data[0],0);self.assertEqual(data[3*12+3],1);self.assertEqual(data[3*12+5],2)


class DocumentReceipts(unittest.TestCase):
    def test_all_document_rows(self):
        for mode,kind in v.DOCUMENTS: v.check_document_row(audit_row(mode,kind))
    def reject(self, fn, mode='vector'):
        row=audit_row(mode);fn(row)
        with self.assertRaises(ValueError): v.check_document_row(row)
    def test_wrong_boundary(self):self.reject(lambda r:r.update(boundary='implicit'))
    def test_wrong_mode(self):self.reject(lambda r:r['audit'].update(mode='preflight'))
    def test_wrong_pages(self):self.reject(lambda r:r['audit'].update(pages=True))
    def test_blocking(self):self.reject(lambda r:r['audit'].update(blocking=True))
    def test_missing_annotation(self):self.reject(lambda r:r['audit']['events'].pop(1))
    def test_missing_drawable(self):self.reject(lambda r:r['audit']['events'].pop())
    def test_backdrop_disguised_as_vector(self):
        self.reject(lambda r:r['audit']['events'].append(dict(page=1,feature='layer-backdrop',status='needs-raster')))
    def test_backdrop_feature_cannot_be_laundered(self):
        self.reject(lambda r:r['audit']['events'].append(dict(page=1,feature='layer-backdrop',status='vector')))
    def test_image_disguised_as_vector(self):
        self.reject(lambda r:r['audit']['events'][-1].update(status='vector'),'layer')
    def test_vector_marker_as_raster(self):
        self.reject(lambda r:r['audit']['events'][0].update(status='embedded-raster'),'layer')
    def test_extra_image(self):
        self.reject(lambda r:r['audit']['events'].append(r['audit']['events'][-1]),'layer')
    def test_wrong_vector_claim(self):self.reject(lambda r:r['audit'].update(vector_only=False))


class Reports(unittest.TestCase):
    def invoke(self, mutate=lambda r,d:None):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);raw=gpu_fixture(directory);mutate(raw,directory)
            (directory/'gpu.json').write_text(json.dumps(raw))
            return v.inspect_gpu(directory,TOKEN,'egl','hardware')
    def reject(self, mutate):
        with self.assertRaises((ValueError,KeyError,TypeError)): self.invoke(mutate)
    def test_complete_receipt(self):self.assertEqual(self.invoke()['status'],'passed')
    def test_stale_token(self):self.reject(lambda r,d:r.update(run_token='old'))
    def test_wrong_stage(self):self.reject(lambda r,d:r.update(stage='0.73'))
    def test_boolean_failures(self):self.reject(lambda r,d:r.update(failures=False))
    def test_failed_run(self):self.reject(lambda r,d:r.update(failures=1,status='failed'))
    def test_incomplete_cases(self):self.reject(lambda r,d:r.update(cases=1))
    def test_wrong_backend(self):self.reject(lambda r,d:r.update(backend='metal'))
    def test_context_not_closed(self):self.reject(lambda r,d:r.update(contexts_closed=False))
    def test_duplicate_capture(self):self.reject(lambda r,d:r['captures'].__setitem__(0,r['captures'][1]))
    def test_missing_capture(self):self.reject(lambda r,d:(d/'layer.rgba').unlink())
    def test_fake_cpu_target(self):self.reject(lambda r,d:r['captures'][0]['target'].update(storage='raster'))
    def test_wrong_native_backend(self):self.reject(lambda r,d:r['captures'][0]['target'].update(native_backend=False))
    def test_hidden_readback(self):self.reject(lambda r,d:r['captures'][0].update(drawing_readbacks=1))
    def test_no_wait(self):self.reject(lambda r,d:r['captures'][0]['io'][2].update(wait_requested=False))
    def test_wrong_event_order(self):self.reject(lambda r,d:r['captures'][0]['io'].reverse())
    def test_extra_readback(self):self.reject(lambda r,d:r['captures'][0]['io'].append(dict(kind='readback')))
    def test_wrong_stride(self):self.reject(lambda r,d:r['captures'][0]['io'][0].update(row_bytes=260))
    def test_foreign_context(self):self.reject(lambda r,d:r['captures'][0]['target'].update(context_generation=9))
    def test_invented_samples(self):self.reject(lambda r,d:r['captures'][0]['target'].update(actual_sample_count=1))
    def test_unchecked_cross_context(self):self.reject(lambda r,d:r['checks'].update(foreign_drawable_rejected=False))
    def test_hdr_claim(self):self.reject(lambda r,d:r.update(hdr_verified=True))
    def test_fabricated_overdraw_skip(self):self.reject(lambda r,d:r['checks'].update(overdraw_supported=False))
    def test_real_zero_capability_is_not_a_pass_for_overdraw(self):
        def change(r,d):
            r['checks']['overdraw_supported']=False
            r['checks']['overdraw_capability'].update(max_sample_count=0,renderable=False)
            (d/'overdraw.alpha').unlink()
        self.assertFalse(self.invoke(change)['overdraw_executed'])
    def test_wrong_overdraw_pixels(self):self.reject(lambda r,d:(d/'overdraw.alpha').write_bytes(bytes(120)))


class Safety(unittest.TestCase):
    def test_unsafe_filenames(self):
        with tempfile.TemporaryDirectory() as temp:
            for name in ('../x','/tmp/x','x/y','C:x','x\\y','..','','missing'):
                with self.assertRaises(ValueError):v.safe_file(Path(temp),name)
    def test_duplicate_json(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'r.json';path.write_text('{"x":1,"x":2}')
            with self.assertRaises(ValueError):v.read_json(path)
    def test_nonfinite_json(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'r.json';path.write_text('{"x":NaN}')
            with self.assertRaises(ValueError):v.read_json(path)
    def test_exact_numbers_not_booleans(self):
        self.assertFalse(v.exact(True,1));self.assertFalse(v.exact(False,0))
    def test_required_backend_arguments(self):
        args=v.arguments(['--require-gpu','--backend','metal','--require-renderers'])
        self.assertTrue(args.require_gpu and args.require_renderers);self.assertEqual(args.backend,'metal')


class Orchestration(unittest.TestCase):
    """Commands and receipts are mocked; no execution evidence is manufactured."""
    def simulate(self, *, fail=None, mutate=False):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            (root/'SOURCE-SHA256SUMS.txt').write_text('synthetic manifest')
            (root/'run-tests.rkt').write_text('(define-runtime-path native-file "tests/native-test.rkt")')
            directory=root/'evidence'
            commands=[]
            def execute(runner,command):
                command=list(map(str,command));commands.append(command)
                if fail and any(fail in x for x in command):
                    raise subprocess.CalledProcessError(1,command)
                if mutate and any(x.endswith('advanced-canvas-doctor.rkt') for x in command):
                    (root/'SOURCE-SHA256SUMS.txt').write_text('changed source')
            with patch.object(v.shutil,'which',return_value=sys.executable), \
                 patch.object(v.Runner,'run',autospec=True,side_effect=execute), \
                 patch.object(v,'inspect_gpu',return_value={'status':'synthetic'}), \
                 patch.object(v,'inspect_documents',return_value={'status':'synthetic'}), \
                 contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                code=v.main(['--racket',sys.executable,'--directory',str(directory),
                             '--require-gpu','--backend','metal','--require-renderers'],root=root)
            return code,json.loads((directory/'validation.json').read_text()),commands
    def test_complete_sequence_uses_selected_racket_and_one_regression_run(self):
        code,report,commands=self.simulate()
        self.assertEqual(code,0)
        runs=[c for c in commands if len(c)==2 and c[1].endswith('run-tests.rkt')]
        self.assertEqual(len(runs),1)
        gpu=next(c for c in commands if any(x.endswith('advanced-canvas-gpu-test.rkt') for x in c) and '--backend' in c)
        doctor=next(c for c in commands if '--gpu-layer' in c)
        self.assertEqual(gpu[gpu.index('--token')+1],doctor[doctor.index('--token')+1])
        self.assertEqual(gpu[0],str(Path(sys.executable).resolve()))
        self.assertTrue(report['gpu_executed'] and report['independent_renderers_executed'])
    def test_failed_GPU_does_not_publish_documents(self):
        code,report,commands=self.simulate(fail='--adapter')
        self.assertEqual(code,1);self.assertFalse(report['documents_checked'])
        self.assertFalse(any('--gpu-layer' in c for c in commands))
    def test_failed_regression_stops_native_acceptance(self):
        code,report,commands=self.simulate(fail='run-tests.rkt')
        self.assertEqual(code,1);self.assertFalse(report['regressions_passed'])
        self.assertFalse(any('--adapter' in c for c in commands))
    def test_mutated_manifest_rejects_publication(self):
        code,report,_=self.simulate(mutate=True)
        self.assertEqual(code,1);self.assertIn('manifest changed',report['error'])


class Sources(unittest.TestCase):
    """Require real integrated files. The bundle verifier runs other classes only."""
    def source(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_version_and_registration(self):
        self.assertIn('(define version "0.76")',self.source('info.rkt'))
        self.assertIn("'test-advanced-canvases.py'",self.source('tools/ci.py'))
        self.assertIn('advanced-canvas-native-tests-file',self.source('run-tests.rkt'))
    def test_actual_suite_counts(self):
        for name,count in (('pure',v.PURE_CASES),('native',v.NATIVE_CASES)):
            self.assertEqual(self.source(f'tests/advanced-canvas-{name}-test.rkt').count('(test-case '),count)
        self.assertEqual(self.source('tests/advanced-canvas-gpu-test.rkt').count('(test! ')-1,v.GPU_CASES)
    def test_real_bindings(self):
        source=self.source('private/native.rkt')
        for name in ('sk_canvas_save_layer_rec','sk_picture_recorder_end_recording_as_drawable',
                     'sk_canvas_draw_drawable','sk_drawable_draw','sk_nodraw_canvas_new',
                     'sk_nway_canvas_add_canvas','sk_overdraw_canvas_new'):
            self.assertIn('(define-native '+name,source)
    def test_no_callback_backed_native_drawables(self):
        text=self.source('drawables.rkt')
        self.assertIn('sk_picture_recorder_end_recording_as_drawable',text)
        self.assertNotIn('_fun',text)
    def test_retained_provenance(self):
        text=self.source('private/audit-trace.rkt')
        for name in ('layer-backdrop','layer-initialization','layer-lcd-text','sk_drawable_draw'):
            self.assertIn(name,text)
    def test_layer_record_affinity(self):
        self.assertIn('sk_canvas_save_layer_rec',self.source('private/lifetime.rkt'))
    def test_scopes_pin_and_restore(self):
        text=self.source('advanced-layers.rkt')
        for name in ('call-with-continuation-barrier','pin-canvas-owner!','unpin-canvas-owner!',
                     'sk_canvas_restore_to_count','canvas-clip-rect!'):
            self.assertIn(name,text)
    def test_scope_owners_expire_and_unlink(self):
        text=self.source('specialized-canvases.rkt')
        self.assertIn('set-specialized-canvas-owner-live?! owner #f',text)
        self.assertIn('set-specialized-canvas-owner-dependencies! owner',text)
        self.assertIn('sk_nway_canvas_remove_all',text)
    def test_no_diagnostic_output_authority(self):
        self.assertIn('audit-specialized-scope!',self.source('specialized-canvases.rkt'))
        self.assertIn('diagnostic canvases cannot replace',self.source('private/audit-trace.rkt'))
    def test_overdraw_unsupported_hidden_text_guard(self):
        self.assertIn('overdraw diagnostics support direct primitives',self.source('private/core.rkt'))
    def test_native_layer_record_layout(self):
        text=self.source('private/advanced-canvas-types.rkt')
        for value in ('[bounds _pointer]','[paint _pointer]','[backdrop _pointer]','[flags _int]'):
            self.assertIn(value,text)
    def test_independent_svg_renderer_has_explicit_pixel_size(self):
        text=self.source('tools/advanced_canvas_validation.py')
        self.assertIn("['rsvg-convert', '--width', str(SIZE[0]), '--height', str(SIZE[1])",text)
    def test_three_workflows_remain(self):
        paths=ROOT/'.github/workflows'
        automatic={p.name for p in paths.glob('*.yml')
                   if '\n  push:' in p.read_text() or '\n  pull_request:' in p.read_text()}
        self.assertEqual(automatic,{'ci.yml','api-inventory.yml','acceptance.yml'})
        child=self.source('.github/workflows/advanced-canvases.yml')
        for value in ('workflow_call:','workflow_dispatch:','--backend egl','--backend direct3d',
                      '--adapter warp','--require-renderers'):
            self.assertIn(value,child)
        self.assertIn('test "$ADVANCED_CANVASES_RESULT" = success',self.source('.github/workflows/acceptance.yml'))


if __name__ == '__main__':unittest.main(verbosity=2)
