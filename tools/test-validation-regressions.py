#!/usr/bin/env python3
"""Regression-scope unit/command-plan tests. Native work and inspectors are mocked.

Run the actual validator main functions, not replicas of their control flow.
No synthetic worker output in these tests is counted as native/GPU evidence.
"""
from __future__ import annotations

import argparse
import ast
import os
import contextlib
import importlib.abc
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

from validation_regressions import (RegressionGate, add_regression_argument, global_compile_targets,
                                    automatic_regression_mode)

ROOT = Path(__file__).resolve().parents[1]
DIRECT = ('validate-effects.py', 'validate-geometry-completion.py', 'validate-typefaces.py',
          'validate-font-queries.py', 'validate-text-blobs.py', 'validate-integer-pixels.py',
          'validate-float-pixels.py', 'validate-image-operations.py', 'validate-gpu-formats.py',
          'advanced_canvas_validation.py', 'validate-dc-output.py')
ALL = (*DIRECT, 'validate-dc-closure.py')
DEPS = ('effects_validation', 'geometry_completion_validation', 'typeface_validation',
        'font_query_validation', 'text_blob_validation', 'integer_pixel_validation',
        'float_pixel_validation', 'image_operation_validation', 'gpu_format_validation',
        'dc_output_validation')
IDENTITY = dict(version='9.3', os='unix', architecture='x86_64', vm='chez-scheme', pointer_bytes=8)


def require(ok, message):
    if not ok:
        raise ValueError(message)


