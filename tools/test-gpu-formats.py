#!/usr/bin/env python3
"""0.73 source/inspector tests; pure Python checks are not GPU execution."""
from pathlib import Path
import copy
import json
import struct
import tempfile
import unittest
from unittest.mock import patch
import gpu_format_validation as gv
ROOT=Path(__file__).resolve().parents[1]

def capture(color,order='little-endian'):
    bpp=gv.FORMATS[color];data=bytearray();marker='<' if order=='little-endian' else '>'
    for y in range(6):
        for x in range(8):
            right=x>=4
            if color in ('rgba-f16','rgba-f32'):
                data.extend(struct.pack(marker+('4e' if color=='rgba-f16' else '4f'),
                                       .501953125 if right else .5009765625,-.125,1.25,1))
            elif color in ('rgba-8888','bgra-8888'):
                p=(192,96,32,255) if right else (32,96,192,255)
                if color=='bgra-8888':p=(p[2],p[1],p[0],p[3])
                data.extend(p)
            elif color=='rgb-888x':data.extend([255 if right else 0]*3+[255])
            elif color=='alpha-8':data.append(192 if right else 64)
            elif color=='gray-8':data.append(255 if right else 0)
            else:
                value=(65535 if right else 0) if color=='rgb-565' else (0xffffffff if right else 0xc0000000)
                data.extend(value.to_bytes(bpp,order.split('-')[0]))
        data.extend([165]*(2*bpp))
    return bytes(data)

def receipt():
    return dict(file='rgba-f16.pdf',format='pdf',color_type='rgba-f16',conversion='explicit-rgba8888',
        audit=dict(mode='export',backend='pdf',blocking=False,vector_only=False,
          events=[dict(feature='geometry',status='vector'),dict(feature='image',status='embedded-raster'),
                  dict(feature='annotation',status='vector')]))

class Pixels(unittest.TestCase):
    def test_all_formats_both_byte_orders(self):
        for color in gv.FORMATS:
            for order in ('little-endian','big-endian'):
                with self.subTest(color=color,order=order):
                    self.assertEqual(gv.pixel_checks(capture(color,order),color,10*gv.FORMATS[color],order)['pixels_checked'],48)
    def test_padding_damage(self):
        for c in gv.FORMATS:
            data=bytearray(capture(c));data[-1]=0
            with self.assertRaisesRegex(ValueError,'padding'):gv.pixel_checks(bytes(data),c,10*gv.FORMATS[c],'little-endian')
    def test_wrong_stride(self):
        with self.assertRaises(ValueError):gv.pixel_checks(capture('rgba-f16'),'rgba-f16',64,'little-endian')
    def test_short_data(self):
        with self.assertRaises(ValueError):gv.pixel_checks(capture('rgba-f32')[:-1],'rgba-f32',160,'little-endian')
    def test_wrong_byte_order(self):
        with self.assertRaises(ValueError):gv.pixel_checks(capture('rgba-f32'),'rgba-f32',160,'native')
    def test_nan(self):
        data=bytearray(capture('rgba-f32'));data[:4]=struct.pack('<f',float('nan'))
        with self.assertRaises(ValueError):gv.pixel_checks(bytes(data),'rgba-f32',160,'little-endian')
    def test_eight_bit_intermediate(self):
        data=bytearray(capture('rgba-f32'));data[:4]=struct.pack('<f',128/255)
        with self.assertRaisesRegex(ValueError,'precision'):gv.pixel_checks(bytes(data),'rgba-f32',160,'little-endian')
    def test_range_clamping(self):
        for value,offset in ((0,4),(1,8)):
            data=bytearray(capture('rgba-f32'));data[offset:offset+4]=struct.pack('<f',value)
            with self.assertRaisesRegex(ValueError,'range'):gv.pixel_checks(bytes(data),'rgba-f32',160,'little-endian')
    def test_channel_swap(self):
        with self.assertRaises(ValueError):gv.pixel_checks(capture('rgba-8888'),'bgra-8888',40,'little-endian')
    def test_missing_nonuniform_pattern(self):
        data=bytearray(capture('rgba-f16'));data[4*8:5*8]=data[:8]
        with self.assertRaises(ValueError):gv.pixel_checks(bytes(data),'rgba-f16',80,'little-endian')
    def test_zero_alpha(self):
        data=bytearray(capture('rgba-f16'));data[6:8]=struct.pack('<e',0)
        with self.assertRaises(ValueError):gv.pixel_checks(bytes(data),'rgba-f16',80,'little-endian')

