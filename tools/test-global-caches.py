#!/usr/bin/env python3
"""Source contracts and synthetic inspector/orchestration tests, not native execution."""
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
import global_cache_validation as v
ROOT=Path(__file__).resolve().parents[1]
TOKEN='synthetic-cache-test'

def synthetic_evidence(root,token=TOKEN):
    root=Path(root);root.mkdir(parents=True,exist_ok=True)
    before=[2097152,2048,33554432,0]
    counters=dict(zip(v.LIMIT_KEYS,v.REQUESTED))
    counters.update({'font-bytes-used':4096,'font-count-used':1,'resource-bytes-used':0,'scope':v.SCOPE,'atomic?':False})
    rows=[dict(kind='numeric',name='skia/sk_glyph_cache',value_name=key,units=units,value=value)
          for key,units,value in [('size','bytes',4096),('budget_size','bytes',8388608),
                                  ('glyph_count','objects',1),('budget_glyph_count','objects',256)]]
    size=sum(len(row[k].encode()) for row in rows for k in ('name','value_name','units'))
    def snap(detail):return dict(scope=v.SCOPE,atomic=False,detailed=detail,dump_wrapped=False,truncated=False,dropped_count=0,string_bytes=size,entries=copy.deepcopy(rows))
    r=dict(schema=1,stage='0.77a',status='passed',run_token=token,native_version='119.0',scope=v.SCOPE,
           gpu_executed=False,process_memory_measured=False,driver_memory_measured=False,
           trace_extension_symbols_resolved=3,limits_before=before,limits_requested=v.REQUESTED,
           setter_previous=before,limits_observed=v.REQUESTED,limits_restored=before,
           purges=[dict(cache=name,before=[1,1,1,524288],after=[1,1,1,524288]) for name in ('font','resource','all')],
           counters=counters,light=snap(False),detailed=snap(True),
           truncated=dict(scope=v.SCOPE,atomic=False,detailed=False,dump_wrapped=False,truncated=True,dropped_count=4,string_bytes=0,entries=[]))
    (root/'global-caches.json').write_text(json.dumps(r),encoding='utf-8')
    for name in ('before.rgba','limited.rgba','purge-font.rgba','purge-resource.rgba','purge-all.rgba'):
        (root/name).write_bytes(v.pixels())
    (root/'font.rgba').write_bytes(bytes((0,0,0,255))+bytes((255,255,255,255))*(80*48-1))
    return r

class Completion(unittest.TestCase):
    def valid(self):return f'{v.PURE_CASES} success(es) 0 failure(s) 0 error(s) {v.PURE_CASES} test(s) run\nglobal-cache-pure: {v.PURE_CASES} cases, 0 failures\n'
    def test_valid(self):v.suite_output(self.valid(),'global-cache-pure',v.PURE_CASES)
    def test_crlf(self):v.suite_output(self.valid().replace('\n','\r\n'),'global-cache-pure',v.PURE_CASES)
    def test_empty(self):
        with self.assertRaises(ValueError):v.suite_output('','global-cache-pure',v.PURE_CASES)
    def test_missing_receipt(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid().split('\n')[0],'global-cache-pure',v.PURE_CASES)
    def test_duplicate(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid()*2,'global-cache-pure',v.PURE_CASES)
    def test_wrong_count(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid(),'global-cache-pure',v.PURE_CASES+1)
    def test_failure(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid().replace('0 failure(s)','1 failure(s)'),'global-cache-pure',v.PURE_CASES)
    def test_error_marker(self):
        with self.assertRaises(ValueError):v.suite_output(self.valid()+'ERROR\n','global-cache-pure',v.PURE_CASES)

