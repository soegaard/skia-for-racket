"""Synthetic inspector regressions; these do not execute pict, plot, or Skia."""
from __future__ import annotations
import copy
from pathlib import Path
import struct
import tempfile
import unittest
import zlib
import dc_validation as d
import dc_consumer_validation as c


def png(pixels):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    w, h = c.SIZE
    raw = b''.join(b'\0' + pixels[y*w*4:(y+1)*w*4] for y in range(h))
    return (d.PNG_MAGIC + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def synthetic_pixels(kind, layout):
    w, h = c.SIZE
    data = bytearray(bytes((255, 255, 255, 255)) * w * h)
    def put(x, y, rgba): data[4*(y*w+x):4*(y*w+x+1)] = bytes(rgba)
    if kind == 'pict':
        for x, y, rgba in ((24,24,(255,0,0,255)), (18,72,(255,128,128,255)),
                           (36,72,(128,128,255,255)), (164,16,(20,180,60,255))):
            put(x, y, rgba)
        for x in range(12, 40): put(x, 138, (0,0,128,255))
    else:
        for x in range(41, 305):
            plot_x = (x-40) / 265 * 4 - 2
            _, y = c.plot_position(layout, plot_x, plot_x / 2)
            for yy in range(round(y)-1, round(y)+2): put(x, yy, (0,0,255,255))
        for px, py in ((-1,1),(1,-1)):
            x, y = map(round, c.plot_position(layout, px, py))
            for xx in range(x-3, x+4):
                for yy in range(y-3, y+4):
                    if (xx-x)**2+(yy-y)**2 <= 9: put(xx, yy, (255,0,0,255))
        for x in range(90, 180): put(x, 12, (0,0,0,255))
    return bytes(data)


def write_consumer_fixture(directory):
    directory = Path(directory)
    layout = dict(lower_left=[40.0,205.0], upper_right=[305.0,35.0])
    captures = []
    for kind in c.KINDS:
        pixels = synthetic_pixels(kind, layout)
        for mode in c.MODES:
            name = c.filename(kind, mode)
            (directory/name).write_bytes(png(pixels))
            captures.append(dict(kind=kind,mode=mode,file=name,layout=layout if kind == 'plot' else False))
    raw = dict(schema=1,stage='0.56',status='passed',validation_run=directory.name,
               os='unix',architecture='x86_64',racket_version='9.3',
               native_cases=16,native_failures=0,snapshots_encoded_after_dc_close=True,
               gui_initialized=False,gpu_execution_verified=False,full_drop_in_compatibility=False,
               reference_pixel_equivalence_claimed=False,captures=captures)
    d.write_json(directory/'dc-consumers.json',raw)
    return raw


class ConsumerInspector(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.raw = write_consumer_fixture(self.directory)
    def reject(self, mutate):
        raw = copy.deepcopy(self.raw); mutate(raw)
        d.write_json(self.directory/'dc-consumers.json',raw)
        with self.assertRaises(ValueError): c.inspect_consumers(self.directory)
    def replace_pixels(self, kind, mode, mutate):
        path = self.directory/c.filename(kind,mode)
        data = bytearray(d.png_rgba(path,c.SIZE)); mutate(data); path.write_bytes(png(data))
    def test_consumer_valid(self):
        r=c.inspect_consumers(self.directory)
        self.assertEqual(r['native_cases'],16); self.assertEqual(len(r['captures']),8)
        self.assertTrue(r['manual_reference_review_required'])
        self.assertFalse(r['reference_pixel_equivalence_claimed'])
    def test_consumer_native_count(self): self.reject(lambda r:r.update(native_cases=15))
    def test_consumer_boolean_count(self): self.reject(lambda r:r.update(native_cases=True))
    def test_consumer_failure(self): self.reject(lambda r:r.update(native_failures=1))
    def test_consumer_boolean_failure_not_zero(self): self.reject(lambda r:r.update(native_failures=False))
    def test_consumer_missing_cases(self): self.reject(lambda r:r.pop('native_cases'))
    def test_consumer_stale_run(self): self.reject(lambda r:r.update(validation_run='other'))
    def test_consumer_stage(self): self.reject(lambda r:r.update(stage='0.55'))
    def test_consumer_failed_status(self): self.reject(lambda r:r.update(status='failed'))
    def test_consumer_missing_capture(self):
        for kind in c.KINDS:
            for mode in c.MODES:
                path=self.directory/c.filename(kind,mode); previous=path.read_bytes();path.unlink()
                try:
                    with self.assertRaises(ValueError): c.inspect_consumers(self.directory)
                finally: path.write_bytes(previous)
    def test_consumer_missing_report(self):
        (self.directory/'dc-consumers.json').unlink()
        with self.assertRaises(ValueError): c.inspect_consumers(self.directory)
    def test_consumer_duplicate_capture(self):
        self.reject(lambda r:r['captures'].__setitem__(1,copy.deepcopy(r['captures'][0])))
    def test_consumer_unsafe_path(self): self.reject(lambda r:r['captures'][0].update(file='../outside.png'))
    def test_consumer_invalid_capture_kind(self): self.reject(lambda r:r['captures'][0].update(kind='other'))
    def test_consumer_invalid_layout(self): self.reject(lambda r:r['captures'][4].update(layout={}))
    def test_consumer_reversed_plot_corners(self):
        self.reject(lambda r:r['captures'][4]['layout'].update(lower_left=[305,35]))
    def test_consumer_boolean_corner(self):
        self.reject(lambda r:r['captures'][4]['layout'].update(lower_left=[True,205]))
    def test_consumer_unbounded_corner(self):
        self.reject(lambda r:r['captures'][4]['layout'].update(lower_left=[1e100,205]))
    def test_consumer_false_equality_claim(self): self.reject(lambda r:r.update(reference_pixel_equivalence_claimed=True))
    def test_consumer_false_gpu_claim(self): self.reject(lambda r:r.update(gpu_execution_verified=True))
    def test_consumer_gui_claim(self): self.reject(lambda r:r.update(gui_initialized=True))
    def test_consumer_post_close_required(self): self.reject(lambda r:r.update(snapshots_encoded_after_dc_close=False))
    def test_consumer_foreign_interpreter(self):
        with self.assertRaises(ValueError):
            c.inspect_consumers(self.directory,identity=dict(os='windows',architecture='x86_64',version='9.3'))
    def test_consumer_blank_images_are_not_evidence(self):
        for cap in self.raw['captures']:
            (self.directory/cap['file']).write_bytes(png(bytes((255,255,255,255))*320*240))
        with self.assertRaises(ValueError): c.inspect_consumers(self.directory)
    def test_consumer_pict_missing_group_composition(self):
        self.replace_pixels('pict','direct',lambda b:b.__setitem__(slice(4*(72*320+36),4*(72*320+36)+4),bytes((128,64,191,255))))
        with self.assertRaises(ValueError): c.inspect_consumers(self.directory)
    def test_consumer_pict_missing_text(self):
        def erase(b):
            for y in range(126,172): b[y*320*4:(y+1)*320*4]=bytes((255,255,255,255))*320
        self.replace_pixels('pict','direct',erase)
        with self.assertRaises(ValueError): c.inspect_consumers(self.directory)
    def test_consumer_plot_missing_curve(self):
        def erase(b):
            for i in range(0,len(b),4):
                if c.color_ink(tuple(b[i:i+4]),'blue'): b[i:i+4]=bytes((255,255,255,255))
        self.replace_pixels('plot','direct',erase)
        with self.assertRaises(ValueError): c.inspect_consumers(self.directory)
    def test_consumer_plot_missing_points(self):
        def erase(b):
            for i in range(0,len(b),4):
                if c.color_ink(tuple(b[i:i+4]),'red'): b[i:i+4]=bytes((255,255,255,255))
        self.replace_pixels('plot','datum',erase)
        with self.assertRaises(ValueError): c.inspect_consumers(self.directory)
    def test_consumer_replay_two_units_allowed_three_rejected(self):
        self.replace_pixels('pict','procedure',lambda b:b.__setitem__(0,253))
        c.inspect_consumers(self.directory)
        self.replace_pixels('pict','procedure',lambda b:b.__setitem__(0,252))
        with self.assertRaisesRegex(ValueError,'replay mismatch'): c.inspect_consumers(self.directory)
    def test_consumer_reference_not_forced_to_match(self):
        self.replace_pixels('pict','reference',lambda b:b.__setitem__(0,0))
        r=c.inspect_consumers(self.directory)
        self.assertEqual(r['reference_comparison']['pict']['max_channel_error'],255)
        self.assertIsNone(r['reference_comparison']['pict']['acceptance_threshold'])
    def test_consumer_sources_fingerprinted(self):
        for path in ('tests/dc-consumer-fixtures.rkt','tests/dc-consumer-native-test.rkt',
                     'tools/dc-consumer-doctor.rkt','tools/dc_consumer_validation.py','examples/dc-consumers.rkt'):
            self.assertIn(path,d.SOURCE_PATHS)
    def test_consumer_real_public_clients_not_bitmap_detours(self):
        root=Path(__file__).resolve().parents[1]
        text=(root/'tests/dc-consumer-fixtures.rkt').read_text()
        for name in ('p:draw-pict','plot:plot/dc','plot/no-gui','rd:recorded-datum->procedure','p:dc-for-text-size'):
            self.assertIn(name,text)
        for name in ('plot:plot-bitmap','plot:plot-pict','racket/gui/base','racket/draw/private'):
            self.assertNotIn(name,text)
    def test_consumer_legend_does_not_occlude_data_probes(self):
        root=Path(__file__).resolve().parents[1]
        text=(root/'tests/dc-consumer-fixtures.rkt').read_text()
        self.assertIn("#:legend-anchor 'outside-top-right",text)
        self.assertNotIn("#:legend-anchor 'top-right",text)
        self.assertIn('platform font metrics',text)
    def test_consumer_count_matches_native_suite(self):
        import re
        text=(Path(__file__).resolve().parents[1]/'tests/dc-consumer-native-test.rkt').read_text()
        self.assertEqual(len(re.findall(r'\(test-case\s',text)),c.NATIVE_CASES)
        self.assertIn(f'(define dc-consumer-native-test-count {c.NATIVE_CASES})',text)
    def test_consumer_doctor_is_required_not_optional(self):
        root=Path(__file__).resolve().parents[1]
        self.assertIn('(dc-consumer-doctor! directory)',(root/'tools/dc-doctor.rkt').read_text())
        self.assertIn('consumers = inspect_consumers(directory, identity=',(root/'tools/dc_validation.py').read_text())


if __name__=='__main__':
    unittest.main(verbosity=2)
