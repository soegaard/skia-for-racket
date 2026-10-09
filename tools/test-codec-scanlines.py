#!/usr/bin/env python3
"""Synthetic scanline evidence/runner tests, never native execution evidence."""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import codec_scanline_validation as v

ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'synthetic-scanline-token'


def synthetic_bmp(top=False):
    pixels = v.fixture_pixels()
    rows = []
    for y in (range(5) if top else reversed(range(5))):
        row = b''.join(pixels[(y*7+x)*4:(y*7+x)*4+3][::-1] for x in range(7))
        rows.append(row + b'\0'*3)
    return (struct.pack('<2sIII', b'BM', 174, 0, 54) +
            struct.pack('<IiiHHIIIIII', 40, 7, -5 if top else 5, 1, 24, 0, 120, 2835, 2835, 0, 0) + b''.join(rows))


def synthetic_evidence(root: Path, token=TOKEN):
    from PIL import Image
    root.mkdir(parents=True, exist_ok=True)
    sources = dict(zip(('bottom.bmp', 'top.bmp'), (synthetic_bmp(), synthetic_bmp(True))))
    sources['short-bottom.bmp'] = sources['bottom.bmp'][:102]
    sources['short-top.bmp'] = sources['top.bmp'][:102]
    image = Image.frombytes('RGBA', v.JPEG_SIZE, v.fixture_pixels(*v.JPEG_SIZE)).convert('RGB')
    output = io.BytesIO();image.save(output, format='JPEG', quality=100, subsampling=0)
    sources['reference.jpeg'] = output.getvalue()
    exif = Image.Exif();exif[274] = 6
    output = io.BytesIO();image.save(output, format='JPEG', quality=100, subsampling=0, exif=exif)
    sources['rotated.jpeg'] = output.getvalue()
    image = Image.frombytes('RGBA', v.BMP_SIZE, v.fixture_pixels())
    output = io.BytesIO();image.save(output, format='PNG');sources['unsupported.png'] = output.getvalue()
    for name, content in sources.items():
        (root/name).write_bytes(content)
    # These are Python-authored expected outcomes, not fabricated native evidence.
    decoded_jpeg = v.independently_decode(sources['reference.jpeg'], 'JPEG', v.JPEG_SIZE)
    decoded_half = v.independently_decode(sources['reference.jpeg'], 'JPEG', v.JPEG_SIZE, half=True)
    cases=[]
    for name, actions in v.ACTIONS.items():
        is_jpeg=name in ('jpeg','jpeg-half','rotated-half')
        w,h=(v.JPEG_SIZE if name=='jpeg' else (8,6)) if is_jpeg else v.BMP_SIZE
        bottom=name in ('bottom','skip','short-bottom','empty','skip-failed')
        mapping=list(reversed(range(h))) if bottom else list(range(h))
        ref=(decoded_jpeg if name=='jpeg' else decoded_half) if is_jpeg else v.fixture_pixels()
        steps=[];position=0;state='ready'
        for i,(op,count) in enumerate(actions):
            before=position;before_row=mapping[position]
            got=min(count,max(0,2-position)) if name in ('short-bottom','short-top','empty') else count
            state='complete' if position+count==h else 'ready'
            if op=='skip':
                result=dict(skipped=name!='skip-failed')
                if not result['skipped']:state='failed'
            else:
                if got<count:state='incomplete'
                first=(h-position-got if bottom else position) if got else False
                stride=32 if name=='bottom' else w*4
                raw=b''.join(ref[((first+j)*w)*4:((first+j+1)*w)*4]+bytes(stride-w*4) for j in range(got))
                file=f'{name}-{i}.rows';(root/file).write_bytes(raw)
                result=dict(decoded=got,first_row=first,row_bytes=stride,height=got,complete=got==count,file=file)
            position+=count
            steps.append(dict(op=op,count=count,before=before,before_row=before_row,after=position,
                              state=state,next_row=mapping[position] if state=='ready' else False,result=result))
        cases.append(dict(name=name,width=w,height=h,color_type='rgba-8888',alpha_type='unpremul',color_space='srgb',
                          order='bottom-up' if bottom else 'top-down',origin='right-top' if name=='rotated-half' else 'top-left',
                          mappings=mapping,steps=steps,final_state=state,closed=True))
    receipt=dict(schema=1,stage='0.76b',run_token=token,status='passed',native_version='119.0',cases=cases,
                 unsupported_png=dict(result='unimplemented',code=9),session_scope='owned-private-codec',
                 scaled_scanline_executed=True,subset_decode_executed=False,incremental_decode_executed=False,
                 live_port_callbacks=False,gpu_executed=False)
    (root/'scanlines.json').write_text(json.dumps(receipt),encoding='utf-8')
    return receipt


