#!/usr/bin/env python3
"""Query evidence and orchestration tests. Python-authored fixtures are synthetic."""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import codec_query_validation as v

ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'synthetic-query-token'


def synthetic_evidence(root, token=TOKEN):
    from PIL import Image
    root.mkdir(parents=True, exist_ok=True)
    rows=[]
    for name in ('png', 'jpeg', 'webp'):
        image=Image.frombytes('RGBA', v.SIZE, v.fixture_pixels())
        data=io.BytesIO()
        if name=='jpeg':image.convert('RGB').save(data,format='JPEG',quality=100,subsampling=0)
        elif name=='webp':image.save(data,format='WEBP',lossless=True)
        else:image.save(data,format='PNG')
        (root/(name+'.encoded')).write_bytes(data.getvalue())
        pixels=v.fixture_pixels()
        (root/(name+'-before.rgba')).write_bytes(pixels)
        (root/(name+'-after.rgba')).write_bytes(pixels)
        dims=[(16,12),(8,6),(4,3),(2,2),(16,12)] if name!='png' else [(16,12)]*5
        rows.append(dict(format=name, source_size=[16,12],
                         scaled=[[s,*d] for s,d in zip(v.SCALES,dims)],
                         odd_subset=[0,2,7,6] if name=='webp' else False,
                         even_subset=[2,4,6,4] if name=='webp' else False,
                         decode_unchanged=True))
    receipt=dict(schema=1,stage='0.76a',status='passed',run_token=token,native_version='119.0',
                 query_coordinates='encoded-pixels',oriented_jpeg_half=[8,6],formats=rows,
                 scaled_decode_executed=False,subset_decode_executed=False,gpu_executed=False)
    (root/'queries.json').write_text(json.dumps(receipt),encoding='utf-8')
    return receipt


class Completion(unittest.TestCase):
    def valid(self):return f'{v.PURE_CASES} success(es) 0 failure(s) 0 error(s) {v.PURE_CASES} test(s) run\ncodec-query-pure: {v.PURE_CASES} cases, 0 failures\n'
    def test_complete(self):v.suite_output(self.valid(),'codec-query-pure',v.PURE_CASES)
    def test_windows_crlf(self):v.suite_output(self.valid().replace('\n','\r\n'),'codec-query-pure',v.PURE_CASES)
    def test_empty(self):
        with self.assertRaises(ValueError):v.suite_output('','codec-query-pure',v.PURE_CASES)
    def test_partial(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid().split('\n')[0],'codec-query-pure',v.PURE_CASES)
    def test_duplicate(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid()*2,'codec-query-pure',v.PURE_CASES)
    def test_wrong_count(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid(),'codec-query-pure',v.PURE_CASES+1)
    def test_failure(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid().replace('0 failure(s)','1 failure(s)'),'codec-query-pure',v.PURE_CASES)
    def test_error(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid()+'ERROR\n','codec-query-pure',v.PURE_CASES)


