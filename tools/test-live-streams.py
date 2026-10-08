#!/usr/bin/env python3
"""Synthetic inspector/control-flow tests; not native Skia execution evidence."""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import live_stream_validation as v
ROOT=Path(__file__).resolve().parents[1]
TOKEN='a'*32
def valid():
    return dict(schema=1,stage='0.75b',status='passed',run_token=TOKEN,native_version='119.0',
      authoring_calls=3,write_callbacks=10,callbacks_on_service_thread=True,compiler_required=False,active_jobs=0,
      native_execution=True,gpu_execution=False,racket_version='synthetic',os='unix')
class Receipt(unittest.TestCase):
    def test_valid(self):v.receipt(valid(),TOKEN)
    def test_wrong_token(self):self.reject('run_token','b'*32)
    def test_no_execution(self):self.reject('native_execution',False)
    def test_foreign_thread(self):self.reject('callbacks_on_service_thread',False)
    def test_active_worker(self):self.reject('active_jobs',1)
    def test_boolean_worker_count(self):self.reject('active_jobs',False)
    def test_reauthoring(self):self.reject('authoring_calls',6)
    def test_boolean_authoring(self):self.reject('authoring_calls',True)
    def test_missing_writes(self):self.reject('write_callbacks',0)
    def test_wrong_native(self):self.reject('native_version','153.0')
    def test_wrong_stage(self):self.reject('stage','0.75a')
    def test_gpu_claim(self):self.reject('gpu_execution',True)
    def reject(self,key,value):
        r=valid();r[key]=value
        with self.assertRaises(ValueError):v.receipt(r,TOKEN)
class Completion(unittest.TestCase):
    def text(self):return '26 success(es) 0 failure(s) 0 error(s) 26 test(s) run\nlive-stream-pure: 26 cases, 0 failures\n'
    def test_valid(self):v.suite_output(self.text(),'live-stream-pure',26)
    def test_crlf(self):v.suite_output(self.text().replace('\n','\r\n'),'live-stream-pure',26)
    def test_duplicate(self):
        with self.assertRaises(ValueError):v.suite_output(self.text()*2,'live-stream-pure',26)
    def test_incomplete(self):
        with self.assertRaises(ValueError):v.suite_output(self.text().split('\n')[0],'live-stream-pure',26)
    def test_wrong_count(self):
        with self.assertRaises(ValueError):v.suite_output(self.text(),'live-stream-pure',25)
    def test_failed(self):
        with self.assertRaises(ValueError):v.suite_output(self.text().replace('0 error(s)','1 error(s)'),'live-stream-pure',26)
class Orchestration(unittest.TestCase):
    def invoke(self,mode=None,failure=None,partial=False):
        spec=importlib.util.spec_from_file_location('live_driver',ROOT/'tools/validate-live-streams.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        commands=[]
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'SOURCE-SHA256SUMS.txt').write_text('synthetic')
            (root/'run-tests.rkt').write_text('(define-runtime-path x "tests/unrelated-native-test.rkt")')
            def execute(command,**kwargs):
                command=list(map(str,command));commands.append(command)
                name=Path(command[1]).name if len(command)>1 else ''
                if name==failure:raise subprocess.CalledProcessError(1,command)
                for kind,count in (('pure',v.PURE_CASES),('native',v.NATIVE_CASES)):
                    if name==f'live-stream-{kind}-test.rkt':
                        kwargs['stdout'].write('incomplete\n' if partial else f'{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run\nlive-stream-{kind}: {count} cases, 0 failures\n')
                return subprocess.CompletedProcess(command,0)
            args=['--racket',sys.executable,'--directory',str(root/'out')]
            if mode:args+=['--regressions',mode]
            with patch.object(module.subprocess,'run',side_effect=execute), patch.object(module.shutil,'which',return_value=sys.executable), \
                 patch.object(module.checks,'inspect',return_value={'status':'passed','scope':'mock inspector'}), \
                 patch.object(module.probe,'run_probe',side_effect=(ValueError('synthetic probe failure') if failure=='probe' else None), return_value={'status':'passed','native_cases':25}), \
                 contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                result=module.main(args,root=root)
            return result,json.loads((root/'out/validation.json').read_text()),commands
    def test_default_full(self):
        rc,r,c=self.invoke();self.assertEqual(rc,0);self.assertTrue(r['regressions_passed']);self.assertTrue(any(Path(x[1]).name=='run-tests.rkt' for x in c))
    def test_none_is_not_pass(self):
        rc,r,c=self.invoke('none');self.assertEqual(rc,0);self.assertFalse(r['regressions_passed']);self.assertEqual(r['regressions_status'],'not-run')
        self.assertFalse(any(Path(x[1]).name=='run-tests.rkt' for x in c))
    def test_full_compile_graph(self):
        _,_,c=self.invoke();compile=next(x for x in c if 'make' in x)
        self.assertTrue(any(x.replace('\\','/').endswith('tests/unrelated-native-test.rkt') for x in compile))
    def test_none_compile_graph(self):
        _,_,c=self.invoke('none');compile=next(x for x in c if 'make' in x)
        self.assertFalse(any('unrelated-native' in x for x in compile))
        self.assertTrue(any(x.replace('\\','/').endswith('tests/live-stream-native-test.rkt') for x in compile))
    def test_compiler_never_invoked(self):
        _,_,commands=self.invoke()
        words={Path(part).name for c in commands for part in c}
        for bad in ('cmake','cc','c++','build-port-bridge.py'):self.assertNotIn(bad,words)
    def test_features_preserved(self):
        _,_,a=self.invoke('full');_,_,b=self.invoke('none')
        def features(c):return [Path(x[1]).name for x in c if x[1]!='-l' and Path(x[1]).name!='run-tests.rkt']
        self.assertEqual(features(a),features(b))
    def test_probe_failure(self):self.assertEqual(self.invoke(failure='probe')[0],1)
    def test_regression_failure(self):
        rc,r,c=self.invoke(failure='run-tests.rkt');self.assertEqual(rc,1);self.assertEqual(r['regressions_status'],'failed');self.assertFalse(r['native_passed'])
    def test_native_failure(self):
        rc,r,_=self.invoke('none',failure='live-stream-native-test.rkt');self.assertEqual(rc,1);self.assertFalse(r['evidence_passed'])
    def test_incomplete_completion(self):self.assertEqual(self.invoke('none',partial=True)[0],1)
    def test_source_failure(self):self.assertEqual(self.invoke('none',failure='api-inventory.py')[0],1)
    def test_doctor_failure(self):self.assertEqual(self.invoke('none',failure='live-stream-doctor.rkt')[0],1)
