#!/usr/bin/env python3
"""Mocked runner checks: document failures may not become source-manifest success."""
import importlib.util
from pathlib import Path
import unittest

HERE=Path(__file__).resolve().parent

def load(name,file):
    spec=importlib.util.spec_from_file_location(name,HERE/file)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

desktop=load('output_desktop_tests','test-validate-gpu-images.py')
headless=load('output_headless_tests','test-validate-gpu-headless.py')

class Checks(unittest.TestCase):
    def desk(self,**options):return desktop.Checks().simulate(**options)
    def egl(self,**options):return headless.Checks().simulate(**options)
    def no_sums(self,calls):self.assertFalse(any('tools/update-source-sums.py' in call for call in calls))
    def test_both_desktop_backends_and_sums_last(self):
        rc,calls,report,_=self.desk();self.assertEqual(rc,0)
        probes=[a for a in calls if a[1]=='tools/gpu-output-doctor.rkt']
        self.assertEqual([a[a.index('--backend')+1] for a in probes],['opengl','metal'])
        self.assertEqual(report['gpu_document_output_verified'],{'opengl':True,'metal':True})
        self.assertEqual(calls[-1][1],'tools/update-source-sums.py')
    def test_desktop_preserves_interop_before_document_validation(self):
        _,calls,_,_=self.desk()
        self.assertLess(next(i for i,a in enumerate(calls) if a[1]=='tools/gpu-interop-doctor.rkt'),
                        next(i for i,a in enumerate(calls) if a[1]=='tools/gpu-output-doctor.rkt'))
    def test_desktop_native_failure_blocks_sums(self):
        rc,calls,_,_=self.desk(failure='tools/gpu-output-doctor.rkt');self.assertEqual(rc,1);self.no_sums(calls)
    def test_desktop_document_inspection_failure_blocks_sums(self):
        rc,calls,_,_=self.desk(failure='tools/inspect-gpu-output.py',failure_probe_only=True)
        self.assertEqual(rc,1);self.no_sums(calls)
    def test_optional_document_failure_is_not_absence(self):
        rc,calls,_,_=self.desk(mode='optional',failure='tools/gpu-output-doctor.rkt')
        self.assertEqual(rc,1);self.no_sums(calls)
    def test_optional_document_absence_is_explicit(self):
        rc,calls,report,_=self.desk(mode='optional',unavailable=('output-metal',))
        self.assertEqual(rc,0);self.assertFalse(report['gpu_document_output_verified']['metal'])
        self.assertTrue(any('output-metal unavailable' in text for text in report['skips']))
    def test_required_document_absence_fails(self):
        rc,calls,_,_=self.desk(unavailable=('output-metal',));self.assertEqual(rc,1);self.no_sums(calls)
    def test_off_has_no_document_gpu_claim(self):
        rc,calls,report,_=self.desk(mode='off');self.assertEqual(rc,0)
        self.assertEqual(report['gpu_document_output_verified'],{})
        self.assertFalse(any(a[1]=='tools/gpu-output-doctor.rkt' for a in calls))
    def test_selected_racket_compiles_all_document_modules(self):
        _,calls,_,_=self.desk();command,=[a for a in calls if 'raco' in a]
        for name in ('gpu-output.rkt','private/output-executor.rkt','tools/gpu-output-doctor.rkt',
                     'examples/gpu-output.rkt','tests/gpu-output-fixtures.rkt'):self.assertIn(name,command)
        self.assertEqual(command[0],desktop.RACKET)
    def test_hardware_flag_reaches_document_probes(self):
        _,calls,_,_=self.desk(hardware=True)
        for command in calls:
            if command[1]=='tools/gpu-output-doctor.rkt':self.assertIn('--require-hardware',command)
    def test_non_macos_does_not_claim_metal_documents(self):
        _,calls,report,_=self.desk(identity='unix/x86_64; Racket mock; VM chez-scheme\n')
        self.assertEqual(report['gpu_document_output_verified'],{'opengl':True})
    def test_linux_baseline_gate_stays_deferred(self):
        _,_,report,_=self.desk();self.assertFalse(report['egl_headless_verified'])
        self.assertIn('deferred',report['egl_validation_note']);self.assertIn('CI',report['egl_validation_note'])
    def test_headless_document_pipeline_and_sums_last(self):
        rc,calls,envs,report=self.egl();self.assertEqual(rc,0)
        self.assertTrue(report['gpu_document_output_verified'])
        command,=[a for a in calls if a[1]=='tools/gpu-output-doctor.rkt']
        self.assertEqual(command[0],headless.RACKET)
        self.assertEqual(command[command.index('--host')+1],'egl')
        self.assertEqual(calls[-1][1],'tools/update-source-sums.py')
    def test_headless_native_failure_blocks_sums(self):
        rc,calls,_,_=self.egl(failure='tools/gpu-output-doctor.rkt');self.assertEqual(rc,1);self.no_sums(calls)
    def test_headless_document_inspection_failure_blocks_sums(self):
        rc,calls,_,_=self.egl(failure='tools/inspect-gpu-output.py',inspector_only=True)
        self.assertEqual(rc,1);self.no_sums(calls)
    def test_headless_document_probes_do_not_get_optional_after_initialization(self):
        _,calls,_,_=self.egl(mode='optional')
        command,=[a for a in calls if a[1]=='tools/gpu-output-doctor.rkt'];self.assertNotIn('--optional',command)
    def test_headless_environment_removed_for_document_work(self):
        _,calls,environments,_=self.egl()
        for command,env in zip(calls,environments):
            if command[1]=='tools/gpu-output-doctor.rkt':
                for key in ('DISPLAY','WAYLAND_DISPLAY','MIR_SOCKET'):self.assertNotIn(key,env)
    def test_headless_device_selection_propagates(self):
        _,calls,_,_=self.egl(platform='device',surface='pbuffer',index='2',hardware=True)
        command,=[a for a in calls if a[1]=='tools/gpu-output-doctor.rkt']
        for flag,value in (('--egl-platform','device'),('--egl-surface','pbuffer'),('--egl-device-index','2')):
            self.assertEqual(command[command.index(flag)+1],value)
        self.assertIn('--require-hardware',command)
    def test_headless_off_does_not_claim_document_execution(self):
        _,calls,_,report=self.egl(mode='off');self.assertFalse(report['gpu_document_output_verified'])
        self.assertFalse(any(a[1]=='tools/gpu-output-doctor.rkt' for a in calls))
    def test_headless_initial_absence_prevents_document_probe(self):
        _,calls,_,report=self.egl(mode='optional',initial='unavailable')
        self.assertFalse(report['gpu_document_output_verified'])
        self.assertFalse(any(a[1]=='tools/gpu-output-doctor.rkt' for a in calls))

if __name__=='__main__':unittest.main(verbosity=2)
