#!/usr/bin/env python3
"""DC oracle/PNG/runner tests. Synthetic fixtures never count as native execution."""
from __future__ import annotations
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout, redirect_stderr
from unittest.mock import patch
import zlib
from functools import lru_cache
import dc_validation as d
from test_dc_consumers import ConsumerInspector, write_consumer_fixture
from test_dc_styles import StyleInspector, write_style_fixture

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
spec = importlib.util.spec_from_file_location('validate_dc', HERE/'validate-dc.py')
v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)


def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind+payload) & 0xffffffff)


def png(width, height, pixels, *, channels=4, filter_type=0, compression_tail=b''):
    raw = bytearray(); previous = bytes(width*channels)
    def paeth(a, b, c):
        p = a+b-c; ds = abs(p-a), abs(p-b), abs(p-c)
        return (a, b, c)[ds.index(min(ds))]
    for y in range(height):
        row = pixels[y*width*4:(y+1)*width*4]
        if channels == 3:
            row = b''.join(row[x:x+3] for x in range(0, len(row), 4))
        raw.append(filter_type)
        for i, value in enumerate(row):
            a = row[i-channels] if i >= channels else 0
            b = previous[i]; c = previous[i-channels] if i >= channels else 0
            predictor = (0, a, b, (a+b)//2, paeth(a, b, c))[filter_type]
            raw.append((value-predictor) & 255)
        previous = row
    return (d.PNG_MAGIC + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6 if channels == 4 else 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes(raw)) + compression_tail) + chunk(b'IEND', b''))


def report(directory):
    return dict(schema=1, stage='0.57', status='passed', validation_run=directory.name,
                storage='persistent-cpu-raster', native_package='3.119.1', native_version='119.0',
                pure_cases=60, pure_failures=0, native_cases=31, native_failures=0,
                compat_pure_cases=36, compat_pure_failures=0, compat_native_cases=34, compat_native_failures=0,
                compat_oracle="dc-compat-oracle.png", text_sample="dc-text.skia.png",
                replay_pure_cases=28, replay_pure_failures=0, replay_native_cases=28, replay_native_failures=0,
                consumer_report="dc-consumers.json", style_report="dc-styles.json", alpha_controller_cases=24, alpha_direct="dc-alpha.direct.png",
                alpha_procedure="dc-alpha.procedure.png", alpha_datum="dc-alpha.datum.png",
                gpu_execution_verified=False, gui_initialized=False, full_drop_in_compatibility=False,
                universal_pixel_identity_claimed=False, demo_pixel_equivalence_verified=False,
                snapshots_encoded_after_dc_close=True, os='unix', architecture='x86_64', racket_version='9.3',
                oracle='dc-oracle.png', skia_demo='dc-primitives.skia.png', reference_demo='dc-primitives.racket.png')


@lru_cache(maxsize=1)
def base_capture_bytes():
    # Cache only immutable synthetic PNG bytes; every test gets fresh files.
    # The inspector still decodes/validates each file, including mutations.
    samples = b''.join(bytes((i%256, (i*3)%256, (i*7)%256, 255)) for i in range(460*320))
    demo = png(460, 320, samples)
    alpha = png(48, 32, d.alpha_oracle_rgba())
    return (('dc-oracle.png', png(48,40,d.oracle_rgba())),
            ('dc-compat-oracle.png', png(64,48,d.compatibility_oracle_rgba())),
            ('dc-text.skia.png', png(320,104,samples[:320*104*4])),
            ('dc-alpha.direct.png', alpha), ('dc-alpha.procedure.png', alpha),
            ('dc-alpha.datum.png', alpha), ('dc-primitives.skia.png', demo),
            ('dc-primitives.racket.png', demo))


def evidence(directory):
    write_consumer_fixture(directory)
    write_style_fixture(directory)
    d.write_json(directory/'dc.diagnostic.json', report(directory))
    for name, data in base_capture_bytes():
        (directory/name).write_bytes(data)