class Harness:
    """Only external execution, inspector results and source fingerprints are mocked."""
    def __init__(self, root, failure=None, malformed_nested=False):
        self.root, self.failure = root, failure
        self.malformed_nested = malformed_nested
        self.commands = []
        self.inspections = []
        self.modules = {}
        (root/'SOURCE-SHA256SUMS.txt').write_text('synthetic source identity\n')
        (root/'run-tests.rkt').write_text(
            '#lang racket/base\n(define-runtime-path other "tests/unrelated-native-test.rkt")\n')

    def inspect(self, *args, **kw):
        self.inspections.append((args, kw))
        if self.failure == 'inspector':
            raise ValueError('injected inspector failure')
        render = kw.get('render')
        if render is None and args and callable(args[-1]):
            render = args[-1]
        if callable(render):
            render(self.root/'mock.pdf', 'pdf')
            render(self.root/'mock.svg', 'svg')
        elif render is True and kw.get('runner'):
            kw['runner'].run(['pdftoppm', 'mock.pdf'])
            kw['runner'].run(['rsvg-convert', 'mock.svg'])
        return {'status': 'passed', 'synthetic': True}

    def dependencies(self):
        result = {}
        for name in DEPS:
            dep = types.ModuleType(name)
            for attr in ('inspect_documents', 'inspect_gpu', 'gpu_receipt', 'inspect'):
                setattr(dep, attr, self.inspect)
            result[name] = dep
        dc = result['dc_output_validation']
        dc.require = require
        dc.unique = dict
        dc.SPECS = tuple(range(24))
        dc.read_json = lambda path: {}
        dc.validate_receipt = lambda *a: [dict(id=str(i),
            file=f'{i}.' + ('pdf' if i % 2 == 0 else 'svg'),
            format='pdf' if i % 2 == 0 else 'svg', width_points=64, height_points=48)
            for i in range(24)]
        dc.safe_file = lambda directory, name: directory/name
        dc.inspect_document = self.inspect
        dc.inspect_pixels = self.inspect
        dc.write_review = lambda *a: None
        return result

    def load(self, name):
        if name in self.modules:
            return self.modules[name]
        real_spec = importlib.util.spec_from_file_location
        harness = self

        class BaseLoader(importlib.abc.Loader):
            def create_module(self, spec):
                return None
            def exec_module(self, module):
                class Runner:
                    def __init__(self, directory, timeout):
                        self.commands, self.timeout = [], timeout
                    def run(self, command, root):
                        self.commands.append(dict(argv=list(map(str, command))))
                        cp = harness.process(command, cwd=root, check=False)
                        if cp.returncode:
                            raise RuntimeError('mock external worker failed')
                        return cp.stdout.decode()
                module.Runner = Runner
                module.validate_identity = lambda v: v
                module.select_backends = lambda request, identity: ('egl', 'opengl')

        def spec_for(name, location, *a, **kw):
            if Path(location).name == 'validate-gpu-dc.py':
                return importlib.util.spec_from_loader(name, BaseLoader())
            return real_spec(name, location, *a, **kw)

        with patch.dict(sys.modules, self.dependencies()), \
             patch.object(importlib.util, 'spec_from_file_location', side_effect=spec_for):
            spec = real_spec('scope_test_' + name.replace('-', '_').replace('.', '_'), ROOT/'tools'/name)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        module.ROOT = self.root
        if name == 'advanced_canvas_validation.py':
            module.inspect_gpu = self.inspect
            module.inspect_documents = self.inspect
        if hasattr(module, 'fingerprint'):
            module.fingerprint = lambda root: {'synthetic': 'unchanged'}
        if name == 'validate-dc-output.py':
            module.dependencies = lambda: {'synthetic': True}
        self.modules[name] = module
        return module

    def process(self, command, **kw):
        command = list(map(str, command))
        self.commands.append(command)
        worker = Path(command[1]).name if len(command) > 1 else ''
        output, rc = b'', 0
        if worker == 'validate-dc-output.py':
            child = self.load(worker)
            rc = child.main(command[2:], root=self.root)
            report_path = Path(command[command.index('--directory') + 1])/'validation.json'
            if not rc and self.malformed_nested:
                value = json.loads(report_path.read_text())
                value['regressions_passed'] = not value['regressions_passed']
                report_path.write_text(json.dumps(value))
        elif worker == 'ci-identity.rkt':
            output = json.dumps(IDENTITY).encode()
        elif worker in ('dc-output-pure-test.rkt', 'dc-output-native-test.rkt',
                        'dc-closure-pure-test.rkt', 'dc-closure-native-test.rkt'):
            n = {'dc-output-pure-test.rkt': 34, 'dc-output-native-test.rkt': 22,
                 'dc-closure-pure-test.rkt': 35, 'dc-closure-native-test.rkt': 22}[worker]
            stem = worker.removesuffix('-test.rkt')
            output = (f'{n} success(es) 0 failure(s) 0 error(s) {n} test(s) run\n'
                      f'{stem}: {n} cases, 0 failures\n').encode()
        elif worker == 'dc-output-doctor.rkt':
            output = b'dc-output-documents: 24 documents; passed.\n'
        for flag in ('--directory', '--report'):
            if flag in command:
                p = Path(command[command.index(flag) + 1])
                (p if flag == '--directory' else p.parent).mkdir(parents=True, exist_ok=True)
        is_global = worker == 'run-tests.rkt'
        is_feature = worker.endswith('.rkt') and ('-gpu-test' in worker or '-doctor' in worker)
        if (self.failure == 'global' and is_global or
            self.failure == 'compile' and '-l' in command and 'make' in command or
            self.failure == 'feature' and is_feature or
            self.failure == 'renderer' and Path(command[0]).name in ('pdftoppm', 'rsvg-convert') or
            self.failure == 'dc-baseline' and worker == 'validate-dc.py'):
            rc = 1
        if kw.get('stdout') not in (None, subprocess.PIPE):
            kw['stdout'].write(output.decode())
        if rc and kw.get('check'):
            raise subprocess.CalledProcessError(rc, command, output=output)
        return subprocess.CompletedProcess(command, rc, stdout=output)

    def invoke(self, name, mode=None, extra=(), missing=None):
        module = self.load(name)
        out = self.root/('evidence-' + str(len(list(self.root.glob('evidence-*')))))
        args = ['--racket', 'racket', '--directory', str(out)]
        if mode is not None:
            args += ['--regressions', mode]
        if name not in ('validate-typefaces.py', 'validate-dc-output.py', 'validate-dc-closure.py'):
            args += ['--require-gpu', '--backend', 'egl']
        args += ['--require-renderers', *extra]
        def which(name):
            name = str(name)
            if name == missing or Path(name).name == missing:
                return None
            return name if Path(name).is_absolute() else '/mock/' + name
        with patch('shutil.which', side_effect=which), patch('subprocess.run', side_effect=self.process), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            try:
                if name in ('advanced_canvas_validation.py', 'validate-dc-output.py', 'validate-dc-closure.py'):
                    rc = module.main(args, root=self.root)
                else:
                    rc = module.main(args)
            except SystemExit as exc:
                rc = exc.code
        report = json.loads((out/'validation.json').read_text()) if (out/'validation.json').is_file() else None
        return rc, report


