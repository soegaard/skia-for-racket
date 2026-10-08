#!/usr/bin/env python3
"""Independent inspector and actual validator orchestration tests.

The Python-authored inputs and mocked subprocess results below are synthetic,
not native execution evidence. Native evidence is produced by the Racket doctor.
"""
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
import zlib
import codec_incremental_validation as v

ROOT=Path(__file__).resolve().parents[1]
TOKEN='synthetic-incremental-token'
PASSES=((0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2))


def synthetic_png_parts(interlaced=False):
    """Independent stored-DEFLATE encoder for the small known-pixel fixture."""
    w,h=8,8 if interlaced else 6
    rgba=v.reference(w,h)
    def pixel(x,y):return rgba[(y*w+x)*4:(y*w+x+1)*4]
    if interlaced:
        blocks=[b''.join(b'\0'+b''.join(pixel(x,y) for x in range(x0,w,dx))
                         for y in range(y0,h,dy)) for x0,y0,dx,dy in PASSES]
    else:blocks=[b'\0'+rgba[y*w*4:(y+1)*w*4] for y in range(h)]
    def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data))
    header=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,int(interlaced)))
    parts=[header]
    for i,b in enumerate(blocks):
        last=i==len(blocks)-1
        data=(b'\x78\x01' if not i else b'')+bytes([int(last)])+struct.pack('<HH',len(b),0xffff-len(b))+b
        if last:data+=struct.pack('>I',zlib.adler32(b''.join(blocks)))
        parts.append(chunk(b'IDAT',data)+(chunk(b'IEND',b'') if last else b''))
    return parts


def pixel_capture(h,rows):
    rgba=v.reference(8,h)
    return b''.join((rgba[y*32:(y+1)*32] if y<rows else b'\0'*32)+b'\0'*12 for y in range(h))


def stats(calls,retained,size,extent,final):
    return {'header-attempts':1,'start-calls':1,'decode-calls':calls,
            'pixel-allocations':1,'input-bytes':extent,'visible-input-bytes':extent,
            'input-final?':final,'stream-creations':1,'stream-destructions':0 if retained else 1,
            'decoder-retained?':retained,'pixel-bytes':size}


def synthetic_evidence(root,token=TOKEN):
    root=Path(root);root.mkdir(parents=True,exist_ok=True)
    matrices=[]
    for interlaced,name,height,count in ((False,'normal',6,6),(True,'adam7',8,7)):
        parts=synthetic_png_parts(interlaced);data=b''.join(parts)
        (root/(name+'.png')).write_bytes(data)
        steps=[]
        for i in range(1,count+1):
            final=i==count;file=f'{name}-{i}.pixels'
            # Deliberately synthetic partial pixels: only the real native gate
            # may assert what the interlaced decoder actually writes per pass.
            (root/file).write_bytes(pixel_capture(height,height if final else i))
            steps.append(dict(state='complete' if final else 'needs-input',
                              result='success' if final else 'incomplete-input',
                              initialized_rows=height if interlaced else i,pixels=file,
                              statistics=stats(i,not final,44*height,len(b''.join(parts[:i+1])),final)))
        matrices.append(dict(name=name,width=8,height=height,row_bytes=44,steps=steps))
    normal=synthetic_png_parts(False);short=b''.join(normal[:3]);extent=len(b''.join(normal[:2]))
    (root/'truncated.png').write_bytes(short);(root/'truncated.pixels').write_bytes(pixel_capture(6,2))
    (root/'live-copy.bin').write_bytes(bytes(range(256)))
    receipt=dict(schema=1,stage='0.76c',status='passed',run_token=token,native_version='119.0',
                 matrices=matrices,
                 truncated=dict(state='incomplete',result='incomplete-input',initialized_rows=2,
                                pixels='truncated.pixels',statistics=stats(1,False,264,len(short),True)),
                 unsupported=dict(state='failed',result='unimplemented',initialized_rows=False,pixels=False,
                                  statistics=stats(0,False,192,200,True)),
                 cancelled=dict(state='cancelled',result='cancelled',initialized_rows=False,pixels=False,
                                statistics=stats(1,False,0,extent,False)),
                 sessions_closed=True,registered_sources=0,incremental_decode_executed=True,
                 one_shot_fallback=False,compiler_required=False,gpu_executed=False)
    (root/'incremental.json').write_text(json.dumps(receipt),encoding='utf-8')
    return receipt