class PNG(unittest.TestCase):
    def read(self, data, size=(48, 40)):
        with tempfile.TemporaryDirectory() as t:
            path = Path(t)/'image.png'; path.write_bytes(data)
            return d.png_rgba(path, size)
    def test_rgba_round_trip(self):
        self.assertEqual(self.read(png(48, 40, d.oracle_rgba())), d.oracle_rgba())
    def test_all_row_filters(self):
        for f in range(5):
            with self.subTest(filter=f):
                self.assertEqual(self.read(png(48, 40, d.oracle_rgba(), filter_type=f)), d.oracle_rgba())
    def test_rgb(self):
        pixels = bytes((10, 20, 30, 255))*8
        for f in range(5):
            self.assertEqual(self.read(png(4, 2, pixels, channels=3, filter_type=f), (4, 2)), pixels)
    def test_crc(self):
        data = bytearray(png(48, 40, d.oracle_rgba())); data[29] ^= 1
        with self.assertRaisesRegex(ValueError, 'CRC'): self.read(bytes(data))
    def test_truncated(self):
        with self.assertRaises(ValueError): self.read(png(48, 40, d.oracle_rgba())[:-5])
    def test_trailing(self):
        with self.assertRaisesRegex(ValueError, 'trailing'): self.read(png(48, 40, d.oracle_rgba())+b'x')
    def test_size(self):
        with self.assertRaisesRegex(ValueError, 'dimensions'): self.read(png(48, 40, d.oracle_rgba()), (48, 41))
    def test_compressed_tail(self):
        with self.assertRaises(ValueError): self.read(png(48, 40, d.oracle_rgba(), compression_tail=b'extra'))
    def test_header_must_be_first(self):
        data = png(48, 40, d.oracle_rgba())
        with self.assertRaisesRegex(ValueError, 'first'): self.read(d.PNG_MAGIC + chunk(b'tEXt', b'x') + data[8:])
    def test_duplicate_header(self):
        data = png(48, 40, d.oracle_rgba())
        with self.assertRaisesRegex(ValueError, 'duplicate'): self.read(data[:33]+data[8:])
    def test_unknown_critical_chunk(self):
        data = png(48, 40, d.oracle_rgba())
        with self.assertRaisesRegex(ValueError, 'critical'): self.read(data[:33]+chunk(b'ABCD', b'x')+data[33:])
    def test_missing_end(self):
        with self.assertRaises(ValueError): self.read(png(48, 40, d.oracle_rgba())[:-12])
    def test_more_pixels_than_header(self):
        original = png(48, 41, d.oracle_rgba()+bytes(48*4))
        data = original[:8]+chunk(b'IHDR', struct.pack('>IIBBBBB',48,40,8,6,0,0,0))+original[33:]
        with self.assertRaises(ValueError): self.read(data)
    def test_oracle_asymmetric(self):
        data=d.oracle_rgba()
        self.assertEqual(data[:4], bytes((255,0,0,255)))
        self.assertEqual(data[24*4:25*4], bytes((0,200,0,255)))
        self.assertEqual(data[(10*48+8)*4:(10*48+9)*4], bytes((120,30,200,255)))
        self.assertEqual(data[(30*48+36)*4:(30*48+37)*4], bytes(4))


class Inspector(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)/'dc-test'; self.directory.mkdir(); evidence(self.directory)
    def mutate(self, key, value):
        raw=report(self.directory); raw[key]=value; d.write_json(self.directory/'dc.diagnostic.json',raw)
        with self.assertRaises(ValueError): d.inspect_directory(self.directory)
    def test_valid(self):
        out=d.inspect_directory(self.directory); self.assertTrue(out['exact_oracle_pixels_verified'])
        self.assertFalse(out['demo_pixel_equivalence_verified']); self.assertEqual(len(out['captures']),8)
    def test_failed(self): self.mutate('status','failed')
    def test_bool_schema(self): self.mutate('schema',True)
    def test_wrong_stage(self): self.mutate('stage','0.52')
    def test_foreign_run(self): self.mutate('validation_run','another')
    def test_gpu_backing(self): self.mutate('storage','metal')
    def test_native_pin(self): self.mutate('native_package','4.0.0')
    def test_native_version(self): self.mutate('native_version','153.0')
    def test_pure_count(self): self.mutate('pure_cases',59)
    def test_native_count(self): self.mutate('native_cases',30)
    def test_bool_failure(self): self.mutate('native_failures',False)
    def test_pure_failure(self): self.mutate('pure_failures',1)
    def test_early_encoding(self): self.mutate('snapshots_encoded_after_dc_close',False)
    def test_bad_os(self): self.mutate('os','unknown')
    def test_empty_version(self): self.mutate('racket_version','')
    def test_missing_file(self):
        (self.directory/'dc-oracle.png').unlink()
        with self.assertRaises(ValueError): d.inspect_directory(self.directory)
    def test_unsafe_path(self): self.mutate('oracle','../dc-oracle.png')
    def test_foreign_interpreter(self):
        with self.assertRaisesRegex(ValueError,'interpreter'):
            d.inspect_directory(self.directory, identity=dict(os='unix',architecture='x86_64',version='8.7'))
    def test_both_images_wrong_still_fails(self):
        wrong=png(48,40,bytes((255,255,255,255))*48*40)
        (self.directory/'dc-oracle.png').write_bytes(wrong)
        with self.assertRaisesRegex(ValueError,'oracle'): d.inspect_directory(self.directory)
    def test_blank_demo(self):
        (self.directory/'dc-primitives.skia.png').write_bytes(png(460,320,bytes(460*320*4)))
        with self.assertRaisesRegex(ValueError,'blank'): d.inspect_directory(self.directory)
    def test_duplicate_keys(self):
        p=self.directory/'dc.diagnostic.json'; p.write_text('{"status":"failed","status":"passed"}')
        with self.assertRaisesRegex(ValueError,'duplicate'): d.inspect_directory(self.directory)
    def test_nonfinite(self):
        p=self.directory/'dc.diagnostic.json'; p.write_text('{"schema":NaN}')
        with self.assertRaisesRegex(ValueError,'nonfinite'): d.inspect_directory(self.directory)
    def test_review_disclaims_equality(self):
        d.write_review(self.directory,d.inspect_directory(self.directory))
        self.assertIn('not certified',(self.directory/'dc.review.html').read_text())
    def test_consumer_report_is_required_by_parent_gate(self):
        (self.directory/'dc-consumers.json').unlink()
        with self.assertRaisesRegex(ValueError,'consumer report'):
            d.inspect_directory(self.directory)
    def test_consumer_failure_blocks_parent_gate(self):
        path=self.directory/'dc-consumers.json'
        raw=d.read_json(path); raw['native_failures']=1; d.write_json(path,raw)
        with self.assertRaisesRegex(ValueError,'consumer test evidence'):
            d.inspect_directory(self.directory)
    def test_consumer_identity_must_match_parent_without_runner(self):
        path=self.directory/'dc-consumers.json'
        raw=d.read_json(path); raw['racket_version']='8.18'; d.write_json(path,raw)
        with self.assertRaisesRegex(ValueError,'foreign consumer interpreter'):
            d.inspect_directory(self.directory)
    def test_consumer_images_appear_in_review(self):
        out=d.inspect_directory(self.directory)
        self.assertEqual(len(out['consumers']['captures']),8)
        d.write_review(self.directory,out)
        text=(self.directory/'dc.review.html').read_text()
        self.assertIn('dc-consumer-pict.direct.png',text)
        self.assertIn('dc-consumer-plot.reference.png',text)
    def test_failed_review_refused(self):
        with self.assertRaises(ValueError): d.write_review(self.directory,dict(status='failed'))


