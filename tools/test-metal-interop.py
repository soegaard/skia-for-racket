#!/usr/bin/env python3
"""Synthetic inspector/runner regressions plus full-checkout integration checks."""
from __future__ import annotations
import copy
import importlib.util
import json
from pathlib import Path
import re
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib
import metal_interop_validation as m

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def png(pixels):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    rows = b''.join(b'\0' + pixels[y*37*4:(y+1)*37*4] for y in range(29))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 37,29,8,6,0,0,0))
            + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def ctx(gen, closed=False):
    return dict(backend='metal', native_backend=2, generation=gen, state='closed' if closed else 'ready',
                binding_package='3.119.1', native_version='119.0', owns_command_queue=True,
                requires_gl_context=False, requires_window=False, device='synthetic device', renderer='synthetic renderer',
                shutdown_requested=False, live_children=0, pending_releases=0, failed_releases=0)


def session():
    return dict(state='closed', quarantined=False, error=False, error_reason=False,
                retained_texture=False, retained_producer=False, retained_completion_buffer=False,
                timeout_ms=5000, waits=[dict(phase=phase, status=4, polls=1, elapsed_ms=0)
                                      for phase in ('producer','ganesh-queue-tail')])


def texture(gen):
    return dict(backend='metal', context_generation=gen, handoff_state='consumed', raw_handles_exposed=False,
                completion='bounded-synchronous', ownership='retained-single-handoff', producer_coverage_verified=False,
                premultiplied=True, same_device=True, producer_retained_references=True,
                width=37,height=29,depth=1,levels=1,array_length=1,samples=1,format=70,texture_type=2,usage=5,
                storage_mode=2,hazard_tracking_mode=2,swizzle=[2,3,4,5],format_name='RGBA8888',origin='top-left',
                framebuffer_only=False,has_parent=False,has_buffer=False,has_heap=False,has_iosurface=False,
                shareable=False,has_remote_storage=False,native=session())


def events(mode):
    result=[dict(kind='flush'),dict(kind='submit',wait_requested=False),
            dict(kind='external-metal-producer-complete',wait_requested=True,producer_status=4,cpu_pixel_readback=False)]
    if mode=='copy':
        result += [dict(kind='gpu-snapshot',width=37,height=29),
                   dict(kind='external-image-copy',backend='metal',aliases_source=False,cpu_readback=False,skia_copy_draws=1)]
    else:
        result += [dict(kind='external-surface-borrow',backend='metal',contents_preserved=True)]
    result += [dict(kind='flush'),dict(kind='submit',wait_requested=False),
               dict(kind='external-metal-completion',wait_requested=True,completion_status=4,same_ganesh_queue=True,cpu_pixel_readback=False),
               dict(kind='external-resource-return',backend='metal',completion_verified=True,cpu_readback=False)]
    return result


