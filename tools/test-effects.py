#!/usr/bin/env python3
"""0.66 source/evidence regression tests. Synthetic receipts are not rendering evidence."""
from __future__ import annotations
import copy
import json
from pathlib import Path
import tempfile
import unittest
import api_inventory as inv
import effects_validation as ev

ROOT=Path(__file__).resolve().parents[1]
NEW_SYMBOLS={
 'sk_path_effect_create_1d_path','sk_path_effect_create_2d_line','sk_path_effect_create_2d_path',
 'sk_maskfilter_new_table','sk_maskfilter_new_gamma','sk_maskfilter_new_clip','sk_maskfilter_new_shader',
 'sk_shader_new_perlin_noise_fractal_noise','sk_shader_new_perlin_noise_turbulence',
 'sk_shader_new_empty','sk_shader_with_color_filter','sk_shader_new_blender',
 'sk_blender_new_arithmetic','sk_imagefilter_new_blender','sk_imagefilter_new_picture_with_rect'}

class Sources(unittest.TestCase):
    def text(self,name): return (ROOT/name).read_text(encoding='utf-8')
    def test_native_registry_contains_all_new_symbols(self):
        forms=inv.forms(self.text('private/native.rkt'))
        declared={f[1] for f in forms if isinstance(f,list) and f and f[0]=='define-native'}
        self.assertTrue(NEW_SYMBOLS<=declared)
    def test_exact_catalog_delta(self):
        c=inv.load_catalog(ROOT);s=inv.validate_catalog(c)
        self.assertNotIn('0.66',s['next_stages'])
    def test_only_shader_masks_inherit_gpu_affinity(self):
        source=self.text('private/lifetime.rkt')
        self.assertIn("'(make-shader-mask-filter paint-mask-filter)",source)
        self.assertIn('path path-effect mask-filter',source)
    def test_shader_mask_children_kept_in_owned_scope(self):
        source=self.text('effects.rkt')
        self.assertIn('(new-mask-filter who (lambda () (sk_maskfilter_new_shader p)))',source)
        self.assertIn('(call-with-owned who (list h)',source)
    def test_implicit_source_normalized(self):
        source=self.text('effects.rkt')
        self.assertIn('(or bp implicit-source) (or fp implicit-source)',source)
        self.assertIn('(sk_imagefilter_new_offset 0.0 0.0 #f #f)',source)
    def test_picture_target_distinct_from_crop(self):
        source=self.text('private/filter-graph.rkt')
        self.assertIn('#:target [target #f] #:crop [crop #f]',source)
        self.assertIn('sk_imagefilter_new_picture_with_rect pp tr',source)
        self.assertIn('(crop-result who cr',source)
    def test_document_policy_and_affinity_not_bypassed(self):
        self.assertIn('arithmetic-blender',self.text('private/output-group-util.rkt'))
        for feature in ('perlin-noise','empty-shader','arithmetic-blender'):
            self.assertIn(feature+' needs-raster needs-raster',self.text('output-policy.rkt'))
    def test_example_cli_has_no_imported_mutation(self):
        s=self.text('examples/effects.rkt')
        self.assertIn('(module+ main',s)
        self.assertNotIn('(set!',s)
        self.assertNotIn('([format ',s)
    def test_regressions_registered(self):
        s=self.text('run-tests.rkt')
        self.assertIn('(run-tests effects-pure-tests)',s)
        self.assertIn("dynamic-require effects-native-tests-file 'effects-native-tests",s)
    def test_validator_recompiles_regression_graph(self):
        s=self.text('tools/validate-effects.py')
        self.assertIn("run_tests=ROOT/'run-tests.rkt'",s)
        self.assertIn("dynamic_targets=sorted(set(re.findall",s)
        self.assertIn("run([racket,'-l','raco','--','make',*modules])",s)
    def test_document_payload_is_exact_and_viewer_check_is_resampling_tolerant(self):
        s=self.text('tools/effects_validation.py')
        self.assertIn('embedded raster pixels differ from direct Skia reference',s)
        self.assertIn('maximum_8x8_block_error',s)
        self.assertNotIn('maximum_pixel_error',s)
    def test_scene_matrix_is_complete(self):
        s=self.text('tests/effects-fixtures.rkt')
        for name in ev.SCENES: self.assertIn(name,s)
        self.assertEqual(len(ev.SCENES),16)
    def test_racket_sources_have_balanced_datums(self):
        for name in ('effects.rkt','private/effects-util.rkt','tests/effects-fixtures.rkt',
                     'tests/effects-pure-test.rkt','tests/effects-native-test.rkt',
                     'tests/effects-gpu-test.rkt','tools/effects-doctor.rkt','examples/effects.rkt'):
            with self.subTest(file=name): self.assertTrue(inv.forms(self.text(name)))
    def test_gpu_gate_separates_drawing_and_capture(self):
        s=self.text('tests/effects-gpu-test.rkt')
        self.assertIn('(zero? (count-reads ledger))',s)
        self.assertIn('(= 1 (count-reads ledger))',s)
        self.assertIn("(gpu-context-state ctx) 'closed",s)
        self.assertIn('(define other (new-context))',s)
        self.assertLess(s.index('(define other (new-context))'),
                        s.index('(call-with-gpu-context ctx'))
    def test_no_native_version_migration(self):
        s=self.text('info.rkt')
        for term in ('(define version "0.77")','("base" #:version "8.18")','("draw-lib" #:version "1.22")'):
            self.assertIn(term,s)
    def test_workflow_selects_real_gpu_and_independent_renderers(self):
        s=self.text('.github/workflows/effects.yml')
        for term in ('--require-gpu','--require-renderers','--backend egl','--backend direct3d','--adapter warp'):
            self.assertIn(term,s)
        self.assertNotIn('continue-on-error',s)

