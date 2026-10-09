#!/usr/bin/env python3
"""0.77b source/inspector tests. Native receipts here are Python-authored fixtures."""
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
import gpu_context_control_validation as v
ROOT=Path(__file__).resolve().parents[1]
TOKEN='synthetic-context-control-token'

def flush(target,g=1000):
    return dict(kind='flush',target=target,context_generation=g,submission_requested=False,completion_guaranteed=False)

def synthetic_evidence(root,token=TOKEN,backend='egl',adapter='hardware'):
    root=Path(root);root.mkdir(parents=True,exist_ok=True)
    base={'egl':'gr_direct_context_make_gl','metal':'gr_direct_context_make_metal','direct3d':'gr_direct_context_make_direct3d'}[backend]
    rbackend={'egl':'opengl','metal':'metal','direct3d':'direct3d'}[backend]
    rows=[]
    for g,(name,opts) in enumerate(v.CONFIGS.items(),1):
        info=dict(backend=rbackend,state='ready',generation=g,context_factory=base+('_with_options' if opts is not False else ''),
                  context_options_source='explicit' if opts is not False else 'native-defaults',context_options=copy.deepcopy(opts),
                  context_options_native_readback=False,adapter_selection=adapter)
        (root/(name+'.rgba')).write_bytes(v.pixels())
        rows.append(dict(name=name,file=name+'.rgba',width=32,height=24,info=info,requested_options=copy.deepcopy(opts),
                         drawing_readbacks=0,readbacks=1,events=[flush('surface',g),dict(kind='gpu-snapshot'),flush('image',g),
                            dict(kind='submit',wait_requested=True),dict(kind='readback'),dict(kind='flush'),dict(kind='submit',wait_requested=True)]))
    report=dict(schema=1,stage='0.77b',status='passed',run_token=token,native_version='119.0',backend=backend,adapter=adapter,
                gpu_executed=True,native_option_readback=False,cases=v.GPU_CASES,failures=0,labels=v.LABELS[:],captures=rows,
                targeted_traces=[dict(name='surface',events=[flush('surface')]),dict(name='image',events=[flush('image')]),
                                dict(name='submit',events=[flush('surface'),dict(kind='submit',wait_requested=True)]),
                                dict(name='release',events=[dict(kind='context-release-and-abandon',context_generation=1000,
                                                               completion_guaranteed=False,readback=False)])],
                lifecycle=dict(before=dict(state='ready',live_children=2,generation=1000,pending_releases=0),
                               after_release=dict(state='abandoned',live_children=2,generation=1000,pending_releases=0),
                               after_close=dict(state='closed',live_children=0,generation=1000,pending_releases=0),
                               children_invalidated=True,child_close_required=True),cleanup_errors=[])
    (root/'gpu.json').write_text(json.dumps(report),encoding='utf-8')
    return report

