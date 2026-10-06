#!/usr/bin/env python3
"""0.71 source contracts and independent inspector regressions (standard library)."""
from __future__ import annotations
import copy
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import float_pixel_validation as fv

ROOT=Path(__file__).resolve().parents[1]
RACKET_FILES=('color4f.rkt','float-colors.rkt','image-info.rkt','raster-buffers.rkt',
              'private/float-color-native.rkt','private/float-pixel-util.rkt','private/pixel-sample-util.rkt',
              'tests/float-pixel-pure-test.rkt','tests/float-pixel-native-test.rkt',
              'tests/float-pixel-fixtures.rkt','tests/float-pixel-gpu-test.rkt',
              'tools/float-pixel-doctor.rkt','examples/float-pixels.rkt')
SIGNATURES={
 'sk_canvas_clear_color4f':'_pointer _sk-color4f -> _void',
 'sk_canvas_draw_color4f':'_pointer _sk-color4f _int -> _void',
 'sk_paint_get_color4f':'_pointer _sk-color4f-pointer -> _void',
 'sk_paint_set_color4f':'_pointer _sk-color4f-pointer _pointer -> _void',
 'sk_shader_new_color4f':'_sk-color4f-pointer _pointer -> _pointer',
 'sk_shader_new_linear_gradient_color4f':'_pointer _pointer _pointer _pointer _int _int _pointer -> _pointer',
 'sk_shader_new_radial_gradient_color4f':'_pointer _float _pointer _pointer _pointer _int _int _pointer -> _pointer',
 'sk_shader_new_sweep_gradient_color4f':'_pointer _pointer _pointer _pointer _int _int _float _float _pointer -> _pointer',
 'sk_shader_new_two_point_conical_gradient_color4f':'_pointer _float _pointer _float _pointer _pointer _pointer _int _int _pointer -> _pointer',
 'sk_pixmap_get_pixel_color4f':'_pointer _int _int _sk-color4f-pointer -> _void',
 'sk_pixmap_get_pixel_alphaf':'_pointer _int _int -> _float',
 'sk_pixmap_erase_color4f':'_pointer _sk-color4f-pointer _pointer -> _stdbool'}
CAPABILITIES=('canvas.float-color','paint.float-color','shaders.float-gradients','pixels.float-pixmap')