class Evidence(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.r=synthetic_evidence(self.root)
    def write(self):(self.root/'global-caches.json').write_text(json.dumps(self.r))
    def rejects(self):
        self.write()
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def test_valid(self):self.assertEqual(v.inspect(self.root,TOKEN)['status'],'passed')
    def test_wrong_token(self):self.r['run_token']='old';self.rejects()
    def test_failed_status(self):self.r['status']='failed';self.rejects()
    def test_schema_bool(self):self.r['schema']=True;self.rejects()
    def test_wrong_abi(self):self.r['native_version']='153.0';self.rejects()
    def test_wrong_scope(self):self.r['scope']='gpu';self.rejects()
    def test_rss_claim(self):self.r['process_memory_measured']=True;self.rejects()
    def test_driver_claim(self):self.r['driver_memory_measured']=True;self.rejects()
    def test_gpu_claim(self):self.r['gpu_executed']=True;self.rejects()
    def test_extension_resolution(self):self.r['trace_extension_symbols_resolved']=2;self.rejects()
    def test_restoration(self):self.r['limits_restored']=[1,1,1,1];self.rejects()
    def test_prior_value(self):self.r['setter_previous']=[1,1,1,1];self.rejects()
    def test_observed_value(self):self.r['limits_observed']=[1,1,1,1];self.rejects()
    def test_bool_integer(self):self.r['limits_before']=[True,2048,33554432,0];self.rejects()
    def test_purge_mutation(self):self.r['purges'][0]['after']=[2,1,1,524288];self.rejects()
    def test_missing_purge(self):self.r['purges'].pop();self.rejects()
    def test_wrong_purge_order(self):self.r['purges'].reverse();self.rejects()
    def test_font_work_not_observed(self):self.r['counters']['font-bytes-used']=0;self.rejects()
    def test_atomic_claim(self):self.r['light']['atomic']=True;self.rejects()
    def test_count_only_is_not_byte_measurement(self):
        self.r['light']['entries']=[x for x in self.r['light']['entries'] if x['units']=='objects'];self.rejects()
    def test_dump_query_disagreement(self):self.r['light']['entries'][0]['value']=1;self.rejects()
    def test_missing_named_measurement(self):self.r['light']['entries'][0]['name']='other';self.rejects()
    def test_duplicate_named_measurement(self):self.r['light']['entries'].append(copy.deepcopy(self.r['light']['entries'][0]));self.rejects()
    def test_native_uint64_overflow(self):self.r['detailed']['entries'][0]['value']=1<<64;self.rejects()
    def test_negative_measurement(self):self.r['light']['entries'][0]['value']=-1;self.rejects()
    def test_inexact_measurement(self):self.r['light']['entries'][0]['value']=4096.0;self.rejects()
    def test_budget_accounting(self):self.r['light']['string_bytes']=0;self.rejects()
    def test_unbounded_string(self):self.r['light']['entries'][0]['name']='x'*4097;self.rejects()
    def test_truncation_hidden(self):self.r['truncated']['truncated']=False;self.rejects()
    def test_truncation_count_missing(self):self.r['truncated']['dropped_count']=0;self.rejects()
    def test_full_report_truncated(self):self.r['light']['truncated']=True;self.rejects()
    def test_wrong_details(self):self.r['detailed']['detailed']=False;self.rejects()
    def test_pixel_change(self):
        (self.root/'limited.rgba').write_bytes(b'\0'*192)
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def test_missing_pixels(self):
        (self.root/'purge-all.rgba').unlink()
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def test_blank_font(self):
        (self.root/'font.rgba').write_bytes(bytes((255,255,255,255))*80*48)
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)
    def test_duplicate_json(self):
        p=self.root/'global-caches.json';p.write_text(p.read_text().replace('"schema": 1','"schema": 1, "schema": 1'))
        with self.assertRaises(ValueError):v.inspect(self.root,TOKEN)

class Orchestration(unittest.TestCase):
    def invoke(self,mode=None,failure=None,partial=False,mutate=False):
        spec=importlib.util.spec_from_file_location('cache_driver_test',ROOT/'tools/validate-global-caches.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        commands=[]
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'SOURCE-SHA256SUMS.txt').write_text('synthetic manifest\n')
            (root/'run-tests.rkt').write_text('(define-runtime-path unrelated "tests/unrelated-native-test.rkt")\n')
            def execute(command,**kwargs):
                command=list(map(str,command));commands.append(command);out=kwargs['stdout']
                name=Path(command[1]).name if len(command)>1 else ''
                if name==failure:
                    out.write('synthetic failure\n');out.flush();raise subprocess.CalledProcessError(1,command)
                for suite,count in (('global-cache-pure',v.PURE_CASES),('global-cache-native',v.NATIVE_CASES)):
                    if name==suite+'-test.rkt':out.write('incomplete\n' if partial else f'{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run\n{suite}: {count} cases, 0 failures\n')
                if name=='global-cache-doctor.rkt':
                    synthetic_evidence(command[command.index('--directory')+1],command[command.index('--token')+1])
                    if mutate:(root/'SOURCE-SHA256SUMS.txt').write_text('changed')
                out.flush();return subprocess.CompletedProcess(command,0)
            args=['--racket',sys.executable,'--directory',str(root/'out')]
            if mode is not None:args+=['--regressions',mode]
            with patch.object(module.shutil,'which',return_value=sys.executable),patch.object(module.subprocess,'run',side_effect=execute),contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                rc=module.main(args,root=root)
            report=json.loads((root/'out/validation.json').read_text())
        return rc,report,commands
    def test_default_full(self):
        rc,r,_=self.invoke();self.assertEqual(rc,0);self.assertEqual(r['regressions_status'],'passed')
    def test_none_not_passed(self):
        rc,r,_=self.invoke('none');self.assertEqual(rc,0);self.assertFalse(r['regressions_passed']);self.assertEqual(r['regressions_status'],'not-run')
    def test_none_compile(self):
        _,_,c=self.invoke('none');args=next(x for x in c if 'make' in x)
        names=[str(x).replace('\\','/') for x in args]
        self.assertFalse(any('unrelated' in x or x.endswith('/run-tests.rkt') for x in names))
        self.assertTrue(any(x.endswith('tests/global-cache-native-test.rkt') for x in names))
    def test_full_compile(self):
        _,_,c=self.invoke();args=next(x for x in c if 'make' in x)
        self.assertTrue(any(str(x).replace('\\','/').endswith('tests/unrelated-native-test.rkt') for x in args))
    def test_feature_commands_preserved(self):
        def commands(rows):return [Path(x[1]).name for x in rows if x[1]!='-l' and Path(x[1]).name!='run-tests.rkt']
        self.assertEqual(commands(self.invoke('full')[2]),commands(self.invoke('none')[2]))
    def test_native_failure(self):
        rc,r,c=self.invoke('none',failure='global-cache-native-test.rkt');self.assertEqual(rc,1);self.assertFalse(r['byte_oracles_passed'])
        self.assertFalse(any(Path(x[1]).name=='global-cache-doctor.rkt' for x in c))
    def test_global_failure(self):self.assertEqual(self.invoke(failure='run-tests.rkt')[0],1)
    def test_pure_failure(self):self.assertEqual(self.invoke('none',failure='global-cache-pure-test.rkt')[0],1)
    def test_partial_suite(self):self.assertEqual(self.invoke('none',partial=True)[0],1)
    def test_changed_manifest(self):self.assertEqual(self.invoke('none',mutate=True)[0],1)
    def test_failed_source(self):self.assertEqual(self.invoke('none',failure='api-inventory.py')[0],1)
    def test_failed_example(self):self.assertEqual(self.invoke('none',failure='global-caches.rkt')[0],1)
    def test_execution_flags(self):
        rc,r,_=self.invoke('none');self.assertEqual(rc,0)
        self.assertTrue(r['global_cache_controls_executed']);self.assertTrue(r['memory_statistics_executed']);self.assertFalse(r['gpu_executed'])