def claim_test(name):
    return lambda self: self.mutate(name,True)
for name in ('gpu_execution_verified','gui_initialized','full_drop_in_compatibility',
             'universal_pixel_identity_claimed','demo_pixel_equivalence_verified'):
    setattr(Inspector,'test_false_claim_'+name,claim_test(name))


class Orchestration(unittest.TestCase):
    def simulate(self, fail=None, mutate=False, manifest_only=False, consumer_failure=False):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t)/'source'; root.mkdir(); directory=Path(t)/'evidence'; directory.mkdir()
            for name in d.SOURCE_PATHS:
                p=root/name; p.parent.mkdir(parents=True,exist_ok=True); p.write_text('; synthetic source\n')
            (root/'SOURCE-SHA256SUMS.txt').write_text('synthetic manifest checked by injected command')
            calls=[]
            class Fake:
                def run(self, argv, *, cwd):
                    a=list(map(str,argv)); calls.append(a)
                    if fail and any(fail in x for x in a): raise RuntimeError('injected command failure')
                    if a[1].endswith('ci-identity.rkt'):
                        return json.dumps(dict(os='unix',architecture='x86_64',version='9.3',pointer_bytes=8,vm='chez-scheme'))
                    if a[1].endswith('dc-doctor.rkt'):
                        evidence(directory)
                        if consumer_failure:
                            child=d.read_json(directory/'dc-consumers.json')
                            child['native_failures']=1
                            d.write_json(directory/'dc-consumers.json',child)
                        if mutate: (root/'dc.rkt').write_text('; changed by test')
                    return ''
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                result=v.execute(root,directory,'/selected/racket',manifest_only=manifest_only,runner=Fake())
            path=directory/('validation.json' if result==0 else 'validation.failed.json')
            return result,calls,d.read_json(path),sorted(x.name for x in directory.iterdir())
    def test_order_and_identity(self):
        code,calls,raw,names=self.simulate(); self.assertEqual(code,0)
        self.assertIn('--check',calls[0]); self.assertIn('--check',calls[-1])
        self.assertEqual(calls[2][0],'/selected/racket'); self.assertIn('make',calls[2])
        self.assertTrue(raw['checks']['native_dc_and_pixels']); self.assertIn('dc.review.html',names)
    def test_manifest_only_installation(self):
        code,calls,raw,names=self.simulate(manifest_only=True)
        self.assertEqual(code,0); self.assertIn('--manifest-only',calls[0]); self.assertIn('--manifest-only',calls[-1])
    def test_compile_failure(self):
        code,_,raw,names=self.simulate(fail='make'); self.assertEqual(code,1)
        self.assertNotIn('native_dc_and_pixels',raw['checks']); self.assertNotIn('validation.json',names)
    def test_native_failure(self):
        code,_,raw,names=self.simulate(fail='dc-doctor.rkt'); self.assertEqual(code,1)
        self.assertNotIn('dc.inspection.json',names)
    def test_consumer_inspection_failure_blocks_runner_success(self):
        code,_,raw,names=self.simulate(consumer_failure=True)
        self.assertEqual(code,1)
        self.assertIn('consumer',raw['error'])
        self.assertIn('dc-consumers.json',names)
        self.assertNotIn('validation.json',names)
        self.assertNotIn('dc.inspection.json',names)
    def test_identity_failure(self): self.assertEqual(self.simulate(fail='ci-identity.rkt')[0],1)
    def test_manifest_failure(self): self.assertEqual(self.simulate(fail='update-source-sums.py')[0],1)
    def test_source_mutation(self):
        code,_,raw,names=self.simulate(mutate=True); self.assertEqual(code,1)
        self.assertIn('source changed',raw['error']); self.assertNotIn('dc.inspection.json',names)
    def test_pointer_bool_identity(self):
        self.assertFalse(v.exact_identity(dict(os='unix',architecture='x86_64',version='9.3',pointer_bytes=True,vm='chez-scheme')))
    def test_unknown_vm(self):
        self.assertFalse(v.exact_identity(dict(os='unix',architecture='x86_64',version='9.3',pointer_bytes=8,vm='racket')))
    def test_existing_evidence_refused(self):
        with tempfile.TemporaryDirectory() as t, patch.object(v.shutil,'which',return_value='/selected/racket'):
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit): v.main(['--output',t])
    def test_command_failure_retains_log(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t); runner=v.Runner(root)
            with redirect_stdout(io.StringIO()), self.assertRaises(RuntimeError):
                runner.run([sys.executable,'-c','print("before failure");raise SystemExit(7)'],cwd=root)
            self.assertIn('before failure',(root/'logs/001.log').read_text())
            self.assertEqual(d.read_json(root/'commands.json')[0]['returncode'],7)
    def test_command_timeout_retains_log(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t); runner=v.Runner(root,timeout=0.1)
            with redirect_stdout(io.StringIO()), self.assertRaises(RuntimeError):
                runner.run([sys.executable,'-c','import time;print("started",flush=True);time.sleep(5)'],cwd=root)
            self.assertTrue(d.read_json(root/'commands.json')[0]['timed_out'])


