#!/usr/bin/env python3
"""0.68b source/inspector regressions. Synthetic inputs do not certify native rendering."""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import font_query_validation as fv

ROOT = Path(__file__).resolve().parents[1]
SIGNATURES = {
    'sk_font_is_force_auto_hinting': '_pointer -> _stdbool',
    'sk_font_set_force_auto_hinting': '_pointer _stdbool -> _void',
    'sk_font_is_embedded_bitmaps': '_pointer -> _stdbool',
    'sk_font_set_embedded_bitmaps': '_pointer _stdbool -> _void',
    'sk_font_is_baseline_snap': '_pointer -> _stdbool',
    'sk_font_set_baseline_snap': '_pointer _stdbool -> _void',
    'sk_font_set_typeface': '_pointer _pointer -> _void',
    'sk_font_get_widths_bounds': '_pointer _pointer _int _pointer _pointer _pointer -> _void',
    'sk_font_get_pos': '_pointer _pointer _int _pointer _pointer -> _void',
    'sk_font_get_xpos': '_pointer _pointer _int _pointer _float -> _void',
    'sk_font_get_paths': '_pointer _pointer _int _fpointer _pointer -> _void',
    'sk_font_break_text': '_pointer _bytes _size _int _float _pointer _pointer -> _size',
}
CAPABILITIES = ('fonts.options', 'fonts.glyph-queries', 'fonts.break-text', 'fonts.mutable-typeface')
RACKET_FILES = ('fonts.rkt', 'private/font-query-util.rkt', 'tests/font-query-pure-test.rkt',
                'tests/font-query-native-test.rkt', 'tests/font-query-fixtures.rkt',
                'tests/font-query-gpu-test.rkt', 'tools/font-query-doctor.rkt', 'examples/font-queries.rkt')