class GateTests(unittest.TestCase):
    def test_default_is_full(self):
        p = argparse.ArgumentParser(); add_regression_argument(p)
        self.assertEqual(p.parse_args([]).regressions, 'full')
    def test_none_is_not_a_pass(self):
        report = {}; gate = RegressionGate('none', report); work = Mock()
        with contextlib.redirect_stdout(io.StringIO()): gate.run(work)
        work.assert_not_called()
        self.assertFalse(report['regressions_passed'])
        self.assertFalse(report['regressions_attempted'])
        self.assertFalse(report['regressions_completed'])
        self.assertEqual(report['regressions_status'], 'not-run')
    def test_full_success(self):
        report = {}; gate = RegressionGate('full', report)
        self.assertEqual(gate.run(lambda: 42), 42)
        self.assertTrue(report['regressions_passed'])
        self.assertTrue(report['regressions_completed'])
    def test_failure_propagates(self):
        report = {}; gate = RegressionGate('full', report)
        with self.assertRaisesRegex(RuntimeError, 'sentinel'):
            gate.run(lambda: (_ for _ in ()).throw(RuntimeError('sentinel')))
        self.assertFalse(report['regressions_passed'])
        self.assertTrue(report['regressions_attempted'])
        self.assertEqual(report['regressions_status'], 'failed')
    def test_cancellation_propagates(self):
        report = {}; gate = RegressionGate('full', report)
        with self.assertRaises(KeyboardInterrupt): gate.run(lambda: (_ for _ in ()).throw(KeyboardInterrupt()))
        self.assertEqual(report['regressions_status'], 'failed')
    def test_no_double_run(self):
        gate = RegressionGate('full', {}); gate.run(lambda: None)
        with self.assertRaises(ValueError): gate.run(lambda: None)
    def test_unknown_modes_reject(self):
        for mode in ('', 'auto', 'skip', True, None):
            with self.subTest(mode=mode), self.assertRaises(ValueError): RegressionGate(mode, {})
    def test_nested_scope_must_match(self):
        child = {'status': 'passed'}; RegressionGate('none', child)
        with self.assertRaises(ValueError): RegressionGate('full', {}).inherit(child)
    def test_nested_boolean_must_not_be_integer(self):
        child = {'status': 'passed'}; RegressionGate('none', child)
        child['regressions_passed'] = 0
        with self.assertRaises(ValueError): RegressionGate('none', {}).inherit(child)
    def test_nested_missing_fields_reject(self):
        with self.assertRaises(ValueError): RegressionGate('none', {}).inherit({'status': 'passed'})
    def test_unsafe_dynamic_path_rejects(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root/'run-tests.rkt').write_text('(define-runtime-path bad "tests/../bad.rkt")')
            with self.assertRaises(ValueError): global_compile_targets(root)


