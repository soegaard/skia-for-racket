#!/usr/bin/env python3
"""Runner orchestration only: all subprocesses mocked, no hardware measurements."""
import importlib.util, os, unittest
from pathlib import Path
from unittest.mock import patch
HERE=Path(__file__).resolve().parent
def load(name,file):
    s=importlib.util.spec_from_file_location(name,HERE/file)
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
desktop=load('performance_desktop_tests','test-validate-gpu-images.py')
headless=load('performance_headless_tests','test-validate-gpu-headless.py')
class Checks(unittest.TestCase):
    def desk(self,**opts):return desktop.Checks().simulate(**opts)
    def egl(self,**opts):return headless.Checks().simulate(**opts)
    def probes(self,calls,name):return [a for a in calls if a[1]==f'tools/gpu-{name}-doctor.rkt']
    def no_sums(self,calls):self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))
    def test_both_backends_and_last_sums(self):
        rc,c,r,_=self.desk();self.assertEqual(rc,0)
        self.assertEqual(len(self.probes(c,'performance')),2);self.assertEqual(len(self.probes(c,'redraw')),2)
        self.assertEqual(c[-1][1],'tools/update-source-sums.py');self.assertTrue(r['performance_measured'])
        self.assertEqual(r['performance_measurements_verified'],{'opengl':True,'metal':True})
    def test_compilation_selected_interpreter(self):
        _,c,_,_=self.desk();a,=[a for a in c if 'raco' in a];self.assertEqual(a[0],desktop.RACKET)
        for f in ('tools/gpu-performance-doctor.rkt','tools/gpu-redraw-doctor.rkt','tools/gpu-performance-work.rkt','tools/gpu-performance-options.rkt'):self.assertIn(f,a)
    def test_stress_configuration_environment(self):
        with patch.dict(os.environ,{'GPU_STRESS_FRAMES':'300','GPU_BENCH_SAMPLES':'17'}):
            _,c,envs,_=self.egl()
        for a,e in zip(c,envs):
            if a[1]=='tools/gpu-performance-doctor.rkt':
                self.assertEqual(e['GPU_STRESS_FRAMES'],'300');self.assertEqual(e['GPU_BENCH_SAMPLES'],'17')
    def test_hardware_propagation(self):
        _,c,_,_=self.desk(hardware=True)
        for a in self.probes(c,'performance')+self.probes(c,'redraw'):self.assertIn('--require-hardware',a)
    def test_perf_failure_blocks_sums(self):
        rc,c,_,_=self.desk(failure='tools/gpu-performance-doctor.rkt');self.assertEqual(rc,1);self.no_sums(c)
    def test_redraw_failure_blocks_sums(self):
        rc,c,_,_=self.desk(failure='tools/gpu-redraw-doctor.rkt');self.assertEqual(rc,1);self.no_sums(c)
    def test_inspection_failure_blocks_sums(self):
        rc,c,_,_=self.desk(failure='tools/inspect-gpu-performance.py',failure_probe_only=True);self.assertEqual(rc,1);self.no_sums(c)
    def test_optional_runtime_failure_not_skipped(self):
        rc,c,_,_=self.desk(mode='optional',failure='tools/gpu-performance-doctor.rkt');self.assertEqual(rc,1);self.no_sums(c)
    def test_optional_absence_recorded(self):
        rc,c,r,_=self.desk(mode='optional',unavailable=('performance-opengl',));self.assertEqual(rc,0)
        self.assertFalse(r['performance_measurements_verified']['opengl']);self.assertTrue(r['skips'])
    def test_required_absence_fails(self):
        rc,c,_,_=self.desk(unavailable=('performance-opengl',));self.assertEqual(rc,1);self.no_sums(c)
    def test_off_no_performance_claim(self):
        rc,c,r,_=self.desk(mode='off');self.assertEqual(rc,0);self.assertFalse(r['performance_measured']);self.assertFalse(self.probes(c,'performance'))
    def test_headless_no_redraw(self):
        rc,c,_,r=self.egl();self.assertEqual(rc,0);self.assertFalse(self.probes(c,'redraw'))
        self.assertNotIn('tools/gpu-redraw-doctor.rkt',next(a for a in c if 'raco' in a))
        self.assertTrue(r['performance_measured']);self.assertFalse(r['redraw_stress_verified'])
    def test_headless_no_display(self):
        _,_,envs,_=self.egl()
        for e in envs:
            for key in ('DISPLAY','WAYLAND_DISPLAY','MIR_SOCKET'):self.assertNotIn(key,e)
    def test_headless_egl_args(self):
        _,c,_,_=self.egl(mode='optional',platform='device',surface='pbuffer',index='2',hardware=True)
        a,=self.probes(c,'performance')
        for flag,value in (('--host','egl'),('--egl-platform','device'),('--egl-surface','pbuffer'),('--egl-device-index','2')):self.assertEqual(a[a.index(flag)+1],value)
        self.assertIn('--require-hardware',a);self.assertNotIn('--optional',a)
    def test_headless_failure_blocks_sums(self):
        rc,c,_,_=self.egl(failure='tools/gpu-performance-doctor.rkt');self.assertEqual(rc,1);self.no_sums(c)
    def test_headless_off_not_measured(self):
        rc,c,_,r=self.egl(mode='off');self.assertEqual(rc,0);self.assertFalse(r['performance_measured'])
    def test_makes_no_CI_claim(self):
        _,_,r,_=self.desk();self.assertFalse(r['egl_headless_verified']);self.assertIn('CI',r['egl_validation_note'])
    def test_performance_doctor_publishes_source_fingerprints(self):
        text=(HERE/'gpu-performance-doctor.rkt').read_text()
        self.assertIn("'workload_sources sources",text)
if __name__=='__main__':unittest.main(verbosity=2)