class Completion(unittest.TestCase):
    def valid(self):return f'{v.PURE_CASES} success(es) 0 failure(s) 0 error(s) {v.PURE_CASES} test(s) run\ncodec-incremental-pure: {v.PURE_CASES} cases, 0 failures\n'
    def test_complete(self):v.suite_output(self.valid(),'codec-incremental-pure',v.PURE_CASES)
    def test_windows_crlf(self):v.suite_output(self.valid().replace('\n','\r\n'),'codec-incremental-pure',v.PURE_CASES)
    def test_empty(self):
        with self.assertRaises(ValueError):v.suite_output('','codec-incremental-pure',v.PURE_CASES)
    def test_partial(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid().split('\n')[0],'codec-incremental-pure',v.PURE_CASES)
    def test_duplicate(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid()*2,'codec-incremental-pure',v.PURE_CASES)
    def test_conflicting_summary(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid()+'0 success(es) 1 failure(s) 0 error(s) 1 test(s) run\n','codec-incremental-pure',v.PURE_CASES)
    def test_wrong_count(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid(),'codec-incremental-pure',v.PURE_CASES+1)
    def test_failure(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid().replace('0 failure(s)','1 failure(s)'),'codec-incremental-pure',v.PURE_CASES)
    def test_error(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid()+'ERROR\n','codec-incremental-pure',v.PURE_CASES)
    def test_wrong_suite(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid(),'codec-incremental-native',v.PURE_CASES)