class Source(unittest.TestCase):
    def test_counts_match_racket_sources(self):
        for kind,count in [('pure',d.PURE_CASES),('native',d.NATIVE_CASES)]:
            text=(ROOT/f'tests/dc-{kind}-test.rkt').read_text()
            self.assertEqual(len(re.findall(r'\(test-case\s',text)),count)
            self.assertIn(f'(define dc-{kind}-test-count {count})',text)
    def test_public_opt_in(self):
        text=(ROOT/'dc.rkt').read_text(); self.assertIn('skia-dc%',text); self.assertIn('exn:fail:skia-dc:unsupported',text)
    def test_no_private_draw_dependency(self):
        for name in ('dc.rkt','private/dc-class.rkt','private/dc-render.rkt','private/dc-geometry.rkt'):
            text=(ROOT/name).read_text()
            self.assertNotIn('racket/draw/private/',text); self.assertNotIn('unsafe/cairo',text)
            self.assertNotIn('racket/gui/base',text)
    def test_only_skia_renderer_in_public_module(self):
        text=(ROOT/'dc.rkt').read_text(); self.assertIn('(make-skia-dc-class skia-dc-renderer)',text)
    def test_alpha_default_override(self):
        text=(ROOT/'private/dc-class.rkt').read_text()
        marker='(class* implementation% (rd:dc<%>)'
        self.assertIn(marker,text)
        base,final=text.split(marker,1)
        # dc<%> itself supplies defaults for start-alpha/end-alpha. The
        # interface may be attached only after the interface-free superclass;
        # defining either method in that superclass causes a class* conflict.
        self.assertNotIn('(define/public (start-alpha',base)
        self.assertNotIn('(define/public (end-alpha',base)
        self.assertIn('(define/override (start-alpha a)',final)
        self.assertIn('(define/override (end-alpha)',final)
    def test_interface_probe_uses_public_membership(self):
        text=(ROOT/'tests/dc-pure-test.rkt').read_text()
        self.assertIn('(check-true (is-a? dc rd:dc<%>))',text)
        self.assertNotIn('(object-interface dc)',text)
    def test_foundation_smoke_keeps_public_boundary_and_replay_is_separate(self):
        native=(ROOT/'tests/dc-native-test.rkt').read_text()
        docs=(ROOT/'docs/SKIA-DC.md').read_text()
        self.assertNotIn('rd:record-dc%',native)
        self.assertIn('public drawing procedure can replay into a Skia dc',native)
        for term in ('record-dc%', 'do-set-pen!', 'do-set-brush!', '0.55'):
            self.assertIn(term,docs)
    def test_direct_public_path_conversion(self):
        text=(ROOT/'private/dc-geometry.rkt').read_text(); self.assertIn('(send path get-datum)',text)
    def test_native_oracle_not_pairwise_only(self):
        text=(HERE/'dc_validation.py').read_text(); self.assertIn('pixels == oracle_rgba()',text)
    def test_doctor_encoding_after_close(self):
        text=(HERE/'dc-doctor.rkt').read_text()
        self.assertLess(text.index('(send dc close)'),text.index('(sk:image->png-bytes im)'))
    def test_python_syntax(self):
        for name in ('dc_validation.py','validate-dc.py','test-dc.py'):
            compile((HERE/name).read_text(),name,'exec')