class Sources(unittest.TestCase):
    def text(self, name): return (ROOT/name).read_text(encoding='utf-8')
    def test_four_capabilities_are_public_without_invented_execution(self):
        import api_inventory as inv
        catalog = inv.load_catalog(ROOT); result = inv.validate_catalog(catalog)
        rows = {r['id']:r for r in catalog['features']['capabilities']}
        for name in CAPABILITIES:
            self.assertEqual(rows[name]['status'], 'supported-with-limits')
            self.assertIsNone(rows[name]['planned_stage'])
            self.assertTrue(rows[name]['public_equivalents'])
            self.assertEqual(rows[name]['execution_evidence'], inv.EVIDENCE_SCOPE)
        self.assertNotIn('0.68b', result['next_stages'])
    def test_reviewed_native_signatures(self):
        import api_inventory as inv
        declarations = {v[1]:v[2] for v in inv.forms(self.text('private/native.rkt'))
                        if isinstance(v,list) and v and v[0] == 'define-native'}
        for name, sig in SIGNATURES.items():
            self.assertEqual(declarations[name], ['_fun', *sig.split()], name)
    def test_direct_native_calls_match_arity(self):
        import api_inventory as inv
        arities = {k:len(v.split(' -> ')[0].split()) for k,v in SIGNATURES.items()}
        def walk(value):
            if not isinstance(value,list) or not value: return
            if isinstance(value[0],str) and value[0] in arities:
                self.assertEqual(len(value)-1, arities[value[0]], value[0])
            for child in value: walk(child)
        walk(inv.forms(self.text('fonts.rkt')))
    def test_sources_parse_and_suite_cases_are_nested(self):
        import api_inventory as inv
        for name in RACKET_FILES: self.assertTrue(inv.forms(self.text(name)), name)
        for name, suite in (('tests/font-query-pure-test.rkt','font-query-pure-tests'),
                            ('tests/font-query-native-test.rkt','font-query-native-tests')):
            forms = inv.forms(self.text(name))
            self.assertFalse(any(isinstance(f,list) and f and f[0] == 'test-case' for f in forms))
            value = next(f[2] for f in forms if isinstance(f,list) and f[:2] == ['define',suite])
            self.assertEqual(value[0], 'test-suite')
            self.assertGreaterEqual(sum(isinstance(f,list) and f and f[0] == 'test-case' for f in value), 20)
    def test_constructor_and_snapshot_copy_all_flags(self):
        source = self.text('private/core.rkt')
        for suffix in ('embedded_bitmaps', 'force_auto_hinting', 'baseline_snap'):
            self.assertIn(f'(sk_font_set_{suffix} fp (sk_font_is_{suffix} font-ptr))', source)
        for clause in ('#:embedded-bitmaps? [embedded-bitmaps? #f]',
                       '#:force-auto-hinting? [force-auto-hinting? #f]',
                       '#:baseline-snap? [baseline-snap? #t]'):
            self.assertIn(clause, source)
        self.assertIn('(font-native-get \'fallback-font base-font sk_font_is_embedded_bitmaps)', source)
        self.assertIn('(font-native-get \'fallback-font base-font sk_font_is_force_auto_hinting)', source)
        self.assertIn('(font-native-get \'fallback-font base-font sk_font_is_baseline_snap)', source)
    def test_typeface_mutation_releases_only_the_private_default_owner(self):
        source = self.text('fonts.rkt')
        self.assertIn('(list (font-h who f) (typeface-h who face))', source)
        self.assertLess(source.index('(sk_font_set_typeface fp tp)'), source.index('(set-font-owner! f #f)'))
        self.assertIn('(when old-owner (skia-close! old-owner))', source)
        self.assertNotIn('(skia-close! face)', source)
        self.assertIn('(struct font (handle [owner #:mutable])', self.text('private/core.rkt'))
    def test_callback_input_is_immobile_and_lifetime_is_explicit(self):
        source = self.text('fonts.rkt')
        self.assertIn("_uint16 'atomic-interior", source)
        self.assertIn('#:keep keeper', source)
        self.assertIn('(set-box! keeper #f)', source)
        self.assertIn('(void/reference-sink keeper callback receive input gs)', source)
        self.assertIn('(sk_path_add_path_matrix out borrowed matrix 0)', source)
        self.assertIn('(sk_path_set_filltype out (sk_path_get_filltype borrowed))', source)
        util = self.text('private/font-query-util.rkt')
        self.assertIn('(parameterize-break #f (invoke receive))', util)
        self.assertIn('(when failed? (raise failure))', util)
        self.assertIn('[(lambda (_) #t) save-failure]', util)
    def test_utf8_strict_index_conversion_and_native_size_t(self):
        self.assertIn('(bytes->string/utf-8 utf8 #f 0 count)', self.text('private/font-query-util.rkt'))
        self.assertIn('(font-break-prefix-length who utf8 count)', self.text('fonts.rkt'))
        self.assertIn('(ptr-set! measured _float 0.0)', self.text('fonts.rkt'))
    def test_no_public_borrowed_pointers_or_user_callbacks(self):
        source = self.text('fonts.rkt')
        for forbidden in ('get-ffi-obj','ffi-lib','all-defined-out','callback-exns?'):
            self.assertNotIn(forbidden, source)
        self.assertIn('(define (font-glyph-paths f glyphs)', source)
    def test_new_suites_registered_and_gpu_omitted_from_ordinary_raco_test(self):
        runner = self.text('run-tests.rkt')
        self.assertIn('(run-tests font-query-pure-tests)', runner)
        self.assertIn("dynamic-require font-query-native-tests-file 'font-query-native-tests", runner)
        self.assertIn('tests/font-query-gpu-test.rkt', self.text('info.rkt'))
        self.assertIn("'test-font-queries.py'", self.text('tools/ci.py'))
    def test_workflow_requires_pixels_and_independent_linux_viewers(self):
        source = self.text('.github/workflows/font-queries.yml')
        for term in ('--require-gpu','--require-renderers','--backend egl','--backend direct3d','--adapter warp'):
            self.assertIn(term, source)
        self.assertNotIn('continue-on-error', source)
    def test_native_pins_and_minimums_unchanged(self):
        source = self.text('info.rkt')
        for clause in ('(define version "0.77")','("base" #:version "8.18")','("draw-lib" #:version "1.22")'):
            self.assertIn(clause, source)
        self.assertEqual(self.text('private/native-default-version.txt').strip(), '3.119.1')


