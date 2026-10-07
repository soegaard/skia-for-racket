#!/usr/bin/env python3
"""Standard-library 0.70 source and inspector regressions. No native claims."""
from __future__ import annotations
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import integer_pixel_validation as v

ROOT=Path(__file__).resolve().parents[1]
RACKET_FILES=('image-info.rkt','raster-buffers.rkt','private/integer-pixel-util.rkt','private/image-info-native.rkt',
              'tests/integer-pixel-pure-test.rkt','tests/integer-pixel-native-test.rkt','tests/integer-pixel-fixtures.rkt',
              'tests/integer-pixel-gpu-test.rkt','tools/integer-pixel-doctor.rkt','examples/integer-pixels.rkt')

def synthetic(fmt):
    return b''.join(bytes(v.oracle_color(fmt,x,y)) for y in range(v.HEIGHT) for x in range(v.WIDTH))

def row(fmt='rgba-8888',kind='pdf'):
    return dict(source_format=fmt,format=kind,conversion='explicit-rgba-nearest',image_width=64,image_height=32,
                file=fmt+'-'+kind+'.'+kind,rgba=fmt+'-'+kind+'.rgba',callback_count=1,audit_policy='error',
                audit=dict(mode='export',backend=kind,blocking=False,vector_only=False,
                           events=[dict(feature='image',status='embedded-raster'),
                                   dict(feature='geometry',status='vector'),
                                   dict(feature='annotation',status='vector')]))

