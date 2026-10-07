#!/usr/bin/env python3
"""Parity policy, orchestration and source-integration regressions.

Temporary reports below are deliberately synthetic; they never count as GPU
execution. Integration tests require the full source tree, without skip logic.
"""
from __future__ import annotations
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch
import gpu_backend_policy as policy
import gpu_parity as parity

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def context(backend='direct3d', selection='warp', index=0):
    c = dict(backend=backend, native_backend=policy.BACKEND_IDS[backend], generation=1,
             live_children=0, pending_releases=0, failed_releases=0, state='ready',
             shutdown_requested=False, binding_package='3.119.1', native_version='119.0',
             renderer='Synthetic adapter', renderer_class='software', vendor='Synthetic', api_version='Synthetic')
    if backend == 'direct3d':
        c.update(api='D3D12', command_queue_owned=True, command_queue_type='direct',
                 adapter_selection=selection, adapter_index=False if selection == 'warp' else index,
                 d3d12_warp=selection == 'warp', adapter_flags=2 if selection == 'warp' else 0,
                 renderer_class='software' if selection == 'warp' else 'hardware-reported',
                 hardware_acceleration_verified=False, adapter_name='Synthetic adapter',
                 adapter_vendor_id=0x1414, adapter_device_id=0x8c, adapter_luid_low=17, adapter_luid_high=0,
                 minimum_feature_level=0xb000)
        c.pop('vendor'); c.pop('api_version')
    return c


def present_event():
    return dict(kind='present-request', backend='direct3d', method='dxgi-same-queue', result='submitted',
                hresult=0, wait_requested=False, buffer_index=0, swap_chain_generation=1, fence_value=1)


def source_fixture(root):
    for name in parity.SOURCE_PATHS:
        path=root/name; path.parent.mkdir(parents=True,exist_ok=True); path.write_text('; synthetic workload ' + name)
    (root/'SOURCE-SHA256SUMS.txt').write_text('synthetic manifest; subprocess verification is injected')


def reports(root, directory, name, backend='direct3d', adapter='warp', index=0):
    _,_,stage,kind,count=parity.SUITES[name]
    identity=dict(os='windows',architecture='x86_64',version='9.3',vm='chez-scheme',pointer_bytes=8)
    host=dict(headless=True,window_created=False,requires_gui=False,requires_gl_context=False)
    raw=dict(schema_version=1,stage=stage,kind=kind,status='passed',backend=backend,required=True,
             validation_run=directory.name,os=identity['os'],architecture=identity['architecture'],
             racket_version=identity['version'],host=host,initial_context=context(backend,adapter,index),
             native_test_cases=count,native_test_failures=0)
    inspected=dict(schema_version=1,stage=stage,kind=kind,status='passed',backend=backend)
    if name=='offscreen':
        inspected.update(scenes_checked=8,rendering_verified=True,detached_image_survived_teardown=True)
    if name=='images':
        raw.update(scenes=[{},{}],detached_survived_teardown=True)
        inspected.update(scenes_checked=2,rendering_verified=True,detached_image_survived_teardown=True,
                         resident_replay_readbacks=0,resident_replay_explicit_cpu_waits=0)
    if name=='output':
        inspected.update(documents_checked=16,gpu_group_readbacks=8,documents_serialized_after_gpu_teardown=True,
                         embedded_svg_pixels_verified=True,pdf_structure_verified=True,
                         vector_surroundings_and_links_verified=True,pdf_rendered_pixels_verified=False)
    if name in ('performance','redraw'):
        sources=[dict(path=p,sha1=hashlib.sha1((root/p).read_bytes()).hexdigest()) for p in parity.SOURCE_PATHS]
        raw.update(config=parity.CONFIG.copy(),performance_measured=True,speedup_claimed=False,
                   display_latency_measured=False,workload_sources=sources)
        inspected.update(config=parity.CONFIG.copy(),resource_envelopes_verified=True)
        if name=='performance': raw.update(scenes=[{}, {}, {}],cycles=[dict(frames=180) for _ in range(3)])
        else: raw.update(windows=[dict(frames=[{} for _ in range(180)]) for _ in range(6)])
    return raw,inspected,identity