class Completion(unittest.TestCase):
    def valid(self):return f'{v.PURE_CASES} success(es) 0 failure(s) 0 error(s) {v.PURE_CASES} test(s) run\ncodec-scanline-pure: {v.PURE_CASES} cases, 0 failures\n'
    def test_complete(self):v.suite_output(self.valid(),'codec-scanline-pure',v.PURE_CASES)
    def test_crlf(self):v.suite_output(self.valid().replace('\n','\r\n'),'codec-scanline-pure',v.PURE_CASES)
    def test_missing(self):
        with self.assertRaises(ValueError):v.suite_output('','codec-scanline-pure',v.PURE_CASES)
    def test_partial(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid().split('\n')[0],'codec-scanline-pure',v.PURE_CASES)
    def test_duplicate(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid()*2,'codec-scanline-pure',v.PURE_CASES)
    def test_wrong_count(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid(),'codec-scanline-pure',v.PURE_CASES+1)
    def test_failure(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid().replace('0 failure(s)','1 failure(s)'),'codec-scanline-pure',v.PURE_CASES)
    def test_hidden_error(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid()+'ERROR\n','codec-scanline-pure',v.PURE_CASES)


class Evidence(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.receipt=synthetic_evidence(self.root)
    def case(self,name='bottom'):return next(c for c in self.receipt['cases'] if c['name']==name)
    def rejects(self):
        (self.root/'scanlines.json').write_text(json.dumps(self.receipt),encoding='utf-8')
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def test_valid(self):self.assertEqual(v.inspect(self.root,TOKEN)['cases_checked'],10)
    def test_foreign_token(self):self.receipt['run_token']='old';self.rejects()
    def test_failed(self):self.receipt['status']='failed';self.rejects()
    def test_schema_boolean(self):self.receipt['schema']=True;self.rejects()
    def test_wrong_abi(self):self.receipt['native_version']='153.0';self.rejects()
    def test_shared_codec_claim(self):self.receipt['session_scope']='borrowed-caller-codec';self.rejects()
    def test_false_incremental_claim(self):self.receipt['incremental_decode_executed']=True;self.rejects()
    def test_missing_scaled_execution(self):self.receipt['scaled_scanline_executed']=False;self.rejects()
    def test_missing_case(self):self.receipt['cases'].pop();self.rejects()
    def test_duplicate_case(self):self.receipt['cases'][1]=copy.deepcopy(self.receipt['cases'][0]);self.rejects()
    def test_wrong_order(self):self.case()['order']='top-down';self.rejects()
    def test_wrong_mapping(self):self.case()['mappings']=[0,1,2,3,4];self.rejects()
    def test_boolean_mapping(self):self.case()['mappings'][-1]=False;self.rejects()
    def test_wrong_width(self):self.case()['width']=8;self.rejects()
    def test_wrong_alpha(self):self.case()['alpha_type']='premul';self.rejects()
    def test_wrong_orientation(self):self.case('rotated-half')['origin']='top-left';self.rejects()
    def test_missing_step(self):self.case()['steps'].pop();self.rejects()
    def test_bad_cursor(self):self.case()['steps'][0]['after']=1;self.rejects()
    def test_bad_native_next(self):self.case()['steps'][0]['next_row']=1;self.rejects()
    def test_bad_batch_first_row(self):self.case()['steps'][0]['result']['first_row']=4;self.rejects()
    def test_boolean_first_row(self):self.case('top')['steps'][0]['result']['first_row']=False;self.rejects()
    def test_partial_claimed_complete(self):self.case('short-bottom')['steps'][0]['result']['complete']=True;self.rejects()
    def test_partial_cursor_not_requested(self):self.case('short-bottom')['steps'][0]['after']=2;self.rejects()
    def test_partial_filler_count(self):self.case('short-bottom')['steps'][0]['result']['decoded']=5;self.rejects()
    def test_partial_fill_offset(self):self.case('short-bottom')['steps'][0]['result']['first_row']=0;self.rejects()
    def test_empty_first_row(self):self.case('empty')['steps'][1]['result']['first_row']=0;self.rejects()
    def test_incomplete_state(self):self.case('short-bottom')['steps'][0]['state']='complete';self.rejects()
    def test_failed_skip_claimed_success(self):self.case('skip-failed')['steps'][0]['result']['skipped']=True;self.rejects()
    def test_no_native_end_query(self):self.case()['steps'][-1]['next_row']=-1;self.rejects()
    def test_unclosed(self):self.case()['closed']=False;self.rejects()
    def test_unsafe_path(self):self.case()['steps'][0]['result']['file']='../bad';self.rejects()
    def test_wrong_native_unsupported(self):self.receipt['unsupported_png']['code']=0;self.rejects()
    def test_missing_capture(self):(self.root/'top-0.rows').unlink();self.rejects()
    def test_extra_capture(self):(self.root/'extra.rows').write_bytes(b'');self.rejects()
    def test_padding_corruption(self):
        p=self.root/'bottom-0.rows';b=bytearray(p.read_bytes());b[28]=1;p.write_bytes(b);self.rejects()
    def test_row_reversal(self):
        p=self.root/'bottom-0.rows';b=p.read_bytes();p.write_bytes(b[32:]+b[:32]);self.rejects()
    def test_partial_publishes_native_fill(self):
        p=self.root/'short-bottom-0.rows';p.write_bytes(bytes(3*28)+p.read_bytes());self.rejects()
    def test_empty_has_bytes(self):(self.root/'empty-1.rows').write_bytes(bytes(28));self.rejects()
    def test_short_fixture_not_really_truncated(self):(self.root/'short-bottom.bmp').write_bytes((self.root/'bottom.bmp').read_bytes());self.rejects()
    def test_duplicate_json(self):
        p=self.root/'scanlines.json';p.write_text(p.read_text().replace('"schema": 1','"schema": 1, "schema": 1'))
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)


