#!/usr/bin/env python3
"""Validator orchestration tests. All subprocesses are mocked; no native pass."""
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

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('gpu_validation_under_test', HERE / 'validate-gpu.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
RACKET = '/test tools/Racket selected/bin/racket'

class Checks(unittest.TestCase):
    def simulate(self, mode='required', *, failure=None, unavailable=(), hardware=False, failure_probe_only=False, failure_directory_only=False,
                 identity='macosx/aarch64; Racket test; VM chez-scheme\n'):
        before = Path.cwd()
        with tempfile.TemporaryDirectory(prefix='skia-runner-test-') as temp:
            root = Path(temp)
            (root/'tests').mkdir(); (root/'private').mkdir()
            (root/'tests/gpu-image-native-test.rkt').write_text('#lang racket/base\n')
            (root/'tests/gpu-image-pure-test.rkt').write_text('#lang racket/base\n')
            (root/'private/gpu-images.rkt').write_text('#lang racket/base\n')
            (root/'tests/gpu-presenter-pure-test.rkt').write_text('#lang racket/base\n')
            (root/'tests/gpu-presenter-native-test.rkt').write_text('#lang racket/base\n')
            (root/'private/gpu-presenter.rkt').write_text('#lang racket/base\n')
            calls = []
            def fake_run(argv, **kwargs):
                calls.append(argv)
                code = 1 if failure and failure in argv and (not failure_probe_only or '--probe-prefix' in argv) and (not failure_directory_only or '--directory' in argv) else 0
                if '--prefix' in argv and not code:
                    prefix = Path(argv[argv.index('--prefix')+1])
                    status = 'unavailable' if prefix.name in unavailable else 'passed'
                    Path(str(prefix)+'.diagnostic.json').write_text(json.dumps({'status':status, 'message':'synthetic'}))
                output = identity if kwargs.get('stdout') is subprocess.PIPE else None
                return subprocess.CompletedProcess(argv, code, output)
            env = {'RACKET':RACKET, 'GPU_MODE':mode, 'SKIP_C_ABI':'1',
                   'REQUIRE_HARDWARE':'1' if hardware else '0'}
            try:
                with patch.dict(os.environ, env, clear=False), patch.object(validator, 'ROOT', root), \
                     patch.object(validator.subprocess, 'run', side_effect=fake_run), \
                     contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    result = validator.main()
                directory, = (root/'output').iterdir()
                report_file = directory/('validation.json' if result == 0 else 'validation.failed.json')
                report = json.loads(report_file.read_text())
                return result, calls, report, directory.name
            finally:
                os.chdir(before)

    def test_required_runs_all_stages_and_manifest_last(self):
        rc, calls, report, directory = self.simulate()
        self.assertEqual(rc, 0)
        self.assertTrue(directory.startswith('gpu-0.43-'))
        self.assertEqual(report['stage'], '0.43')
        paths = [a[1] for a in calls if len(a) > 1]
        for path in ('run-tests.rkt','tools/gpu-offscreen-doctor.rkt','tools/gpu-window-doctor.rkt',
                     'tools/gpu-image-doctor.rkt','tools/inspect-gpu-images.py'):
            self.assertIn(path, paths)
        self.assertEqual(calls[-1][1], 'tools/update-source-sums.py')
        self.assertLess(paths.index('tools/gpu-window-doctor.rkt'), paths.index('tools/gpu-image-doctor.rkt'))

    def test_selected_racket_compiles_dynamic_image_modules(self):
        _, calls, _, _ = self.simulate()
        compile_call, = [a for a in calls if '-l' in a and 'raco' in a]
        self.assertEqual(compile_call[0], RACKET)
        for name in ('private/gpu-images.rkt','tests/gpu-image-native-test.rkt',
                     'tests/gpu-image-pure-test.rkt','tools/gpu-image-doctor.rkt','examples/gpu-images.rkt'):
            self.assertIn(name, compile_call)
        for a in calls:
            if len(a)>1 and (a[1].endswith('-doctor.rkt') or a[1]=='run-tests.rkt'):
                self.assertEqual(a[0], RACKET)

    def test_live_image_failure_does_not_update_manifest(self):
        rc, calls, report, _ = self.simulate(failure='tools/gpu-image-doctor.rkt')
        self.assertEqual(rc, 1); self.assertEqual(report['status'], 'failed')
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))
        self.assertFalse(any('tools/inspect-gpu-images.py' in a and '--probe-prefix' in a for a in calls))

    def test_image_inspection_failure_does_not_update_manifest(self):
        rc, calls, _, _ = self.simulate(failure='tools/inspect-gpu-images.py', failure_probe_only=True)
        self.assertTrue(any('tools/gpu-image-doctor.rkt' in a and '--prefix' in a for a in calls))
        self.assertEqual(rc, 1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))

    def test_optional_initialization_skip_is_explicit(self):
        rc, calls, report, _ = self.simulate(mode='optional', unavailable=('images-opengl','images-metal'))
        self.assertEqual(rc, 0)
        self.assertTrue(any('images-opengl unavailable' in s for s in report['skips']))
        self.assertFalse(any('tools/inspect-gpu-images.py' in a and '--probe-prefix' in a for a in calls))
        image_calls = [a for a in calls if 'tools/gpu-image-doctor.rkt' in a and '--prefix' in a]
        self.assertEqual(len(image_calls), 2)
        self.assertTrue(all('--optional' in a for a in image_calls))
        self.assertFalse(report['backend_parity_verified'])

    def test_optional_does_not_hide_render_failure(self):
        rc, calls, report, _ = self.simulate(mode='optional', failure='tools/gpu-image-doctor.rkt')
        self.assertEqual(rc, 1); self.assertEqual(report['status'], 'failed')
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))

    def test_off_explicitly_skips_live_work_but_runs_pure_checks(self):
        rc, calls, report, _ = self.simulate(mode='off')
        self.assertEqual(rc, 0)
        self.assertTrue(any('GPU_MODE=off' in s for s in report['skips']))
        self.assertFalse(any('--prefix' in a for a in calls))
        self.assertTrue(any('run-tests.rkt' in a and len(a)==2 for a in calls))
        self.assertTrue(any('tools/inspect-gpu-images.py' in a and '--self-test' in a for a in calls))

    def test_macos_keeps_metal_probe_and_propagates_hardware_requirement(self):
        _, calls, _, _ = self.simulate(hardware=True)
        construction, = [a for a in calls if 'tools/gpu-doctor.rkt' in a and 'metal' in a]
        self.assertNotIn('--require-hardware', construction)
        for a in calls:
            if '--prefix' in a and a is not construction:
                self.assertIn('--require-hardware', a)

    def test_shared_suites_run_on_both_backends(self):
        rc, calls, report, _ = self.simulate()
        for kind in ('offscreen','image'):
            selected = [a for a in calls if f'tools/gpu-{kind}-doctor.rkt' in a and '--prefix' in a]
            self.assertEqual({a[a.index('--backend')+1] for a in selected}, {'opengl','metal'})
        self.assertTrue(report['metal_rendering_verified'])
        self.assertTrue(report['backend_parity_verified'])
        self.assertFalse(report['metal_presentation_verified'])

    def test_metal_does_not_request_a_window(self):
        _, calls, _, _ = self.simulate()
        window, = [a for a in calls if 'tools/gpu-window-doctor.rkt' in a and '--prefix' in a]
        self.assertNotIn('metal', window)
        self.assertNotIn('--backend', window)

    def test_metal_failure_cannot_update_manifest(self):
        rc, calls, _, _ = self.simulate(failure='tools/gpu-metal-doctor.rkt')
        self.assertEqual(rc,1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))

    def test_parity_inspection_failure_cannot_update_manifest(self):
        rc, calls, _, _ = self.simulate(failure='tools/inspect-gpu-parity.py', failure_probe_only=True)
        self.assertEqual(rc,1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))

    def test_combined_parity_failure_cannot_update_manifest(self):
        rc, calls, _, _ = self.simulate(failure='tools/inspect-gpu-parity.py', failure_directory_only=True)
        self.assertEqual(rc, 1)
        self.assertTrue(any('tools/inspect-gpu-parity.py' in a and '--directory' in a for a in calls))
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))

    def test_selected_racket_compiles_metal_and_cross_backend_tools(self):
        _, calls, _, _ = self.simulate()
        compilation, = [a for a in calls if '-l' in a and 'raco' in a]
        for name in ('tools/gpu-metal-doctor.rkt','tools/gpu-cross-backend-doctor.rkt','tools/gpu-test-host.rkt','examples/gpu-metal.rkt'):
            self.assertIn(name, compilation)

    def test_run_identifier_is_in_report(self):
        _, _, report, directory = self.simulate()
        self.assertEqual(report['validation_run'], directory)

    def test_non_macos_does_not_claim_metal_execution(self):
        rc, calls, report, _ = self.simulate(identity='unix/x86_64; Racket test; VM chez-scheme\n')
        self.assertEqual(rc, 0)
        self.assertFalse(any('--backend' in a and 'metal' in a for a in calls))
        self.assertTrue(any('Metal construction' in s for s in report['skips']))
        self.assertFalse(report['metal_rendering_verified'])
        self.assertFalse(report['backend_parity_verified'])

    def test_presenter_suites_run_on_both_backends(self):
        rc, calls, report, _ = self.simulate()
        self.assertEqual(rc, 0)
        chosen = [a for a in calls if 'tools/gpu-presenter-doctor.rkt' in a and '--prefix' in a]
        self.assertEqual({a[a.index('--backend')+1] for a in chosen}, {'opengl','metal'})
        self.assertEqual(report['presentation_submission_verified'], {'opengl':True,'metal':True})
        self.assertTrue(report['presentation_summary_verified'])
        self.assertFalse(report['visible_window_pixels_verified'])
        self.assertFalse(report['metal_presentation_verified'])

    def test_presenter_compile_uses_selected_racket(self):
        _, calls, _, _ = self.simulate()
        c, = [a for a in calls if '-l' in a and 'raco' in a]
        for path in ('gpu-gui.rkt','private/gpu-presenter.rkt','tests/gpu-presenter-native-test.rkt',
                     'tests/gpu-presenter-pure-test.rkt','tools/gpu-presenter-doctor.rkt',
                     'tools/gpu-presentation-host.rkt','examples/gpu-presenters.rkt',
                     'examples/gpu-presentation-scene.rkt'):
            self.assertIn(path, c)
        self.assertEqual(c[0], RACKET)

    def test_presenter_failure_cannot_update_manifest(self):
        rc, calls, report, _ = self.simulate(failure='tools/gpu-presenter-doctor.rkt')
        self.assertEqual(rc, 1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))
        self.assertEqual(report['status'], 'failed')

    def test_presenter_inspection_failure_cannot_update_manifest(self):
        rc, calls, _, _ = self.simulate(failure='tools/inspect-gpu-presentation.py', failure_probe_only=True)
        self.assertEqual(rc, 1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))

    def test_combined_presenter_failure_cannot_update_manifest(self):
        rc, calls, _, _ = self.simulate(failure='tools/inspect-gpu-presentation.py', failure_directory_only=True)
        self.assertEqual(rc, 1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))

    def test_optional_presenter_unavailability_is_explicit(self):
        rc, calls, report, _ = self.simulate(mode='optional', unavailable=('presentation-metal',))
        self.assertEqual(rc, 0)
        self.assertEqual(report['presentation_submission_verified'], {'opengl':True,'metal':False})
        self.assertFalse(report['presentation_summary_verified'])
        self.assertTrue(any('presentation-metal unavailable' in s for s in report['skips']))
        self.assertFalse(any('tools/inspect-gpu-presentation.py' in a and '--directory' in a for a in calls))

    def test_optional_presenter_test_failure_is_not_an_initialization_skip(self):
        rc, calls, _, _ = self.simulate(mode='optional', failure='tools/gpu-presenter-doctor.rkt')
        self.assertEqual(rc, 1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))

    def test_off_does_not_claim_presenter_submission(self):
        rc, calls, report, _ = self.simulate(mode='off')
        self.assertEqual(rc, 0)
        self.assertEqual(report['presentation_submission_verified'], {})
        self.assertFalse(report['presentation_summary_verified'])
        self.assertFalse(any('tools/gpu-presenter-doctor.rkt' in a and '--prefix' in a for a in calls))

    def test_non_macos_runs_gl_presenter_only(self):
        rc, calls, report, _ = self.simulate(identity='unix/x86_64; Racket test; VM chez-scheme\n')
        self.assertEqual(rc, 0)
        self.assertEqual(report['presentation_submission_verified'], {'opengl':True})
        self.assertTrue(report['presentation_summary_verified'])
        self.assertFalse(any('tools/gpu-presenter-doctor.rkt' in a and 'metal' in a for a in calls))

    def test_interop_uses_existing_gl_host_without_claiming_egl(self):
        rc, calls, report, _ = self.simulate()
        self.assertEqual(rc, 0)
        self.assertTrue(report['gl_interop_verified'])
        self.assertFalse(report['egl_headless_verified'])
        probe, = [a for a in calls if 'tools/gpu-interop-doctor.rkt' in a and '--prefix' in a]
        self.assertNotIn('--host', probe)
        self.assertFalse(any('tools/gpu-egl-doctor.rkt' in a and '--prefix' in a for a in calls))

    def test_interop_failure_blocks_manifest(self):
        rc, calls, _, _ = self.simulate(failure='tools/gpu-interop-doctor.rkt')
        self.assertEqual(rc, 1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))

    def test_interop_inspector_failure_blocks_manifest(self):
        rc, calls, _, _ = self.simulate(failure='tools/inspect-gpu-headless.py', failure_probe_only=True)
        self.assertEqual(rc, 1)
        self.assertFalse(any('tools/update-source-sums.py' in a for a in calls))

    def test_optional_interop_initialization_skip(self):
        rc, calls, report, _ = self.simulate(mode='optional', unavailable=('interop-opengl',))
        self.assertEqual(rc, 0)
        self.assertFalse(report['gl_interop_verified'])
        self.assertTrue(any('interop-opengl unavailable' in s for s in report['skips']))

    def test_off_cannot_claim_interop(self):
        rc, calls, report, _ = self.simulate(mode='off')
        self.assertEqual(rc, 0)
        self.assertFalse(report['gl_interop_verified'])
        self.assertFalse(any('tools/gpu-interop-doctor.rkt' in a and '--prefix' in a for a in calls))

    def test_selected_racket_compiles_egl_interop(self):
        _, calls, _, _ = self.simulate()
        compile_call, = [a for a in calls if 'raco' in a]
        for name in ('gpu-egl.rkt','gpu-gl-interop.rkt','tools/gpu-egl-doctor.rkt','tools/gpu-interop-doctor.rkt'):
            self.assertIn(name, compile_call)

if __name__ == '__main__':
    unittest.main(verbosity=2)