def fixture(directory):
    raw=dict(schema=1,stage='0.52',backend='metal',validation_run=directory.name,os='macosx',architecture='aarch64',
             racket_version='9.3',vm='chez-scheme',hardware_acceleration_verified=False,presentation_verified=False,
             performance_measured=False,zero_copy_claimed=False,producer_coverage_verified=False,
             status='passed',error=False,native_cases=m.NATIVE_CASES,native_failures=0,sdk_texture_getters_verified=True,
             typed_swizzle_return_verified=True,producer='independent-metal-sdk-fixture',consumer='independent-metal-command-queue',
             interop_symbols=[dict(name=n,available=True) for n in sorted(m.SYMBOLS)],
             suite_contexts=[ctx(1,True),ctx(2,True)],cycles=[],captures=[])
    for ci in range(3):
        cs=[]
        for slot in range(2):
            gen=3+ci*2+slot;rows=[]
            for ordinal in range(24):
                mode='copy' if ordinal%2==0 else 'surface'
                im=dict(backend='metal',context_generation=gen,storage='gpu',texture_backed=True,context_matches=True,width=37,height=29)
                rows.append(dict(ordinal=ordinal,mode=mode,handoff=texture(gen),pixels_verified=True,
                                 producer_closed_before_skia_readback=mode=='copy',independent_consumer_readback=mode=='surface',
                                 image=im if mode=='copy' else False,io_events=events(mode)))
                if ordinal<2:
                    name=f'{ci}-{slot}-{mode}.png';(directory/name).write_bytes(png(m.expected_pixels(mode=='surface')))
                    raw['captures'].append(dict(cycle=ci,context=slot,ordinal=ordinal,mode=mode,png=name,width=37,height=29,
                                                encoded_after_context_teardown=True))
            cs.append(dict(context=slot,initial=ctx(gen),final=ctx(gen,True),handoffs=rows))
        raw['cycles'].append(dict(cycle=ci,contexts=cs))
    negative={k:copy.deepcopy(v) for k,v in raw.items() if k in ('schema','stage','backend','validation_run','os','architecture',
              'racket_version','vm','hardware_acceleration_verified','presentation_verified','performance_measured','zero_copy_claimed','producer_coverage_verified')}
    n=session();n.update(state='quarantined',quarantined=True,error='synthetic timeout',error_reason='timeout',
                         retained_texture=True,retained_producer=True,waits=[],timeout_ms=25)
    c=ctx(9);c.update(shutdown_requested=True,live_children=1)
    negative.update(status='expected-timeout-quarantined',normal_process_exit=True,dependency_unblocked_after_timeout=True,
                    intentional_retention_until_process_exit=True,graphics_handoff_submitted=False,native=n,context=c)
    m.write(directory/'metal-interop.diagnostic.json',raw);m.write(directory/'metal-interop.timeout.json',negative)
    return raw,negative