class PolicyTests(unittest.TestCase):
    def test_ids(self): self.assertEqual(dict(policy.BACKEND_IDS),dict(opengl=0,metal=2,direct3d=3))
    def test_declarations_not_probe(self):
        for b in policy.BACKEND_IDS:
            c=policy.declared_capabilities(b)
            self.assertEqual(c['runtime_availability'],'not-probed')
            self.assertFalse(c['native_probe_performed']);self.assertFalse(c['hardware_acceleration_verified'])
    def test_declarations_detached(self):
        c=policy.declared_capabilities('direct3d');c['features']['offscreen']=False
        self.assertTrue(policy.declared_capabilities('direct3d')['features']['offscreen'])
    def test_common_features(self):
        for b in policy.BACKEND_IDS:
            for f in policy.FEATURES-{'external_resource_interop'}:self.assertTrue(policy.declared_capabilities(b)['features'][f])
    def test_interop_support_is_backend_specific(self):
        self.assertTrue(policy.declared_capabilities('direct3d')['features']['external_resource_interop'])
        self.assertTrue(policy.declared_capabilities('metal')['features']['external_resource_interop'])
    def test_unknown_backend(self):
        for b in ('vulkan','auto','raster',False):
            with self.assertRaises(ValueError):policy.declared_capabilities(b)
    def test_catalog_duplicate_id(self):
        c=copy.deepcopy(policy._CATALOG);c['backends'][2]['native_backend']=0
        with self.assertRaises(ValueError):policy.validate_catalog(c)
    def test_catalog_bool_id(self):
        c=copy.deepcopy(policy._CATALOG);c['backends'][0]['native_backend']=False
        with self.assertRaises(ValueError):policy.validate_catalog(c)
    def test_catalog_missing_feature(self):
        c=copy.deepcopy(policy._CATALOG);c['backends'][2]['features'].pop('document_executor')
        with self.assertRaises(ValueError):policy.validate_catalog(c)
    def test_explicit_warp(self):self.assertEqual(policy.selection('direct3d','owned','warp',0),('warp',0))
    def test_hardware_default_not_fallback(self):self.assertEqual(policy.selection('direct3d','owned'),('hardware',0))
    def test_bad_selections(self):
        for args in [('opengl','owned',None,None),('metal','egl',None,None),('opengl','gui','warp',0),
                     ('direct3d','owned','auto',0),('direct3d','owned','warp',1),
                     ('direct3d','owned','hardware',True),('direct3d','owned','hardware',-1)]:
            with self.assertRaises(ValueError):policy.selection(*args)
    def test_real_d3d_identity_fields(self):policy.check_backend_context(context(),'direct3d',adapter='warp',adapter_index=0)
    def test_no_fake_gl_driver_strings_required(self):
        c=context();self.assertNotIn('api_version',c);self.assertNotIn('vendor',c)
        self.assertIn('D3D12',policy.context_api_label(c,'direct3d'))
        self.assertTrue(policy.context_signature(c,'direct3d'))
    def test_wrong_native_id(self):
        c=context();c['native_backend']=False
        with self.assertRaises(ValueError):policy.check_backend_context(c,'direct3d')
    def test_hardware_must_match_request(self):
        with self.assertRaises(ValueError):policy.check_backend_context(context(selection='hardware'),'direct3d',adapter='warp')
    def test_no_hardware_attestation(self):
        c=context();c['hardware_acceleration_verified']=True
        with self.assertRaises(ValueError):policy.check_backend_context(c,'direct3d')
    def test_bad_luid(self):
        c=context();c['adapter_luid_low']=True
        with self.assertRaises(ValueError):policy.check_backend_context(c,'direct3d')
    def test_unowned_queue(self):
        c=context();c['command_queue_owned']=False
        with self.assertRaises(ValueError):policy.check_backend_context(c,'direct3d')
    def test_wrong_adapter_flags(self):
        c=context();c['adapter_flags']=0
        with self.assertRaises(ValueError):policy.check_backend_context(c,'direct3d')
    def test_warp_has_no_hardware_index(self):
        c=context();c['adapter_index']=0
        with self.assertRaises(ValueError):policy.check_backend_context(c,'direct3d')
    def test_wrong_host(self):
        r=dict(os='windows',architecture='x86_64',host=dict(headless=True,window_created=True))
        with self.assertRaises(ValueError):policy.check_backend_host(r,'direct3d')
    def test_duplicate_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'a.json';p.write_text('{"x":1,"x":2}')
            with self.assertRaisesRegex(ValueError,'duplicate'):policy.read_json(p)
    def test_nonfinite_json(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'a.json';p.write_text('{"x":NaN}')
            with self.assertRaisesRegex(ValueError,'non-finite'):policy.read_json(p)
    def test_occlusion_not_measured_success(self):
        e=present_event();e.update(result='occluded',hresult=0x087a0001)
        with self.assertRaises(ValueError):policy.check_dxgi_present_event(e)
    def test_boolean_hresult(self):
        e=present_event();e['hresult']=False
        with self.assertRaises(ValueError):policy.check_dxgi_present_event(e)


class FenceTests(unittest.TestCase):
    def window(self):
        row=lambda a,b:dict(backend_fence_waits=a,retry_backend_fence_waits=b,
                           backend_fence_waits_included_in_elapsed=True,io_events=[present_event()])
        return dict(warmup=row(1,0),frames=[row(2,1)],measured_backend_fence_waits=4,
                    backend_fence_waits_outside_samples=3,closed_presenter=dict(adapter=dict(blocking_fence_waits=7,
                    queue_ownership='context-driver',buffer_count=2,swap_effect='flip-discard')),
                    checkpoints=[dict(presenter=dict(adapter=dict(presentation_context_children=1,
                                                                  quarantined=False,quarantined_frames=0)))])
    def test_complete(self):policy.check_redraw_fence_accounting(self.window())
    def test_no_hidden_waits(self):
        w=self.window();w['closed_presenter']['adapter']['blocking_fence_waits']+=1
        with self.assertRaises(ValueError):policy.check_redraw_fence_accounting(w)
    def test_measured_waits_not_fabricated(self):
        w=self.window();w['measured_backend_fence_waits']=5
        with self.assertRaises(ValueError):policy.check_redraw_fence_accounting(w)
    def test_bool_counts(self):
        w=self.window();w['warmup']['backend_fence_waits']=True
        with self.assertRaises(ValueError):policy.check_redraw_fence_accounting(w)
    def test_pin_not_zero(self):
        w=self.window();w['checkpoints'][0]['presenter']['adapter']['presentation_context_children']=0
        with self.assertRaises(ValueError):policy.check_redraw_fence_accounting(w)
    def test_wait_timing_disclaimer(self):
        w=self.window();w['warmup']['backend_fence_waits_included_in_elapsed']=False
        with self.assertRaises(ValueError):policy.check_redraw_fence_accounting(w)


class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);source_fixture(self.root)
        self.directory=self.root/'unique-run';self.directory.mkdir()
    def validate(self,name,change=None):
        raw,checked,identity=reports(self.root,self.directory,name)
        if change:change(raw,checked)
        return parity.check_receipt(name,raw,checked,root=self.root,run_id=self.directory.name,
                                    identity=identity,backend='direct3d',adapter='warp',adapter_index=0)
    def bad(self,name,change):
        with self.assertRaises((ValueError,KeyError,TypeError)):self.validate(name,change)
    def test_all_suites(self):
        for name in parity.SUITES:self.assertEqual(self.validate(name)['status'],'passed')
    def test_foreign_run(self):self.bad('offscreen',lambda r,i:r.update(validation_run='foreign'))
    def test_optional(self):self.bad('output',lambda r,i:r.update(required=False))
    def test_native_failed(self):self.bad('output',lambda r,i:r.update(native_test_failures=1))
    def test_bool_native_count(self):self.bad('images',lambda r,i:r.update(native_test_failures=False))
    def test_no_inspection(self):self.bad('output',lambda r,i:i.update(status='unavailable'))
    def test_wrong_interpreter(self):self.bad('offscreen',lambda r,i:r.update(racket_version='8.7'))
    def test_wrong_backend(self):self.bad('offscreen',lambda r,i:i.update(backend='metal'))
    def test_wrong_adapter(self):self.bad('offscreen',lambda r,i:r.update(initial_context=context(selection='hardware')))
    def test_short_scenes(self):self.bad('offscreen',lambda r,i:i.update(scenes_checked=7))
    def test_short_documents(self):self.bad('output',lambda r,i:i.update(documents_checked=8))
    def test_document_teardown(self):self.bad('output',lambda r,i:i.update(documents_serialized_after_gpu_teardown=False))
    def test_fake_pdf_pixels(self):self.bad('output',lambda r,i:i.update(pdf_rendered_pixels_verified=True))
    def test_short_timing(self):self.bad('performance',lambda r,i:r['config'].update(samples=3))
    def test_short_stress(self):self.bad('performance',lambda r,i:r['cycles'][0].update(frames=60))
    def test_short_redraw(self):self.bad('redraw',lambda r,i:r['windows'][0]['frames'].pop())
    def test_fingerprint_wrong(self):self.bad('performance',lambda r,i:r['workload_sources'][0].update(sha1='0'*40))
    def test_device_changes(self):
        def change(r,i):
            r['other_context']=context();r['other_context']['adapter_luid_low']=18
        self.bad('images',change)
    def test_pin_change(self):self.bad('output',lambda r,i:r['initial_context'].update(binding_package='4.153.1'))