class Integration(unittest.TestCase):
    """These checks intentionally require a COMPLETE applied checkout."""
    def test_racket_suites_in_main_runner(self):
        text=(ROOT/'run-tests.rkt').read_text()
        self.assertIn('"tests/dc-pure-test.rkt"',text); self.assertIn('(run-tests dc-pure-tests)',text)
        self.assertIn('"tests/dc-native-test.rkt"',text)
        self.assertIn("(dynamic-require dc-native-tests-file 'dc-native-tests)",text)
        self.assertIn('(run-tests dc-compat-pure-tests)',text)
        self.assertIn("(dynamic-require dc-compat-native-tests-file 'dc-compat-native-tests)",text)
        self.assertIn('"tests/dc-replay-pure-test.rkt"',text)
        self.assertIn('(run-tests dc-replay-pure-tests)',text)
        self.assertIn('"tests/dc-replay-native-test.rkt"',text)
        self.assertIn("(dynamic-require dc-replay-native-tests-file 'dc-replay-native-tests)",text)
        self.assertIn('(run-tests dc-style-pure-tests)',text)
        self.assertIn("(dynamic-require dc-style-native-tests-file 'dc-style-native-tests)",text)
    def test_native_free_import_smoke(self): self.assertIn('skia/dc',(HERE/'ci-import-smoke.rkt').read_text())
    def test_required_installed_package_pixel_gate(self):
        text=(HERE/'ci.py').read_text()
        self.assertIn("installed / 'tools/validate-dc.py'",text)
        self.assertIn("report['checks']['dc_foundation'] = True",text)
        self.assertIn("'--output', runner.output / 'dc-foundation'",text)
        self.assertIn("'--manifest-only'",text)
    def test_source_and_local_tests_wired(self):
        self.assertIn("'test-dc.py'",(HERE/'ci.py').read_text())
        self.assertIn("'tools/test-dc.py'",(HERE/'validate-gpu.py').read_text())
    def test_version_assertions_all_updated(self):
        metadata=(ROOT/'info.rkt').read_text()
        self.assertIn('(define version "0.61")',metadata)
        self.assertIn('("base" #:version "8.18")',metadata)
        self.assertIn('("draw-lib" #:version "1.22")',metadata)
        matrix=json.loads((HERE/'ci-matrix.json').read_text())
        self.assertEqual([r['racket'] for r in matrix['cpu'] if r['id']=='minimum-racket'],['8.18'])
        for name in ('test-ci.py','test-gpu-interop.py','test-metal-interop.py','test-gpu-parity.py','test-dxgi.py'):
            text=(HERE/name).read_text()
            self.assertIn('(define version "0.61")',text)
            for obsolete in ('0.52','0.53','0.54','0.55'):
                self.assertNotIn('(define version "'+obsolete+'")',text)
    def test_pin_and_gpu_workflow_preserved(self):
        self.assertEqual((ROOT/'private/native-default-version.txt').read_text().strip(),'3.119.1')
        workflow=(ROOT/'.github/workflows/ci.yml').read_text()
        self.assertIn('needs: [source, cpu, egl, d3d12, dxgi, canvas]',workflow)
        self.assertNotIn('continue-on-error:',workflow)
    def test_drawing_module_not_reexported_by_core(self):
        self.assertNotIn('"dc.rkt"',(ROOT/'main.rkt').read_text())
    def test_docs_record_limits(self):
        text=(ROOT/'docs/SKIA-DC.md').read_text()
        for term in ('0.55','0.56','immutable','aligned','snapshot','close'):
            self.assertIn(term,text)


