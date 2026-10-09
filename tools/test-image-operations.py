#!/usr/bin/env python3
"""0.72 source and fail-closed evidence tests. Synthetic fixtures are not native execution."""
from __future__ import annotations
import copy
import json
from pathlib import Path
import re
import struct
import tempfile
import unittest
import image_operation_validation as iv

ROOT=Path(__file__).resolve().parents[1]
SIGNATURES={
 'sk_image_get_unique_id':'_pointer -> _uint32',
 'sk_image_is_alpha_only':'_pointer -> _stdbool',
 'sk_image_is_lazy_generated':'_pointer -> _stdbool',
 'sk_image_is_texture_backed':'_pointer -> _stdbool',
 'sk_image_is_valid':'_pointer _pointer -> _stdbool',
 'sk_image_make_non_texture_image':'_pointer -> _pointer',
 'sk_image_make_raw_shader':'_pointer _int _int _sk-sampling-pointer _pointer -> _pointer',
 'sk_image_read_pixels_into_pixmap':'_pointer _pointer _int _int _int -> _stdbool',
 'sk_image_scale_pixels':'_pointer _pointer _sk-sampling-pointer _int -> _stdbool',
 'sk_image_make_with_filter_raster':'_pointer _pointer _sk-irect-pointer _sk-irect-pointer _sk-irect-pointer _sk-ipoint-pointer -> _pointer'}
FEATURES=('images.filter-application','images.extra-inspection','images.residency','images.raw-shader',
          'images.direct-scale','images.nontexture','images.raster-core')
RACKET_FILES=('image-operations.rkt','private/image-operation-util.rkt','private/gpu-image-operations.rkt',
              'tests/image-operation-pure-test.rkt','tests/image-operation-native-test.rkt','tests/image-operation-gpu-test.rkt',
              'tests/image-operation-fixtures.rkt','tools/image-operation-doctor.rkt','tools/check-package-version.rkt',
              'examples/image-operations.rkt')

def synthetic_row(scene='offset',kind='pdf'):
    sizes={'offset':(16,12),'clip':(5,3),'blur':(28,24),'shadow':(30,24),'scale':(16,12),'raw':(16,12)}
    offsets={'offset':(7,5),'clip':(12,9),'blur':(-6,-6),'shadow':(0,0),'scale':(0,0),'raw':(0,0)}
    w,h=sizes[scene];ox,oy=offsets[scene]
    meta=(dict(backing_dimensions=[w+4,h+2],valid_subset=[2,1,w,h],offset=[ox,oy],clip=iv.CLIPS[scene])
          if scene in iv.CLIPS else dict(conversion='explicit-f32-to-rgba8888',source_dimensions=[4,3])
          if scene=='scale' else dict(conversion='explicit-raw-shader-rasterization'))
    return dict(scene=scene,format=kind,file=scene+'-'+kind+'.'+kind,rgba=scene+'-'+kind+'.rgba',
                callback_count=1,image_dimensions=[w,h],placement=[24+ox,20+oy],metadata=meta,
                raw='scale.f32' if scene=='scale' else False,audit_policy='error',
                audit=dict(mode='export',backend=kind,blocking=False,vector_only=False,
                           events=[dict(feature='geometry',status='vector'),dict(feature='image',status='embedded-raster'),
                                   dict(feature='annotation',status='vector')]))

def synthetic_capture(scene):
    # Deliberately synthetic probe fixture, not a native render receipt.
    row=synthetic_row(scene);w,h=row['image_dimensions'];px,py=row['placement']
    data=bytearray(bytes(iv.WHITE)*(iv.WIDTH*iv.HEIGHT))
    def point(x,y,c):data[4*(y*iv.WIDTH+x):4*(y*iv.WIDTH+x+1)]=bytes(c)
    for y in range(2,7):
        for x in range(2,7):point(x,y,(0,255,0,255))
    if scene in ('offset','clip','scale','raw'):
        for y in range(py,py+h):
            for x in range(px,px+w):point(x,y,(128,64,191,255) if scene=='scale' else iv.BLUE)
    elif scene=='blur':
        point(32,26,iv.BLUE);point(22,26,(220,230,240,255))
    else:
        point(32,26,iv.BLUE);point(44,34,(30,30,30,255))
    return bytes(data)