class RunnerTests(unittest.TestCase):
    def simulate(self,fail=None,change=None,scope='offscreen',identity_change=None):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);source_fixture(root);directory=root/'unique-run';directory.mkdir();calls=[]
            current={}
            def run(argv):
                a=[str(x) for x in argv];calls.append(a)
                if fail and any(fail in x for x in a):raise RuntimeError('synthetic subprocess failure')
                if a[1].endswith('ci-identity.rkt'):
                    identity=dict(os='windows',architecture='x86_64',version='9.3',vm='chez-scheme',pointer_bytes=8)
                    if identity_change:identity_change(identity)
                    return json.dumps(identity)
                if a[1].endswith('gpu-backend-doctor.rkt'):
                    return json.dumps(dict(schema=1,native_probe_performed=False,
                                           backends=[policy.declared_capabilities(b) for b in policy.BACKEND_IDS]))
                if '--prefix' in a:
                    name=Path(a[a.index('--prefix')+1]).name
                    raw,inspection,_=reports(root,directory,name)
                    if change:change(name,raw,inspection,root)
                    parity.write_json(directory/(name+'.diagnostic.json'),raw);current[name]=inspection
                if '--probe-prefix' in a:
                    name=Path(a[a.index('--probe-prefix')+1]).name
                    parity.write_json(directory/(name+'.inspection.json'),current[name])
                return ''
            try:
                result=parity.execute(root,'/selected Racket/racket',directory,run,backend='direct3d',
                                      host='owned',adapter='warp',adapter_index=0,scope=scope)
            except BaseException:
                self.assertFalse((directory/parity.RESULT).exists())
                self.assertTrue((directory/parity.FAILURE).exists())
                raise
            self.assertTrue((directory/parity.RESULT).exists());self.assertFalse((directory/parity.FAILURE).exists())
            return calls,result
    def test_order_full_workload_and_explicit_selection(self):
        calls,r=self.simulate(scope='all')
        self.assertEqual(r['native_test_cases'],137);self.assertEqual(r['presentation_stress_frames'],1080)
        self.assertEqual(r['offscreen_stress_frames'],540);self.assertEqual(r['documents_checked'],16)
        self.assertEqual([x['name'] for x in r['suites']],list(parity.SUITES))
        for a in calls:
            if a[1].endswith('.rkt') or 'raco' in a:self.assertEqual(a[0],'/selected Racket/racket')
            if '--prefix' in a:self.assertIn('warp',a);self.assertIn('direct3d',a)
            if 'gpu-performance-doctor.rkt' in Path(a[1]).name or 'gpu-redraw-doctor.rkt' in Path(a[1]).name:
                self.assertEqual(a[-len(parity.TIMING_ARGS):],parity.TIMING_ARGS)
        self.assertEqual(sum('--manifest-only' in a for a in calls),2)
    def test_offscreen_scope(self):self.assertEqual(len(self.simulate()[1]['suites']),4)
    def test_presentation_scope(self):self.assertEqual([x['name'] for x in self.simulate(scope='presentation')[1]['suites']],['redraw'])
    def test_compile_failure(self):
        with self.assertRaises(RuntimeError):self.simulate(fail='raco')
    def test_doctor_failure(self):
        with self.assertRaises(RuntimeError):self.simulate(fail='gpu-output-doctor.rkt')
    def test_inspector_failure(self):
        with self.assertRaises(RuntimeError):self.simulate(fail='inspect-gpu-output.py')
    def test_identity_failure(self):
        with self.assertRaises(ValueError):self.simulate(identity_change=lambda r:r.update(os='unix'))
    def test_wrong_report_failure(self):
        with self.assertRaises(ValueError):self.simulate(change=lambda n,r,i,root:r.update(validation_run='other'))
    def test_manifest_mutation(self):
        def change(n,r,i,root):
            if n=='performance':(root/'SOURCE-SHA256SUMS.txt').write_text('changed')
        with self.assertRaises(ValueError):self.simulate(change=change)
    def test_reuse_rejected_without_deleting_evidence(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);source_fixture(root);e=root/'e';e.mkdir();(e/'old.txt').write_text('old')
            with self.assertRaises(ValueError):parity.execute(root,'racket',e,lambda _:self.fail('must not run'),
                                                               backend='direct3d',host='owned')
            self.assertEqual((e/'old.txt').read_text(),'old')
    def test_egl_cannot_present(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t)
            with self.assertRaises(ValueError):parity.execute(root,'racket',root,lambda _:self.fail('must not run'),
                                                               backend='opengl',host='egl',scope='all')


