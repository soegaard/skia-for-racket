#!/usr/bin/env python3
"""Regression tests for canvas validator gates using mocked command results.

These cases do not render Skia pixels or initialize a GUI. Their purpose is to
prevent missing, failed or skipped GUI execution from becoming a green gate.
"""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('canvas_validation', Path(__file__).with_name('validate-skia-canvas.py'))
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)

IDENTITY = dict(os='unix', architecture='x86_64', vm='chez-scheme', version='9.3', pointer_bytes=8)


def suite_output(name, count):
    return (f'{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run\n'
            f'{name}: {count} cases, 0 failures; synthetic validator fixture.\n')


class FakeRunner:
    def __init__(self, root, *, failure=None, bad_output=None, identity=None, mutate=False):
        self.root = root
        self.calls = []
        self.failure = failure
        self.bad_output = bad_output or {}
        self.identity = IDENTITY if identity is None else identity
        self.mutate = mutate
        self.manifests = 0

    def run(self, argv, *, cwd):
        argv = [str(part) for part in argv]
        self.calls.append(argv)
        self.assert_cwd = str(cwd)
        filename = Path(argv[1]).name
        if self.failure and any(Path(arg).name == self.failure for arg in argv):
            raise RuntimeError('injected command failure: ' + self.failure)
        if filename == 'update-source-sums.py':
            self.manifests += 1
            if self.mutate and self.manifests == 2:
                (self.root / 'canvas.rkt').write_text('changed during validation\n', encoding='utf-8')
        if filename == 'ci-identity.rkt':
            return json.dumps(self.identity)
        if filename == 'canvas-text-load-order.rkt':
            order = argv[2]
            result = dict(status='passed', load_order=order, skia_text_checks=2,
                          racket_text_checks=2, gui_initialized=True)
            return self.bad_output.get(filename + ':' + order,
                                       'canvas-text-load-order: ' + json.dumps(result) + '\n')
        for file, name, cases in (
                ('canvas-dc-pure-test.rkt', 'canvas-dc-pure', validation.PURE_CASES),
                ('canvas-dc-native-test.rkt', 'canvas-dc-native', validation.NATIVE_CASES),
                ('canvas-gui-test.rkt', 'canvas-gui', validation.GUI_CASES)):
            if filename == file:
                return self.bad_output.get(file, suite_output(name, cases))
        return ''