class Compatibility(unittest.TestCase):
    def test_minimum_identity(self):
        self.assertTrue(v.supported_version('8.18'))
        self.assertTrue(v.supported_version('9.3.0.2'))
        for version in ('8.7','8.17','8.17.0.4','stable','',False):
            self.assertFalse(v.supported_version(version))
    def test_compatibility_case_counts(self):
        for kind,count in [('pure',d.COMPAT_PURE_CASES),('native',d.COMPAT_NATIVE_CASES)]:
            source=(ROOT/f'tests/dc-compat-{kind}-test.rkt').read_text()
            self.assertEqual(len(re.findall(r'\(test-case\s',source)),count)
            self.assertIn(f'(define dc-compat-{kind}-test-count {count})',source)
    def test_all_compatibility_sources_fingerprinted(self):
        for file in ('dc-region-adapter.rkt','dc-text-spec.rkt','dc-text.rkt','dc-bitmap.rkt','dc-native-util.rkt'):
            self.assertIn('private/'+file,d.SOURCE_PATHS)
    def test_private_region_dependency_is_isolated(self):
        sources=list((ROOT/'private').glob('dc-*.rkt'))
        private=[p.name for p in sources if 'racket/draw/private/' in p.read_text()]
        self.assertEqual(sorted(private),['dc-region-adapter.rkt','dc-replay-adapter.rkt'])
        adapter=(ROOT/'private/dc-region-adapter.rkt').read_text()
        self.assertIn('[get-clipping-matrix private-get-clipping-matrix]',adapter)
        self.assertNotIn('unsafe/cairo',adapter)
    def test_copy_uses_immutable_snapshot_and_source_blending(self):
        source=(ROOT/'private/dc-render.rkt').read_text()
        self.assertIn('(define (copy! snapshot surface',source)
        self.assertIn('([image (snapshot surface)]',source)
        self.assertIn('#:internal-snapshot [internal-snapshot snapshot]',source)
        self.assertIn('(lambda args (apply copy! internal-snapshot args))',source)
        self.assertIn('sk:skia-close! sk:surface-snapshot',source)
        self.assertIn("#:blend-mode 'src",source)
        self.assertIn("#:tile-x 'decal #:tile-y 'decal",source)
    def test_text_is_skia_harfbuzz_not_reference_dc(self):
        source=(ROOT/'private/dc-text.rkt').read_text()
        for token in ('sk:layout-mixed-text','sk:draw-mixed-text-layout','sk:font-get-metrics'):
            self.assertIn(token,source)
        for token in ('bitmap-dc%','unsafe/pango','pango_cairo'):
            self.assertNotIn(token,'\n'.join(l for l in source.splitlines() if not l.lstrip().startswith(';')))
    def test_oracle_copy_overlap_and_hole(self):
        p=d.compatibility_oracle_rgba()
        at=lambda x,y:tuple(p[4*(y*64+x):4*(y*64+x+1)])
        self.assertEqual(at(7,17),(20,30,40,255))
        self.assertEqual(at(3,13),(240,120,20,255))
        self.assertEqual(at(4,33),(0,80,160,255))
        self.assertEqual(at(9,33),(150,80,160,255))
    def test_doctor_runs_all_suites_before_capture(self):
        source=(HERE/'dc-doctor.rkt').read_text()
        for name in ('dc-compat-pure-tests','dc-compat-native-tests'):
            self.assertLess(source.index('(run-tests '+name+')'),source.index('(render "dc-oracle.png"'))
    def test_compatibility_counts_fail_closed(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);evidence(root)
            for key in ('compat_pure_cases','compat_native_cases','compat_pure_failures','compat_native_failures'):
                for bad in (None,False,-1):
                    value=report(root);value[key]=bad;d.write_json(root/'dc.diagnostic.json',value)
                    with self.assertRaises(ValueError): d.inspect_directory(root)
    def test_compatibility_oracle_corruption_fails(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);evidence(root)
            b=bytearray(d.compatibility_oracle_rgba());b[4*(33*64+4)]=1
            (root/'dc-compat-oracle.png').write_bytes(png(64,48,b))
            with self.assertRaisesRegex(ValueError,'independent oracle'): d.inspect_directory(root)
    def test_text_sample_blank_fails(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);evidence(root)
            (root/'dc-text.skia.png').write_bytes(png(320,104,bytes((255,255,255,255))*320*104))
            with self.assertRaisesRegex(ValueError,'red/blue ink'): d.inspect_directory(root)
    def test_missing_compatibility_capture_fails(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);evidence(root);(root/'dc-compat-oracle.png').unlink()
            with self.assertRaises(ValueError):d.inspect_directory(root)
    def test_runner_compiles_new_tests_and_example(self):
        code,calls,_,_=Orchestration().simulate()
        self.assertEqual(code,0)
        compile=next(c for c in calls if 'make' in c)
        for path in ('tests/dc-compat-pure-test.rkt','tests/dc-compat-native-test.rkt','examples/dc-compatibility.rkt'):
            self.assertTrue(any(c.endswith(path) for c in compile))



