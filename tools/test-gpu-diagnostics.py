#!/usr/bin/env python3
"""0.77c source, inspector and control-flow tests. All generated receipts are synthetic.

These tests validate the inspector/validator, never claim to execute Racket or GPU
operations. RepositorySources is mandatory when run from the complete checkout.
"""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import gpu_diagnostics_validation as v
ROOT=Path(__file__).resolve().parents[1]
TOKEN='synthetic-077c-token'

def numeric(name,key,value,units='bytes'):
    return dict(kind='numeric',name=name,value_name=key,units=units,value=value)

def textrow(name,key,value):
    return dict(kind='string',name=name,value_name=key,units=False,value=value)

def memory(*,global_=False,detailed=False,wrapped=False,zero=False):
    name='skia/sk_glyph_cache' if global_ else 'skia/gpu_resources/resource_1'
    rows=[] if zero else [numeric(name,'size',4096),textrow(name,'type','Texture'),
                           textrow(name,'label',''),numeric(name,'purgeable_size',4096)]
    n=sum(len(x.encode()) for r in rows for x in (r['name'],r['value_name'],r['units'] if r['kind']=='numeric' else r['value']))
    return dict(scope=v.GLOBAL_SCOPE if global_ else v.GPU_SCOPE,atomic=False,detailed=detailed,
                dump_wrapped=wrapped,truncated=zero,dropped_count=4 if zero else 0,string_bytes=n,entries=rows)

def synthetic_evidence(root,token=TOKEN,backend='egl',adapter='hardware'):
    root=Path(root);root.mkdir(parents=True,exist_ok=True)
    native_backend='opengl' if backend=='egl' else backend
    cache=dict(backend=native_backend,context_generation=11,limit_bytes=32*1024*1024,
               budgeted_resources=2,budgeted_bytes=8192,purgeable_bytes=False,total_gpu_bytes=False,
               limit_is_hard_allocation_cap=False,scope='Ganesh budgeted resource cache; not total VRAM or process RSS')
    reports=dict(cache_before=copy.deepcopy(cache),cache_after=copy.deepcopy(cache),
                 light=memory(),detailed=memory(detailed=True),wrapped=memory(wrapped=True),
                 zero_entries=memory(zero=True),zero_strings=memory(zero=True),zero_bytes=memory(zero=True),
                 global_=memory(global_=True),extra=memory())
    reports['global']=reports.pop('global_')
    captures=[]
    names=['before','after']+(['auto','desktop'] if backend=='egl' else [])+['after-close']
    # Synthetic reference authoring; not Skia output.
    raw=bytearray()
    for y in range(24):
        for x in range(32):
            color=(17,34,51,255)
            if 2<=x<13 and 3<=y<10:color=(229,41,53,255)
            if 15<=x<28 and 10<=y<20:color=(11,179,67,255)
            raw.extend(color)
    for name in names:
        (root/(name+'.rgba')).write_bytes(raw)
        captures.append(dict(name=name,file=name+'.rgba',width=32,height=24))
    interfaces=[]
    if backend=='egl':
        for mode in ('default','auto','desktop'):
            interfaces.append(dict(mode=mode,info=dict(requested=mode,
                factory='assembled-auto' if mode=='auto' else 'assembled-desktop-gl',validated=True,
                extension_source='context-owned-skia-interface'),extension='GL_ARB_framebuffer_object',
                host_extension_present=True,fabricated_extension_present=False))
    life={k:dict(state=state,backend=native_backend,generation=11,live_children=live,pending_releases=0,failed_releases=0)
          for k,state,live in [('after_release','abandoned',2),('after_close','closed',0)]}
    traces=[dict(name=n,events=[]) for n in (*v.TRACE_NAMES,*(v.GL_TRACE_NAMES if backend=='egl' else ()))]
    receipt=dict(schema=1,stage='0.77c',status='passed',run_token=token,native_version='119.0',backend=backend,adapter=adapter,
                 gpu_executed=True,driver_memory_measured=False,process_memory_measured=False,gles_rendering_executed=False,
                 webgl_rendering_executed=False,cases=v.GPU_CASES,failures=0,labels=list(v.LABELS),cleanup_errors=[],
                 reports=reports,diagnostic_traces=traces,captures=captures,interfaces=interfaces,lifecycle=life)
    (root/'gpu.json').write_text(json.dumps(receipt),encoding='utf-8')
    return receipt