class Sources(unittest.TestCase):
    def text(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_reviewed_signatures_include_value_versus_pointer_boundary(self):
        import api_inventory as inv
        decl=[f for f in inv.forms(self.text('private/native.rkt')) if isinstance(f,list) and f and f[0]=='define-native']
        for name,sig in SIGNATURES.items():
            matches=[f for f in decl if f[1]==name]
            self.assertEqual(len(matches),1,name)
            self.assertEqual(matches[0][2],['_fun',*sig.split()],name)
    def test_direct_native_calls_have_reviewed_arities(self):
        import api_inventory as inv
        arities={k:len(v.split(' -> ')[0].split()) for k,v in SIGNATURES.items()}
        def walk(f):
            if not isinstance(f,list) or not f:return
            if isinstance(f[0],str) and f[0] in arities:self.assertEqual(len(f)-1,arities[f[0]],f[0])
            for child in f:walk(child)
        for name in ('float-colors.rkt','raster-buffers.rkt'):walk(inv.forms(self.text(name)))
    def test_layout_catalog_and_declaration_agree(self):
        profile=json.loads(self.text('private/native-abi.json'))['profiles'][0]
        self.assertEqual(profile['layout_sizes']['color4f'],16)
        self.assertIn('(ctype-sizeof _sk-color4f)',self.text('private/native-layouts.rkt'))
        self.assertIn('(define-cstruct _sk-color4f ([r _float] [g _float] [b _float] [a _float]))',self.text('private/types.rkt'))
    def test_all_racket_sources_parse_and_suites_stay_nested(self):
        import api_inventory as inv
        for name in RACKET_FILES:self.assertTrue(inv.forms(self.text(name)),name)
        for label in ('pure','native'):
            forms=inv.forms(self.text(f'tests/float-pixel-{label}-test.rkt'))
            self.assertFalse(any(isinstance(f,list) and f and f[0]=='test-case' for f in forms))
            body=next(f[2] for f in forms if isinstance(f,list) and f[:2]==['define',f'float-pixel-{label}-tests'])
            self.assertEqual(body[0],'test-suite')
            self.assertGreaterEqual(sum(isinstance(f,list) and f and f[0]=='test-case' for f in body),30)
    def test_four_families_have_public_anchors_not_execution_claims(self):
        import api_inventory as inv
        catalog=inv.load_catalog(ROOT);inv.validate_catalog(catalog)
        rows={r['id']:r for r in catalog['features']['capabilities']}
        for name in CAPABILITIES:
            self.assertEqual(rows[name]['status'],'supported-with-limits')
            self.assertIsNone(rows[name]['planned_stage'])
            self.assertTrue(rows[name]['public_equivalents'])
            self.assertEqual(rows[name]['execution_evidence'],inv.EVIDENCE_SCOPE)
    def test_pins_and_minimums_stay_unchanged(self):
        info=self.text('info.rkt')
        self.assertIn('(define version "0.72")',info)
        for s in ('("base" #:version "8.18")','("draw-lib" #:version "1.22")'):self.assertIn(s,info)
        self.assertEqual(self.text('private/native-default-version.txt').strip(),'3.119.1')
    def test_runner_and_source_ci_register_new_suites(self):
        runner=self.text('run-tests.rkt')
        self.assertIn('(run-tests float-pixel-pure-tests)',runner)
        self.assertIn("dynamic-require float-pixel-native-tests-file 'float-pixel-native-tests",runner)
        self.assertIn("'test-float-pixels.py'",self.text('tools/ci.py'))
        self.assertIn('tests/float-pixel-gpu-test.rkt',self.text('info.rkt'))
    def test_float_precision_provenance_survives_recordings_and_replacement(self):
        audit=self.text('private/audit-trace.rkt')
        for term in ('audit-mark-float-pixels!',"'(image raster-image surface)",
                     "'(paint picture path image raster-image unknown)",
                     "'(sk_paint_set_color sk_paint_set_color4f)",
                     "'(sk_canvas_clear sk_canvas_clear_color4f)"):
            self.assertIn(term,audit)
        policy=self.text('output-policy.rkt')
        self.assertIn('(float-color needs-raster needs-raster',policy)
        self.assertIn('(float-pixels needs-raster needs-raster',policy)
    def test_old_integer_util_and_legacy_rgba_path_stay_present(self):
        s=self.text('raster-buffers.rkt')
        self.assertIn('prepare-raster-input',s)
        self.assertIn('pixel-storage-input',s)
        self.assertIn('integer-storage-input',self.text('private/pixel-sample-util.rkt'))
        self.assertIn('integer-sample->bytes',self.text('private/integer-pixel-util.rkt'))
        self.assertIn("'#(rgba-8888 bgra-8888 rgb-888x alpha-8 gray-8 rgb-565 rgba-1010102)",self.text('image-info.rkt'))
    def test_float_fill_validates_staging_before_destination_write(self):
        s=self.text('raster-buffers.rkt');s=s[s.index('(define (pixmap-fill-color4f!'):]
        self.assertLess(s.index('pixel-bytes->sample'),s.index('(memcpy (ptr-add'))
        self.assertIn('sk_pixmap_erase_color4f',s)
    def test_no_raw_handles_exported_or_new_ffi_registry(self):
        s=self.text('float-colors.rkt')
        for term in ('get-ffi-obj','ffi-lib','(provide (all-defined-out))'):self.assertNotIn(term,s)
        self.assertIn('call-with-owned',s)
        self.assertIn('call-with-float-source-space',s)
    def test_doctor_intentionally_quantizes_with_error_policy(self):
        s=self.text('tools/float-pixel-doctor.rkt')
        self.assertIn("#:policy 'error",s);self.assertNotIn("#:policy 'vector-only",s)
        self.assertIn('raster-buffer-convert',s)
        self.assertIn('raster-buffer->storage-bytes source',s)
        self.assertIn('explicit-float-to-rgba8888',s)
    def test_workflow_requires_backend_and_viewers_without_soft_failure(self):
        s=self.text('.github/workflows/float-pixels.yml')
        for term in ('--require-gpu','--require-renderers','--backend egl','--backend direct3d','--adapter warp'):self.assertIn(term,s)
        self.assertNotIn('continue-on-error',s)

def good_row(spec=('rgba-f16','samples','pdf')):
    fmt,scene,kind=spec;prefix=fmt+'-'+scene;stem=prefix+'-'+kind
    return dict(source_format=fmt,scene=scene,format=kind,file=stem+'.'+kind,rgba=stem+'.rgba',raw=prefix+'.pixels',
                image_width=64,image_height=32,conversion='explicit-float-to-rgba8888',callback_count=1,audit_policy='error',
                audit=dict(mode='export',backend=kind,blocking=False,vector_only=False,events=[
                    dict(feature='image',status='embedded-raster'),dict(feature='geometry',status='vector'),
                    dict(feature='annotation',status='vector')]))

class Receipts(unittest.TestCase):
    def test_positive_synthetic_receipts(self):
        for spec in fv.SPECS:fv.receipt(good_row(spec),spec)
    def reject(self,change):
        row=good_row();change(row)
        with self.assertRaises(ValueError):fv.receipt(row,('rgba-f16','samples','pdf'))
    def test_vector_only_policy_rejected(self):self.reject(lambda r:r.update(audit_policy='vector-only'))
    def test_report_only_policy_rejected(self):self.reject(lambda r:r.update(audit_policy='report'))
    def test_preflight_rejected(self):self.reject(lambda r:r['audit'].update(mode='preflight'))
    def test_false_vector_only_claim(self):self.reject(lambda r:r['audit'].update(vector_only=True))
    def test_image_cannot_claim_vector(self):self.reject(lambda r:r['audit']['events'][0].update(status='vector'))
    def test_marker_cannot_be_raster(self):self.reject(lambda r:r['audit']['events'][1].update(status='embedded-raster'))
    def test_unconverted_float_pixels_rejected(self):self.reject(lambda r:r['audit']['events'].append(dict(feature='float-pixels',status='needs-raster')))
    def test_float_color_falsely_vector_rejected(self):self.reject(lambda r:r['audit']['events'].append(dict(feature='float-color',status='vector')))
    def test_double_image_rejected(self):self.reject(lambda r:r['audit']['events'].append(dict(feature='image',status='embedded-raster')))
    def test_boolean_count_rejected(self):self.reject(lambda r:r.update(callback_count=True))
    def test_wrong_image_dimensions(self):self.reject(lambda r:r.update(image_width=96))
    def test_missing_annotation(self):self.reject(lambda r:r['audit']['events'].pop())
    def test_other_filename(self):self.reject(lambda r:r.update(raw='other.pixels'))
    def test_implicit_quantization_rejected(self):self.reject(lambda r:r.update(conversion='automatic'))

class RawPixels(unittest.TestCase):
    @staticmethod
    def data(fmt='rgba-f16',scene='samples',order='little-endian',mutate=lambda v:v):
        code=('<' if order=='little-endian' else '>')+('4e' if fmt=='rgba-f16' else '4f')
        return b''.join(struct.pack(code,*mutate(fv.sample_oracle(scene,i%64))) for i in range(2048))
    def test_known_float_patterns_both_endiannesses(self):
        for fmt in fv.FORMATS:
            for scene in ('samples','linear'):
                for order in ('little-endian','big-endian'):fv.raw_checks(self.data(fmt,scene,order),fmt,scene,order)
    def test_eight_bit_intermediate_rejected(self):
        # Keep extended pixels untouched to isolate the precision oracle.
        def q(v):return v if min(v)<0 or max(v)>1 else tuple(round(x*255)/255 for x in v)
        with self.assertRaises(ValueError):fv.raw_checks(self.data(mutate=q),'rgba-f16','samples','little-endian')
    def test_clipped_range_rejected(self):
        with self.assertRaises(ValueError):fv.raw_checks(self.data(mutate=lambda v:tuple(max(0,min(1,x)) for x in v)),'rgba-f16','samples','little-endian')
    def test_nonfinite_rejected(self):
        d=bytearray(self.data());d[0:2]=struct.pack('<e',float('nan'))
        with self.assertRaises(ValueError):fv.raw_checks(bytes(d),'rgba-f16','samples','little-endian')
    def test_truncation_rejected(self):
        with self.assertRaises(ValueError):fv.raw_checks(self.data()[:-1],'rgba-f16','samples','little-endian')
    def test_wrong_byte_order_rejected(self):
        with self.assertRaises(ValueError):fv.raw_checks(self.data(),'rgba-f16','samples','big-endian')
    def test_unknown_sample_type_rejected(self):
        with self.assertRaises(ValueError):fv.raw_checks(self.data(),'rgba-f16-norm','samples','little-endian')

class Pixels(unittest.TestCase):
    @staticmethod
    def data(scene,document=True):
        w,h=(96,64) if document else (64,32)
        rows=[]
        for y in range(h):
            for x in range(w):
                if not document:c=fv.quantize(fv.sample_oracle(scene,x))
                elif 2<=x<6 and 2<=y<6:c=(0,255,0,255)
                elif 16<=x<80 and 16<=y<48:c=fv.quantize(fv.sample_oracle(scene,x-16))
                else:c=(255,255,255,255)
                rows.append(bytes(c))
        return b''.join(rows)
    def test_known_document_patterns(self):
        for scene in ('samples','linear'):fv.pixel_checks(self.data(scene),scene)
    def test_known_gpu_patterns(self):
        for scene in fv.SCENES:fv.pixel_checks(self.data(scene,False),scene,document=False)
    def test_blank_rejected(self):
        with self.assertRaises(ValueError):fv.pixel_checks(bytes([255])*96*64*4,'samples')
    def test_wrong_scene(self):
        with self.assertRaises(ValueError):fv.pixel_checks(self.data('samples'),'linear')
    def test_marker_required(self):
        d=bytearray(self.data('linear'));i=4*(3*96+3);d[i:i+4]=bytes([255])*4
        with self.assertRaises(ValueError):fv.pixel_checks(bytes(d),'linear')
    def test_outside_content_cannot_be_rasterized_whole_page(self):
        d=bytearray(self.data('linear'));i=4*(10*96+90);d[i:i+4]=bytes((0,0,0,255))
        with self.assertRaises(ValueError):fv.pixel_checks(bytes(d),'linear')
    def test_opacity_required(self):
        d=bytearray(self.data('samples'));d[3]=0
        with self.assertRaises(ValueError):fv.pixel_checks(bytes(d),'samples')

class GPUReceipts(unittest.TestCase):
    def good(self):
        return dict(schema=1,stage='0.71',status='passed',run_token='t',backend='egl',adapter='hardware',
                    failures=0,frames=6,drawing_readbacks=0,inspection_readbacks=6,float_readback_rejections=2,
                    context_closed=True,gpu_target_format='rgba-8888',float_gpu_storage_verified=False,
                    hdr_verified=False,physical_display_verified=False,
                    captures=[dict(scene=s,file=s+'.rgba') for s in fv.SCENES])
    def check(self,v):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'gpu.json').write_text(json.dumps(v))
            for s in fv.SCENES:(root/(s+'.rgba')).write_bytes(Pixels.data(s,False))
            return fv.inspect_gpu(root,'t','egl','hardware')
    def test_positive_synthetic_receipt(self):self.check(self.good())
    def test_incorrect_numeric_counters(self):
        for key in ('schema','frames','failures','drawing_readbacks','inspection_readbacks','float_readback_rejections'):
            for value in (True,-1,10,None):
                v=self.good();v[key]=value
                with self.subTest(key=key,value=value),self.assertRaises(ValueError):self.check(v)
    def test_stale_token_backend_and_status(self):
        for key,val in (('run_token','stale'),('stage','0.70'),('backend','metal'),('adapter','warp'),('status','failed')):
            v=self.good();v[key]=val
            with self.assertRaises(ValueError):self.check(v)
    def test_unearned_hdr_and_float_storage_claims(self):
        for key in ('hdr_verified','physical_display_verified','float_gpu_storage_verified'):
            v=self.good();v[key]=True
            with self.assertRaises(ValueError):self.check(v)
    def test_unclosed_context(self):
        v=self.good();v['context_closed']=False
        with self.assertRaises(ValueError):self.check(v)
    def test_duplicate_scene(self):
        v=self.good();v['captures'][-1]=v['captures'][0]
        with self.assertRaises(ValueError):self.check(v)
    def test_unsafe_filename(self):
        v=self.good();v['captures'][0]['file']='../clear.rgba'
        with self.assertRaises(ValueError):self.check(v)

class Gate(unittest.TestCase):
    def load(self):
        spec=importlib.util.spec_from_file_location('float_gate',ROOT/'tools/validate-float-pixels.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
    def test_complete_dynamic_compile_graph(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp);(p/'run-tests.rkt').write_text('(define-runtime-path n "tests/a.rkt")\n(define-runtime-path m "tests/a.rkt")')
            targets=self.load().compile_targets(p)
            self.assertEqual(targets.count(p/'tests/a.rkt'),1)
            self.assertIn(p/'float-colors.rkt',targets)
    def test_empty_graph_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp);(p/'run-tests.rkt').write_text('#lang racket/base')
            with self.assertRaises(ValueError):self.load().compile_targets(p)
    def test_nonfinite_timeout_rejected(self):
        for value in ('nan','inf','0','-1'):
            with self.assertRaises(SystemExit),patch('shutil.which',return_value='/racket'):self.load().main(['--timeout',value])

if __name__=='__main__':unittest.main(verbosity=2)