class CanvasValidationTests(unittest.TestCase):
    def simulate(self, *, require_gui=False, **options):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'source'
            output = Path(temp) / 'evidence'
            root.mkdir()
            output.mkdir()
            for name in validation.SOURCE_PATHS:
                file = root / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('synthetic source fixture\n', encoding='utf-8')
            (root / 'SOURCE-SHA256SUMS.txt').write_text('synthetic source manifest\n', encoding='utf-8')
            runner = FakeRunner(root, **options)
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                status = validation.execute(root, output, '/chosen/racket', require_gui=require_gui,
                                            manifest_only=True, runner=runner)
            report_file = output / ('validation.json' if status == 0 else 'validation.failed.json')
            report = json.loads(report_file.read_text(encoding='utf-8'))
            return status, report, runner.calls, (output / 'validation.json').exists()

    def test_headless_success_does_not_claim_any_gui_execution(self):
        status, report, calls, passed_exists = self.simulate()
        self.assertEqual(status, 0)
        self.assertTrue(passed_exists)
        self.assertEqual(report['pure_cases'], validation.PURE_CASES)
        self.assertEqual(report['native_cases'], validation.NATIVE_CASES)
        self.assertEqual(report['gui'], dict(required=False, executed=False, status='not-run', cases=0, text_load_orders=[]))
        self.assertFalse(report['checks']['required_gui'])
        self.assertFalse(report['presentation_submission_verified'])
        self.assertFalse(any(Path(arg).name == 'canvas-gui-test.rkt' for call in calls for arg in call))

    def test_required_gui_success_records_explicit_complete_execution(self):
        status, report, calls, _ = self.simulate(require_gui=True)
        self.assertEqual(status, 0)
        self.assertEqual({k: report['gui'][k] for k in ('required', 'executed', 'status', 'cases')},
                         dict(required=True, executed=True, status='passed', cases=validation.GUI_CASES))
        self.assertEqual([result['load_order'] for result in report['gui']['text_load_orders']], ['gtk-first', 'skia-first'])
        self.assertTrue(report['checks']['required_gui'])
        self.assertTrue(report['presentation_submission_verified'])
        self.assertFalse(report['screen_pixel_equivalence_claimed'])
        self.assertFalse(report['gpu_execution_verified'])
        execution = [call for call in calls if len(call) == 2 and Path(call[1]).name == 'canvas-gui-test.rkt']
        self.assertEqual(len(execution), 1)
        self.assertEqual(execution[0][0], '/chosen/racket')

    def test_both_text_load_orders_run_in_fresh_processes(self):
        status, report, calls, _ = self.simulate(require_gui=True)
        self.assertEqual(status, 0)
        self.assertTrue(report['checks']['text_load_orders'])
        processes = [call for call in calls if len(call) == 3 and Path(call[1]).name == 'canvas-text-load-order.rkt']
        self.assertEqual([call[2] for call in processes], ['gtk-first', 'skia-first'])
        self.assertTrue(all(call[0] == '/chosen/racket' for call in processes))

    def test_second_text_load_order_failure_prevents_required_gui_success(self):
        status, report, _, passed_exists = self.simulate(
            require_gui=True, bad_output={'canvas-text-load-order.rkt:skia-first': 'skipped\n'})
        self.assertEqual(status, 1)
        self.assertFalse(passed_exists)
        self.assertFalse(report['checks']['required_gui'])
        self.assertFalse(report['checks']['text_load_orders'])
        self.assertEqual([item['load_order'] for item in report['gui']['text_load_orders']], ['gtk-first'])

    def test_text_load_order_result_cannot_substitute_the_other_order(self):
        output = 'canvas-text-load-order: ' + json.dumps(dict(status='passed', load_order='gtk-first',
                   skia_text_checks=2, racket_text_checks=2, gui_initialized=True)) + '\n'
        with self.assertRaises(ValueError):
            validation.validate_load_order_output(output, 'skia-first')

    def test_gui_process_or_compilation_failure_removes_the_passing_report(self):
        status, report, _, passed_exists = self.simulate(require_gui=True, failure='canvas-gui-test.rkt')
        self.assertEqual(status, 1)
        self.assertFalse(passed_exists)
        self.assertEqual(report['status'], 'failed')
        self.assertEqual(report['gui']['status'], 'failed')
        self.assertFalse(report['checks']['required_gui'])

    def test_missing_display_skip_message_cannot_count_as_gui_success(self):
        status, report, _, passed_exists = self.simulate(
            require_gui=True, bad_output={'canvas-gui-test.rkt': 'No display; skipped GUI tests.\n'})
        self.assertEqual(status, 1)
        self.assertFalse(passed_exists)
        self.assertTrue(report['gui']['executed'])
        self.assertEqual(report['gui']['status'], 'failed')
        self.assertFalse(report['checks']['required_gui'])

    def test_a_clean_marker_cannot_hide_rackunit_failure_on_an_eventspace(self):
        output = suite_output('canvas-gui', validation.GUI_CASES).replace('0 failure(s)', '1 failure(s)')
        status, report, _, passed_exists = self.simulate(
            require_gui=True, bad_output={'canvas-gui-test.rkt': output})
        self.assertEqual(status, 1)
        self.assertFalse(passed_exists)
        self.assertFalse(report['presentation_submission_verified'])

    def test_partial_native_suite_cannot_pass_even_with_zero_process_status(self):
        status, report, calls, _ = self.simulate(
            require_gui=True, bad_output={'canvas-dc-native-test.rkt': suite_output('canvas-dc-native', 1)})
        self.assertEqual(status, 1)
        self.assertFalse(report['checks']['native_pixels_and_bitmap_bridge'])
        self.assertFalse(report['gui']['executed'])
        self.assertFalse(any(Path(arg).name == 'canvas-gui-test.rkt' for call in calls for arg in call))

    def test_source_change_during_validation_fails_after_other_checks_pass(self):
        status, report, _, passed_exists = self.simulate(require_gui=True, mutate=True)
        self.assertEqual(status, 1)
        self.assertFalse(passed_exists)
        self.assertTrue(report['checks']['required_gui'])
        self.assertFalse(report['checks']['source_unchanged'])

    def test_unsupported_interpreter_fails_before_running_the_suites(self):
        identity = dict(IDENTITY, version='8.17')
        status, report, calls, _ = self.simulate(require_gui=True, identity=identity)
        self.assertEqual(status, 1)
        self.assertFalse(report['checks']['pure_lifecycle'])
        self.assertFalse(any(Path(arg).name == 'canvas-dc-pure-test.rkt' for call in calls for arg in call))

    def test_both_manifest_checks_are_read_only_and_include_installed_package_mode(self):
        status, _, calls, _ = self.simulate(require_gui=True)
        self.assertEqual(status, 0)
        manifests = [call for call in calls if Path(call[1]).name == 'update-source-sums.py']
        self.assertEqual(len(manifests), 2)
        for command in manifests:
            self.assertIn('--check', command)
            self.assertIn('--manifest-only', command)
        self.assertEqual(calls[-1], manifests[-1])

    def test_duplicate_or_missing_completion_markers_are_rejected(self):
        clean = suite_output('canvas-gui', validation.GUI_CASES)
        for output in ('', clean + clean, clean.splitlines()[0] + '\n', clean.splitlines()[1] + '\n'):
            with self.subTest(output=output):
                with self.assertRaises(ValueError):
                    validation.validate_suite_output(output, 'canvas-gui', validation.GUI_CASES)

    def test_supported_identity_requires_real_integer_pointer_width(self):
        self.assertTrue(validation.supported_identity(dict(IDENTITY, version='8.18')))
        self.assertTrue(validation.supported_identity(dict(IDENTITY, version='9.3.0.2')))
        self.assertFalse(validation.supported_identity(dict(IDENTITY, pointer_bytes=8.0)))
        self.assertFalse(validation.supported_identity(dict(IDENTITY, vm='racket')))
        self.assertFalse(validation.supported_identity(dict(IDENTITY, version='9.3+patched')))


if __name__ == '__main__':
    unittest.main()