class Receipts(unittest.TestCase):
    def test_valid_document(self):gv.document_receipt(receipt())
    def reject(self,fn):
        r=receipt();fn(r)
        with self.assertRaises(ValueError):gv.document_receipt(r)
    def test_implicit_conversion(self):self.reject(lambda r:r.update(conversion='implicit'))
    def test_missing_images(self):self.reject(lambda r:r['audit']['events'].pop(1))
    def test_image_as_vector(self):self.reject(lambda r:r['audit']['events'][1].update(status='vector'))
    def test_marker_as_raster(self):self.reject(lambda r:r['audit']['events'][0].update(status='embedded-raster'))
    def test_no_annotation(self):self.reject(lambda r:r['audit']['events'].pop())
    def test_blocking(self):self.reject(lambda r:r['audit'].update(blocking=True))
    def test_preflight(self):self.reject(lambda r:r['audit'].update(mode='preflight'))
    def test_wrong_backend(self):self.reject(lambda r:r['audit'].update(backend='svg'))
    def test_float_document_loss(self):self.reject(lambda r:r['audit']['events'].append(dict(feature='float-pixels',status='needs-raster')))
    def test_duplicate_image(self):self.reject(lambda r:r['audit']['events'].append(dict(feature='image',status='embedded-raster')))
    def test_no_capture_forgery(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ('../escape','/absolute','x/y','C:x','x\\y','missing','.'):
                with self.assertRaises(ValueError):gv.safe_file(Path(d),name)
    def test_duplicate_JSON_keys(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'r.json';p.write_text('{"a":1,"a":2}')
            with self.assertRaises(ValueError):gv.read_json(p)
    def test_nonfinite_JSON(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'r.json';p.write_text('{"a":NaN}')
            with self.assertRaises(ValueError):gv.read_json(p)


class Reports(unittest.TestCase):
    """Synthetic reports/files; document parser is mocked, never called native evidence."""
    def fixture(self,root):
        rows=[]
        for color,bpp in gv.FORMATS.items():
            (root/(color+'.pixels')).write_bytes(capture(color))
            cap=dict(backend='opengl',context_generation=1,color_type_name=color,renderable=True,
                     max_sample_count=4,allocation_verified=False,actual_sample_count=False)
            rows.append(dict(color_type=color,status='passed',capability=cap,width=8,height=6,
                alpha_type='opaque' if color in ('rgb-888x','gray-8','rgb-565') else 'premul',
                bytes_per_pixel=bpp,row_bytes=10*bpp,readbacks=1,file=color+'.pixels',
                properties=dict(pixel_geometry='unknown',flags=0,device_independent_fonts=False,dynamic_msaa=False,always_dither=False)))
        docs=[]
        for color in ('rgba-8888','rgba-f16'):
            for kind in ('pdf','svg'):
                row=receipt();row.update(color_type=color,format=kind,file=color+'.'+kind)
                row['audit']['backend']=kind;docs.append(row);(root/row['file']).write_text('SYNTHETIC document parser mock input')
        return dict(schema=1,stage='0.73',run_token='fixture',status='passed',backend='egl',adapter='hardware',
            cases=20,failures=0,context_closed=True,physical_display_verified=False,hdr_verified=False,
            drawing_readbacks=0,descriptor_symbols=[dict(name=n,available=True) for n in sorted(gv.DESCRIPTOR_SYMBOLS)],
            staging=dict(creations=4,reuses=1,retirements=3,live_targets=1),formats=rows,unsupported_rejections=0,
            byte_order='little-endian',documents=docs)
    def invoke(self,mutate=None):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);r=self.fixture(root)
            if mutate:mutate(r)
            (root/'gpu.json').write_text(json.dumps(r))
            with patch.object(gv,'document_structure',return_value={'synthetic':True}):
                return gv.inspect(root,'fixture','egl','hardware')
    def test_valid_synthetic_report(self):self.assertEqual(self.invoke()['status'],'passed')
    def reject(self,fn):
        with self.assertRaises(ValueError):self.invoke(fn)
    def test_failed_execution(self):self.reject(lambda r:r.update(status='failed'))
    def test_wrong_token(self):self.reject(lambda r:r.update(run_token='foreign'))
    def test_wrong_backend(self):self.reject(lambda r:r.update(backend='metal'))
    def test_context_still_live(self):self.reject(lambda r:r.update(context_closed=False))
    def test_hidden_transfer(self):self.reject(lambda r:r.update(drawing_readbacks=1))
    def test_fake_sample_observation(self):self.reject(lambda r:r['formats'][0]['capability'].update(actual_sample_count=4))
    def test_missing_format(self):self.reject(lambda r:r['formats'].pop())
    def test_required_format_not_run(self):
        def change(r):r['formats'][0].update(status='unsupported');r['formats'][0]['capability'].update(renderable=False,max_sample_count=0)
        self.reject(change)
    def test_supported_format_skipped(self):self.reject(lambda r:r['formats'][-1].update(status='unsupported'))
    def test_wrong_default_properties(self):self.reject(lambda r:r['formats'][0]['properties'].update(flags=1))
    def test_duplicate_symbol(self):self.reject(lambda r:r['descriptor_symbols'].append(r['descriptor_symbols'][0]))
    def test_unresolved_symbol(self):self.reject(lambda r:r['descriptor_symbols'][0].update(available=False))
    def test_missing_retirement(self):self.reject(lambda r:r['staging'].update(retirements=0))
    def test_no_MSAA_metadata_as_allocation(self):self.reject(lambda r:r['formats'][0]['capability'].update(allocation_verified=True))
    def test_hdr_claim(self):self.reject(lambda r:r.update(hdr_verified=True))
    def test_incomplete_case_count(self):self.reject(lambda r:r.update(cases=1))
    def test_boolean_case_count(self):self.reject(lambda r:r.update(cases=True))
    def test_boolean_failed_count(self):self.reject(lambda r:r.update(failures=False))
    def test_duplicate_document(self):self.reject(lambda r:r['documents'].__setitem__(1,r['documents'][0]))
    def test_unsupported_integer_format(self):
        def change(r):
            row=next(v for v in r['formats'] if v['color_type']=='gray-8')
            row.update(status='unsupported');row.pop('file');row['capability'].update(renderable=False,max_sample_count=0)
            r['unsupported_rejections']=1
        self.assertEqual(self.invoke(change)['unsupported_formats'],1)

class Sources(unittest.TestCase):
    """Complete checkout checks; absence is a failure, never a synthetic pass."""
    def text(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_canonical_version_and_pins(self):
        self.assertIn('(define version "0.75")',self.text('info.rkt'))
        for s in ('("base" #:version "8.18")','("draw-lib" #:version "1.22")'):self.assertIn(s,self.text('info.rkt'))
        self.assertEqual(self.text('private/native-default-version.txt').strip(),'3.119.1')
    def test_public_properties_are_detached(self):
        s=self.text('surface-properties.rkt')
        self.assertNotIn('ffi/unsafe',s);self.assertNotIn('native.rkt',s)
        for flag in ('device-independent-fonts?','dynamic-msaa?','always-dither?'):self.assertIn(flag,s)
    def test_native_property_calls_are_real(self):
        s=self.text('private/native.rkt')
        for name in ('new','delete','get_flags','get_pixel_geometry'):self.assertIn('(define-native sk_surfaceprops_'+name,s)
        self.assertIn('(define-native sk_surface_get_props',s)
    def test_cache_key_not_only_extents(self):
        s=self.text('private/gpu-frame-target-cache.rkt')
        self.assertIn('(equal? configuration (target-entry-configuration entry))',s)
        self.assertIn('gpu-cache-budget!',s);self.assertIn('configuration-change',s)
    def test_current_GPU_case_count(self):
        count=self.text('tests/gpu-format-gpu-test.rkt').count('(test! ')-2+len(gv.FORMATS)
        self.assertEqual(count,gv.GPU_CASES)
    def test_stage_contracts_are_registered(self):
        s=self.text('run-tests.rkt')
        for term in ('tests/gpu-format-pure-test.rkt','tests/gpu-format-native-test.rkt','run-tests gpu-format-pure-tests'):self.assertIn(term,s)
        self.assertIn("'test-gpu-formats.py'",self.text('tools/ci.py'))
        self.assertIn('tests/gpu-format-gpu-test.rkt',self.text('info.rkt'))
    def test_readback_is_transactional_and_immobile(self):
        s=self.text('private/gpu-surfaces.rkt')
        for term in ('call-with-pixmap-write-staging','call-with-gpu-image-info','destination unchanged','read-pixels/native'):self.assertIn(term,s)
        self.assertIn('pixel-storage-input',self.text('raster-buffers.rkt'))
    def test_typed_readback_ledger_precedes_completion_boundary(self):
        s=self.text('private/gpu-surfaces.rkt')
        start=s.index('(define (gpu-surface-read-pixmap!')
        end=s.index('(define (gpu-surface->raster-buffer',start)
        body=s[start:end]
        self.assertIn('(image-info-storage-layout (r:pixmap-image-info destination))',body)
        self.assertLess(body.index('(record-gpu-io!'),body.index('(gpu-wait!'))
    def test_float_upload_does_not_ignore_reduced_precision(self):
        s=self.text('private/gpu-images.rkt')
        self.assertIn('operation-precision-compatible?',s)
        self.assertIn('#:color-type (image-color-type im)',s)
    def test_frame_DC_passes_whole_key(self):
        s=self.text('private/gpu-dc-native.rkt')
        self.assertIn('gpu-staging-key',s);self.assertIn('#:configuration key',s)
        self.assertIn('#:surface-properties properties',s)
    def test_native_descriptors_are_checked_not_exported_raw(self):
        for name in ('gpu-gl-interop-native.rkt','gpu-metal-interop-native.rkt','gpu-d3d12-interop-native.rkt'):
            self.assertIn('checked-backend-resource/native',self.text('private/'+name))
        self.assertNotIn('checked-backend-resource/native',self.text('gpu.rkt'))
    def test_keep_three_automatic_workflows(self):
        workflows=ROOT/'.github/workflows'
        auto={p.name for p in workflows.glob('*.yml') if '\n  push:' in p.read_text() or '\n  pull_request:' in p.read_text()}
        self.assertEqual(auto,{'ci.yml','api-inventory.yml','acceptance.yml'})
        s=self.text('.github/workflows/gpu-formats.yml')
        for term in ('workflow_call:','workflow_dispatch:','--require-gpu','--backend egl','--backend direct3d','--adapter warp','--require-renderers'):
            self.assertIn(term,s)
        self.assertNotIn('continue-on-error',s)
        self.assertIn('test "$GPU_FORMATS_RESULT" = success',self.text('.github/workflows/acceptance.yml'))

if __name__=='__main__':unittest.main(verbosity=2)