class Evidence(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.addCleanup(self.temporary.cleanup)
        self.root=Path(self.temporary.name);self.receipt=synthetic_evidence(self.root)
    def write(self): (self.root/'queries.json').write_text(json.dumps(self.receipt),encoding='utf-8')
    def rejects(self):
        self.write()
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def test_valid_synthetic_matrix(self):self.assertEqual(v.inspect(self.root,TOKEN)['status'],'passed')
    def test_foreign_token(self):self.receipt['run_token']='old';self.rejects()
    def test_failed_status(self):self.receipt['status']='failed';self.rejects()
    def test_boolean_schema(self):self.receipt['schema']=True;self.rejects()
    def test_wrong_abi(self):self.receipt['native_version']='153.0';self.rejects()
    def test_missing_format(self):self.receipt['formats'].pop();self.rejects()
    def test_duplicate_format(self):self.receipt['formats'][1]=copy.deepcopy(self.receipt['formats'][0]);self.rejects()
    def test_missing_scale(self):self.receipt['formats'][0]['scaled'].pop();self.rejects()
    def test_invented_png_scaling(self):self.receipt['formats'][0]['scaled'][1]=[.5,8,6];self.rejects()
    def test_wrong_jpeg_rounding(self):self.receipt['formats'][1]['scaled'][3]=[.125,2,1];self.rejects()
    def test_upscale_not_clamped(self):self.receipt['formats'][2]['scaled'][4]=[2,32,24];self.rejects()
    def test_false_not_empty_list(self):self.receipt['formats'][0]['odd_subset']=[];self.rejects()
    def test_unadjusted_webp_subset(self):self.receipt['formats'][2]['odd_subset']=[1,3,6,5];self.rejects()
    def test_orientation_not_applied(self):self.receipt['oriented_jpeg_half']=[6,8];self.rejects()
    def test_bool_not_integer_extent(self):self.receipt['formats'][2]['scaled'][1][1]=True;self.rejects()
    def test_scaled_decode_claim(self):self.receipt['scaled_decode_executed']=True;self.rejects()
    def test_missing_subset_decode_claim(self):self.receipt.pop('subset_decode_executed');self.rejects()
    def test_decode_stability_false(self):self.receipt['formats'][0]['decode_unchanged']=False;self.rejects()
    def test_pixel_corruption(self):
        p=self.root/'png-after.rgba';p.write_bytes(b'\0'+p.read_bytes()[1:2]+b'\0'+p.read_bytes()[3:])
        # First pixel begins black; modify a definitely nonzero pixel instead.
        data=bytearray(p.read_bytes());data[4]^=255;p.write_bytes(data)
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def test_short_pixels(self):
        (self.root/'jpeg-after.rgba').write_bytes(b'x')
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def test_missing_capture(self):
        (self.root/'webp.encoded').unlink()
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def test_wrong_encoded_dimensions(self):
        from PIL import Image
        Image.new('RGB',(8,6)).save(self.root/'jpeg.encoded',format='JPEG')
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def test_duplicate_json_key(self):
        p=self.root/'queries.json';p.write_text(p.read_text().replace('"schema": 1','"schema": 1, "schema": 1'),encoding='utf-8')
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)