class Sources(unittest.TestCase):
    def text(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_native_signatures_in_existing_CPU_registry(self):
        import api_inventory as inv
        rows=[f for f in inv.forms(self.text('private/native.rkt')) if type(f) is list and f and f[0]=='define-native']
        for name,signature in SIGNATURES.items():
            found=[f for f in rows if f[1]==name];self.assertEqual(len(found),1,name)
            self.assertEqual(found[0][2],['_fun',*signature.split()],name)
    def test_GPU_filter_is_in_existing_GPU_registry(self):
        import api_inventory as inv
        rows=[f for f in inv.forms(self.text('private/gpu-image-native.rkt')) if type(f) is list and f and f[0]=='define-image-native']
        found=[f for f in rows if f[2]=='sk_image_make_with_filter'];self.assertEqual(len(found),1)
        self.assertEqual(found[0][3],['_fun',*('_pointer '*7).split(),'->','_pointer'])
        self.assertNotIn('(define-native sk_image_make_with_filter\n',self.text('private/native.rkt'))
    def test_seven_current_capabilities_have_public_source_anchors(self):
        import api_inventory as inv
        catalog=inv.load_catalog(ROOT);summary=inv.validate_catalog(catalog)
        rows={r['id']:r for r in catalog['features']['capabilities']}
        for name in FEATURES:
            self.assertEqual(rows[name]['status'],'supported-with-limits')
            self.assertIsNone(rows[name]['planned_stage']);self.assertTrue(rows[name]['public_equivalents'])
            self.assertEqual(rows[name]['execution_evidence'],inv.EVIDENCE_SCOPE)
        self.assertNotIn('0.72',summary['next_stages'])
    def test_all_new_Racket_files_parse_and_cases_are_nested(self):
        import api_inventory as inv
        for name in RACKET_FILES:self.assertTrue(inv.forms(self.text(name)),name)
        for kind in ('pure','native'):
            forms=inv.forms(self.text(f'tests/image-operation-{kind}-test.rkt'))
            self.assertFalse(any(type(f) is list and f and f[0]=='test-case' for f in forms))
            suite=next(f[2] for f in forms if type(f) is list and f[:2]==['define',f'image-operation-{kind}-tests'])
            self.assertEqual(suite[0],'test-suite')
            self.assertGreaterEqual(sum(type(f) is list and f and f[0]=='test-case' for f in suite),30)
    def test_suites_are_registered(self):
        runner=self.text('run-tests.rkt')
        self.assertIn('(run-tests image-operation-pure-tests)',runner)
        self.assertIn("dynamic-require image-operation-native-tests-file 'image-operation-native-tests",runner)
        self.assertIn("'test-image-operations.py'",self.text('tools/ci.py'))
        self.assertIn('tests/image-operation-gpu-test.rkt',self.text('info.rkt'))
    def test_real_Racket_version_guard_and_pins(self):
        self.assertIn('(define version "0.78")',self.text('info.rkt'))
        self.assertIn('(valid-version? value)',self.text('tools/check-package-version.rkt'))
        self.assertIn('tools/check-package-version.rkt',self.text('tools/validate-image-operations.py'))
        self.assertIn('("base" #:version "8.18")',self.text('info.rkt'))
        self.assertIn('("draw-lib" #:version "1.22")',self.text('info.rkt'))
        self.assertEqual(self.text('private/native-default-version.txt').strip(),'3.119.1')
    def test_staging_is_immobile_and_commit_follows_validation(self):
        text=self.text('raster-buffers.rkt');at=text.index('(module* image-operation-internals #f');text=text[at:]
        self.assertIn("(malloc size 'raw)",text);self.assertIn('(free memory)',text)
        self.assertLess(text.index('(proc pm native)'),text.index('pixel-storage-input'))
        self.assertLess(text.index('pixel-storage-input'),text.index('(memcpy (ptr-add address'))
        self.assertIn('(view-owner who destination #t)',text)
    def test_CPU_operations_reject_GPU_sources(self):
        text=self.text('image-operations.rkt')
        self.assertIn('(owned-gpu-domain ih)',text)
        self.assertIn('(sk_image_is_texture_backed ip)',text)
        for name in ('image->non-texture-image','image->raster-image','image-read-pixmap!','image-scale-pixmap!','image-apply-filter'):
            self.assertIn(name,self.text('private/lifetime.rkt'))
    def test_GPU_results_keep_domain_and_no_fallback(self):
        text=self.text('private/gpu-image-operations.rkt')
        for term in ('new-gpu-owned','(list ih fh)','texture-backed?/native','valid-image?/native','max_texture_size'):
            self.assertIn(term,text)
        self.assertNotIn('gpu-image->raster-image',text)
        self.assertNotIn('sk_image_make_with_filter_raster',text)
    def test_out_parameters_are_only_read_after_owned_result(self):
        text=self.text('image-operations.rkt')
        self.assertIn('cpu-image-result',text)
        self.assertIn('operation-result-geometry',text)
        self.assertIn('(define (image-apply-filter im filter #:subset [subset #f] #:clip clip)',text)
        self.assertIn('operation-precision-compatible?',text)
    def test_provenance_and_strict_document_policy(self):
        self.assertIn("[(make-raw-image-shader) '(raw-image-shader)]",self.text('private/audit-trace.rkt'))
        self.assertIn('(raw-image-shader needs-raster needs-raster',self.text('output-policy.rkt'))
        self.assertIn('audit-inherit-image-precision!',self.text('private/audit-trace.rkt'))
        doctor=self.text('tools/image-operation-doctor.rkt')
        self.assertIn("#:policy 'error",doctor);self.assertNotIn("#:policy 'vector-only",doctor)
    def test_no_public_native_address_or_callback(self):
        text=self.text('image-operations.rkt')
        provide=text[text.index('(provide '):text.index('\n\n',text.index('(provide '))]
        for forbidden in ('pointer','call-with-pixmap-write-staging','image-h','native'):
            self.assertNotIn(forbidden,provide)
    def test_workflow_requires_GPU_and_independent_linux_viewers(self):
        text=self.text('.github/workflows/image-operations.yml')
        for term in ('--require-gpu','--require-renderers','--backend egl','--backend direct3d','--adapter warp'):
            self.assertIn(term,text)
        self.assertNotIn('continue-on-error',text)
    def test_public_documented_APIs(self):
        import api_inventory as inv
        doc=self.text('docs/IMAGE-OPERATIONS.md')
        for name in inv.source_exports(ROOT,'image-operations.rkt'):self.assertIn(name,doc)
        self.assertIn('gpu-image-apply-filter',doc)

class Receipts(unittest.TestCase):
    def test_complete_synthetic_matrix(self):
        for spec in iv.SPECS:iv.receipt(synthetic_row(*spec),spec)

def reject_receipt(change,scene='offset'):
    def test(self):
        row=synthetic_row(scene);change(row)
        with self.assertRaises((ValueError,KeyError,TypeError)):iv.receipt(row,(scene,'pdf'))
    return test

MUTATIONS={
 'wrong_callback':lambda r:r.update(callback_count=2),
 'boolean_count':lambda r:r.update(callback_count=True),
 'vector_only_policy':lambda r:r.update(audit_policy='vector-only'),
 'report_policy':lambda r:r.update(audit_policy='report'),
 'preflight':lambda r:r['audit'].update(mode='preflight'),
 'blocking':lambda r:r['audit'].update(blocking=True),
 'vector_only_claim':lambda r:r['audit'].update(vector_only=True),
 'wrong_backend':lambda r:r['audit'].update(backend='svg'),
 'foreign_filename':lambda r:r.update(file='../foreign.pdf'),
 'lost_offset':lambda r:r.update(placement=[24,20]),
 'texture_origin_as_offset':lambda r:r.update(placement=[26,21]),
 'invalid_backing':lambda r:r['metadata'].update(backing_dimensions=[1,1]),
 'invalid_subset':lambda r:r['metadata'].update(valid_subset=[-1,0,16,12]),
 'subset_extent':lambda r:r.update(image_dimensions=[18,12]),
 'foreign_clip':lambda r:r['metadata'].update(clip=[0,0,16,12]),
 'escaped_clip':lambda r:r['metadata'].update(offset=[100,100]),
 'float_integer':lambda r:r.update(placement=[31.0,25]),
 'missing_events':lambda r:r['audit'].update(events=[]),
 'image_as_vector':lambda r:r['audit']['events'][1].update(status='vector'),
 'geometry_as_raster':lambda r:r['audit']['events'][0].update(status='embedded-raster'),
 'extra_image':lambda r:r['audit']['events'].append(dict(feature='image',status='embedded-raster')),
 'implicit_fallback':lambda r:r['audit']['events'].append(dict(feature='raster-group',status='rasterized')),
 'lost_precision':lambda r:r['audit']['events'].append(dict(feature='float-pixels',status='needs-raster')),
 'unhandled_raw_shader':lambda r:r['audit']['events'].append(dict(feature='raw-image-shader',status='needs-raster')),
 'missing_annotation':lambda r:r['audit']['events'].pop(),
 'full_page_raster':lambda r:r.update(image_dimensions=[96,64])}
for name,change in MUTATIONS.items():setattr(Receipts,'test_reject_'+name,reject_receipt(change))
for scene in ('scale','raw'):
    setattr(Receipts,'test_reject_'+scene+'_implicit_conversion',reject_receipt(lambda r:r['metadata'].update(conversion='implicit'),scene))
setattr(Receipts,'test_reject_missing_F32',reject_receipt(lambda r:r.update(raw=False),'scale'))

class Pixels(unittest.TestCase):
    def test_synthetic_semantic_probes(self):
        for scene in iv.SCENES:self.assertGreater(iv.pixel_checks(synthetic_capture(scene),scene),0)
    def test_missing_marker(self):
        data=bytearray(synthetic_capture('offset'));at=4*(4*96+4);data[at:at+4]=bytes(iv.WHITE)
        with self.assertRaises(ValueError):iv.pixel_checks(bytes(data),'offset')
    def test_blank_capture(self):
        for scene in iv.SCENES:
            with self.assertRaises(ValueError):iv.pixel_checks(bytes(iv.WHITE)*(96*64),scene)
    def test_lost_shadow(self):
        data=bytearray(synthetic_capture('shadow'));at=4*(34*96+44);data[at:at+4]=bytes(iv.WHITE)
        with self.assertRaises(ValueError):iv.pixel_checks(bytes(data),'shadow')
    def test_wrong_capture_size(self):
        with self.assertRaises(ValueError):iv.pixel_checks(b'', 'offset')
    def test_F32_both_byte_orders(self):
        for marker,order in (('<','little-endian'),('>','big-endian')):
            self.assertTrue(iv.raw_checks(struct.pack(marker+'4f',.5009765625,.25,.75,1)*192,order)['sub_byte_precision_verified'])
    def test_F32_rejects_8bit_loss(self):
        with self.assertRaises(ValueError):iv.raw_checks(struct.pack('<4f',128/255,64/255,191/255,1)*192,'little-endian')
    def test_F32_rejects_nonfinite(self):
        with self.assertRaises(ValueError):iv.raw_checks(struct.pack('<4f',float('nan'),.25,.75,1)*192,'little-endian')
    def test_F32_rejects_bad_order(self):
        with self.assertRaises(ValueError):iv.raw_checks(bytes(192*16),'native')
    def test_F32_rejects_wrong_extent(self):
        with self.assertRaises(ValueError):iv.raw_checks(bytes(16),'little-endian')
    def test_JSON_duplicate_keys(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'test.json';p.write_text('{"a":1,"a":2}')
            with self.assertRaises(ValueError):iv.read_json(p)
    def test_JSON_nonfinite(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'test.json';p.write_text('{"a":NaN}')
            with self.assertRaises(ValueError):iv.read_json(p)

if __name__=='__main__':unittest.main(verbosity=2)
