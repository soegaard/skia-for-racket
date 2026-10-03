"""Synthetic style-inspector tests: no claim of Racket/Skia rendering."""
from __future__ import annotations
import copy
from pathlib import Path
import struct
import tempfile
import unittest
import zlib
import dc_validation as d
import dc_style_validation as s

IDENTITY = dict(os='unix', architecture='x86_64', version='9.3')

def png(pixels):
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    w,h=s.SIZE
    raw=b''.join(b'\0'+pixels[4*y*w:4*(y+1)*w] for y in range(h))
    return (d.PNG_MAGIC+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+
            chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))

def write_style_fixture(directory):
    data=bytearray(bytes((255,255,255,255))*64*64)
    for x,y,rgba in s.probes('direct'):
        data[4*(y*64+x):4*(y*64+x)+4]=bytes(rgba)
    for x in range(2,30):
        data[4*(56*64+x):4*(56*64+x)+4]=bytes((255,0,0,255))
    names=[s.filename(mode) for mode in s.MODES]
    for name in names: (directory/name).write_bytes(png(data))
    raw=dict(schema=1,stage='0.57',status='passed',validation_run=directory.name,
             pure_cases=24,native_cases=40,math_cases=45,pure_failures=0,native_failures=0,
             snapshots_encoded_after_dc_close=True,region_query_scratch_context=True,
             gui_initialized=False,gpu_execution_verified=False,full_drop_in_compatibility=False,
             cairo_drawing_fallback=False,reference_pixel_equivalence_claimed=False,
             os='unix',architecture='x86_64',racket_version='9.3',captures=names)
    d.write_json(directory/'dc-styles.json',raw)
    return raw