class OrchestrationTests(unittest.TestCase):
    def run_matrix(self, modes, failure=None, expected=0):
        for name in DIRECT:
            for mode in modes:
                with tempfile.TemporaryDirectory() as d:
                    h = Harness(Path(d), failure=failure)
                    rc, report = h.invoke(name, mode)
                    self.assertEqual(rc, expected, (name, report))
                    yield name, mode, h, report
    def test_defaults_and_explicit_full_run_once(self):
        for name, mode, h, report in self.run_matrix((None, 'full')):
            globals_ = [c for c in h.commands if len(c)>1 and Path(c[1]).name == 'run-tests.rkt']
            self.assertEqual(len(globals_), 1)
            self.assertTrue(report['regressions_passed'])
            self.assertEqual(report['regressions_mode'], 'full')
    def test_none_runs_features_without_global_compilation(self):
        for name, mode, h, report in self.run_matrix(('none',), failure='global'):
            flat = [Path(x).name for c in h.commands for x in c]
            self.assertNotIn('run-tests.rkt', flat)
            self.assertNotIn('unrelated-native-test.rkt', flat)
            self.assertEqual(report['regressions_status'], 'not-run')
            self.assertFalse(report['regressions_passed'])
            self.assertTrue(h.inspections)
            self.assertTrue(any('doctor.rkt' in x or 'gpu-test.rkt' in x for x in flat))
            self.assertIn('pdftoppm', flat)
            self.assertIn('rsvg-convert', flat)
    def test_none_omits_only_global_work_from_command_plan(self):
        for name in DIRECT:
            with self.subTest(validator=name), tempfile.TemporaryDirectory() as d:
                h = Harness(Path(d))
                self.assertEqual(h.invoke(name, 'full')[0], 0)
                full = list(h.commands); h.commands.clear()
                self.assertEqual(h.invoke(name, 'none')[0], 0)
                def normalize(commands):
                    result = []
                    for command in commands:
                        if len(command) > 1 and Path(command[1]).name == 'run-tests.rkt':
                            continue
                        compile_command = len(command) > 1 and command[1] == '-l'
                        fields = []
                        for value in command:
                            if compile_command and Path(value).name in ('run-tests.rkt', 'unrelated-native-test.rkt'):
                                continue
                            value = re.sub(r'evidence-\d+', 'evidence', value)
                            if re.fullmatch('[0-9a-f]{32}', value): value = '<token>'
                            fields.append(value)
                        # Compilation root order is immaterial; dependencies
                        # are resolved by raco, not by the argument ordering.
                        if compile_command: fields = fields[:5] + sorted(set(fields[5:]))
                        result.append(fields)
                    return result
                self.assertEqual(normalize(full), normalize(h.commands))
    def test_full_failure_stops_before_feature_capture(self):
        for name, mode, h, report in self.run_matrix(('full',), failure='global', expected=1):
            self.assertEqual(report['regressions_status'], 'failed')
            self.assertFalse(report['regressions_passed'])
            self.assertFalse(h.inspections)
    def test_feature_failure_is_fatal_in_none(self):
        for _ in self.run_matrix(('none',), failure='feature', expected=1): pass
    def test_compile_failure_is_fatal_in_none(self):
        for _ in self.run_matrix(('none',), failure='compile', expected=1): pass
    def test_inspector_failure_is_fatal_in_none(self):
        for _ in self.run_matrix(('none',), failure='inspector', expected=1): pass
    def test_renderer_failure_is_fatal_in_none(self):
        for _ in self.run_matrix(('none',), failure='renderer', expected=1): pass
    def test_unknown_cli_mode_rejects_every_validator(self):
        for name in ALL:
            with self.subTest(validator=name), tempfile.TemporaryDirectory() as d:
                h = Harness(Path(d)); rc, report = h.invoke(name, 'invalid')
                self.assertEqual(rc, 2); self.assertEqual(h.commands, [])
    def test_missing_required_renderer_never_skips(self):
        for name in DIRECT:
            with self.subTest(validator=name), tempfile.TemporaryDirectory() as d:
                h = Harness(Path(d)); rc, report = h.invoke(name, 'none', missing='rsvg-convert')
                self.assertNotEqual(rc, 0)
    def test_none_does_not_read_the_regression_graph(self):
        for name in DIRECT:
            with self.subTest(validator=name), tempfile.TemporaryDirectory() as d:
                h = Harness(Path(d)); (Path(d)/'run-tests.rkt').unlink()
                rc, report = h.invoke(name, 'none'); self.assertEqual(rc, 0, report)
    def test_dc_specific_baseline_remains_required(self):
        with tempfile.TemporaryDirectory() as d:
            h = Harness(Path(d), failure='dc-baseline'); rc, report = h.invoke('validate-dc-output.py', 'none')
            self.assertEqual(rc, 1); self.assertFalse(report['baseline_passed'])
    def test_nested_document_mode_propagates(self):
        for mode in (None, 'full', 'none'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as d:
                h = Harness(Path(d)); rc, report = h.invoke('validate-dc-closure.py', mode)
                self.assertEqual(rc, 0, report)
                child = next(c for c in h.commands if len(c)>1 and Path(c[1]).name=='validate-dc-output.py')
                self.assertEqual(child[child.index('--regressions')+1], mode or 'full')
                self.assertEqual(report['regressions_mode'], mode or 'full')
                self.assertIs(report['regressions_passed'], mode != 'none')
                self.assertTrue(report['document_baseline_passed'])
    def test_existing_closure_mock_reports_both_scopes(self):
        # Inspect the existing independent fixture without importing its entire
        # source/native test graph into this command-plan test process.
        tree = ast.parse((ROOT/'tools/test-dc-closure.py').read_text())
        function = next(n for n in tree.body if isinstance(n, ast.FunctionDef)
                        and n.name == 'document_report')
        namespace = {'IDENTITY': IDENTITY}
        exec(compile(ast.Module(body=[function], type_ignores=[]), '<existing fixture>', 'exec'), namespace)
        for mode in ('full', 'none'):
            report = namespace['document_report'](regressions=mode)
            parent = {}; RegressionGate(mode, parent).inherit(report)
            self.assertIs(parent['regressions_passed'], mode == 'full')
    def test_nested_forged_regression_pass_rejects(self):
        with tempfile.TemporaryDirectory() as d:
            h = Harness(Path(d), malformed_nested=True)
            rc, report = h.invoke('validate-dc-closure.py', 'none')
            self.assertEqual(rc, 1); self.assertIn('scope/report mismatch', report['error'])


class WorkflowTests(unittest.TestCase):
    def test_all_child_modes_and_safe_shell_arguments(self):
        umbrella = (ROOT/'.github/workflows/acceptance.yml').read_text()
        names = re.findall(r'uses: \./\.github/workflows/([\w-]+\.yml)', umbrella)
        self.assertTrue(names); self.assertEqual(len(set(names)), len(names))
        self.assertEqual(umbrella.count('regressions: ${{ needs.regression-scope.outputs.regressions }}'), len(names))
        self.assertEqual(umbrella.count('    needs: regression-scope\n'), len(names))
        for name in names:
            text = (ROOT/'.github/workflows'/name).read_text()
            with self.subTest(workflow=name):
                self.assertIn("default: 'full'", text)
                self.assertIn("options: ['full', 'none']", text)
                self.assertIn('workflow_call:', text)
                self.assertNotIn('\n  push:', text)
                self.assertNotIn('continue-on-error:', text)
                if name not in ('gpu-dc.yml', 'render-canvas.yml'):
                    self.assertIn('SKIA_REGRESSIONS_MODE: ${{ inputs.regressions }}', text)
                    self.assertIn('--regressions "$SKIA_REGRESSIONS_MODE"', text)
                    if 'windows-2022' in text:
                        self.assertIn('--regressions "$env:SKIA_REGRESSIONS_MODE"', text)
                for step in re.split(r'(?m)^      - ', text)[1:]:
                    if 'run-tests.rkt' in step:
                        self.assertIn("if: inputs.regressions != 'none'", step)
    def test_required_gate_still_requires_all_children(self):
        text = (ROOT/'.github/workflows/acceptance.yml').read_text()
        self.assertIn('name: Acceptance required\n    if: always()', text)
        names = re.findall(r'uses: \./\.github/workflows/([\w-]+)\.yml', text)
        self.assertIn('needs: [regression-scope, ' + ', '.join(names) + ']', text)
        self.assertIn('test "$REGRESSION_SCOPE_RESULT" = success', text)
        for name in names:
            self.assertIn('test "$' + name.upper().replace('-', '_') + '_RESULT" = success', text)
    def test_automatic_scope_truth_table(self):
        for event, ref, manual, expected in (
            ('push', 'refs/heads/main', '', 'none'),
            ('push', 'refs/tags/v0.74', '', 'none'),
            ('pull_request', 'refs/pull/1/merge', '', 'none'),
            ('push', 'refs/heads/topic', '', 'full'),
            ('push', 'refs/tags/other', '', 'full'),
            ('push', 'refs/tags/v0.74/preview', '', 'full'),
            ('push', 'refs/heads/MAIN', '', 'full'),
            ('push', 'refs/tags/V0.74', '', 'full'),
            ('push', 'refs/tags/v', '', 'none'),
            ('schedule', 'refs/heads/main', '', 'full'),
            ('workflow_dispatch', 'refs/heads/main', '', 'full'),
            ('workflow_dispatch', 'refs/heads/main', 'full', 'full'),
            ('workflow_dispatch', 'refs/heads/main', 'none', 'none')):
            with self.subTest(event=event, ref=ref, manual=manual):
                actual = automatic_regression_mode(event, ref, manual)
                self.assertEqual(actual, expected)
    def test_scope_selector_matches_central_automatic_triggers(self):
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        match = re.search(r'(?ms)^on:\n(.*?)(?=^\S)', text)
        self.assertIsNotNone(match)
        self.assertEqual(match[1].strip(),
                         "  push:\n    branches: [main]\n    tags: ['v*']\n"
                         "  pull_request:\n  workflow_dispatch:\n  workflow_call:".strip())
    def test_scope_job_uses_checked_selector(self):
        text = (ROOT/'.github/workflows/acceptance.yml').read_text()
        self.assertIn('run: python3 tools/validation_regressions.py --github-output', text)
        self.assertIn('SKIA_REQUESTED_REGRESSIONS: ${{ inputs.regressions }}', text)
        self.assertIn('regressions: ${{ steps.scope.outputs.regressions }}', text)
    def test_scope_command_writes_output(self):
        with tempfile.TemporaryDirectory() as d:
            output = Path(d)/'github-output'
            env = dict(os.environ, GITHUB_OUTPUT=str(output), GITHUB_EVENT_NAME='push',
                       GITHUB_REF='refs/heads/main', SKIA_REQUESTED_REGRESSIONS='')
            process = subprocess.run([sys.executable, ROOT/'tools/validation_regressions.py',
                                      '--github-output'], env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(process.returncode, 0, process.stderr)
            self.assertEqual(output.read_text(), 'regressions=none\n')
    def test_scope_command_rejects_invalid_input(self):
        with tempfile.TemporaryDirectory() as d:
            output = Path(d)/'github-output'
            env = dict(os.environ, GITHUB_OUTPUT=str(output), GITHUB_EVENT_NAME='workflow_dispatch',
                       GITHUB_REF='refs/heads/main', SKIA_REQUESTED_REGRESSIONS='none\nforged=pass')
            process = subprocess.run([sys.executable, ROOT/'tools/validation_regressions.py',
                                      '--github-output'], env=env, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(process.returncode, 0)
            self.assertFalse(output.exists())
    def test_registered_in_source_gate(self):
        self.assertIn("'test-validation-regressions.py'", (ROOT/'tools/ci.py').read_text())


if __name__ == '__main__':
    unittest.main(verbosity=2)