class Orchestration(unittest.TestCase):
    def invoke(self,mode=None,failure=None,partial=False,mutate=False):
        spec=importlib.util.spec_from_file_location('codec_scanline_driver_test',ROOT/'tools/validate-codec-scanlines.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        commands=[]
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);(root/'SOURCE-SHA256SUMS.txt').write_text('synthetic manifest\n')
            (root/'run-tests.rkt').write_text('(define-runtime-path unrelated "tests/unrelated-native-test.rkt")\n')
            def execute(command,**kwargs):
                command=list(map(str,command));commands.append(command);name=Path(command[1]).name
                out=kwargs['stdout']
                if name==failure:
                    out.write('synthetic failure\n');out.flush();raise subprocess.CalledProcessError(1,command)
                for suite,count in (('codec-scanline-pure',v.PURE_CASES),('codec-scanline-native',v.NATIVE_CASES)):
                    if name==suite+'-test.rkt':out.write('incomplete\n' if partial else f'{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run\n{suite}: {count} cases, 0 failures\n')
                if name=='codec-scanline-doctor.rkt':
                    synthetic_evidence(Path(command[command.index('--directory')+1]),command[command.index('--token')+1])
                    if mutate:(root/'SOURCE-SHA256SUMS.txt').write_text('changed')
                out.flush();return subprocess.CompletedProcess(command,0)
            args=['--racket',sys.executable,'--directory',str(root/'out')]
            if mode is not None:args+=['--regressions',mode]
            with patch.object(module.shutil,'which',return_value=sys.executable),patch.object(module.subprocess,'run',side_effect=execute),contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                rc=module.main(args,root=root)
            report=json.loads((root/'out/validation.json').read_text())
        return rc,report,commands
    def test_default_full(self):
        rc,r,_=self.invoke();self.assertEqual(rc,0);self.assertEqual(r['regressions_status'],'passed');self.assertTrue(r['native_passed'])
    def test_none_not_a_pass(self):
        rc,r,c=self.invoke('none');self.assertEqual(rc,0);self.assertEqual(r['regressions_status'],'not-run');self.assertFalse(r['regressions_passed'])
        self.assertFalse(any(Path(x[1]).name=='run-tests.rkt' for x in c));self.assertTrue(r['scaled_scanline_executed'])
    def test_focused_compile(self):
        _,_,c=self.invoke('none');names=[str(x).replace('\\','/') for x in next(cmd for cmd in c if 'make' in cmd)]
        self.assertTrue(any(x.endswith('tests/codec-scanline-native-test.rkt') for x in names));self.assertFalse(any('unrelated' in x for x in names))
    def test_full_compile(self):
        _,_,c=self.invoke();names=[str(x).replace('\\','/') for x in next(cmd for cmd in c if 'make' in cmd)]
        self.assertTrue(any(x.endswith('tests/unrelated-native-test.rkt') for x in names))
    def test_features_survive_split(self):
        def selected(c):return [Path(x[1]).name for x in c if x[1]!='-l' and Path(x[1]).name!='run-tests.rkt']
        self.assertEqual(selected(self.invoke('full')[2]),selected(self.invoke('none')[2]))
    def test_regression_failure(self):
        rc,r,c=self.invoke(failure='run-tests.rkt');self.assertEqual(rc,1);self.assertFalse(r['native_passed']);self.assertEqual(r['regressions_status'],'failed')
    def test_native_failure(self):
        rc,r,c=self.invoke('none',failure='codec-scanline-native-test.rkt');self.assertEqual(rc,1);self.assertFalse(r['byte_oracles_passed'])
        self.assertFalse(any(Path(x[1]).name=='codec-scanline-doctor.rkt' for x in c))
    def test_pure_failure(self):self.assertEqual(self.invoke('none',failure='codec-scanline-pure-test.rkt')[0],1)
    def test_partial_output(self):self.assertEqual(self.invoke('none',partial=True)[0],1)
    def test_manifest_change(self):self.assertEqual(self.invoke('none',mutate=True)[0],1)
    def test_source_gate(self):self.assertEqual(self.invoke('none',failure='api-inventory.py')[0],1)
    def test_example_failure(self):self.assertEqual(self.invoke('none',failure='codec-scanlines.rkt')[0],1)