class StyleInspector(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.raw=write_style_fixture(self.root)
    def reject(self, **changes):
        raw=copy.deepcopy(self.raw);raw.update(changes)
        d.write_json(self.root/'dc-styles.json',raw)
        with self.assertRaises(ValueError): s.inspect_styles(self.root,IDENTITY)
    def alter(self, mode, x,y,rgba):
        path=self.root/s.filename(mode);data=bytearray(d.png_rgba(path,s.SIZE))
        data[4*(y*64+x):4*(y*64+x)+4]=bytes(rgba);path.write_bytes(png(data))
    def test_style_valid(self):
        r=s.inspect_styles(self.root,IDENTITY)
        self.assertTrue(r['independent_style_probes_verified']);self.assertEqual(len(r['captures']),4)
        self.assertFalse(r['reference_pixel_equivalence_claimed'])
    def test_style_stage(self): self.reject(stage='0.56')
    def test_style_schema(self): self.reject(schema=True)
    def test_style_failed(self): self.reject(status='failed')
    def test_style_stale(self): self.reject(validation_run='other')
    def test_style_pure_count(self): self.reject(pure_cases=23)
    def test_style_native_count(self): self.reject(native_cases=39)
    def test_style_math_count(self): self.reject(math_cases=44)
    def test_style_boolean_count(self): self.reject(pure_cases=True)
    def test_style_boolean_failure(self): self.reject(native_failures=False)
    def test_style_pure_failure(self): self.reject(pure_failures=1)
    def test_style_native_failure(self): self.reject(native_failures=1)
    def test_style_post_close_required(self): self.reject(snapshots_encoded_after_dc_close=False)
    def test_style_query_disclosure_required(self): self.reject(region_query_scratch_context=False)
    def test_style_no_gpu_claim(self): self.reject(gpu_execution_verified=True)
    def test_style_no_gui_claim(self): self.reject(gui_initialized=True)
    def test_style_no_dropin_claim(self): self.reject(full_drop_in_compatibility=True)
    def test_style_no_cairo_rendering(self): self.reject(cairo_drawing_fallback=True)
    def test_style_no_reference_equality_claim(self): self.reject(reference_pixel_equivalence_claimed=True)
    def test_style_foreign_os(self): self.reject(os='macosx')
    def test_style_foreign_version(self): self.reject(racket_version='8.18')
    def test_style_foreign_architecture(self): self.reject(architecture='aarch64')
    def test_style_missing_report(self):
        (self.root/'dc-styles.json').unlink()
        with self.assertRaises(ValueError): s.inspect_styles(self.root,IDENTITY)
    def test_style_missing_capture(self):
        for mode in s.MODES:
            p=self.root/s.filename(mode);old=p.read_bytes();p.unlink()
            try:
                with self.assertRaises(ValueError): s.inspect_styles(self.root,IDENTITY)
            finally: p.write_bytes(old)
    def test_style_wrong_capture_order(self): self.reject(captures=list(reversed(self.raw['captures'])))
    def test_style_unsafe_name(self): self.reject(captures=['../x']+self.raw['captures'][1:])
    def test_style_symlink_capture(self):
        p=self.root/s.filename('datum');p.unlink()
        try: p.symlink_to(self.root/s.filename('direct'))
        except (OSError,NotImplementedError): self.skipTest('host does not permit test symlinks')
        with self.assertRaises(ValueError): s.inspect_styles(self.root,IDENTITY)
    def test_style_symlink_report(self):
        p=self.root/'dc-styles.json';target=self.root/'copied.json';p.rename(target)
        try: p.symlink_to(target)
        except (OSError,NotImplementedError): self.skipTest('host does not permit test symlinks')
        with self.assertRaises(ValueError): s.inspect_styles(self.root,IDENTITY)
    def test_style_each_mode_independently_checked(self):
        for mode in s.MODES:
            with self.subTest(mode=mode):
                write_style_fixture(self.root);self.alter(mode,20,4,(0,0,0,255))
                with self.assertRaises(ValueError): s.inspect_styles(self.root,IDENTITY)
    def test_style_equal_but_wrong_is_not_evidence(self):
        for mode in s.MODES:self.alter(mode,20,4,(0,0,0,255))
        with self.assertRaises(ValueError):s.inspect_styles(self.root,IDENTITY)
    def test_style_gradient_direction(self):
        self.alter('direct',0,8,(0,0,255,255))
        with self.assertRaises(ValueError):s.inspect_styles(self.root,IDENTITY)
    def test_style_missing_hatch_gap(self):
        self.alter('direct',36,4,(255,0,0,255))
        with self.assertRaises(ValueError):s.inspect_styles(self.root,IDENTITY)
    def test_style_missing_stipple_pen(self):
        self.alter('direct',10,56,(255,255,255,255))
        with self.assertRaises(ValueError):s.inspect_styles(self.root,IDENTITY)
    def test_style_replay_tolerance_is_two(self):
        self.alter('procedure',0,63,(253,255,255,255));s.inspect_styles(self.root,IDENTITY)
        self.alter('procedure',0,63,(252,255,255,255))
        with self.assertRaises(ValueError):s.inspect_styles(self.root,IDENTITY)
    def test_style_reference_edges_are_not_equality_gate(self):
        self.alter('reference',0,63,(0,0,0,255))
        self.assertEqual(s.inspect_styles(self.root,IDENTITY)['reference_max_channel_difference'],255)
    def test_style_hidpi_stipple_contract_is_checked_on_skia_paths(self):
        for mode in ('direct','procedure','datum'):
            write_style_fixture(self.root);self.alter(mode,53,36,(255,0,0,255))
            with self.assertRaises(ValueError):s.inspect_styles(self.root,IDENTITY)
    def test_style_reference_hidpi_backend_quirk_is_review_only(self):
        self.alter('reference',53,36,(255,0,0,255));s.inspect_styles(self.root,IDENTITY)
    def test_style_probe_tolerance_is_three(self):
        x,y,want=s.probes()[0]
        for mode in s.MODES:self.alter(mode,x,y,(want[0]-3,*want[1:]))
        s.inspect_styles(self.root,IDENTITY)
        for mode in s.MODES:self.alter(mode,x,y,(want[0]-4,*want[1:]))
        with self.assertRaises(ValueError):s.inspect_styles(self.root,IDENTITY)
    def test_style_duplicate_json_key(self):
        p=self.root/'dc-styles.json';p.write_text(p.read_text().replace('"schema": 1','"schema": 1, "schema": 1'))
        with self.assertRaises(ValueError):s.inspect_styles(self.root,IDENTITY)
    def test_style_nonfinite_json(self):
        p=self.root/'dc-styles.json';p.write_text(p.read_text().replace('"math_cases": 45','"math_cases": NaN'))
        with self.assertRaises(ValueError):s.inspect_styles(self.root,IDENTITY)

if __name__=='__main__': unittest.main(verbosity=2)