class Evidence(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.receipt=synthetic_evidence(self.root)
    def write(self):(self.root/'incremental.json').write_text(json.dumps(self.receipt),encoding='utf-8')
    def rejects(self):
        self.write()
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def step(self,n=0,m=0):return self.receipt['matrices'][m]['steps'][n]
    def corrupt(self,name,at):
        p=self.root/name;b=bytearray(p.read_bytes());b[at]^=127;p.write_bytes(b)
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def test_valid(self):self.assertEqual(v.inspect(self.root,TOKEN)['partial_captures'],11)
    def test_independent_normal_and_adam7_pixels(self):
        from PIL import Image
        for interlaced,height in ((False,6),(True,8)):
            data=b''.join(synthetic_png_parts(interlaced))
            with Image.open(io.BytesIO(data)) as im:self.assertEqual(im.convert('RGBA').tobytes(),v.reference(8,height))
    def test_token(self):self.receipt['run_token']='stale';self.rejects()
    def test_status(self):self.receipt['status']='failed';self.rejects()
    def test_boolean_schema(self):self.receipt['schema']=True;self.rejects()
    def test_abi(self):self.receipt['native_version']='153.0';self.rejects()
    def test_no_native_execution(self):self.receipt['incremental_decode_executed']=False;self.rejects()
    def test_fallback_claim(self):self.receipt['one_shot_fallback']=True;self.rejects()
    def test_missing_claim(self):self.receipt.pop('compiler_required');self.rejects()
    def test_no_close(self):self.receipt['sessions_closed']=False;self.rejects()
    def test_registry_leak(self):self.receipt['registered_sources']=1;self.rejects()
    def test_missing_matrix(self):self.receipt['matrices'].pop();self.rejects()
    def test_duplicate_matrix(self):self.receipt['matrices'][1]=copy.deepcopy(self.receipt['matrices'][0]);self.rejects()
    def test_dimensions(self):self.receipt['matrices'][0]['height']=5;self.rejects()
    def test_boolean_dimension(self):self.receipt['matrices'][0]['width']=True;self.rejects()
    def test_missing_step(self):self.receipt['matrices'][0]['steps'].pop();self.rejects()
    def test_premature_completion(self):self.step()['state']='complete';self.rejects()
    def test_final_still_incomplete(self):self.step(5)['state']='needs-input';self.rejects()
    def test_native_result_disagrees(self):self.step()['result']='success';self.rejects()
    def test_invented_rows(self):self.step()['initialized_rows']=6;self.rejects()
    def test_negative_adam7_rows(self):self.step(0,1)['initialized_rows']=-1;self.rejects()
    def test_unknown_adam7_rows_allowed(self):
        self.step(0,1)['initialized_rows']=False;self.write();v.inspect(self.root,TOKEN)
    def test_initialized_height_does_not_complete(self):
        self.assertEqual(self.step(0,1)['initialized_rows'],8)
        self.assertEqual(self.step(0,1)['state'],'needs-input');v.inspect(self.root,TOKEN)
    def test_new_decoder(self):self.step(1)['statistics']['header-attempts']=2;self.rejects()
    def test_second_start(self):self.step(1)['statistics']['start-calls']=2;self.rejects()
    def test_replaced_pixels(self):self.step(1)['statistics']['pixel-allocations']=2;self.rejects()
    def test_missing_advance(self):self.step(1)['statistics']['decode-calls']=1;self.rejects()
    def test_bool_native_count(self):self.step()['statistics']['decode-calls']=True;self.rejects()
    def test_retired_before_complete(self):self.step()['statistics']['decoder-retained?']=False;self.rejects()
    def test_leaked_after_complete(self):self.step(5)['statistics']['stream-destructions']=0;self.rejects()
    def test_wrong_fed_size(self):self.step()['statistics']['input-bytes']+=1;self.rejects()
    def test_wrong_visible_size(self):self.step()['statistics']['visible-input-bytes']-=1;self.rejects()
    def test_wrong_final_marker(self):self.step()['statistics']['input-final?']=True;self.rejects()
    def test_unsafe_file(self):self.step()['pixels']='../normal-1.pixels';self.rejects()
    def test_short_capture(self):(self.root/'normal-1.pixels').write_bytes(b'x');self.rejects()
    def test_changed_padding(self):self.corrupt('normal-1.pixels',32)
    def test_changed_pixels(self):self.corrupt('normal-1.pixels',4)
    def test_uninitialized_remainder(self):self.corrupt('normal-1.pixels',44)
    def test_encoded_crc(self):self.corrupt('normal.png',29)
    def test_interlace_flag(self):
        b=bytearray((self.root/'adam7.png').read_bytes());b[28]=0;b[29:33]=struct.pack('>I',zlib.crc32(b[12:29]))
        (self.root/'adam7.png').write_bytes(b);self.rejects()
    def test_truncated_marked_complete(self):self.receipt['truncated']['state']='complete';self.rejects()
    def test_truncated_rows(self):self.receipt['truncated']['initialized_rows']=6;self.rejects()
    def test_truncation_without_final(self):self.receipt['truncated']['statistics']['input-final?']=False;self.rejects()
    def test_unsupported_fallback(self):self.receipt['unsupported']['result']='success';self.rejects()
    def test_unsupported_decoded(self):self.receipt['unsupported']['statistics']['decode-calls']=1;self.rejects()
    def test_cancelled_leaks_pixels(self):self.receipt['cancelled']['statistics']['pixel-bytes']=192;self.rejects()
    def test_cancelled_snapshot(self):self.receipt['cancelled']['pixels']='normal-1.pixels';self.rejects()
    def test_live_provider_changed(self):self.corrupt('live-copy.bin',100)
    def test_missing_capture(self):(self.root/'adam7-7.pixels').unlink();self.rejects()
    def test_duplicate_json_key(self):
        p=self.root/'incremental.json';p.write_text(p.read_text().replace('"schema": 1','"schema": 1, "schema": 1'))
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)