class Sources(unittest.TestCase):
    def text(self,p):return (ROOT/p).read_text(encoding='utf-8')
    def test_case_counts(self):
        for kind,n in (('pure',v.PURE_CASES),('native',v.NATIVE_CASES)):
            s=self.text(f'tests/live-stream-{kind}-test.rkt');self.assertEqual(s.count('(test-case '),n)
            self.assertIn(f'(define live-stream-{kind}-test-count {n})',s)
    def test_native_import_manifest(self):
        source=self.text('private/live-port-native.rkt')
        rows=dict(re.findall(r'^\(define-raw (sk_\w+) (\(_fun[^\n]*\))\)$',source,re.M))
        manifest=json.loads(self.text('api/live-stream-ffi.json'))
        self.assertEqual(rows,manifest['standard']|manifest['xamarin'])
        self.assertEqual(len(manifest['xamarin']),6)
    def test_callbacks_enqueue_thunks_only(self):
        source=self.text('private/live-port-runtime.rkt')
        body=source[source.index('(define (dispatch-callback'):source.index('(define (guarded-callback')]
        self.assertIn('os-async-channel-put',body)
        self.assertNotIn('(thunk)',body);self.assertNotIn('write-bytes',body);self.assertNotIn('(sync ',body)
    def test_protected_service_owns_cleanup(self):
        source=self.text('private/live-port-runtime.rkt')
        self.assertIn('make-custodian-at-root',source)
        self.assertIn('(thread-dead-evt (operation-owner j))',source)
        self.assertIn('(finish-once (and (not (operation-error j))',source)
        self.assertLess(source.index('(finish-once (and'),source.index('(set! current-operation #f)',source.index('(finish-once (and')))
    def test_lease_roots_and_poison(self):
        source=self.text('private/live-native-lease.rkt')
        for term in ('register-finalizer','check-live-pin!','check-live-fault!','poison-live-pin!','set-native-reference-pointer!'):
            self.assertIn(term,source)
    def test_original_probe_still_has_25_cases(self):
        source=self.text('tests/live-ffi-probe/probe.rkt')
        self.assertEqual(source.count('(test-case '),25)
        for term in ('killed caller','custodian','bounded output pipe','collections during callbacks'):
            self.assertIn(term,source)
    def test_no_custom_native_bridge(self):
        self.assertFalse((ROOT/'tools/port-bridge').exists())
        self.assertFalse((ROOT/'tools/build-port-bridge.py').exists())
    def test_cpu_gate_preserved(self):
        s=self.text('live-streams.rkt');self.assertIn("call-with-owned 'picture->bytes",s);self.assertIn("call-with-owned 'image->encoded-bytes",s)
    def test_not_byte_serialization_wrappers(self):
        s=self.text('live-streams.rkt');self.assertNotIn('(picture->bytes ',s);self.assertNotIn('(image->encoded-bytes ',s)
        self.assertNotIn('port->bytes',s)
    def test_audit_before_publication(self):
        s=self.text('live-streams.rkt');self.assertIn('call-with-audit-collector format policy #t',s)
        self.assertIn('(proc pictures sizes)',s);self.assertIn('make-output-page (car size)',s)
    def test_svg_root_and_renderer_dimensions(self):
        self.assertIn('16384',self.text('private/live-port-util.rkt'))
        self.assertIn("'--width','64','--height','48'",self.text('tools/live_stream_validation.py'))
    def test_native_stream_memory_guards(self):
        if not (ROOT/'streams.rkt').exists():self.skipTest('complete checkout integration tested by installer')
        s=self.text('streams.rkt');self.assertIn('memory-output-only',s);self.assertIn('with-output stream-h',s)
    def test_registration(self):
        if not (ROOT/'run-tests.rkt').exists():self.skipTest('complete checkout integration tested by installer')
        s=self.text('run-tests.rkt');self.assertIn('(run-tests live-stream-pure-tests)',s)
        self.assertIn("dynamic-require live-stream-native-tests-file 'live-stream-native-tests",s)
        self.assertIn("'test-live-streams.py'",self.text('tools/ci.py'))
    def test_no_new_automatic_workflow(self):
        if not (ROOT/'.github/workflows/streams.yml').exists():self.skipTest('complete checkout integration tested by installer')
        s=self.text('.github/workflows/streams.yml');self.assertNotIn('\n  push:',s)
        self.assertIn('validate-live-streams.py --regressions none',s)
if __name__=='__main__':unittest.main(verbosity=2)