class Orchestration(unittest.TestCase):
    def invoke(self,mode=None,failure=None,partial=False,mutate=False):
        spec=importlib.util.spec_from_file_location('codec_query_driver_test',ROOT/'tools/validate-codec-queries.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        commands=[]
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            (root/'SOURCE-SHA256SUMS.txt').write_text('synthetic manifest\n')
            (root/'run-tests.rkt').write_text('(define-runtime-path unrelated "tests/unrelated-native-test.rkt")\n')
            def execute(command,**kwargs):
                command=list(map(str,command));commands.append(command)
                name=Path(command[1]).name if len(command)>1 else ''
                out=kwargs['stdout']
                if name==failure:
                    out.write('synthetic failure\n');out.flush();raise subprocess.CalledProcessError(1,command)
                for suite,count in (('codec-query-pure',v.PURE_CASES),('codec-query-native',v.NATIVE_CASES)):
                    if name==suite+'-test.rkt':out.write('incomplete\n' if partial else f'{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run\n{suite}: {count} cases, 0 failures\n')
                if name=='codec-query-doctor.rkt':
                    synthetic_evidence(Path(command[command.index('--directory')+1]),command[command.index('--token')+1])
                    if mutate:(root/'SOURCE-SHA256SUMS.txt').write_text('changed')
                out.flush();return subprocess.CompletedProcess(command,0)
            args=['--racket',sys.executable,'--directory',str(root/'out')]
            if mode is not None:args+=['--regressions',mode]
            with patch.object(module.shutil,'which',return_value=sys.executable),patch.object(module.subprocess,'run',side_effect=execute),contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                rc=module.main(args,root=root)
            report=json.loads((root/'out/validation.json').read_text())
        return rc,report,commands
    def test_default_is_full(self):
        rc,r,c=self.invoke();self.assertEqual(rc,0);self.assertEqual(r['regressions_status'],'passed');self.assertTrue(r['regressions_attempted'])
    def test_none_is_not_run_not_passed(self):
        rc,r,c=self.invoke('none');self.assertEqual(rc,0);self.assertEqual(r['regressions_status'],'not-run');self.assertFalse(r['regressions_passed'])
        self.assertFalse(any(Path(x[1]).name=='run-tests.rkt' for x in c))
    def test_none_compile_excludes_dynamic_graph(self):
        _,_,c=self.invoke('none');args=next(x for x in c if 'make' in x)
        names=[str(x).replace('\\','/') for x in args]
        self.assertFalse(any('unrelated' in x or x.endswith('run-tests.rkt') for x in names))
        self.assertTrue(any(x.endswith('tests/codec-query-native-test.rkt') for x in names))
    def test_full_compile_includes_dynamic_graph(self):
        _,_,c=self.invoke();args=next(x for x in c if 'make' in x)
        self.assertTrue(any(str(x).replace('\\','/').endswith('tests/unrelated-native-test.rkt') for x in args))
    def test_features_preserved_in_none(self):
        def selected(commands):return [Path(c[1]).name for c in commands if c[1]!='-l' and Path(c[1]).name!='run-tests.rkt']
        self.assertEqual(selected(self.invoke('full')[2]),selected(self.invoke('none')[2]))
    def test_regression_failure_stops_features(self):
        rc,r,c=self.invoke(failure='run-tests.rkt');self.assertEqual(rc,1);self.assertFalse(r['native_passed']);self.assertEqual(r['regressions_status'],'failed')
    def test_native_failure_stops_doctor(self):
        rc,r,c=self.invoke('none',failure='codec-query-native-test.rkt');self.assertEqual(rc,1);self.assertFalse(r['byte_oracles_passed'])
        self.assertFalse(any(Path(x[1]).name=='codec-query-doctor.rkt' for x in c))
    def test_pure_failure(self):self.assertEqual(self.invoke('none',failure='codec-query-pure-test.rkt')[0],1)
    def test_partial_completion(self):self.assertEqual(self.invoke('none',partial=True)[0],1)
    def test_changed_manifest(self):self.assertEqual(self.invoke('none',mutate=True)[0],1)
    def test_failed_source_gate(self):self.assertEqual(self.invoke('none',failure='api-inventory.py')[0],1)
    def test_failed_example(self):self.assertEqual(self.invoke('none',failure='codec-queries.rkt')[0],1)


class Sources(unittest.TestCase):
    def text(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_source_case_counts(self):
        for kind,count in (('pure',v.PURE_CASES),('native',v.NATIVE_CASES)):
            s=self.text('tests/codec-query-'+kind+'-test.rkt');self.assertEqual(s.count('(test-case '),count)
            self.assertIn(f'(define codec-query-{kind}-test-count {count})',s)
    def test_exactly_two_native_queries(self):
        text=self.text('private/native.rkt')
        for name in ('sk_codec_get_scaled_dimensions','sk_codec_get_valid_subset'):
            self.assertEqual(text.count('(define-native '+name+' '),1)
    def test_no_decoder_or_resampling_fallback(self):
        s=self.text('codec-queries.rkt')
        for name in ('sk_codec_get_pixels','codec->image','image-scale','sk_codec_start_','skia-native-library-handle','get-ffi-obj'):
            self.assertNotIn(name,s)
    def test_failed_subset_output_is_unread(self):
        s=self.text('codec-queries.rkt');self.assertIn('(and (sk_codec_get_valid_subset ptr rect)',s)
        self.assertIn('(codec-query-subset-result who source-width source-height',s)
    def test_native_and_pure_registration(self):
        s=self.text('run-tests.rkt');self.assertIn('(run-tests codec-query-pure-tests)',s)
        self.assertIn("dynamic-require codec-query-native-tests-file 'codec-query-native-tests",s)
        self.assertIn("'test-codec-queries.py'",self.text('tools/ci.py'))
    def test_no_automatic_workflow_added(self):
        auto={p.name for p in (ROOT/'.github/workflows').glob('*.yml') if '\n  push:' in p.read_text() or '\n  pull_request:' in p.read_text()}
        self.assertEqual(auto,{'ci.yml','acceptance.yml','api-inventory.yml'})
        self.assertIn('test "$CODEC_QUERIES_RESULT" = success',self.text('.github/workflows/acceptance.yml'))
    def test_query_docs_and_numeric_version(self):
        for name in ('codec-scaled-dimensions','codec-supported-subset'):self.assertIn(name,self.text('docs/CODEC-QUERIES.md'))
        self.assertIn('(define version "0.77")',self.text('info.rkt'))
    def test_split_visible(self):
        s=self.text('plans/skia-for-racket-gap-reduction-roadmap.md')
        for stage in ('0.76a','0.76b','0.76c'):self.assertIn('## '+stage,s)


if __name__=='__main__':unittest.main(verbosity=2)