class Orchestration(unittest.TestCase):
    def invoke(self,mode=None,failure=None,partial=False,mutate=False,bad_evidence=False,timeout=False):
        spec=importlib.util.spec_from_file_location('incremental_validator_test',ROOT/'tools/validate-codec-incremental.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);commands=[]
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);(root/'SOURCE-SHA256SUMS.txt').write_text('synthetic\n')
            (root/'run-tests.rkt').write_text('(define-runtime-path unrelated "tests/unrelated-native-test.rkt")\n')
            def execute(command,**kwargs):
                command=list(map(str,command));commands.append(command)
                name=Path(command[1]).name if len(command)>1 else '';out=kwargs['stdout']
                if name==failure:
                    out.write('selected synthetic failure\n');out.flush()
                    if timeout:raise subprocess.TimeoutExpired(command,1)
                    raise subprocess.CalledProcessError(1,command)
                for suite,count in (('codec-incremental-pure',v.PURE_CASES),('codec-incremental-native',v.NATIVE_CASES)):
                    if name==suite+'-test.rkt':out.write('partial\n' if partial else f'{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run\n{suite}: {count} cases, 0 failures\n')
                if name=='codec-incremental-doctor.rkt':
                    directory=Path(command[command.index('--directory')+1]);token=command[command.index('--token')+1]
                    receipt=synthetic_evidence(directory,token)
                    if mutate:(root/'SOURCE-SHA256SUMS.txt').write_text('changed\n')
                    if bad_evidence:
                        receipt['one_shot_fallback']=True
                        (directory/'incremental.json').write_text(json.dumps(receipt))
                out.flush();return subprocess.CompletedProcess(command,0)
            args=['--racket',sys.executable,'--directory',str(root/'out')]
            if mode is not None:args+=['--regressions',mode]
            with patch.object(module.shutil,'which',return_value=sys.executable),patch.object(module.subprocess,'run',side_effect=execute),contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                result=module.main(args,root=root)
            report=json.loads((root/'out/validation.json').read_text())
        return result,report,commands
    def test_default_full(self):
        rc,r,_=self.invoke();self.assertEqual(rc,0);self.assertEqual(r['regressions_status'],'passed');self.assertTrue(r['regressions_attempted'])
    def test_none_not_passed(self):
        rc,r,c=self.invoke('none');self.assertEqual(rc,0);self.assertFalse(r['regressions_passed']);self.assertFalse(r['regressions_attempted']);self.assertEqual(r['regressions_status'],'not-run')
        self.assertFalse(any(Path(x[1]).name=='run-tests.rkt' for x in c))
    def test_feature_compile_roots(self):
        _,_,c=self.invoke('none');names=[x.replace('\\','/') for x in next(x for x in c if 'make' in x)]
        self.assertTrue(any(x.endswith('/tests/codec-incremental-native-test.rkt') for x in names))
        self.assertFalse(any(x.endswith('run-tests.rkt') or 'unrelated' in x for x in names))
    def test_full_compile_graph(self):
        _,_,c=self.invoke();names=[x.replace('\\','/') for x in next(x for x in c if 'make' in x)]
        self.assertTrue(any(x.endswith('/tests/unrelated-native-test.rkt') for x in names))
    def test_features_preserved(self):
        def selected(cs):return [Path(c[1]).name for c in cs if c[1]!='-l' and Path(c[1]).name!='run-tests.rkt']
        self.assertEqual(selected(self.invoke('full')[2]),selected(self.invoke('none')[2]))
    def test_global_failure_stops_feature(self):
        rc,r,c=self.invoke(failure='run-tests.rkt');self.assertEqual(rc,1);self.assertEqual(r['regressions_status'],'failed');self.assertFalse(r['native_passed'])
    def test_pure_failure(self):self.assertEqual(self.invoke('none',failure='codec-incremental-pure-test.rkt')[0],1)
    def test_native_failure_stops_doctor(self):
        rc,r,c=self.invoke('none',failure='codec-incremental-native-test.rkt');self.assertEqual(rc,1);self.assertFalse(r['byte_oracles_passed'])
        self.assertFalse(any(Path(x[1]).name=='codec-incremental-doctor.rkt' for x in c))
    def test_doctor_failure(self):self.assertEqual(self.invoke('none',failure='codec-incremental-doctor.rkt')[0],1)
    def test_example_failure(self):self.assertEqual(self.invoke('none',failure='codec-incremental.rkt')[0],1)
    def test_source_failure(self):self.assertEqual(self.invoke('none',failure='api-inventory.py')[0],1)
    def test_partial_summary(self):self.assertEqual(self.invoke('none',partial=True)[0],1)
    def test_changed_manifest(self):self.assertEqual(self.invoke('none',mutate=True)[0],1)
    def test_inspector_failure(self):
        rc,r,_=self.invoke('none',bad_evidence=True);self.assertEqual(rc,1);self.assertFalse(r['incremental_decode_executed'])
    def test_timeout_is_failure(self):
        rc,r,_=self.invoke('none',failure='codec-incremental-native-test.rkt',timeout=True);self.assertEqual(rc,1);self.assertIn('TimeoutExpired',r['error'])
    def test_positive_native_claim_requires_inspection(self):
        rc,r,_=self.invoke('none');self.assertEqual(rc,0);self.assertTrue(r['incremental_decode_executed']);self.assertFalse(r['one_shot_fallback']);self.assertFalse(r['gpu_executed'])


