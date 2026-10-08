#!/usr/bin/env python3
"""Standard-library-only 0.67 source, receipt and orchestration regressions."""
from __future__ import annotations
import copy
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch
import api_inventory as inv
import geometry_completion_validation as gv

ROOT=Path(__file__).resolve().parents[1]
SPEC=importlib.util.spec_from_file_location('geometry_gate',ROOT/'tools/validate-geometry-completion.py')
GATE=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(GATE)
CAPABILITIES={'paths.arc-authoring','paths.recognition','paths.operation-builder','paths.conics',
 'paths.remaining-convenience','paint.fill-query','paint.introspection','geometry.regions-extra','geometry.rrect-extra'}
# Reviewed signatures from pinned m119 headers. They are an ABI declaration
# regression, NOT a runtime ABI certificate.
SIGNATURES = {'sk_opbuilder_add': '_pointer _pointer _int -> _void',
 'sk_opbuilder_destroy': '_pointer -> _void',
 'sk_opbuilder_new': '-> _pointer',
 'sk_opbuilder_resolve': '_pointer _pointer -> _stdbool',
 'sk_paint_get_blendmode': '_pointer -> _int',
 'sk_paint_get_stroke_cap': '_pointer -> _int',
 'sk_paint_get_stroke_join': '_pointer -> _int',
 'sk_paint_get_stroke_miter': '_pointer -> _float',
 'sk_paint_get_stroke_width': '_pointer -> _float',
 'sk_paint_is_antialias': '_pointer -> _stdbool',
 'sk_paint_is_dither': '_pointer -> _stdbool',
 'sk_paint_reset': '_pointer -> _void',
 'sk_paint_set_dither': '_pointer _stdbool -> _void',
 'sk_path_add_arc': '_pointer _pointer _float _float -> _void',
 'sk_path_add_path_matrix': '_pointer _pointer _pointer _int -> _void',
 'sk_path_add_poly': '_pointer _pointer _int _stdbool -> _void',
 'sk_path_add_rect_start': '_pointer _pointer _int _uint32 -> _void',
 'sk_path_add_rrect_start': '_pointer _pointer _int _uint32 -> _void',
 'sk_path_arc_to': '_pointer _float _float _float _int _int _float _float -> _void',
 'sk_path_arc_to_with_oval': '_pointer _pointer _float _float _stdbool -> _void',
 'sk_path_arc_to_with_points': '_pointer _float _float _float _float _float -> _void',
 'sk_path_convert_conic_to_quads': '_pointer _pointer _pointer _float _pointer _int -> _int',
 'sk_path_count_verbs': '_pointer -> _int',
 'sk_path_get_segment_masks': '_pointer -> _uint32',
 'sk_path_is_line': '_pointer _pointer -> _stdbool',
 'sk_path_is_oval': '_pointer _pointer -> _stdbool',
 'sk_path_is_rect': '_pointer _pointer _pointer _pointer -> _stdbool',
 'sk_path_is_rrect': '_pointer _pointer -> _stdbool',
 'sk_path_rarc_to': '_pointer _float _float _float _int _int _float _float -> _void',
 'sk_path_rewind': '_pointer -> _void',
 'sk_pathop_tight_bounds': '_pointer _pointer -> _stdbool',
 'sk_region_cliperator_delete': '_pointer -> _void',
 'sk_region_cliperator_done': '_pointer -> _stdbool',
 'sk_region_cliperator_new': '_pointer _pointer -> _pointer',
 'sk_region_cliperator_next': '_pointer -> _void',
 'sk_region_cliperator_rect': '_pointer _pointer -> _void',
 'sk_region_intersects_rect': '_pointer _pointer -> _stdbool',
 'sk_region_op_rect': '_pointer _pointer _int -> _stdbool',
 'sk_region_quick_contains': '_pointer _pointer -> _stdbool',
 'sk_region_quick_reject': '_pointer _pointer -> _stdbool',
 'sk_region_quick_reject_rect': '_pointer _pointer -> _stdbool',
 'sk_region_set_empty': '_pointer -> _stdbool',
 'sk_region_set_rect': '_pointer _pointer -> _stdbool',
 'sk_region_spanerator_delete': '_pointer -> _void',
 'sk_region_spanerator_new': '_pointer _int _int _int -> _pointer',
 'sk_region_spanerator_next': '_pointer _pointer _pointer -> _stdbool',
 'sk_rrect_get_radii': '_pointer _int _pointer -> _void',
 'sk_rrect_get_rect': '_pointer _pointer -> _void',
 'sk_rrect_get_type': '_pointer -> _int',
 'sk_rrect_inset': '_pointer _float _float -> _void',
 'sk_rrect_is_valid': '_pointer -> _stdbool',
 'sk_rrect_offset': '_pointer _float _float -> _void',
 'sk_rrect_outset': '_pointer _float _float -> _void',
 'sk_rrect_set_nine_patch': '_pointer _pointer _float _float _float _float -> _void',
 'sk_rrect_transform': '_pointer _pointer _pointer -> _stdbool'}