def good_receipts():
    rows = []
    for scene in fv.SCENES:
        for fmt in ('pdf','svg'):
            feature = 'native-text' if fmt == 'pdf' and scene != 'batch' else 'geometry'
            rows.append(dict(scene=scene, format=fmt, text_mode='native' if fmt=='pdf' else 'outline',
                             file=f'{scene}-{fmt}.{fmt}', rgba=f'{scene}-{fmt}.rgba', callback_count=1,
                             audit_policy='vector-only', audit=dict(mode='export', backend=fmt, blocking=False,
                             vector_only=True, events=[dict(feature=feature,status='vector')])))
    return dict(schema=1, stage='0.68b', run_token='token', status='passed', width=160, height=100,
                documents=rows, rendering_executed=True, gui_executed=False, gpu_executed=False)


class Receipts(unittest.TestCase):
    def test_complete_synthetic_receipt(self): self.assertEqual(len(fv.document_receipts(good_receipts(),'token')),6)
    def reject(self, change):
        value=good_receipts();change(value)
        with self.assertRaises(ValueError):fv.document_receipts(value,'token')
    def test_schema_bool(self):self.reject(lambda v:v.update(schema=True))
    def test_stale_identity(self):self.reject(lambda v:v.update(run_token='old'))
    def test_missing_document(self):self.reject(lambda v:v['documents'].pop())
    def test_duplicate_document(self):self.reject(lambda v:v['documents'].__setitem__(1,copy.deepcopy(v['documents'][0])))
    def test_wrong_dimensions(self):self.reject(lambda v:v.update(width=True))
    def test_wrong_filename(self):self.reject(lambda v:v['documents'][0].update(file='../x.pdf'))
    def test_boolean_authoring_count(self):self.reject(lambda v:v['documents'][0].update(callback_count=True))
    def test_weakened_policy(self):self.reject(lambda v:v['documents'][0].update(audit_policy='report'))
    def test_preflight_is_not_export(self):self.reject(lambda v:v['documents'][0]['audit'].update(mode='preflight'))
    def test_raster_event(self):self.reject(lambda v:v['documents'][0]['audit']['events'][0].update(status='rasterized'))
    def test_missing_events(self):self.reject(lambda v:v['documents'][0]['audit'].update(events=[]))
    def test_native_text_not_outlined_silently(self):self.reject(lambda v:v['documents'][0]['audit']['events'][0].update(feature='geometry'))
    def test_false_gpu_execution_claim(self):self.reject(lambda v:v.update(gpu_executed=True))
    def test_failed_generation(self):self.reject(lambda v:v.update(status='failed'))


class Pixels(unittest.TestCase):
    @staticmethod
    def data(scene):
        raw = bytearray(bytes(fv.WHITE)*fv.WIDTH*fv.HEIGHT)
        for x,y,color in fv.PROBES[scene]:raw[4*(y*fv.WIDTH+x):4*(y*fv.WIDTH+x)+4]=bytes(color)
        return bytes(raw)
    def test_synthetic_interior_probes(self):
        for scene in fv.SCENES:fv.pixel_checks(self.data(scene),scene)
    def test_blank_rejected(self):
        for scene in fv.SCENES:
            with self.assertRaises(ValueError):fv.pixel_checks(bytes(fv.WHITE)*160*100,scene)
    def test_missing_byte(self):
        with self.assertRaises(ValueError):fv.pixel_checks(self.data('batch')[:-1],'batch')
    def test_transparency_outside_probes(self):
        raw=bytearray(self.data('snapshot'));raw[3]=0
        with self.assertRaises(ValueError):fv.pixel_checks(raw,'snapshot')
    def test_mutation_scene_distinguished(self):
        with self.assertRaises(ValueError):fv.pixel_checks(self.data('mutated'),'snapshot')