class Sources(unittest.TestCase):
    def text(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def reader(self):
        import api_inventory as inv
        return inv
    def test_all_sources_have_balanced_reader_forms(self):
        inv=self.reader()
        for name in RACKET_FILES:self.assertTrue(inv.forms(self.text(name)),name)
    def test_cases_are_nested_in_the_two_suites(self):
        inv=self.reader()
        for kind in ('pure','native'):
            forms=inv.forms(self.text('tests/integer-pixel-'+kind+'-test.rkt'))
            self.assertFalse(any(isinstance(x,list) and x and x[0]=='test-case' for x in forms))
            body=next(x[2] for x in forms if isinstance(x,list) and x[:2]==['define','integer-pixel-'+kind+'-tests'])
            self.assertEqual(body[0],'test-suite')
            self.assertGreaterEqual(sum(isinstance(x,list) and x and x[0]=='test-case' for x in body),30)
    def test_six_families_have_reviewed_public_anchors(self):
        inv=self.reader();c=inv.load_catalog(ROOT);summary=inv.validate_catalog(c)
        self.assertNotIn('0.70',summary['next_stages'])
        rows={r['id']:r for r in c['features']['capabilities']}
        for ident in ('pixels.bitmap-alpha','pixels.bitmap-general','pixels.opacity','pixels.pixmap-info','images.bitmap-copy','surfaces.raster'):
            r=rows[ident];self.assertIn(r['status'],('supported-with-limits','racket-equivalent'))
            self.assertTrue(r['public_equivalents']);self.assertIsNone(r['planned_stage'])
            self.assertEqual(r['execution_evidence'],inv.EVIDENCE_SCOPE)
    def test_only_reviewed_opacity_native_binding_added(self):
        inv=self.reader()
        forms=inv.forms(self.text('private/native.rkt'))
        found=[f for f in forms if isinstance(f,list) and f[:2]==['define-native','sk_pixmap_compute_is_opaque']]
        self.assertEqual(len(found),1)
        self.assertEqual(found[0][2],['_fun','_pointer','->','_stdbool'])
    def test_legacy_constructor_arity_is_preserved_by_auto_field(self):
        self.assertIn('[description #:auto #:mutable]',self.text('private/core.rkt'))
        self.assertIn('set-raster-buffer-resource-description!',self.text('private/core.rkt'))
        self.assertIn('(make-raster-buffer-record handle w h rb cp (box #f))',self.text('raster-buffers.rkt'))
    def test_default_buffer_premultiplication_stays_in_existing_helper(self):
        self.assertIn('(prepare-raster-input who w h data row-bytes premultiplied?)',self.text('raster-buffers.rkt'))
    def test_no_rgba_hard_coded_subset_offset(self):
        source=self.text('raster-buffers.rkt')
        self.assertIn('(* (buffer-bpp b) (pixmap-x v))',source)
        self.assertNotIn('(* 4 (pixmap-x v))',source)
    def test_gpu_transfer_guard_precedes_exclusive_pointer_borrow(self):
        s=self.text('raster-buffers.rkt');s=s[s.index('(define (call-with-raster-buffer-gpu-transfer'):]
        self.assertLess(s.index("'gpu-readback"),s.index('(call-exclusive'))
        self.assertIn('rgba-8888',self.text('image-info.rkt'))
    def test_owned_color_space_refs_have_matching_cleanup(self):
        s=self.text('raster-buffers.rkt')
        self.assertIn('(when cp (sk_colorspace_ref cp))',s)
        self.assertIn('(when cp (sk_colorspace_unref cp))',s)
    def test_pixmap_staging_uses_immobile_address_and_finally_free(self):
        s=self.text('raster-buffers.rkt')
        self.assertIn("(malloc (bytes-length input) 'raw)",s)
        self.assertIn('(sk_pixmap_new_with_params native memory (* w 4))',s)
        self.assertIn('(lambda () (free memory))',s)
    def test_raw_validation_precedes_destination_memcpy(self):
        s=self.text('raster-buffers.rkt');s=s[s.index('(define (raster-buffer-write-storage!'):s.index('(define (pixmap->rgba-bytes')]
        self.assertLess(s.index('pixel-storage-input'),s.index('(memcpy p input'))
    def test_no_pointer_ingress_or_uninitialized_allocation_api(self):
        s=self.text('image-info.rkt')+self.text('raster-buffers.rkt')
        self.assertNotIn('get-ffi-obj',s)
        self.assertNotIn('(provide (all-defined-out))',s)
        self.assertNotIn('make-uninitialized',s)
    def test_source_and_runtime_suites_registered(self):
        runner=self.text('run-tests.rkt')
        self.assertIn('(run-tests integer-pixel-pure-tests)',runner)
        self.assertIn("dynamic-require integer-pixel-native-tests-file 'integer-pixel-native-tests",runner)
        self.assertIn("'test-integer-pixels.py'",self.text('tools/ci.py'))
        self.assertIn('tests/integer-pixel-gpu-test.rkt',self.text('info.rkt'))
    def test_pins_and_package_minimums_unchanged(self):
        for clause in ('(define version "0.75")','("base" #:version "8.18")','("draw-lib" #:version "1.22")'):
            self.assertIn(clause,self.text('info.rkt'))
        self.assertEqual(self.text('private/native-default-version.txt').strip(),'3.119.1')
    def test_metadata_module_never_loads_skia(self):
        s=self.text('image-info.rkt')
        for forbidden in ('"private/core.rkt"','"private/native.rkt"','skia-check!','ffi-lib','get-ffi-obj'):
            self.assertNotIn(forbidden,s)
    def test_current_stage_does_not_claim_generalized_gpu_surfaces(self):
        s=self.text('tests/integer-pixel-gpu-test.rkt')
        self.assertIn("'gpu_target_format \"rgba-8888\"",s)
        self.assertIn('make-integer-fixture-image',s)
        self.assertIn('gpu-surface-read-raster-buffer! surface wrong',s)
    def test_workflow_requires_full_regressions_and_renderers(self):
        s=self.text('.github/workflows/integer-pixels.yml')
        for x in ('--require-gpu','--require-renderers','--backend egl','--backend direct3d','--adapter warp'):
            self.assertIn(x,s)
        self.assertNotIn('continue-on-error',s)
    def test_native_call_arities_and_dynamic_wind_arity(self):
        inv=self.reader()
        arities={'sk_pixmap_new_with_params':3,'sk_pixmap_read_pixels':6,'sk_pixmap_scale_pixels':3,
                 'sk_pixmap_compute_is_opaque':1,'sk_pixmap_erase_color':3,'sk_image_new_raster_copy':3,
                 'sk_surface_new_raster':3,'sk_surface_new_raster_direct':6,'dynamic-wind':3,
                 'call-with-native-temporary':5,'make-raster-buffer-record':6,'make-surface-record':4,
                 'make-image-record':3,'new-owned':4,'call-with-owned':3}
        def walk(f):
            if not isinstance(f,list) or not f or f[0]=='quote':return
            if isinstance(f[0],str) and f[0] in arities:self.assertEqual(len(f)-1,arities[f[0]],repr(f)[:300])
            for x in f:walk(x)
        for name in RACKET_FILES:walk(inv.forms(self.text(name)))

class Pixels(unittest.TestCase):
    def test_all_synthetic_oracles(self):
        for f in v.FORMATS:self.assertGreater(v.pixel_checks(synthetic(f),f),2000)
    def test_blank_cannot_pass(self):
        for f in v.FORMATS:
            with self.assertRaises(ValueError):v.pixel_checks(bytes([255])*(v.WIDTH*v.HEIGHT*4),f)
    def test_swapped_red_blue_rejected(self):
        data=bytearray(synthetic('rgba-8888'))
        for i in range(0,len(data),4):data[i],data[i+2]=data[i+2],data[i]
        with self.assertRaises(ValueError):v.pixel_checks(bytes(data),'rgba-8888')
    def test_alpha_and_gray_are_not_interchangeable(self):
        with self.assertRaises(ValueError):v.pixel_checks(synthetic('alpha-8'),'gray-8')
    def test_transparent_background_rejected(self):
        data=bytearray(synthetic('rgb-565'));data[3]=0
        with self.assertRaises(ValueError):v.pixel_checks(bytes(data),'rgb-565')
    def test_truncated_pixels(self):
        with self.assertRaises(ValueError):v.pixel_checks(synthetic('rgb-565')[:-1],'rgb-565')
    def test_marker_is_independently_required(self):
        data=bytearray(synthetic('gray-8'));at=4*(4*v.WIDTH+4);data[at:at+4]=bytes([255])*4
        with self.assertRaises(ValueError):v.pixel_checks(bytes(data),'gray-8')
    def test_shifted_content_rejected(self):
        data=b''.join(bytes(v.oracle_color('rgb-565',max(0,x-5),y)) for y in range(v.HEIGHT) for x in range(v.WIDTH))
        with self.assertRaises(ValueError):v.pixel_checks(data,'rgb-565')

class Receipts(unittest.TestCase):
    def reject(self,change):
        r=row();change(r)
        with self.assertRaises(ValueError):v.receipt(r,('rgba-8888','pdf'))
    def test_positive(self):v.receipt(row(),('rgba-8888','pdf'))
    def test_boolean_count(self):self.reject(lambda r:r.update(callback_count=True))
    def test_wrong_format(self):self.reject(lambda r:r.update(source_format='alpha-8'))
    def test_hidden_conversion(self):self.reject(lambda r:r.update(conversion='automatic'))
    def test_wrong_extent(self):self.reject(lambda r:r.update(image_width=80))
    def test_wrong_filename(self):self.reject(lambda r:r.update(file='../other.pdf'))
    def test_weakened_policy(self):self.reject(lambda r:r.update(audit_policy='report'))
    def test_preflight_instead_of_export(self):self.reject(lambda r:r['audit'].update(mode='preflight'))
    def test_raster_fallback(self):self.reject(lambda r:r['audit']['events'][0].update(status='rasterized'))
    def test_image_must_be_embedded_raster(self):self.reject(lambda r:r['audit']['events'][0].update(status='vector'))
    def test_non_image_content_must_stay_vector(self):self.reject(lambda r:r['audit']['events'][1].update(status='embedded-raster'))
    def test_missing_marker(self):self.reject(lambda r:r['audit']['events'].pop(1))
    def test_no_duplicate_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x.json';p.write_text('{"x":1,"x":2}')
            with self.assertRaises(ValueError):v.read_json(p)
    def test_nonfinite_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x.json';p.write_text('{"x":NaN}')
            with self.assertRaises(ValueError):v.read_json(p)
    def test_stale_matrix(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);(p/'documents.json').write_text(json.dumps(dict(schema=1,stage='0.70',status='passed',run_token='old')))
            with self.assertRaises(ValueError):v.inspect_documents(p,'new')

class GPU(unittest.TestCase):
    def fixture(self,p):
        value=dict(schema=1,stage='0.70',status='passed',run_token='token',backend='egl',adapter='hardware',
                   failures=0,frames=7,drawing_readbacks=0,inspection_readbacks=7,layout_rejections=7,
                   conversion='explicit-rgba-nearest',gpu_target_format='rgba-8888',contexts_closed=True,
                   gui_executed=False,physical_display_verified=False,
                   captures=[dict(source_format=f,file=f+'.rgba') for f in v.FORMATS])
        for f in v.FORMATS:(p/(f+'.rgba')).write_bytes(synthetic(f))
        return value
    def check(self,mutate):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);value=self.fixture(p);mutate(value);(p/'gpu.json').write_text(json.dumps(value))
            return v.inspect_gpu(p,'token','egl','hardware')
    def test_positive_synthetic_receipt(self):self.check(lambda r:None)
    def test_booleans_are_not_counts(self):
        for key in ('schema','frames','layout_rejections','inspection_readbacks','drawing_readbacks','failures'):
            with self.subTest(key=key),self.assertRaises(ValueError):self.check(lambda r:r.update({key:True}))
    def test_hidden_readback_rejected(self):
        with self.assertRaises(ValueError):self.check(lambda r:r.update(drawing_readbacks=1))
    def test_duplicate_capture_rejected(self):
        with self.assertRaises(ValueError):self.check(lambda r:r['captures'].__setitem__(0,r['captures'][1]))
    def test_wrong_backend_rejected(self):
        with self.assertRaises(ValueError):self.check(lambda r:r.update(backend='metal'))
    def test_open_context_rejected(self):
        with self.assertRaises(ValueError):self.check(lambda r:r.update(contexts_closed=False))
    def test_hdr_or_changed_target_claim_rejected(self):
        with self.assertRaises(ValueError):self.check(lambda r:r.update(gpu_target_format='rgba-f16'))
    def test_no_physical_display_claim(self):
        with self.assertRaises(ValueError):self.check(lambda r:r.update(physical_display_verified=True))

if __name__=='__main__':unittest.main(verbosity=2)