class StyleGate(unittest.TestCase):
    def test_style_failure_reaches_parent_gate(self):
        with tempfile.TemporaryDirectory() as t:
            directory=Path(t); evidence(directory)
            raw=d.read_json(directory/'dc-styles.json');raw['native_failures']=1
            d.write_json(directory/'dc-styles.json',raw)
            with self.assertRaisesRegex(ValueError,'native_failures'): d.inspect_directory(directory)
    def test_style_missing_report_reaches_parent_gate(self):
        with tempfile.TemporaryDirectory() as t:
            directory=Path(t);evidence(directory);(directory/'dc-styles.json').unlink()
            with self.assertRaises(ValueError):d.inspect_directory(directory)
    def test_style_missing_link_reaches_parent_gate(self):
        with tempfile.TemporaryDirectory() as t:
            directory=Path(t);evidence(directory);raw=report(directory);raw.pop('style_report')
            d.write_json(directory/'dc.diagnostic.json',raw)
            with self.assertRaises(ValueError):d.inspect_directory(directory)
    def test_style_source_fingerprints(self):
        for name in ('private/native.rkt','private/dc-style-math.rkt','private/dc-styles.rkt',
                     'private/dc-style-render.rkt','private/dc-path-bounds.rkt',
                     'private/dc-region-query.rkt','tests/dc-style-fixtures.rkt',
                     'tests/dc-style-pure-test.rkt','tests/dc-style-native-test.rkt',
                     'tests/dc-style-math-test.rkt','tools/dc-style-doctor.rkt'):
            self.assertIn(name,d.SOURCE_PATHS)
    def test_style_suites_and_counts(self):
        for kind,n in [('pure',24),('native',40)]:
            text=(ROOT/f'tests/dc-style-{kind}-test.rkt').read_text()
            self.assertIn(f'(define dc-style-{kind}-test-count {n})',text)
            self.assertEqual(len(re.findall(r'\(test-case\s',text)),n)
        text=(HERE/'dc-style-doctor.rkt').read_text()
        self.assertIn('(run-tests dc-style-pure-tests)',text)
        self.assertIn('(run-tests dc-style-native-tests)',text)
        self.assertIn('(dc-style-doctor! directory)',(HERE/'dc-doctor.rkt').read_text())
    def test_style_renderer_is_skia_not_cairo(self):
        text=(ROOT/'private/dc-style-render.rkt').read_text()
        for api in ('sk:make-linear-gradient-shader','sk:make-two-point-conical-gradient-shader',
                    'sk:make-image-shader','sk:shader-with-local-matrix','sk:make-dash-path-effect'):
            self.assertIn(api,text)
        self.assertNotIn('unsafe/cairo',text)
        query=(ROOT/'private/dc-region-query.rkt').read_text()
        self.assertNotIn('cairo_paint',query);self.assertNotIn('surface->rgba',query)
        self.assertIn('call-with-continuation-barrier',query)
    def test_style_runner_compiles_new_modules(self):
        code,calls,_,_=Orchestration().simulate();self.assertEqual(code,0)
        compile=next(c for c in calls if 'make' in c)
        for name in ('dc-style-doctor.rkt','dc-style-pure-test.rkt','dc-style-native-test.rkt',
                     'dc-style-math-test.rkt','dc-styles.rkt'):
            self.assertTrue(any(str(p).endswith('/'+name) for p in compile),name)
    def test_style_review_contains_twenty_captures(self):
        with tempfile.TemporaryDirectory() as t:
            directory=Path(t);evidence(directory)
            d.write_review(directory,d.inspect_directory(directory))
            self.assertEqual((directory/'dc.review.html').read_text().count('<img '),20)