class GPUReceipts(unittest.TestCase):
    @staticmethod
    def good():
        return dict(schema=1, stage='0.68b', status='passed', run_token='token', backend='egl', adapter='hardware',
                    failures=0, frames=3, scenes=list(fv.SCENES), drawing_readbacks=0, inspection_readbacks=3,
                    contexts_closed=True, gui_executed=False, physical_display_verified=False)
    def read(self, value):
        with tempfile.TemporaryDirectory() as name:
            path=Path(name)/'gpu.json';path.write_text(json.dumps(value),encoding='utf-8')
            return fv.gpu_receipt(path,'token','egl','hardware')
    def test_synthetic_complete(self):self.assertEqual(self.read(self.good())['frames'],3)
    def test_counts_not_booleans_or_missing(self):
        for key in ('schema','failures','frames','drawing_readbacks','inspection_readbacks'):
            for value in (True,None,-1,99):
                row=self.good();row[key]=value
                with self.subTest(key=key,value=value),self.assertRaises(ValueError):self.read(row)
    def test_wrong_execution_identity(self):
        for key,value in (('backend','metal'),('adapter','warp'),('stage','0.68a'),('run_token','old'),('status','failed')):
            row=self.good();row[key]=value
            with self.assertRaises(ValueError):self.read(row)
    def test_cleanup_and_display_scope(self):
        for key in ('contexts_closed','gui_executed','physical_display_verified'):
            row=self.good();row[key]=not row[key]
            with self.assertRaises(ValueError):self.read(row)
    def test_duplicate_or_missing_scene(self):
        row=self.good();row['scenes']=['batch']*3
        with self.assertRaises(ValueError):self.read(row)


class FileChecks(unittest.TestCase):
    def test_json_rejects_duplicate_nonfinite_nonobject(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x.json'
            for text in ('{"x":1,"x":2}','{"x":NaN}','[]','true'):
                p.write_text(text)
                with self.assertRaises(ValueError):fv.read_json(p)
    def test_unsafe_evidence_names(self):
        with tempfile.TemporaryDirectory() as t:
            for name in ('../x','/x','a/b','a\\b','',None):
                with self.assertRaises(ValueError):fv.checked_file(Path(t),name)
    def test_svg_vectors_and_physical_dimensions(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x.svg'
            p.write_text('<svg width="160pt" height="100pt"><rect/><path/></svg>')
            self.assertEqual(fv.inspect_svg(p)['vector_shapes'],2)
    def test_svg_refuses_fallbacks_and_entities(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x.svg'
            for body in ('<image/>','<text>AV</text>','<foreignObject/>','<script/>','<use href="https://example.invalid/x"/>'):
                p.write_text('<svg width="160pt" height="100pt"><rect/><path/>'+body+'</svg>')
                with self.assertRaises(ValueError):fv.inspect_svg(p)
            p.write_text('<!DOCTYPE svg><svg/>')
            with self.assertRaises(ValueError):fv.inspect_svg(p)
    def test_svg_wrong_size(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x.svg';p.write_text('<svg width="160px" height="100px"><rect/><path/></svg>')
            with self.assertRaises(ValueError):fv.inspect_svg(p)


class CompileGraph(unittest.TestCase):
    @staticmethod
    def gate():
        spec=importlib.util.spec_from_file_location('font_gate',ROOT/'tools/validate-font-queries.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
    def test_dynamic_suites_and_gpu_program_compiled(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'run-tests.rkt').write_text('(define-runtime-path a "tests/a.rkt")\n(define-runtime-path a "tests/a.rkt")')
            paths=self.gate().compile_targets(root)
            self.assertEqual(paths.count(root/'tests/a.rkt'),1)
            self.assertIn(root/'tests/font-query-gpu-test.rkt',paths)
    def test_empty_dynamic_graph_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'run-tests.rkt').write_text('#lang racket/base')
            with self.assertRaises(ValueError):self.gate().compile_targets(root)
    def test_invalid_timeouts(self):
        gate=self.gate()
        for timeout in ('nan','inf','0','-1'):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                gate.main(['--timeout',timeout])
    def test_failure_logs_retained(self):
        source=(ROOT/'tools/validate-font-queries.py').read_text()
        self.assertIn('failed_command=command, failed_log=str(log)',source)
        self.assertIn("'validation.json'",source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