class Receipts(unittest.TestCase):
    def good(self):
        return dict(name='table-mask',format='pdf',callback_count=1,vector_rejected=True,audit_policy='error',
                    audit=dict(mode='export',backend='pdf',blocking=False,events=[dict(feature='raster-group')]),
                    group=dict(backend='pdf',strategy='raster',policy='raster',pixel_size=[64,48],
                               bounds=[8,16,64,48],features=['mask-filter']))
    def test_valid_synthetic_receipt(self): ev.receipt(self.good(),'table-mask','pdf')
    def test_mode_is_not_policy(self):
        row=self.good();row['audit']['mode']='error'
        with self.assertRaises(ValueError):ev.receipt(row,'table-mask','pdf')
    def test_count_is_not_a_boolean(self):
        row=self.good();row['callback_count']=True
        with self.assertRaises(ValueError):ev.receipt(row,'table-mask','pdf')
    def test_missing_raster_boundary(self):
        row=self.good();row['audit']['events']=[]
        with self.assertRaises(ValueError):ev.receipt(row,'table-mask','pdf')
    def test_unknown_provenance(self):
        row=self.good();row['group']['features']=['unknown-resource']
        with self.assertRaises(ValueError):ev.receipt(row,'table-mask','pdf')
    def test_full_page_image_rejected(self):
        row=self.good();row['group']['pixel_size']=[96,72]
        with self.assertRaises(ValueError):ev.receipt(row,'table-mask','pdf')
    def test_missing_rejection(self):
        row=self.good();row['vector_rejected']=False
        with self.assertRaises(ValueError):ev.receipt(row,'table-mask','pdf')
    def test_blocking_audit(self):
        row=self.good();row['audit']['blocking']=True
        with self.assertRaises(ValueError):ev.receipt(row,'table-mask','pdf')
    def test_foreign_document(self):
        with self.assertRaises(ValueError):ev.receipt(self.good(),'fractal-noise','pdf')

class Data(unittest.TestCase):
    def test_premul_composite(self):
        px=bytes([64,0,0,64])*(64*48)
        self.assertEqual(ev.white_composite(px)[:4],bytes([255,191,191,255]))
    def test_premul_shape(self):
        with self.assertRaises(ValueError):ev.white_composite(b'')
    def test_straight_premultiplication(self):
        px=bytes([255,128,0,64])*(64*48)
        self.assertEqual(ev.premultiply_straight(px)[:4],bytes([64,32,0,64]))
    def test_block_comparison_tolerates_edge_resampling_but_rejects_blank(self):
        expected=bytearray(bytes([255,255,255,255])*(64*48))
        for y in range(24,28):
            for x in range(8,12): expected[4*(y*64+x):4*(y*64+x)+4]=bytes([255,0,0,255])
        filtered=bytearray(expected)
        filtered[4*(24*64+8):4*(24*64+8)+4]=bytes([255,128,128,255])
        maximum,mean=ev.block_rgb_error(bytes(filtered),bytes(expected))
        self.assertLess(maximum,40);self.assertLess(mean,8)
        maximum,mean=ev.block_rgb_error(bytes([255,255,255,255])*(64*48),bytes(expected))
        self.assertGreater(maximum,40)
    def test_nonpremul_data(self):
        with self.assertRaises(ValueError):ev.white_composite(bytes([255,0,0,64])*(64*48))
    def test_duplicate_json_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x';p.write_text('{"a":1,"a":2}')
            with self.assertRaises(ValueError):ev.read_json(p)
    def test_nonfinite_json_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x';p.write_text('{"a":NaN}')
            with self.assertRaises(ValueError):ev.read_json(p)
    def test_traversal(self):
        with tempfile.TemporaryDirectory() as t:
            for name in ('../x','/x','a\\x','a:x','..'):
                with self.assertRaises(ValueError):ev.evidence_file(Path(t),name)
    def test_missing_matrix(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);(p/'documents.json').write_text(json.dumps(dict(schema=1,stage='0.66',run_token='x',status='passed',documents=[])))
            with self.assertRaises(ValueError):ev.inspect_documents(p,'x')

class GPUReceipt(unittest.TestCase):
    def check(self,**updates):
        r=dict(schema=1,stage='0.66',run_token='x',status='passed',backend='egl',frames=30,
               inspection_readbacks=30,drawing_readbacks=0,failures=0,context_closed=True,
               gui_executed=False,physical_display_verified=False)
        r.update(updates)
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'gpu.json';p.write_text(json.dumps(r))
            return ev.gpu_receipt(p,'x','egl')
    def test_valid_synthetic_gpu_receipt(self): self.assertEqual(self.check()['frames'],30)
    def test_stale_token(self):
        with self.assertRaises(ValueError):self.check(run_token='old')
    def test_implicit_readback(self):
        with self.assertRaises(ValueError):self.check(drawing_readbacks=1)
    def test_no_positive_capture_control(self):
        with self.assertRaises(ValueError):self.check(inspection_readbacks=0)
    def test_failed_cleanup(self):
        with self.assertRaises(ValueError):self.check(context_closed=False)
    def test_missing_backend(self):
        with self.assertRaises(ValueError):self.check(backend='metal')
    def test_failed_native_test(self):
        with self.assertRaises(ValueError):self.check(failures=1)
    def test_false_display_claim(self):
        with self.assertRaises(ValueError):self.check(physical_display_verified=True)

if __name__=='__main__':unittest.main(verbosity=2)