class Evidence(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.data=synthetic_evidence(self.root)
    def reject(self,change):
        change(self.data);(self.root/'gpu.json').write_text(json.dumps(self.data),encoding='utf-8')
        with self.assertRaises(ValueError):v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')
    def test_valid_synthetic(self):self.assertEqual(v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')['total_pixels_checked'],3840)
    def test_all_backend_schemas(self):
        for backend,adapter in [('metal','hardware'),('direct3d','warp')]:
            synthetic_evidence(self.root,TOKEN,backend,adapter)
            self.assertEqual(v.inspect(self.root/'gpu.json',TOKEN,backend,adapter)['status'],'passed')
    def test_pixel_corruption(self):
        path=self.root/'manual.rgba';b=bytearray(path.read_bytes());b[120]^=1;path.write_bytes(b)
        with self.assertRaises(ValueError):v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')
    def test_missing_capture(self):
        (self.root/'tuned.rgba').unlink()
        with self.assertRaises(ValueError):v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')
    def test_short_capture(self):
        (self.root/'tuned.rgba').write_bytes(b'x')
        with self.assertRaises(ValueError):v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')
    def test_duplicate_json_key(self):
        p=self.root/'gpu.json';p.write_text(p.read_text().replace('"schema": 1','"schema": 1, "schema": 1'))
        with self.assertRaises(ValueError):v.inspect(p,TOKEN,'egl','hardware')
    def test_symlink(self):
        p=self.root/'tuned.rgba';p.unlink()
        try:p.symlink_to(self.root/'manual.rgba')
        except OSError:self.skipTest('host cannot create symlinks')
        with self.assertRaises(ValueError):v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')

MUTATIONS={
 'old_token':lambda r:r.update(run_token='old'),
 'boolean_schema':lambda r:r.update(schema=True),
 'wrong_stage':lambda r:r.update(stage='0.77a'),
 'failed_status':lambda r:r.update(status='failed'),
 'wrong_abi':lambda r:r.update(native_version='153.0'),
 'wrong_backend':lambda r:r.update(backend='metal'),
 'skipped_gpu':lambda r:r.update(gpu_executed=False),
 'invented_readback':lambda r:r.update(native_option_readback=True),
 'missing_case':lambda r:r.update(cases=v.GPU_CASES-1),
 'boolean_failures':lambda r:r.update(failures=False),
 'missing_label':lambda r:r['labels'].pop(),
 'cleanup_error':lambda r:r.update(cleanup_errors=['failed release']),
 'missing_scenario':lambda r:r['captures'].pop(),
 'duplicate_scenario':lambda r:r['captures'][1].update(name='native-defaults'),
 'unsafe_file':lambda r:r['captures'][0].update(file='../elsewhere'),
 'wrong_factory':lambda r:r['captures'][2]['info'].update(context_factory='gr_direct_context_make_gl'),
 'wrong_request':lambda r:r['captures'][2]['info']['context_options'].update(runtime_program_cache_size=256),
 'wrong_provenance':lambda r:r['captures'][0]['info'].update(context_options_source='explicit'),
 'hidden_readback':lambda r:r['captures'][0].update(drawing_readbacks=1),
 'foreign_flush':lambda r:r['captures'][0]['events'][0].update(context_generation=999),
 'flush_claims_wait':lambda r:r['captures'][0]['events'][0].update(completion_guaranteed=True),
 'no_completion':lambda r:r['captures'][0]['events'][-1].update(wait_requested=False),
 'early_submit':lambda r:r['captures'][0]['events'].insert(0,dict(kind='submit',wait_requested=True)),
 'wrong_lifecycle':lambda r:r['lifecycle']['after_release'].update(state='closed'),
 'child_disappears':lambda r:r['lifecycle']['after_release'].update(live_children=0),
 'pending_child':lambda r:r['lifecycle']['after_close'].update(pending_releases=1),
 'target_upload':lambda r:r['targeted_traces'][0]['events'].append(dict(kind='upload')),
 'release_readback':lambda r:r['targeted_traces'][3]['events'][0].update(readback=True),
}
for name,change in MUTATIONS.items():
    def test(self,change=change):self.reject(change)
    setattr(Evidence,'test_reject_'+name,test)

class Completion(unittest.TestCase):
    def valid(self):return f'{v.PURE_CASES} success(es) 0 failure(s) 0 error(s) {v.PURE_CASES} test(s) run\ngpu-context-control-pure: {v.PURE_CASES} cases, 0 failures\n'
    def test_complete(self):v.suite_output(self.valid(),'gpu-context-control-pure',v.PURE_CASES)
    def test_windows(self):v.suite_output(self.valid().replace('\n','\r\n'),'gpu-context-control-pure',v.PURE_CASES)
    def test_incomplete(self):
        for text in ('',self.valid().split('\n')[0],self.valid()*2,self.valid().replace('0 failure(s)','1 failure(s)')):
            with self.assertRaises(ValueError):v.suite_output(text,'gpu-context-control-pure',v.PURE_CASES)

class Orchestration(unittest.TestCase):
    def invoke(self,mode=None,failure=None,partial=False,changed=False):
        spec=importlib.util.spec_from_file_location('gpu_controls_driver_test',ROOT/'tools/validate-gpu-context-controls.py')
        m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
        calls=[]
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'SOURCE-SHA256SUMS.txt').write_text('synthetic manifest\n')
            (root/'run-tests.rkt').write_text('(define-runtime-path unrelated "tests/unrelated-native-test.rkt")\n')
            def execute(command,**kw):
                command=list(map(str,command));calls.append(command);name=Path(command[1]).name
                log=kw['stdout']
                if name==failure:log.write('intentional mocked failure\n');raise subprocess.CalledProcessError(1,command)
                for kind,count in [('pure',v.PURE_CASES),('native',v.NATIVE_CASES)]:
                    if name==f'gpu-context-control-{kind}-test.rkt':
                        log.write('incomplete\n' if partial else f'{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run\ngpu-context-control-{kind}: {count} cases, 0 failures\n')
                if name=='gpu-context-control-gpu-test.rkt':
                    report=Path(command[command.index('--report')+1])
                    synthetic_evidence(report.parent,command[command.index('--token')+1],command[command.index('--backend')+1],command[command.index('--adapter')+1])
                    if changed:(root/'SOURCE-SHA256SUMS.txt').write_text('changed')
                log.flush();return subprocess.CompletedProcess(command,0)
            args=['--racket',sys.executable,'--backend','egl','--directory',str(root/'out')]
            if mode:args+=['--regressions',mode]
            with patch.object(m.shutil,'which',return_value=sys.executable),patch.object(m.subprocess,'run',side_effect=execute),contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                code=m.main(args,root=root)
            report=json.loads((root/'out/validation.json').read_text())
        return code,report,calls
    def test_full_default(self):
        code,r,_=self.invoke();self.assertEqual(code,0);self.assertEqual(r['regressions_status'],'passed');self.assertTrue(r['gpu_executed'])
    def test_none_is_not_passed(self):
        code,r,c=self.invoke('none');self.assertEqual(code,0);self.assertEqual(r['regressions_status'],'not-run');self.assertFalse(r['regressions_passed'])
        self.assertFalse(any(Path(x[1]).name=='run-tests.rkt' for x in c))
    def test_compile_scopes(self):
        for mode,want in [('full',True),('none',False)]:
            _,_,calls=self.invoke(mode);cmd=next(c for c in calls if 'make' in c)
            self.assertEqual(any('unrelated-native-test.rkt' in x for x in cmd),want)
            self.assertTrue(any('gpu-context-control-gpu-test.rkt' in x for x in cmd))
    def test_features_preserved(self):
        def selected(cs):return [Path(c[1]).name for c in cs if c[1]!='-l' and Path(c[1]).name!='run-tests.rkt']
        self.assertEqual(selected(self.invoke('full')[2]),selected(self.invoke('none')[2]))
    def test_global_failure(self):
        code,r,c=self.invoke(failure='run-tests.rkt');self.assertEqual(code,1);self.assertEqual(r['regressions_status'],'failed');self.assertFalse(r['gpu_executed'])
    def test_source_failure(self):self.assertEqual(self.invoke('none',failure='api-inventory.py')[0],1)
    def test_pure_failure(self):self.assertEqual(self.invoke('none',failure='gpu-context-control-pure-test.rkt')[0],1)
    def test_native_failure(self):
        code,r,_=self.invoke('none',failure='gpu-context-control-native-test.rkt');self.assertEqual(code,1);self.assertFalse(r['gpu_executed'])
    def test_gpu_failure(self):
        code,r,_=self.invoke('none',failure='gpu-context-control-gpu-test.rkt');self.assertEqual(code,1);self.assertFalse(r['byte_oracles_passed'])
    def test_partial_summary(self):self.assertEqual(self.invoke('none',partial=True)[0],1)
    def test_source_change(self):self.assertEqual(self.invoke('none',changed=True)[0],1)

class Sources(unittest.TestCase):
    def text(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_counts(self):
        for kind,count in [('pure',v.PURE_CASES),('native',v.NATIVE_CASES)]:
            s=self.text(f'tests/gpu-context-control-{kind}-test.rkt');self.assertEqual(s.count('(test-case '),count)
            self.assertIn(f'(define gpu-context-control-{kind}-test-count {count})',s)
        s=self.text('tests/gpu-context-control-gpu-test.rkt')
        self.assertEqual(len(re.findall(r'\(test! "',s)),v.GPU_CASES)
        self.assertIn(f'(define GPU-CASES {v.GPU_CASES})',s)
    def test_options_have_no_native_load(self):
        s=self.text('gpu-context-options.rkt')
        for bad in ('ffi-lib','get-ffi-obj','dynamic-require','native.rkt','racket/gui'):
            self.assertNotIn(bad,s)
    def test_control_does_not_transfer_pixels(self):
        s=self.text('private/gpu-context-control.rkt')
        for bad in ('gpu-upload-image','gpu-surface->rgba-bytes','gpu-image->rgba-bytes','gpu-submit!','gpu-wait!'):
            self.assertNotIn(bad,s)
        self.assertIn('domain-release-and-abandon!',s)
    def test_new_ci_gate_requires_gpu(self):
        s=self.text('.github/workflows/gpu-context-controls.yml')
        for term in ('--require-gpu','--backend egl','--backend direct3d','--adapter warp','workflow_call:','workflow_dispatch:'):
            self.assertIn(term,s)
        for term in ('continue-on-error:','\n  push:','\n  pull_request:','cmake','gcc','clang'):self.assertNotIn(term,s)
    def test_complete_driver_integration(self):
        if not (ROOT/'gpu.rkt').is_file():self.skipTest('requires complete installed source checkout')
        for file,term in [('gpu.rkt','#:options [options #f]'),('gpu-egl.rkt','#:options [options #f]'),
            ('private/gpu-driver-gl.rkt','gr_direct_context_make_gl_with_options'),
            ('private/gpu-driver-metal.rkt','gr_direct_context_make_metal_with_options'),
            ('private/gpu-driver-d3d12.rkt','gr_direct_context_make_direct3d_with_options')]:self.assertIn(term,self.text(file))
    def test_complete_domain_integration(self):
        if not (ROOT/'private/gpu-domain.rkt').is_file():self.skipTest('requires complete installed source checkout')
        s=self.text('private/gpu-domain.rkt')
        self.assertIn('domain-release-and-abandon!',s);self.assertIn("'release-failed",s);self.assertIn('quarantined',s)
    def test_required_gate_integration(self):
        if not (ROOT/'.github/workflows/acceptance.yml').is_file():self.skipTest('requires complete installed source checkout')
        self.assertIn('test "$GPU_CONTEXT_CONTROLS_RESULT" = success',self.text('.github/workflows/acceptance.yml'))
        auto={p.name for p in (ROOT/'.github/workflows').glob('*.yml') if '\n  push:' in p.read_text() or '\n  pull_request:' in p.read_text()}
        self.assertEqual(auto,{'ci.yml','api-inventory.yml','acceptance.yml'})

if __name__=='__main__':unittest.main(verbosity=2)