class Sources(unittest.TestCase):
    def source(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_counts(self):
        for kind,count in (('pure',v.PURE_CASES),('native',v.NATIVE_CASES)):
            s=self.source(f'tests/codec-scanline-{kind}-test.rkt')
            self.assertEqual(s.count('(test-case '),count);self.assertIn(f'(define codec-scanline-{kind}-test-count {count})',s)
    def test_six_native_bindings(self):
        s=self.source('private/native.rkt')
        for name in ('start_scanline_decode','get_scanlines','skip_scanlines','get_scanline_order','next_scanline','output_scanline'):
            self.assertEqual(s.count('(define-native sk_codec_'+name+' '),1)
    def test_no_complete_decode_fallback(self):
        s=self.source('codec-scanlines.rkt')
        for token in ('sk_codec_get_pixels','codec->image','image-scale','sk_codec_start_incremental','get-ffi-obj'):
            self.assertNotIn(token,s)
    def test_native_scratch_not_borrowed_pixels(self):
        s=self.source('codec-scanlines.rkt');self.assertIn("(malloc size 'raw)",s);self.assertIn('(free memory)',s)
        self.assertIn('(memset memory 0 size)',s);self.assertIn('(ptr-add memory (* offset stride))',s)
    def test_partial_rows_and_eof_guard(self):
        s=self.source('codec-scanlines.rkt');self.assertIn('(* stride decoded)',s)
        self.assertIn('(< position (session-height s))',s);self.assertIn('(unless (zero? decoded)',s)
    def test_generic_resource_lifetime(self):
        s=self.source('private/core.rkt');self.assertIn('(scanline-session-record? v)',s)
        self.assertIn('(scanline-session-record-handle v)',s)
    def test_case_registration(self):
        s=self.source('run-tests.rkt');self.assertIn('(run-tests codec-scanline-pure-tests)',s)
        self.assertIn("dynamic-require codec-scanline-native-tests-file 'codec-scanline-native-tests",s)
        self.assertIn("'test-codec-scanlines.py'",self.source('tools/ci.py'))
    def test_workflow_no_global_duplication(self):
        s=self.source('.github/workflows/codec-queries.yml')
        self.assertEqual(s.count('tools/validate-codec-scanlines.py --regressions none'),2)
        self.assertIn('output/codec-scanlines-linux/',s);self.assertIn('output/codec-scanlines-windows/',s)
    def test_public_docs(self):
        import api_inventory as inv
        docs=self.source('docs/CODEC-SCANLINES.md')
        for name in inv.source_exports(ROOT,'codec-scanlines.rkt'):self.assertIn(name,docs)
    def test_incremental_remains_separate(self):
        self.assertIn('## 0.76c',self.source('plans/skia-for-racket-gap-reduction-roadmap.md'))
        self.assertIn('(define version "0.78")',self.source('info.rkt'))

if __name__=='__main__':unittest.main(verbosity=2)