class Sources(unittest.TestCase):
    def text(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_case_counts(self):
        for kind,count in (('pure',v.PURE_CASES),('native',v.NATIVE_CASES)):
            s=self.text(f'tests/codec-incremental-{kind}-test.rkt');self.assertEqual(s.count('(test-case '),count)
            self.assertIn(f'(define codec-incremental-{kind}-test-count {count})',s)
    def test_native_declarations(self):
        s=self.text('private/native.rkt')
        for name in ('sk_codec_start_incremental_decode','sk_codec_incremental_decode'):
            self.assertEqual(s.count('(define-native '+name),1)
    def test_no_one_shot_fallback(self):
        s=self.text('codec-incremental.rkt')
        for name in ('sk_codec_get_pixels','sk_codec_get_scanlines','codec->image','codec-from-bytes','get-ffi-obj'):
            self.assertNotIn(name,s)
    def test_destroy_before_release(self):
        s=self.text('codec-incremental.rkt');body=s[s.index('(define (release-cell!'):s.index('(define (finish-native!')]
        self.assertLess(body.index('(destroy-codec! c)'),body.index('(release-pixels! c)'))
    def test_provider_reused(self):
        s=self.text('private/live-port-native.rkt')
        self.assertIn('incremental-source-callback input-kind fallback arguments',s)
        self.assertIn('(and input-kind (cadr arguments))',s)
        self.assertIn('(apply ordinary arguments)',s)
        self.assertIn('dispatch-managed-callback',s)
        for name in ('codec-incremental.rkt','private/codec-incremental-source.rkt'):
            self.assertNotIn('sk_managedstream_set_procs',self.text(name))
    def test_memory_registration_does_not_root_session(self):
        s=self.text('private/codec-incremental-source.rkt');self.assertIn('(struct source (input context [position #:mutable]))',s)
        self.assertNotIn('incremental-session-record',s)
    def test_native_summaries_registered(self):
        s=self.text('run-tests.rkt');self.assertIn('(run-tests codec-incremental-pure-tests)',s)
        self.assertIn("dynamic-require codec-incremental-native-tests-file 'codec-incremental-native-tests",s)
        self.assertIn("'test-codec-incremental.py'",self.text('tools/ci.py'))
    def test_resource_integration(self):
        self.assertIn('(incremental-session-record? v)',self.text('private/core.rkt'))
        self.assertIn('(incremental-session-record-handle v)',self.text('private/core.rkt'))
        self.assertIn('codec-incremental stream-input stream-output',self.text('private/lifetime.rkt'))
    def test_three_automatic_workflows(self):
        auto={p.name for p in (ROOT/'.github/workflows').glob('*.yml') if '\n  push:' in p.read_text() or '\n  pull_request:' in p.read_text()}
        self.assertEqual(auto,{'ci.yml','acceptance.yml','api-inventory.yml'})
        s=self.text('.github/workflows/codec-queries.yml')
        self.assertEqual(s.count('validate-codec-incremental.py --regressions none'),2)
        self.assertIn('codec-incremental-windows',s)
    def test_public_docs(self):
        import api_inventory as inv
        doc=self.text('docs/CODEC-INCREMENTAL.md')
        for name in inv.source_exports(ROOT,'codec-incremental.rkt'):self.assertIn(name,doc)
    def test_version_and_scope(self):
        self.assertIn('(define version "0.77")',self.text('info.rkt'))
        self.assertIn('## 0.76c',self.text('plans/skia-for-racket-gap-reduction-roadmap.md'))


if __name__=='__main__':unittest.main(verbosity=2)