class Sources(unittest.TestCase):
    def text(self,name):return (ROOT/name).read_text(encoding='utf-8')
    def test_counts(self):
        for kind,count in (('pure',v.PURE_CASES),('native',v.NATIVE_CASES)):
            s=self.text(f'tests/global-cache-{kind}-test.rkt')
            self.assertEqual(s.count('(test-case '),count);self.assertIn(f'(define global-cache-{kind}-test-count {count})',s)
    def test_exact_graphics_registry(self):
        import api_inventory as inv
        side=inv.read_json(ROOT/'api/upstream-m119.json')
        expected=set(side['headers']['include/c/sk_graphics.h'])
        actual=set(inv.scan_bindings(ROOT)['symbols'])
        self.assertEqual(len(expected),16);self.assertTrue(expected<=actual)
    def test_trace_extensions(self):
        import api_inventory as inv
        from global_cache_ffi import checked_imports
        self.assertEqual(len(checked_imports(ROOT,inv.forms,inv.String)),3)
    def test_registered(self):
        self.assertIn('(run-tests global-cache-pure-tests)',self.text('run-tests.rkt'))
        self.assertIn("dynamic-require global-cache-native-tests-file 'global-cache-native-tests",self.text('run-tests.rkt'))
        self.assertIn("'test-global-caches.py'",self.text('tools/ci.py'))
    def test_current_version(self):self.assertIn('(define version "0.78")',self.text('info.rkt'))
    def test_workflow_wiring(self):
        self.assertIn('test "$GLOBAL_CACHES_RESULT" = success',self.text('.github/workflows/acceptance.yml'))
        child=self.text('.github/workflows/global-caches.yml')
        self.assertIn('workflow_call:',child);self.assertNotIn('\n  push:',child)
        self.assertIn('--regressions "$SKIA_REGRESSIONS_MODE"',child)
        self.assertIn('--regressions "$env:SKIA_REGRESSIONS_MODE"',child)
    def test_public_names_documented(self):
        import api_inventory as inv
        doc=self.text('docs/GLOBAL-CACHES.md')
        for name in inv.source_exports(ROOT,'graphics.rkt'):self.assertIn(name,doc)
    def test_trace_no_user_callback_path(self):
        text=self.text('private/graphics-trace-native.rkt')
        self.assertNotIn('call-in-os-thread',text);self.assertNotIn('read-bytes',text);self.assertNotIn('write-bytes',text)
        self.assertIn('(parameterize-break #f',text);self.assertIn('(call-as-atomic',text)
        self.assertIn('(lambda (_) #t)',text)
    def test_global_not_gpu_controls(self):
        self.assertNotIn('gr_direct_context',self.text('graphics.rkt'))
        self.assertIn('global-memory-statistics/native',self.text('graphics.rkt'))

if __name__=='__main__':unittest.main(verbosity=2)