class ReplayAlpha(unittest.TestCase):
    """0.55 receipt/oracle checks; synthetic data, not native execution."""
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)/'dc-replay'; self.directory.mkdir()
        evidence(self.directory)
    def rejected(self, key, value):
        raw=report(self.directory); raw[key]=value
        d.write_json(self.directory/'dc.diagnostic.json',raw)
        with self.assertRaises(ValueError): d.inspect_directory(self.directory)
    def test_replay_pure_count_required(self): self.rejected('replay_pure_cases',27)
    def test_replay_native_count_required(self): self.rejected('replay_native_cases',27)
    def test_controller_count_required(self): self.rejected('alpha_controller_cases',23)
    def test_replay_pure_failure_blocks(self): self.rejected('replay_pure_failures',1)
    def test_replay_native_failure_blocks(self): self.rejected('replay_native_failures',1)
    def test_boolean_failure_is_not_zero(self): self.rejected('replay_native_failures',False)
    def test_missing_replay_count(self): self.rejected('replay_native_cases',None)
    def test_each_alpha_capture_required(self):
        for name in ('dc-alpha.direct.png','dc-alpha.procedure.png','dc-alpha.datum.png'):
            with self.subTest(name=name):
                path=self.directory/name; data=path.read_bytes(); path.unlink()
                try:
                    with self.assertRaises(ValueError): d.inspect_directory(self.directory)
                finally: path.write_bytes(data)
    def test_each_alpha_capture_independently_checked(self):
        for name in ('dc-alpha.direct.png','dc-alpha.procedure.png','dc-alpha.datum.png'):
            with self.subTest(name=name):
                path=self.directory/name; data=path.read_bytes()
                path.write_bytes(png(48,32,bytes((255,255,255,255))*48*32))
                try:
                    with self.assertRaisesRegex(ValueError,'independent oracle'): d.inspect_directory(self.directory)
                finally: path.write_bytes(data)
    def test_three_identical_wrong_captures_do_not_pass(self):
        for name in ('dc-alpha.direct.png','dc-alpha.procedure.png','dc-alpha.datum.png'):
            (self.directory/name).write_bytes(png(48,32,bytes((255,255,255,255))*48*32))
        with self.assertRaises(ValueError): d.inspect_directory(self.directory)
    def test_two_channel_units_accepted_three_rejected(self):
        path=self.directory/'dc-alpha.direct.png'
        data=bytearray(d.alpha_oracle_rgba()); original=data[0]
        data[0]=original+2; path.write_bytes(png(48,32,data)); d.inspect_directory(self.directory)
        data[0]=original+3; path.write_bytes(png(48,32,data))
        with self.assertRaises(ValueError): d.inspect_directory(self.directory)
    def test_old_oracles_stay_exact(self):
        for name,w,h,pixels in (('dc-oracle.png',48,40,d.oracle_rgba()),
                                ('dc-compat-oracle.png',64,48,d.compatibility_oracle_rgba())):
            with self.subTest(name=name):
                path=self.directory/name; before=path.read_bytes()
                data=bytearray(pixels); data[0]^=1; path.write_bytes(png(w,h,data))
                try:
                    with self.assertRaises(ValueError): d.inspect_directory(self.directory)
                finally: path.write_bytes(before)
    def test_oracle_distinguishes_overlap_from_per_draw_alpha(self):
        def pixel(x,y): return d.alpha_oracle_rgba()[4*(48*y+x):4*(48*y+x+1)]
        self.assertEqual(pixel(11,6),bytes((128,128,255,255)))
        self.assertEqual(pixel(11,22),bytes((191,128,191,255)))
        self.assertEqual(pixel(36,22),bytes((223,255,223,255)))
        self.assertEqual(pixel(36,6),bytes((255,255,255,255)))
    def test_runner_compiles_replay_and_controller(self):
        code,calls,_,_=Orchestration().simulate(); self.assertEqual(code,0)
        command=next(c for c in calls if 'make' in c)
        for path in ('tests/dc-replay-pure-test.rkt','tests/dc-replay-native-test.rkt',
                     'tests/dc-alpha-test.rkt','examples/dc-replay.rkt'):
            self.assertTrue(any(c.endswith(path) for c in command))
    def test_source_fingerprint_covers_protocol_and_controller(self):
        for path in ('private/dc-alpha.rkt','private/dc-replay-adapter.rkt',
                     'tests/dc-replay-pure-test.rkt','tests/dc-replay-native-test.rkt',
                     'tests/dc-alpha-test.rkt','examples/dc-replay.rkt'):
            self.assertIn(path,d.SOURCE_PATHS)
    def test_suite_counts_are_real_top_level_cases(self):
        for name in ('pure','native'):
            text=(ROOT/'tests'/f'dc-replay-{name}-test.rkt').read_text()
            self.assertEqual(len(re.findall(r'\(test-case\s',text)),28)
            self.assertIn(f'(define dc-replay-{name}-test-count 28)',text)
    def test_no_recording_format_decoder_or_cairo_draw_fallback(self):
        text=(ROOT/'private/dc-replay-adapter.rkt').read_text()
        self.assertIn('[do-set-pen! replay-set-pen!]',text)
        self.assertIn('[do-set-brush! replay-set-brush!]',text)
        self.assertIn('adjust-lock',text)
        self.assertNotIn('cairo_create',text)
        self.assertNotIn('record-unconvert',text)
    def test_documentation_keeps_exception_and_scope_limits(self):
        text=(ROOT/'docs/SKIA-DC.md').read_text()
        for phrase in ('normal completion','0.56','0.57','0.58','unfinished',
                       'same object','2 per 8-bit channel','root backing only'):
            self.assertIn(phrase,text.replace('\n',' ').replace('**',''))

if __name__ == '__main__':
    unittest.main(verbosity=2)
