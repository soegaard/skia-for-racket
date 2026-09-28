#!/usr/bin/env python3
"""Headless validator tests with mocked processes, not live GPU validation."""
from __future__ import annotations
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('headless_validation',Path(__file__).with_name('validate-gpu-headless.py'))
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
RACKET='/selected Racket/bin/racket'

class Checks(unittest.TestCase):
    def simulate(self, *, mode='required', failure=None, initial='passed', later='passed',
                 platform='surfaceless', surface='surfaceless', index='0', hardware=False,
                 system='linux', inspector_only=False, directory_only=False):
        before=Path.cwd()
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'tests').mkdir();(root/'private').mkdir()
            for name in ('gpu-egl-native-test','gpu-gl-interop-native-test','gpu-egl-pure-test',
                         'gpu-presenter-native-test','gpu-cross-backend-native-test'):
                (root/'tests'/f'{name}.rkt').write_text('#lang racket/base\n')
            (root/'private/gpu-egl-system.rkt').write_text('#lang racket/base\n')
            calls=[]; environments=[]
            def fake(argv,**kwargs):
                calls.append(argv);environments.append(kwargs.get('env'))
                code=int(bool(failure and failure in argv and (not inspector_only or '--probe-prefix' in argv)
                              and (not directory_only or '--directory' in argv)))
                if '--prefix' in argv and not code:
                    prefix=Path(argv[argv.index('--prefix')+1])
                    status=initial if prefix.name=='egl-lifecycle' else later
                    Path(str(prefix)+'.diagnostic.json').write_text(json.dumps(dict(status=status,message='synthetic')))
                stdout='unix/x86_64; Racket mock; VM chez-scheme\n' if kwargs.get('stdout') is subprocess.PIPE else None
                return subprocess.CompletedProcess(argv,code,stdout)
            env=dict(RACKET=RACKET,GPU_MODE=mode,SKIP_C_ABI='1',DISPLAY=':99',WAYLAND_DISPLAY='wayland-0',MIR_SOCKET='socket',
                     SKIA_EGL_PLATFORM=platform,SKIA_EGL_DEVICE_INDEX=index,SKIA_EGL_SURFACE=surface,
                     REQUIRE_HARDWARE='1' if hardware else '0')
            try:
                with patch.dict(os.environ,env),patch.object(v,'ROOT',root),patch.object(v.sys,'platform',system),\
                     patch.object(v.subprocess,'run',side_effect=fake),contextlib.redirect_stdout(io.StringIO()),\
                     contextlib.redirect_stderr(io.StringIO()): rc=v.main()
                directory,=(root/'output').iterdir()
                report=json.loads((directory/('validation.json' if rc==0 else 'validation.failed.json')).read_text())
                return rc,calls,environments,report
            finally:os.chdir(before)
    def test_full_headless_pipeline_and_sums_last(self):
        rc,calls,_,r=self.simulate();self.assertEqual(rc,0);self.assertTrue(r['headless_rendering_verified'])
        self.assertEqual(calls[-1][1],'tools/update-source-sums.py')
        self.assertEqual([a[1] for a in calls if '--prefix' in a],['tools/gpu-egl-doctor.rkt','tools/gpu-offscreen-doctor.rkt','tools/gpu-image-doctor.rkt','tools/gpu-interop-doctor.rkt','tools/gpu-output-doctor.rkt'])
    def test_all_child_processes_have_no_display_environment(self):
        _,_,envs,_=self.simulate()
        for env in envs:
            for name in v.DISPLAY_VARIABLES:self.assertNotIn(name,env)
    def test_all_children_share_run_identity(self):
        _,_,envs,r=self.simulate()
        self.assertEqual({e['SKIA_GPU_VALIDATION_RUN'] for e in envs},{r['validation_run']})
    def test_no_gui_compilation_or_execution_host(self):
        _,calls,_,r=self.simulate()
        compile_call,=[a for a in calls if 'raco' in a]
        self.assertNotIn('gpu-gui.rkt',compile_call);self.assertNotIn('tests/gpu-presenter-native-test.rkt',compile_call)
        self.assertFalse(any(a[1] in ('tools/gpu-window-doctor.rkt','tools/gpu-presenter-doctor.rkt','tools/gpu-gui-host.rkt') for a in calls))
        self.assertFalse(r['presentation_verified'])
    def test_shared_probes_use_egl_host(self):
        _,calls,_,_=self.simulate()
        for a in calls:
            if '--prefix' in a and a[1]!='tools/gpu-egl-doctor.rkt':self.assertEqual(a[a.index('--host')+1],'egl')
    def test_selected_racket_compiles_dynamic_native_suites(self):
        _,calls,_,_=self.simulate();a,=[a for a in calls if 'raco' in a]
        self.assertEqual(a[0],RACKET)
        for name in ('gpu-egl.rkt','gpu-gl-interop.rkt','tests/gpu-egl-native-test.rkt','tests/gpu-gl-interop-native-test.rkt','private/gpu-egl-system.rkt'):self.assertIn(name,a)
        for a in calls:
            if a[1].endswith('.rkt'):self.assertEqual(a[0],RACKET)
    def test_device_pbuffer_selection_is_explicit_everywhere(self):
        _,calls,_,r=self.simulate(platform='device',surface='pbuffer',index='2')
        for a in calls:
            if '--prefix' in a:
                for flag,val in (('--egl-platform','device'),('--egl-surface','pbuffer'),('--egl-device-index','2')):self.assertEqual(a[a.index(flag)+1],val)
        self.assertEqual(r['egl_device_index'],2)
    def test_hardware_flag_reaches_each_native_probe(self):
        _,calls,_,_=self.simulate(hardware=True)
        for a in calls:
            if '--prefix' in a:self.assertIn('--require-hardware',a)
    def test_optional_initialization_skip_is_explicit(self):
        rc,calls,_,r=self.simulate(mode='optional',initial='unavailable');self.assertEqual(rc,0)
        self.assertFalse(r['headless_rendering_verified']);self.assertTrue(any('unavailable' in x for x in r['skips']))
        self.assertEqual(len([a for a in calls if '--prefix' in a]),1)
    def test_required_initialization_skip_fails(self):
        rc,calls,_,_=self.simulate(initial='unavailable');self.assertEqual(rc,1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))
    def test_optional_does_not_pass_after_native_failure(self):
        rc,calls,_,_=self.simulate(mode='optional',failure='tools/gpu-interop-doctor.rkt');self.assertEqual(rc,1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))
    def test_optional_does_not_skip_after_lifecycle_success(self):
        rc,calls,_,_=self.simulate(mode='optional',later='unavailable');self.assertEqual(rc,1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))
    def test_inspector_failure_blocks_sums(self):
        rc,calls,_,_=self.simulate(failure='tools/inspect-gpu-headless.py',inspector_only=True);self.assertEqual(rc,1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))
    def test_combined_failure_blocks_sums(self):
        rc,calls,_,_=self.simulate(failure='tools/inspect-gpu-headless.py',directory_only=True);self.assertEqual(rc,1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))
    def test_off_runs_cpu_and_pure_checks_only(self):
        rc,calls,_,r=self.simulate(mode='off');self.assertEqual(rc,0);self.assertFalse(r['headless_rendering_verified'])
        self.assertTrue(any(a[1]=='run-tests.rkt' for a in calls));self.assertFalse(any('--prefix' in a for a in calls))
    def test_non_linux_is_explicitly_rejected(self):
        rc,calls,_,_=self.simulate(system='darwin');self.assertEqual(rc,1);self.assertEqual(calls,[])
    def test_bad_device_index(self): self.assertEqual(self.simulate(index='-1')[0],1)
    def test_bad_platform(self): self.assertEqual(self.simulate(platform='default')[0],1)
    def test_no_implicit_device_selection(self): self.assertEqual(self.simulate(index='1')[0],1)
    def test_bad_mode(self): self.assertEqual(self.simulate(mode='maybe')[0],1)

if __name__=='__main__':unittest.main(verbosity=2)