class HookTests(unittest.TestCase):
    def test_installed_root_environment_and_pass_flag(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);installed=root/'installed';installed.mkdir();away=root/'away';away.mkdir()
            calls=[];report=dict(racket_executable='selected-racket',checks={})
            runner=types.SimpleNamespace(run=lambda a,**kw:calls.append((a,kw)))
            env={'PLTADDONDIR':'isolated','GPU_MODE':'optional'}
            def execute(r,interpreter,directory,run,**kw):
                self.assertEqual(r,installed);self.assertEqual(interpreter,'selected-racket')
                self.assertEqual(directory.parent,installed/'output');self.assertEqual(kw['adapter'],'warp')
                run(['dummy-command']);return dict(status='passed')
            with patch.object(parity,'execute',side_effect=execute):
                parity.parity_ci_checks(runner,installed,away,env,report,scope='offscreen')
            self.assertTrue(report['checks']['required_backend_parity_offscreen'])
            self.assertEqual(calls[0][1]['cwd'],away)
            self.assertEqual(calls[0][1]['env']['PLTADDONDIR'],'isolated')
            self.assertEqual(calls[0][1]['env']['GPU_MODE'],'required')
            self.assertEqual(env['GPU_MODE'],'optional')
    def test_failure_not_marked_passed(self):
        with tempfile.TemporaryDirectory() as t:
            report=dict(racket_executable='racket',checks={})
            with patch.object(parity,'execute',side_effect=RuntimeError('failed')):
                with self.assertRaises(RuntimeError):
                    parity.parity_ci_checks(None,Path(t),Path(t),{},report,scope='presentation')
            self.assertNotIn('required_backend_parity_presentation',report['checks'])
    def load_entry(self,name):
        fake=types.ModuleType('ci');matrix=types.ModuleType('ci_matrix');matrix.load_matrix=lambda:{}
        spec=importlib.util.spec_from_file_location('parity_entry_'+name,HERE/name)
        module=importlib.util.module_from_spec(spec)
        with patch.dict('sys.modules',ci=fake,ci_matrix=matrix):spec.loader.exec_module(module)
        return module
    def test_original_gates_precede_parity(self):
        for path,old,new in [('ci-d3d12.py','warp_checks','warp_and_parity_checks'),
                             ('ci-dxgi.py','dxgi_checks','dxgi_and_parity_checks')]:
            m=self.load_entry(path);calls=[]
            with patch.object(m,old,side_effect=lambda *a:calls.append('old')), \
                 patch.object(m,'parity_ci_checks',side_effect=lambda *a,**k:calls.append('parity')):
                getattr(m,new)(None,None,None,None,None)
            self.assertEqual(calls,['old','parity'])
    def test_original_failure_stops_parity(self):
        for path,old,new in [('ci-d3d12.py','warp_checks','warp_and_parity_checks'),
                             ('ci-dxgi.py','dxgi_checks','dxgi_and_parity_checks')]:
            m=self.load_entry(path)
            with patch.object(m,old,side_effect=RuntimeError('old failure')),patch.object(m,'parity_ci_checks') as after:
                with self.assertRaises(RuntimeError):getattr(m,new)(None,None,None,None,None)
                after.assert_not_called()