class Evidence(unittest.TestCase):
    def setUp(self):
        t=tempfile.TemporaryDirectory();self.addCleanup(t.cleanup);self.root=Path(t.name)
        self.data=synthetic_evidence(self.root)
    def write(self): (self.root/'gpu.json').write_text(json.dumps(self.data),encoding='utf-8')
    def rejects(self):
        self.write()
        with self.assertRaises(ValueError):v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')
    def test_valid_egl(self):self.assertEqual(v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')['status'],'passed')
    def test_valid_metal(self):
        synthetic_evidence(self.root,backend='metal');self.assertEqual(v.inspect(self.root/'gpu.json',TOKEN,'metal','hardware')['gl_factories_executed'],[])
    def test_valid_warp(self):
        synthetic_evidence(self.root,backend='direct3d',adapter='warp');v.inspect(self.root/'gpu.json',TOKEN,'direct3d','warp')
    def test_no_invented_memory_total(self):
        r=v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware');self.assertNotIn('total_bytes',r);self.assertFalse(r['driver_or_process_memory_measured'])
    def test_usage_not_required_to_equal_overlapping_dump_fields(self):
        self.data['reports']['cache_after']['budgeted_bytes']=5555;self.write();v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')
    def test_uint64_exactness(self):
        self.data['reports']['light']['entries'][0]['value']=2**64-1;self.write();v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')
    def test_scope_substitution(self):self.data['reports']['light']['scope']=v.GLOBAL_SCOPE;self.rejects()
    def test_truncation_cannot_hide_full_dump(self):self.data['reports']['light']['truncated']=True;self.rejects()
    def test_dropped_counter(self):self.data['reports']['light']['dropped_count']=1;self.rejects()
    def test_missing_resource_size(self):self.data['reports']['light']['entries'][0]['value']=1;self.rejects()
    def test_no_global_size_as_gpu_evidence(self):self.data['reports']['light']=memory(global_=True);self.rejects()
    def test_unknown_record_kind(self):self.data['reports']['light']['entries'][0]['kind']='pointer';self.rejects()
    def test_boolean_numeric_value(self):self.data['reports']['light']['entries'][0]['value']=True;self.rejects()
    def test_uint64_overflow(self):self.data['reports']['light']['entries'][0]['value']=2**64;self.rejects()
    def test_negative_numeric_value(self):self.data['reports']['light']['entries'][0]['value']=-1;self.rejects()
    def test_fractional_numeric_value(self):self.data['reports']['light']['entries'][0]['value']=3.5;self.rejects()
    def test_wrong_string_units(self):self.data['reports']['light']['entries'][1]['units']='bytes';self.rejects()
    def test_wrong_string_bytes(self):self.data['reports']['light']['string_bytes']+=1;self.rejects()
    def test_overlong_native_string(self):self.data['reports']['light']['entries'][1]['value']='x'*4097;self.rejects()
    def test_embedded_nul(self):self.data['reports']['light']['entries'][1]['value']='x\0y';self.rejects()
    def test_zero_capture_not_empty(self):self.data['reports']['zero_entries']['entries']=self.data['reports']['light']['entries'];self.rejects()
    def test_zero_budget_missing_drops(self):self.data['reports']['zero_bytes']['dropped_count']=0;self.rejects()
    def test_cache_limit_mutated(self):self.data['reports']['cache_after']['limit_bytes']+=1;self.rejects()
    def test_cache_generation_changed(self):self.data['reports']['cache_after']['context_generation']+=1;self.rejects()
    def test_cache_vram_claim(self):self.data['reports']['cache_after']['total_gpu_bytes']=8192;self.rejects()
    def test_flush_trace(self):self.data['diagnostic_traces'][0]['events']=[dict(kind='flush')];self.rejects()
    def test_readback_trace(self):self.data['diagnostic_traces'][0]['events']=[dict(kind='readback')];self.rejects()
    def test_missing_trace(self):self.data['diagnostic_traces'].pop();self.rejects()
    def test_duplicate_trace(self):self.data['diagnostic_traces'][1]=self.data['diagnostic_traces'][0];self.rejects()
    def test_wrong_gl_factory(self):self.data['interfaces'][1]['info']['factory']='native';self.rejects()
    def test_missing_assembly_route(self):self.data['interfaces'].pop();self.rejects()
    def test_extension_disagrees(self):self.data['interfaces'][1]['host_extension_present']=False;self.rejects()
    def test_invented_extension_pass(self):self.data['interfaces'][0]['fabricated_extension_present']=True;self.rejects()
    def test_wrong_extension_source(self):self.data['interfaces'][0]['info']['extension_source']='rebuilt';self.rejects()
    def test_invalid_extension_name(self):self.data['interfaces'][0]['extension']='GL_X GL_Y';self.rejects()
    def test_lifetime_wrong_state(self):self.data['lifecycle']['after_close']['state']='ready';self.rejects()
    def test_children_left_alive(self):self.data['lifecycle']['after_close']['live_children']=1;self.rejects()
    def test_failed_release(self):self.data['lifecycle']['after_release']['failed_releases']=1;self.rejects()
    def test_no_children_at_abandon(self):self.data['lifecycle']['after_release']['live_children']=0;self.rejects()
    def test_pixel_corruption(self):
        p=self.root/'after.rgba';data=bytearray(p.read_bytes());data[200]^=1;p.write_bytes(data)
        with self.assertRaises(ValueError):v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')
    def test_missing_pixels(self):
        (self.root/'after.rgba').unlink()
        with self.assertRaises(ValueError):v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')
    def test_duplicate_json(self):
        p=self.root/'gpu.json';p.write_text(p.read_text().replace('"schema": 1','"schema": 1, "schema": 1'))
        with self.assertRaises(ValueError):v.inspect(p,TOKEN,'egl','hardware')
    def test_symlink_pixel(self):
        p=self.root/'after.rgba';p.unlink()
        try:p.symlink_to(self.root/'before.rgba')
        except OSError:self.skipTest('host cannot create test symlink')
        with self.assertRaises(ValueError):v.inspect(self.root/'gpu.json',TOKEN,'egl','hardware')

# Every field below changes a valid receipt into invalid/misleading evidence.
def change_test(field,value):
    def test(self):self.data[field]=copy.deepcopy(value);self.rejects()
    return test
for field,value in [('schema',True),('stage','0.77b'),('status','failed'),('run_token','old'),('native_version','153.0'),
                    ('backend','metal'),('adapter','warp'),('gpu_executed',False),('driver_memory_measured',True),
                    ('process_memory_measured',True),('gles_rendering_executed',True),('webgl_rendering_executed',True),
                    ('cases',True),('cases',19),('failures',1),('labels',[]),('cleanup_errors',['failed']),('reports',[])]:
    name='test_reject_'+field+('_'+str(value) if field=='cases' else '')
    setattr(Evidence,name,change_test(field,value))

class BoundsAndCompletion(unittest.TestCase):
    def valid(self):return f'{v.PURE_CASES} success(es) 0 failure(s) 0 error(s) {v.PURE_CASES} test(s) run\ngpu-diagnostics-pure: {v.PURE_CASES} cases, 0 failures\n'
    def test_valid(self):v.suite_output(self.valid(),'gpu-diagnostics-pure',v.PURE_CASES)
    def test_crlf(self):v.suite_output(self.valid().replace('\n','\r\n'),'gpu-diagnostics-pure',v.PURE_CASES)
    def test_partial(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid().split('\n')[0],'gpu-diagnostics-pure',v.PURE_CASES)
    def test_duplicate(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid()*2,'gpu-diagnostics-pure',v.PURE_CASES)
    def test_failure(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid().replace('0 error(s)','1 error(s)'),'gpu-diagnostics-pure',v.PURE_CASES)
    def test_error_text(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid()+'ERROR\n','gpu-diagnostics-pure',v.PURE_CASES)
    def test_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            for path in ('../x','/x','a//x','./x','a\\x','a:x','a\nx',''):
                with self.subTest(path=path),self.assertRaises(ValueError):v.safe_file(Path(tmp),path)
    def test_json_not_object(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'x.json';p.write_text('[]')
            with self.assertRaises(ValueError):v.read_json(p)
    def test_json_nonfinite(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'x.json';p.write_text('{"x":NaN}')
            with self.assertRaises(ValueError):v.read_json(p)
    def test_json_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'x.json';p.write_text('{}')
            with patch.object(v,'MAX_JSON',1),self.assertRaises(ValueError):v.read_json(p)

class Orchestration(unittest.TestCase):
    def invoke(self,mode=None,*,failure=None,partial=False,manifest_change=False,backend='egl',missing_racket=False,timeout=False):
        spec=importlib.util.spec_from_file_location('diagnostics_driver_test',ROOT/'tools/validate-gpu-diagnostics.py')
        m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
        commands=[]
        with tempfile.TemporaryDirectory(prefix='diagnostics source ') as tmp:
            root=Path(tmp);(root/'SOURCE-SHA256SUMS.txt').write_text('synthetic manifest\n')
            (root/'run-tests.rkt').write_text('(define-runtime-path another "tests/unrelated-native-test.rkt")\n')
            def execute(command,**kwargs):
                c=list(map(str,command));commands.append(c);name=Path(c[1]).name;out=kwargs['stdout']
                if name==failure:
                    out.write('synthetic selected command failure\n');out.flush()
                    if timeout:raise subprocess.TimeoutExpired(c,1)
                    raise subprocess.CalledProcessError(1,c)
                for suite,count in [('gpu-diagnostics-pure',v.PURE_CASES),('gpu-diagnostics-native',v.NATIVE_CASES)]:
                    if name==suite+'-test.rkt':out.write('partial\n' if partial else f'{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run\n{suite}: {count} cases, 0 failures\n')
                if name=='gpu-diagnostics-gpu-test.rkt':
                    receipt=Path(c[c.index('--report')+1]);token=c[c.index('--token')+1]
                    synthetic_evidence(receipt.parent,token,backend,'hardware')
                    if manifest_change:(root/'SOURCE-SHA256SUMS.txt').write_text('changed\n')
                out.flush();return subprocess.CompletedProcess(c,0)
            args=['--racket','definitely-no-racket' if missing_racket else sys.executable,'--directory',str(root/'out'),'--backend',backend]
            if mode is not None:args+=['--regressions',mode]
            with patch.object(m.shutil,'which',return_value=None if missing_racket else sys.executable),patch.object(m.subprocess,'run',side_effect=execute),contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                rc=m.main(args,root=root)
            report=json.loads((root/'out/validation.json').read_text())
        return rc,report,commands
    def test_default_full(self):
        rc,r,c=self.invoke();self.assertEqual(rc,0);self.assertTrue(r['regressions_passed']);self.assertEqual(r['regressions_status'],'passed')
    def test_none_is_not_run(self):
        rc,r,c=self.invoke('none');self.assertEqual(rc,0);self.assertFalse(r['regressions_passed']);self.assertFalse(r['regressions_attempted']);self.assertEqual(r['regressions_status'],'not-run')
        self.assertFalse(any(Path(c[1]).name=='run-tests.rkt' for c in c))
    def test_feature_commands_preserved(self):
        def names(cs):return [Path(c[1]).name for c in cs if c[1]!='-l' and Path(c[1]).name!='run-tests.rkt']
        self.assertEqual(names(self.invoke('full')[2]),names(self.invoke('none')[2]))
    def test_no_unrelated_compile_in_none(self):
        args=next(c for c in self.invoke('none')[2] if 'make' in c)
        self.assertFalse(any('unrelated' in n or n.endswith('run-tests.rkt') for n in args))
        self.assertTrue(any(n.replace('\\','/').endswith('tests/gpu-diagnostics-native-test.rkt') for n in args))
    def test_full_compile_graph(self):
        args=next(c for c in self.invoke('full')[2] if 'make' in c)
        self.assertTrue(any(n.replace('\\','/').endswith('tests/unrelated-native-test.rkt') for n in args))
    def test_metal_selected(self):self.assertEqual(self.invoke('none',backend='metal')[0],0)
    def test_direct3d_selected(self):self.assertEqual(self.invoke('none',backend='direct3d')[0],0)
    def test_source_failure(self):self.assertEqual(self.invoke(failure='api-inventory.py')[0],1)
    def test_global_failure_stops_features(self):
        rc,r,c=self.invoke(failure='run-tests.rkt');self.assertEqual(rc,1);self.assertEqual(r['regressions_status'],'failed');self.assertFalse(r['pure_passed'])
    def test_native_failure_stops_gpu(self):
        rc,r,c=self.invoke('none',failure='gpu-diagnostics-native-test.rkt');self.assertEqual(rc,1);self.assertFalse(r['gpu_executed'])
        self.assertFalse(any(Path(x[1]).name=='gpu-diagnostics-gpu-test.rkt' for x in c))
    def test_example_failure(self):self.assertEqual(self.invoke('none',failure='gpu-diagnostics.rkt')[0],1)
    def test_gpu_failure(self):
        rc,r,c=self.invoke('none',failure='gpu-diagnostics-gpu-test.rkt');self.assertEqual(rc,1);self.assertFalse(r['byte_oracles_passed']);self.assertEqual(r['commands'][-1]['status'],'failed')
    def test_timeout(self):self.assertEqual(self.invoke('none',failure='gpu-diagnostics-gpu-test.rkt',timeout=True)[0],1)
    def test_partial_native_suite(self):self.assertEqual(self.invoke('none',partial=True)[0],1)
    def test_manifest_mutation(self):self.assertEqual(self.invoke('none',manifest_change=True)[0],1)
    def test_no_racket_is_not_a_skip(self):
        rc,r,c=self.invoke('none',missing_racket=True);self.assertEqual(rc,1);self.assertFalse(r['gpu_executed']);self.assertEqual(c,[])

class PayloadSources(unittest.TestCase):
    def test_case_counts(self):
        for kind,n in [('pure',v.PURE_CASES),('native',v.NATIVE_CASES)]:
            text=(ROOT/f'tests/gpu-diagnostics-{kind}-test.rkt').read_text()
            self.assertEqual(text.count('(test-case '),n)
            self.assertIn(f'(define gpu-diagnostics-{kind}-test-count {n})',text)
    def test_gpu_labels_match_required_receipt(self):
        text=(ROOT/'tests/gpu-diagnostics-gpu-test.rkt').read_text()
        self.assertEqual(re.findall(r'^      \(test! "([^"]+)"',text,re.M),list(v.LABELS))
        self.assertIn(f'(define GPU-CASES {v.GPU_CASES})',text)
    def test_no_transfer_or_completion_in_diagnostic_module(self):
        text=(ROOT/'private/gpu-diagnostics-native.rkt').read_text()
        for forbidden in ('gr_direct_context_flush','gr_direct_context_submit','read_pixels','sk_image_make_raster','gpu-wait!'):
            self.assertNotIn(forbidden,text)
    def test_no_third_party_callback_table(self):
        text=(ROOT/'private/gpu-diagnostics-native.rkt').read_text()
        self.assertIn('collect-memory-statistics/native',text);self.assertNotIn('sk_managedtracememorydump_set_procs',text)
    def test_explicit_standard_checked(self):
        text=(ROOT/'private/gpu-gl-interface.rkt').read_text()
        self.assertIn('gl-version-standard',text);self.assertIn('gl-interface-standard',text)
        self.assertLess(text.index('gl-interface-standard'),text.index('(native-call mode #f callback)'))
    def test_retained_interface_destroyed_once(self):
        text=(ROOT/'private/gpu-gl-interface.rkt').read_text();part=text[text.index('(define (release-gl-interface!'):]
        self.assertLess(part.index('(hash-remove!'),part.index("(native-call 'unref"))

@unittest.skipUnless((ROOT/'gpu.rkt').is_file(),'complete-checkout integration, not available in payload-only delivery')
class RepositorySources(unittest.TestCase):
    def test_registry_and_export_wiring(self):
        s=(ROOT/'private/gpu-native.rkt').read_text()
        for name in ('gr_direct_context_dump_memory_statistics','gr_glinterface_assemble_interface','gr_glinterface_assemble_gles_interface','gr_glinterface_assemble_webgl_interface','gr_glinterface_has_extension'):
            self.assertEqual(len(re.findall(r'\(define-gpu-native\s+\w+\s+'+name+r'\b',s)),1)
        self.assertIn('(all-from-out "gpu-diagnostics.rkt")',(ROOT/'gpu.rkt').read_text())
        self.assertIn("'test-gpu-diagnostics.py'",(ROOT/'tools/ci.py').read_text())
    def test_workflow_preserves_separate_gates(self):
        s=(ROOT/'.github/workflows/gpu-context-controls.yml').read_text()
        self.assertEqual(s.count('tools/validate-gpu-diagnostics.py'),2)
        self.assertEqual(s.count('tools/validate-gpu-context-controls.py'),2)
        calls=re.findall(r'python tools/validate-gpu-diagnostics\.py(.*?)(?=\n\s*- name:|\Z)',s,re.S)
        self.assertEqual(len(calls),2)
        for call in calls:self.assertIn('--regressions none',call)
        auto={p.name for p in (ROOT/'.github/workflows').glob('*.yml') if '\n  push:' in p.read_text() or '\n  pull_request:' in p.read_text()}
        self.assertEqual(auto,{'ci.yml','acceptance.yml','api-inventory.yml'})
    def test_public_docs_and_global_scope_preserved(self):
        s=(ROOT/'docs/GPU-DIAGNOSTICS.md').read_text()
        for name in ('gpu-memory-statistics','gpu-gl-interface-info','gpu-gl-has-extension?','#:gl-interface'):self.assertIn(name,s)
        self.assertIn('process-global-skia-caches',(ROOT/'private/graphics-data.rkt').read_text())
        self.assertIn('gpu-context-skia-resources',(ROOT/'private/graphics-data.rkt').read_text())
        self.assertIn('(define version "0.78")',(ROOT/'info.rkt').read_text())

if __name__=='__main__':unittest.main(verbosity=2)