class Inspector(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.directory=Path(self.temp.name);self.raw,self.negative=fixture(self.directory)
    def reject(self, change, negative=False):
        change(self.negative if negative else self.raw)
        m.write(self.directory/('metal-interop.timeout.json' if negative else 'metal-interop.diagnostic.json'),
                self.negative if negative else self.raw)
        with self.assertRaises((ValueError,KeyError,TypeError)):m.inspect(self.directory)
    def first(self,d):return d['cycles'][0]['contexts'][0]['handoffs'][0]
    def test_valid(self):
        d=m.inspect(self.directory);self.assertEqual(d['handoffs'],144);self.assertEqual(len(d['captures']),12)
        self.assertFalse(d['zero_copy_claimed']);self.assertFalse(d['hardware_acceleration_verified'])
    def test_shared_error_values_not_zero(self):self.reject(lambda d:d.update(native_failures=False))
    def test_duplicate_json(self):
        p=self.directory/'metal-interop.diagnostic.json';p.write_text('{"schema":1,"schema":1}')
        with self.assertRaises(ValueError):m.inspect(self.directory)
    def test_bad_actual_png(self):
        p=self.directory/self.raw['captures'][0]['png'];p.write_bytes(png(bytes(37*29*4)))
        with self.assertRaises(ValueError):m.inspect(self.directory)
    def test_png_crc(self):
        p=self.directory/self.raw['captures'][0]['png'];b=bytearray(p.read_bytes());b[-1]^=1;p.write_bytes(b)
        with self.assertRaises(ValueError):m.inspect(self.directory)
    def test_symmetric_wrong_oracle_is_rejected(self):
        for c in self.raw['captures']:(self.directory/c['png']).write_bytes(png(bytes(37*29*4)))
        with self.assertRaises(ValueError):m.inspect(self.directory)
    def test_png_path(self):self.reject(lambda d:d['captures'][0].update(png='../image.png'))
    def test_missing_capture(self):self.reject(lambda d:d['captures'].pop())
    def test_duplicate_capture(self):self.reject(lambda d:d['captures'].__setitem__(1,d['captures'][0]))
    def test_early_capture(self):self.reject(lambda d:d['captures'][0].update(encoded_after_context_teardown=False))
    def test_extra_io(self):self.reject(lambda d:self.first(d)['io_events'].append(dict(kind='readback')))
    def test_unbounded_wait(self):self.reject(lambda d:self.first(d)['io_events'][1].update(wait_requested=True))
    def test_failed_native_suite(self):self.reject(lambda d:d.update(native_failures=1))
    def test_shortened_suite(self):self.reject(lambda d:d.update(native_cases=32))
    def test_shortened_stress(self):self.reject(lambda d:d['cycles'][0]['contexts'][0]['handoffs'].pop())
    def test_same_context_generation(self):self.reject(lambda d:d['cycles'][0]['contexts'][0]['initial'].update(generation=1))
    def test_no_completion_boundaries(self):self.reject(lambda d:self.first(d)['handoff']['native'].update(waits=[]))
    def test_scheduled_is_not_complete(self):self.reject(lambda d:self.first(d)['handoff']['native']['waits'][0].update(status=3))
    def test_nan_elapsed(self):
        p=self.directory/'metal-interop.diagnostic.json';p.write_text(p.read_text().replace('"elapsed_ms": 0','"elapsed_ms": NaN',1))
        with self.assertRaises(ValueError):m.inspect(self.directory)
    def test_borrowed_image_escape(self):self.reject(lambda d:d['cycles'][0]['contexts'][0]['handoffs'][1].update(image={}))
    def test_nonindependent_producer(self):self.reject(lambda d:d.update(producer='skia'))
    def test_nonindependent_consumer(self):self.reject(lambda d:d.update(consumer='skia'))
    def test_aliasing_copy(self):self.reject(lambda d:self.first(d)['io_events'][4].update(aliases_source=True))
    def test_wrong_queue_tail(self):self.reject(lambda d:self.first(d)['io_events'][-2].update(same_ganesh_queue=False))
    def test_wrong_swizzle(self):self.reject(lambda d:self.first(d)['handoff'].update(swizzle=[4,3,2,5]))
    def test_wrong_native_backend(self):self.reject(lambda d:d['cycles'][0]['contexts'][0]['initial'].update(native_backend=3))
    def test_unchecked_swizzle_abi(self):self.reject(lambda d:d.update(typed_swizzle_return_verified=False))
    def test_failed_symbol(self):self.reject(lambda d:d['interop_symbols'][0].update(available=False))
    def test_missing_symbol(self):self.reject(lambda d:d['interop_symbols'].pop())
    def test_timeout_wrong_reason(self):self.reject(lambda d:d['native'].update(error_reason='command-error'),True)
    def test_timeout_not_quarantined(self):self.reject(lambda d:d['native'].update(quarantined=False),True)
    def test_timeout_released_texture(self):self.reject(lambda d:d['native'].update(retained_texture=False),True)
    def test_timeout_false_completion(self):self.reject(lambda d:d['native'].update(waits=[dict(phase='producer',status=4,polls=1,elapsed_ms=0)]),True)
    def test_timeout_unpinned_context(self):self.reject(lambda d:d['context'].update(live_children=0),True)
    def test_timeout_submitted_handoff(self):self.reject(lambda d:d.update(graphics_handoff_submitted=True),True)
    def test_timeout_abnormal_process(self):self.reject(lambda d:d.update(normal_process_exit=False),True)
    def test_timeout_foreign_interpreter(self):self.reject(lambda d:d.update(racket_version='8.7'),True)
    def test_timeout_never_unblocked(self):self.reject(lambda d:d.update(dependency_unblocked_after_timeout=False),True)


def add_mutations():
    for field,value in [('schema',True),('stage','0.51'),('backend','opengl'),('validation_run','foreign'),('os','unix'),
                        ('hardware_acceleration_verified',True),('performance_measured',True),('presentation_verified',True),
                        ('zero_copy_claimed',True),('producer_coverage_verified',True)]:
        def check(self,f=field,v=value):self.reject(lambda d:d.update({f:v}))
        setattr(Inspector,'test_metadata_'+field,check)
    for field,value in [('same_device',False),('raw_handles_exposed',True),('levels',2),('storage_mode',1),('samples',4),
                        ('has_parent',True),('has_heap',True),('shareable',True),('hazard_tracking_mode',1),('premultiplied',False)]:
        def check(self,f=field,v=value):self.reject(lambda d:self.first(d)['handoff'].update({f:v}))
        setattr(Inspector,'test_texture_'+field,check)
add_mutations()


class Runner(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)/'source';self.directory=Path(self.temp.name)/'evidence'
        self.directory.mkdir();self.root.mkdir()
        for name in (*m.SOURCES,'SOURCE-SHA256SUMS.txt'):
            p=self.root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('synthetic source '+name)
        self.commands=[];self.fail=None;self.os='macosx';self.sdk_bad=False;self.mutate=False
    def fake_run(self,argv):
        xs=[str(x) for x in argv];self.commands.append(xs)
        if self.fail and any(self.fail in x for x in xs):raise RuntimeError('injected subprocess failure')
        if any(x.endswith('ci-identity.rkt') for x in xs):
            return json.dumps(dict(os=self.os,architecture='aarch64',version='9.3',vm='chez-scheme',pointer_bytes=8))
        if xs[0].endswith('metal-interop-sdk-check'):
            return json.dumps(dict(schema=1,kind='apple-metal-sdk',status='passed',pointer_bytes=8,nsuinteger_bytes=8,
                                   bool_bytes=1,swizzle_bytes=8 if self.sdk_bad else 4,gpu_execution_verified=False))
        if any(x.endswith('gpu-metal-interop-doctor.rkt') for x in xs) and 'make' not in xs:
            fixture(self.directory)
            if self.mutate:(self.root/m.SOURCES[0]).write_text('mutated')
        return ''
    def go(self):return m.execute(self.root,'/selected/racket',self.directory,self.fake_run)
    def test_complete_sequence(self):
        result=self.go();self.assertTrue(result['metal_execution_verified'])
        self.assertEqual(sum('--timeout-case' in c for c in self.commands),1)
        self.assertEqual(sum('--check' in c for c in self.commands),2)
        self.assertTrue((self.directory/'metal-interop.inspection.json').is_file())
    def test_selected_racket_compiles(self):
        self.go();compile=next(c for c in self.commands if 'make' in c)
        self.assertEqual(compile[:5],['/selected/racket','-l','raco','--','make'])
    def test_non_macos(self):
        self.os='unix'
        with self.assertRaises(ValueError):self.go()
    def test_bad_sdk_layout(self):
        self.sdk_bad=True
        with self.assertRaises(ValueError):self.go()
    def test_source_mutation(self):
        self.mutate=True
        with self.assertRaises(ValueError):self.go()
        self.assertFalse((self.directory/'metal-interop.inspection.json').exists())
    def test_existing_evidence_refused(self):
        (self.directory/'old').write_text('preserve')
        with self.assertRaises(ValueError):self.go()
        self.assertEqual((self.directory/'old').read_text(),'preserve')

for label,fragment in [('cmake','cmake'),('ctest','ctest'),('compile','make'),('doctor','--fixture'),('negative_child','--timeout-case')]:
    def check(self,f=fragment):
        self.fail=f
        with self.assertRaises(RuntimeError):self.go()
        self.assertFalse((self.directory/'metal-interop.inspection.json').exists())
    setattr(Runner,'test_failure_'+label,check)


class Source(unittest.TestCase):
    def test_production_uses_generic_handoff(self):
        s=(ROOT/'private/gpu-metal-interop.rkt').read_text()
        self.assertIn("(make-external-texture 'metal",s);self.assertIn('gpu-surface-snapshot',s)
        self.assertIn('call-with-canvas-state',s);self.assertIn('domain-request-shutdown!',s)
    def test_same_queue_not_exposed(self):
        s=(ROOT/'private/gpu-metal-interop.rkt').read_text()
        self.assertIn('(lambda (device _queue)',s);self.assertIn('(proc device)',s)
        self.assertNotIn('(proc device _queue)',s)
    def test_per_call_native_pool(self):
        s=(ROOT/'private/gpu-metal-interop-system.rkt').read_text()
        self.assertIn('call-with-gpu-native-scope',s);self.assertNotIn('(sleep ',s)
        self.assertIn('class_getMethodImplementation',s);self.assertIn('-> _mtl-swizzle',s)
    def test_no_unbounded_production_wait(self):
        s=(ROOT/'private/gpu-metal-interop-system.rkt').read_text()
        self.assertNotIn('waitUntilCompleted',s);self.assertNotIn('waitUntilScheduled',s)
        self.assertNotIn('getBytes:',s);self.assertNotIn('replaceRegion:',s)
    def test_native_case_count(self):
        s=(ROOT/'tests/gpu-metal-interop-native-test.rkt').read_text()
        self.assertEqual(len(re.findall(r'\(test-case\s',s)),m.NATIVE_CASES)
    def test_pure_case_count(self):
        self.assertEqual(len(re.findall(r'\(test-case\s',(ROOT/'tests/gpu-metal-interop-pure-test.rkt').read_text())),49)
    def test_fixture_is_independent(self):
        s=(HERE/'metal-interop-fixture/fixture.mm').read_text()
        self.assertIn('producer_queue',s);self.assertIn('consumer_queue',s)
        self.assertNotRegex(s,r'#(?:include|import).*Sk');self.assertNotIn('abort(',s)
        self.assertIn('encodeWaitForEvent',s);self.assertIn('signaledValue=1',s)
    def test_swizzle_negative_fixture_is_not_render_target(self):
        s=(HERE/'metal-interop-fixture/fixture.mm').read_text()
        block=re.search(r'if \(variant==9\) \{(.*?)\n      \}',s,re.S)
        self.assertIsNotNone(block)
        self.assertIn('d.usage = MTLTextureUsageShaderRead;',block.group(1))
        self.assertIn('d.swizzle = MTLTextureSwizzleChannelsMake',block.group(1))
        self.assertNotIn('MTLTextureUsageRenderTarget',block.group(1))
    def test_sdk_checks_survive_release(self):
        s=(HERE/'metal-interop-fixture/sdk-check.mm').read_text()
        self.assertIn('static_assert',s);self.assertNotRegex(s,r'(?<!_)assert\(')
        self.assertNotIn('MTLCreateSystemDefaultDevice',s)
    def test_all_new_python_files_parse(self):
        for n in ('metal_interop_validation.py','validate-metal-interop.py','check-metal-interop-sdk.py','test-metal-interop.py'):
            compile((HERE/n).read_text(),n,'exec')


class Integration(unittest.TestCase):
    def test_version_pin_and_registry(self):
        self.assertIn('(define version "0.78")',(ROOT/'info.rkt').read_text())
        self.assertEqual((ROOT/'private/native-default-version.txt').read_text().strip(),'3.119.1')
        data=json.loads((ROOT/'private/gpu-backends.json').read_text())
        self.assertTrue(all(b['features']['external_resource_interop'] for b in data['backends']))
    def test_pure_suite_wired(self):
        s=(ROOT/'run-tests.rkt').read_text()
        self.assertIn('"tests/gpu-metal-interop-pure-test.rkt"',s)
        self.assertIn('(run-tests gpu-metal-interop-pure-tests)',s)
    def test_native_free_import(self):self.assertIn('skia/unsafe/gpu-metal',(HERE/'ci-import-smoke.rkt').read_text())
    def test_source_and_local_checks(self):
        self.assertIn("'test-metal-interop.py'",(HERE/'ci.py').read_text())
        self.assertIn("'tools/test-metal-interop.py'",(HERE/'validate-gpu.py').read_text())
    def test_sdk_ci_inside_existing_macos_cpu_lanes(self):
        s=(ROOT/'.github/workflows/ci.yml').read_text();cpu=s.split('\n  cpu:',1)[1].split('\n  egl:',1)[0]
        self.assertIn("if: runner.os == 'macOS'",cpu)
        self.assertIn('check-metal-interop-sdk.py',cpu)
        self.assertNotIn('validate-metal-interop.py',cpu) # SDK is not GPU evidence
        self.assertIn('needs: [source, cpu, egl, d3d12, dxgi, canvas]',s)
    def test_shared_cleanup_reused_by_d3d12(self):
        self.assertIn('(require "gpu-interop-cleanup.rkt")',(ROOT/'private/gpu-d3d12-interop-policy.rkt').read_text())
    def test_roadmap_targets_dc_not_new_backends(self):
        s=(ROOT/'docs/GANESH-CLOSEOUT.md').read_text()
        for name in ('skia-dc%','skia-canvas%','0.53','0.57','deferred'):self.assertIn(name,s)


if __name__=='__main__':
    unittest.main(verbosity=2)