class IntegrationTests(unittest.TestCase):
    """These require the complete applied checkout/installed sources; never skip."""
    def test_native_suite_counts_unchanged(self):
        import re
        for name,count in [('gpu-surface-native-test.rkt',33),('gpu-image-native-test.rkt',42),
                           ('gpu-output-native-test.rkt',42),('gpu-cache-native-test.rkt',20),
                           ('gpu-presenter-native-test.rkt',28)]:
            self.assertEqual(len(re.findall(r'\(test-case\s', (ROOT/'tests'/name).read_text())),count)
    def test_pure_tests_wired(self):
        source=(ROOT/'run-tests.rkt').read_text()
        self.assertIn('"tests/gpu-backends-pure-test.rkt"',source)
        self.assertIn('(run-tests gpu-backends-pure-tests)',source)
    def test_production_identity_after_native_pointer_check(self):
        s=(ROOT/'private/gpu-surfaces.rkt').read_text()
        start=s.index('(define (gpu-surface-info s)')
        part=s[start:s.index('(define (ready-for-read!',start)]
        self.assertLess(part.index('(pointer=?'),part.index('(gpu-surface-identity/validated'))
    def test_output_protocol_uses_registry(self):
        s=(ROOT/'private/output-executor.rkt').read_text()
        self.assertIn('(gpu-backend? (output-raster-plan-backend plan))',s)
        self.assertNotIn("'(raster opengl metal)",s)
    def test_all_shared_doctors_have_adapter_options(self):
        for name in ('gpu-offscreen-doctor.rkt','gpu-image-doctor.rkt','gpu-output-doctor.rkt','gpu-performance-options.rkt'):
            s=(HERE/name).read_text();self.assertIn('"--adapter"',s);self.assertIn('"--adapter-index"',s)
    def test_required_matrix_unchanged(self):
        s=(ROOT/'.github/workflows/ci.yml').read_text()
        self.assertIn('needs: [source, cpu, egl, d3d12, dxgi, canvas]',s)
        self.assertNotIn('continue-on-error',s)
    def test_source_ci_runs_this_suite(self):self.assertIn("'test-gpu-parity.py'",(HERE/'ci.py').read_text())
    def test_required_hooks_not_only_configuration(self):
        for path,scope,hook in [('ci-d3d12.py','offscreen','warp_and_parity_checks'),
                                ('ci-dxgi.py','presentation','dxgi_and_parity_checks')]:
            s=(HERE/path).read_text()
            self.assertIn('extra_checks='+hook,s)
            self.assertIn("report['checks'].get('required_backend_parity_"+scope+"') is True",s)
    def test_version_and_pin(self):
        self.assertIn('(define version "0.74")',(ROOT/'info.rkt').read_text())
        self.assertEqual((ROOT/'private/native-default-version.txt').read_text().strip(),'3.119.1')
    def test_no_native_probe_in_declaration(self):
        s=(ROOT/'private/gpu-backends.rkt').read_text()
        self.assertNotIn('ffi-lib',s);self.assertNotIn('dynamic-require',s)
        self.assertIn('runtime_availability "not-probed"',s)


if __name__=='__main__':unittest.main(verbosity=2)