class Sources(unittest.TestCase):
    def text(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_nine_groups_are_classified_with_real_public_anchors(self):
        c=inv.load_catalog(ROOT);summary=inv.validate_catalog(c)
        self.assertNotIn('0.67',summary['next_stages'])
        rows={r['id']:r for r in c['features']['capabilities']}
        for name in CAPABILITIES:
            self.assertEqual(rows[name]['status'],'supported-with-limits')
            self.assertTrue(rows[name]['public_equivalents'])
            self.assertEqual(rows[name]['execution_evidence'],inv.EVIDENCE_SCOPE)
    def test_snapshot_equivalents_do_not_invent_bindings(self):
        c=inv.load_catalog(ROOT);b=set(c['bindings']['symbols'])
        for name in ('sk_path_iter_is_closed_contour','sk_path_rawiter_peek','sk_region_iterator_rewind','sk_rrect_set_empty'):
            self.assertNotIn(name,b)
        self.assertIn('(map path-segment-verb (path-segments p #:mode',self.text('geometry.rkt'))
    def test_native_declarations_match_reviewed_signatures(self):
        declarations={f[1]:f[2] for f in inv.forms(self.text('private/native.rkt'))
                      if isinstance(f,list) and len(f)>2 and f[0]=='define-native'}
        for name,sig in SIGNATURES.items():
            self.assertEqual(declarations[name],['_fun',*sig.split()],name)
    def test_direct_native_calls_have_correct_arity(self):
        arity={n:len(s.split(' -> ')[0].split()) for n,s in SIGNATURES.items() if not s.startswith('->')}
        arity.update({n:0 for n,s in SIGNATURES.items() if s.startswith('->')})
        def walk(form):
            if not isinstance(form,list) or not form:return
            if form[0]=='quote':return
            if isinstance(form[0],str) and form[0] in arity:
                self.assertEqual(len(form)-1,arity[form[0]],form[0])
            for x in form:walk(x)
        for f in inv.forms(self.text('geometry.rkt')):walk(f)
    def test_new_racket_files_are_structurally_complete(self):
        for name in ('geometry.rkt','private/geometry-completion-util.rkt','tests/geometry-completion-fixtures.rkt',
                     'tests/geometry-completion-pure-test.rkt','tests/geometry-completion-native-test.rkt',
                     'tests/geometry-completion-gpu-test.rkt','tools/geometry-completion-doctor.rkt','examples/geometry.rkt'):
            with self.subTest(file=name):self.assertTrue(inv.forms(self.text(name)))
    def test_hairline_status_is_not_misreported_as_allocation_failure(self):
        s=self.text('geometry.rkt')
        self.assertIn('(values result fillable?)',s)
        self.assertNotIn('(unless fillable?',s)
    def test_blend_mode_getter_advertises_native_fallback(self):
        self.assertIn('paint-blend-mode-or-src-over',self.text('geometry.rkt'))
        self.assertNotIn('(define (paint-blend-mode p)',self.text('geometry.rkt'))
    def test_path_results_refresh_fill_provenance(self):
        self.assertIn('(sk_path_set_filltype dst (sk_path_get_filltype dst))',self.text('geometry.rkt'))
        self.assertIn('(sk_path_set_filltype pp (sk_path_get_filltype pp))',self.text('geometry.rkt'))
    def test_native_reset_and_provenance_are_both_handled(self):
        for name in ('private/lifetime.rkt','private/audit-trace.rkt'):
            self.assertIn("[(eq? name 'sk_paint_reset)",self.text(name))
        s=self.text('private/lifetime.rkt');at=s.index("[(eq? name 'sk_paint_reset)")
        block=s[at:s.index("[(eq? name 'sk_paint_set_blendmode)",at)]
        self.assertLess(block.index('(thunk)'),block.index('(set-owned-slots! h empty-slots)'))
        self.assertIn('(install-binding! name h #f)',block)
    def test_dither_policy_is_explicit(self):
        self.assertIn('dither needs-raster needs-raster',self.text('output-policy.rkt'))
        self.assertIn("'dither (if (cadr args) '(dither) '())",self.text('private/audit-trace.rkt'))
    def test_no_new_raw_pointer_ingress(self):
        s=self.text('geometry.rkt')
        self.assertNotIn('get-ffi-obj',s);self.assertNotIn('ffi-lib',s)
        self.assertIn('call-with-native-temporary',s)
        self.assertNotIn('(provide (all-defined-out))',s)
    def test_regressions_and_gpu_omit_registered(self):
        s=self.text('run-tests.rkt')
        self.assertIn('(run-tests geometry-completion-pure-tests)',s)
        self.assertIn("dynamic-require geometry-completion-native-tests-file 'geometry-completion-native-tests",s)
        self.assertIn('tests/geometry-completion-gpu-test.rkt',self.text('info.rkt'))
    def test_version_and_native_pins(self):
        s=self.text('info.rkt')
        for text in ('(define version "0.77")','("base" #:version "8.18")','("draw-lib" #:version "1.22")'):
            self.assertIn(text,s)
        self.assertEqual(inv.load_catalog(ROOT)['upstream']['package_version'],'3.119.1')
    def test_no_stale_current_package_assertion(self):
        for p in (ROOT/'tools').glob('*.py'):
            # Test this source itself without containing the literal old clause.
            self.assertNotIn('(define version "'+'0.66'+'")',p.read_text(encoding='utf-8'),p.name)
    def test_source_job_registers_new_standard_library_tests(self):
        self.assertIn("'test-geometry-completion.py'",self.text('tools/ci.py'))
    def test_gpu_domains_created_before_entry(self):
        s=self.text('tests/geometry-completion-gpu-test.rkt')
        self.assertLess(s.index('(set! other (create))'),s.index('(call-with-gpu-context ctx'))
        self.assertIn("'reset_inspection_readbacks reset-reads",s)
        self.assertIn("'reset_drawing_readbacks reset-drawing-reads",s)
    def test_vector_doctor_rejects_raster_representation(self):
        s=self.text('tools/geometry-completion-doctor.rkt')
        self.assertIn("#:policy 'vector-only",s);self.assertIn("#:policy 'require-vector",s)
        self.assertIn("(eq? (output-group-report-strategy group) 'native)",s)
        self.assertNotIn('draw-rasterized',s)
    def test_workflow_requires_selected_gpu_and_viewers(self):
        s=self.text('.github/workflows/geometry-completion.yml')
        for term in ('--require-gpu','--require-renderers','--backend egl','--backend direct3d','--adapter warp'):
            self.assertIn(term,s)
        self.assertNotIn('continue-on-error',s)

class Receipts(unittest.TestCase):
    def good(self):
        return dict(name='arc',format='pdf',callback_count=1,audit_policy='vector-only',
                    audit=dict(mode='export',backend='pdf',blocking=False,vector_only=True,
                               events=[dict(feature='geometry',status='vector')]),
                    group=dict(backend='pdf',policy='require-vector',strategy='native',pixel_size=False,bounds=[8,16,64,48]))
    def test_valid_receipt(self):gv.receipt(self.good(),'arc','pdf')
    def reject(self,change):
        row=self.good();change(row)
        with self.assertRaises(ValueError):gv.receipt(row,'arc','pdf')
    def test_boolean_callback_count(self):self.reject(lambda r:r.update(callback_count=True))
    def test_wrong_policy(self):self.reject(lambda r:r.update(audit_policy='report'))
    def test_preflight_is_not_export(self):self.reject(lambda r:r['audit'].update(mode='preflight'))
    def test_blocking_report(self):self.reject(lambda r:r['audit'].update(blocking=True))
    def test_nonvector_event(self):self.reject(lambda r:r['audit']['events'][0].update(status='rasterized'))
    def test_missing_geometry_event(self):self.reject(lambda r:r['audit'].update(events=[]))
    def test_raster_strategy(self):self.reject(lambda r:r['group'].update(strategy='raster'))
    def test_pixel_dimensions_on_native_group(self):self.reject(lambda r:r['group'].update(pixel_size=[64,48]))
    def test_displaced_group(self):self.reject(lambda r:r['group'].update(bounds=[0,0,64,48]))
    def test_foreign_scene(self):self.reject(lambda r:r.update(name='foreign'))

class PixelData(unittest.TestCase):
    @staticmethod
    def positive(name):
        out=bytearray(gv.WHITE*(64*48))
        for x,y,color in gv.PROBES[name]:out[4*(y*64+x):4*(y*64+x)+4]=bytes(color)
        return bytes(out)
    def test_positive_synthetic_probes(self):
        for name in gv.SCENES:gv.pixel_checks(self.positive(name),name)
    def test_blank_rejected(self):
        for name in gv.SCENES:
            with self.assertRaises(ValueError):gv.pixel_checks(bytes(gv.WHITE)*(64*48),name)
    def test_missing_pixel(self):
        with self.assertRaises(ValueError):gv.pixel_checks(self.positive('arc')[:-4],'arc')
    def test_transparent_background(self):
        data=bytearray(self.positive('arc'));data[3]=0
        with self.assertRaises(ValueError):gv.pixel_checks(bytes(data),'arc')
    def test_wrong_scene(self):
        with self.assertRaises(ValueError):gv.pixel_checks(self.positive('arc'),'missing')

class GPUReceipts(unittest.TestCase):
    def good(self):
        return dict(schema=1,stage='0.67',status='passed',run_token='token',backend='egl',adapter='hardware',
                    failures=0,frames=7,scenes=list(gv.SCENES),drawing_readbacks=0,inspection_readbacks=7,
                    reset_drawing_readbacks=0,reset_inspection_readbacks=1,reset_transfer_test_passed=True,
                    contexts_closed=True,gui_executed=False,physical_display_verified=False)
    def read(self,row):
        with tempfile.TemporaryDirectory() as t:
            path=Path(t)/'gpu.json';path.write_text(json.dumps(row))
            return gv.gpu_receipt(path,'token','egl','hardware')
    def test_valid_synthetic(self):self.assertEqual(self.read(self.good())['frames'],7)
    def test_bad_counts_fail(self):
        for key in ('failures','frames','drawing_readbacks','inspection_readbacks','reset_drawing_readbacks','reset_inspection_readbacks'):
            for value in (None,True,-1,100):
                row=self.good();row[key]=value
                with self.subTest(key=key,value=value),self.assertRaises(ValueError):self.read(row)
    def test_stale_or_failed_or_other_adapter(self):
        for key,value in [('schema',True),('run_token','stale'),('status','failed'),('backend','metal'),('adapter','warp')]:
            row=self.good();row[key]=value
            with self.assertRaises(ValueError):self.read(row)
    def test_incomplete_duplicate_scenes(self):
        row=self.good();row['scenes'][-1]='arc'
        with self.assertRaises(ValueError):self.read(row)
    def test_false_cleanup_or_display_claim(self):
        for key in ('reset_transfer_test_passed','contexts_closed','gui_executed','physical_display_verified'):
            row=self.good();row[key]=not row[key]
            with self.assertRaises(ValueError):self.read(row)

class CompileGraph(unittest.TestCase):
    def test_static_runner_and_dynamic_native_targets_both_compiled(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'run-tests.rkt').write_text('(define-runtime-path a "tests/a.rkt")\n(define-runtime-path a "tests/a.rkt")')
            targets=GATE.compile_targets(root)
            self.assertIn(root/'run-tests.rkt',targets);self.assertEqual(targets.count(root/'tests/a.rkt'),1)
            self.assertIn(root/'tests/geometry-completion-gpu-test.rkt',targets)
    def test_empty_dynamic_graph_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'run-tests.rkt').write_text('#lang racket/base')
            with self.assertRaises(ValueError):GATE.compile_targets(root)
    def test_failure_log_path_is_reported(self):
        s=(ROOT/'tools/validate-geometry-completion.py').read_text()
        self.assertIn("report['failed_log']=str(log)",s)
        self.assertIn("report['failed_command']=command",s)
    def test_timeout_rejects_nonfinite_values(self):
        for value in ('nan','inf','0','-1'):
            with self.assertRaises(SystemExit),patch.object(GATE.shutil,'which',return_value='/selected/racket'):
                GATE.main(['--timeout',value])

if __name__=='__main__':unittest.main(verbosity=2)
