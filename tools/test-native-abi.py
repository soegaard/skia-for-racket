#!/usr/bin/env python3
"""0.47 regressions. Shared libraries here are tiny C fixtures, NOT Skia.

Default includes integration assertions against a complete checkout. Named
unittest classes can be run independently when reviewing a source-only bundle.
"""
from __future__ import annotations
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile

import native_abi as abi


class PolicyTests(unittest.TestCase):
    def test_default(self): self.assertEqual(abi.default_version(), '3.119.1')
    def test_supported(self): self.assertEqual(abi.profile_for(abi.catalog(), 119, 0, 8)['id'], 'skiasharp-m119')
    def test_increment(self): self.assertIsNotNone(abi.profile_for(abi.catalog(), 119, 1, 8))
    def test_candidate_closed(self): self.assertIsNone(abi.profile_for(abi.catalog(), 153, 0, 8))
    def test_32bit_closed(self): self.assertIsNone(abi.profile_for(abi.catalog(), 119, 0, 4))
    def test_future_closed(self): self.assertIsNone(abi.profile_for(abi.catalog(), 1000, 0, 8))
    def test_negative(self):
        with self.assertRaises(ValueError): abi.profile_for(abi.catalog(), 119, -1, 8)
    def test_bool_is_not_version(self):
        with self.assertRaises(ValueError): abi.profile_for(abi.catalog(), True, 0, 8)
    def test_ambiguous_profiles(self):
        data = abi.catalog(); data['profiles'] *= 2
        with self.assertRaises(ValueError): abi.profile_for(data, 119, 0, 8)
    def test_layout_count(self): self.assertEqual(len(abi.catalog()['profiles'][0]['layout_sizes']), 27)
    def test_direct3d_wrapper_and_no_graphite(self):
        contracts = abi.catalog()['profiles'][0]['contracts']
        self.assertFalse(contracts['graphite_wrapper']); self.assertTrue(contracts['direct3d_wrapper'])
    def test_package_targets(self):
        self.assertEqual(abi.target_package('Linux', 'x86_64'), ('skiasharp.nativeassets.linux', 'linux-x64', 'libSkiaSharp.so'))
        self.assertEqual(abi.target_package('Darwin', 'arm64')[1], 'osx')
        self.assertEqual(abi.target_package('Windows', 'AMD64')[1], 'win-x64')
    def test_unsupported_host(self):
        with self.assertRaises(ValueError): abi.target_package('Windows', 'arm64')
    def test_https_only(self):
        with self.assertRaises(ValueError): abi.download('http://example.invalid/p', Path('never-written'))
    def test_redirect_downgrade(self):
        with self.assertRaises(ValueError): abi.HTTPSRedirects().redirect_request(None, None, 302, '', {}, 'http://example.invalid')


class ReaderTests(unittest.TestCase):
    def test_brackets(self): self.assertEqual(abi.forms('(a [b {c}])'), [['a', ['b', ['c']]]])
    def test_strings_comments(self):
        self.assertEqual(abi.forms('#lang racket/base\n; hi\n#| (bad #| nested |#) |# (a "(")')[0][0], 'a')
    def test_datum_comment(self): self.assertEqual(abi.forms('#;(ignore me) (keep)'), [['keep']])
    def test_nested_datum_comment(self): self.assertEqual(abi.forms('#; #; (first) (second) (keep)'), [['keep']])
    def test_quotes_not_declarations(self):
        self.assertEqual(abi.forms("'(define-native sk_fake _int)")[0][0], 'quote')
    def test_unclosed(self):
        with self.assertRaises(ValueError): abi.forms('(bad')
    def test_mismatched(self):
        with self.assertRaises(ValueError): abi.forms('(bad]')
    def test_comment_incomplete(self):
        with self.assertRaises(ValueError): abi.forms('#| bad')
    def test_inventory_uses_real_top_level_forms(self):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t); (root / 'private').mkdir()
            for path, macro, index, _ in abi.BINDINGS:
                prefix = ' '.join(['alias'] * (index - 1))
                (root / path).write_text(f'#lang racket/base\n; ({macro} {prefix} sk_comment (_fun))\n'
                    f"'({macro} {prefix} sk_quoted (_fun))\n"
                    f'(define-syntax-rule ({macro} x) (ignored x))\n'
                    f'({macro} {prefix} sk_actual (_fun -> _int))\n')
            groups = abi.source_inventory(root)
            self.assertEqual(len(groups), 7)
            self.assertTrue(all(names == ['sk_actual'] for names in groups.values()))
    def test_missing_registry_fails(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaises(FileNotFoundError): abi.source_inventory(Path(t))


class ArchiveTests(unittest.TestCase):
    package = 'skiasharp.nativeassets.linux'
    version = '4.153.1'
    member = 'runtimes/linux-x64/native/libSkiaSharp.so'
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
    def archive(self, *, version=None, package=None, duplicate=False, symlink=False, missing=False, xml=None, payload=b'FIXTURE-NOT-SKIA'):
        path = self.root / 'input.nupkg'
        with zipfile.ZipFile(path, 'w') as z:
            z.writestr('package.nuspec', xml or f'<package><metadata><id>{package or self.package}</id><version>{version or self.version}</version></metadata></package>')
            z.writestr('../escape.txt', 'not extracted')
            if not missing:
                info = zipfile.ZipInfo(self.member)
                if symlink: info.create_system = 3; info.external_attr = (stat.S_IFLNK | 0o777) << 16
                z.writestr(info, payload)
                if duplicate:
                    with warnings.catch_warnings():
                        warnings.simplefilter('ignore'); z.writestr(self.member, payload)
        return path
    def extract(self, **kw): return abi.extract_package(self.archive(**kw), self.package, self.version, self.member, self.root / 'library')
    def test_fixed_member(self):
        report = self.extract()
        self.assertEqual((self.root / 'library').read_bytes(), b'FIXTURE-NOT-SKIA')
        self.assertFalse((self.root.parent / 'escape.txt').exists())
        self.assertTrue(report['hashes_are_observations_not_independent_authentication'])
    def test_wrong_version(self):
        with self.assertRaises(ValueError): self.extract(version='4.0.0')
    def test_wrong_package(self):
        with self.assertRaises(ValueError): self.extract(package='other')
    def test_duplicate(self):
        with self.assertRaises(ValueError): self.extract(duplicate=True)
    def test_symlink(self):
        with self.assertRaises(ValueError): self.extract(symlink=True)
    def test_missing(self):
        with self.assertRaises(ValueError): self.extract(missing=True)
    def test_empty(self):
        with self.assertRaises(ValueError): self.extract(payload=b'')
    def test_dtd(self):
        with self.assertRaises(ValueError): self.extract(xml='<!DOCTYPE package><package/>')
    def test_duplicate_metadata(self):
        with self.assertRaises(ValueError): self.extract(xml='<package><metadata/><metadata/></package>')
    def test_no_overwrite(self):
        (self.root / 'library').write_text('existing')
        with self.assertRaises(FileExistsError): self.extract()
        self.assertEqual((self.root / 'library').read_text(), 'existing')
    def test_size_bound(self):
        with mock.patch.object(abi, 'MAX_NATIVE', 1):
            with self.assertRaises(ValueError): self.extract()
    def test_archive_size_bound(self):
        with mock.patch.object(abi, 'MAX_ARCHIVE', 1):
            with self.assertRaises(ValueError): self.extract()


class WorkerTests(unittest.TestCase):
    """Compile and execute C fixture libraries in isolated subprocesses."""
    @classmethod
    def setUpClass(cls):
        cls.compiler = shutil.which(os.environ.get('CC', 'cc'))
        if not cls.compiler:
            raise RuntimeError('C compiler required for native ABI worker regressions; do not skip in CI')
        if sys.platform not in ('linux', 'darwin'):
            raise RuntimeError('C fixture tests require the Unix source-check lane')
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
    def library(self, milestone='return 119;', increment=True, extra=''):
        source = self.root / 'fixture.c'
        source.write_text('#include <stdbool.h>\n#include <stdlib.h>\n#include <signal.h>\n'
            'int sk_version_get_milestone(void) {' + milestone + '}\n' +
            ('int sk_version_get_increment(void) { return 0; }\n' if increment else '') + extra)
        lib = self.root / ('fixture.dylib' if sys.platform == 'darwin' else 'fixture.so')
        subprocess.run([self.compiler, '-dynamiclib' if sys.platform == 'darwin' else '-shared', '-fPIC', str(source), '-o', str(lib)], check=True, capture_output=True)
        return lib
    def probe(self, lib, *, timeout=10, graphite=153):
        output = self.root / 'evidence'; output.mkdir()
        groups = {'cpu': ['sk_version_get_milestone', 'sk_missing'], 'graphite': ['sk_graphite_backend_is_available']}
        return abi.run_probe(lib, groups, output, timeout, graphite_milestone=graphite), groups
    def test_observes_without_calling_other_symbols(self):
        result, groups = self.probe(self.library(extra='void sk_missing(void) { abort(); }'))
        self.assertTrue(result['symbols']['sk_missing'])
        self.assertEqual(result['native_calls'], ['sk_version_get_milestone', 'sk_version_get_increment'])
        self.assertFalse(result['rendering_executed'])
        assessed = abi.assessment(abi.catalog(), result, groups)
        self.assertEqual(assessed['wrapper_load_policy'], 'eligible-for-runtime-checks')
        self.assertFalse(assessed['runtime_suite_executed'])
    def test_missing_cpu_rejects(self):
        result, groups = self.probe(self.library())
        self.assertEqual(abi.assessment(abi.catalog(), result, groups)['wrapper_load_policy'], 'reject')
    def test_candidate_never_enabled_by_symbols(self):
        result, groups = self.probe(self.library('return 153;', extra='void sk_missing(void) {}'))
        assessed = abi.assessment(abi.catalog(), result, groups)
        self.assertEqual(assessed['missing_symbols']['cpu'], [])
        self.assertEqual(assessed['wrapper_load_policy'], 'reject')
        self.assertIsNone(assessed['supported_profile'])
    def test_graphite_compilation_is_not_device_support(self):
        result, _ = self.probe(self.library('return 153;', extra='bool sk_graphite_backend_is_available(int n) { return n == 2; }'))
        self.assertEqual(result['graphite_compiled_backends'], {'dawn': False, 'metal': False, 'vulkan': True})
        self.assertFalse(result['backend_creation_verified'])
    def test_unreviewed_graphite_function_not_called(self):
        result, _ = self.probe(self.library('return 154;', extra='bool sk_graphite_backend_is_available(int n) { abort(); }'))
        self.assertIsNone(result['graphite_compiled_backends'])
    def test_missing_bootstrap_is_failure(self):
        with self.assertRaisesRegex(ValueError, 'failed/crashed'): self.probe(self.library(increment=False))
    def test_signal_termination_is_failure(self):
        # SIGKILL exercises abnormal worker termination without asking macOS
        # Crash Reporter to record an intentional SIGABRT from the fixture.
        with self.assertRaisesRegex(ValueError, 'failed/crashed'):
            self.probe(self.library('raise(SIGKILL);'))
    def test_timeout_is_failure(self):
        with self.assertRaisesRegex(ValueError, 'timed out'): self.probe(self.library('for (;;) {}'), timeout=1)
    def test_missing_file_is_failure(self):
        with self.assertRaisesRegex(ValueError, 'failed/crashed'): self.probe(self.root / 'absent')
    def test_environment_sanitized(self):
        with mock.patch.dict(os.environ, {'RACKET_SKIA_LIBRARY': 'ambient', 'LD_PRELOAD': 'ambient'}):
            env = abi.clean_probe_environment()
            self.assertNotIn('RACKET_SKIA_LIBRARY', env); self.assertNotIn('LD_PRELOAD', env)


class IntegrationTests(unittest.TestCase):
    def test_real_registries_nonempty(self):
        groups = abi.source_inventory()
        self.assertGreater(len(groups['cpu']), 300)
        self.assertEqual(set(groups), {entry[3] for entry in abi.BINDINGS})
    def test_one_shared_handle(self):
        for path, _, _, _ in abi.BINDINGS[1:]:
            source = (abi.ROOT / path).read_text()
            self.assertIn('(delay/sync (skia-native-library-handle))', source)
            self.assertNotIn('(ffi-lib (skia-native-library-path))', source)
    def test_layout_gate_and_preflight_preserved(self):
        source = (abi.ROOT / 'private/native.rkt').read_text()
        self.assertIn('(native-abi-check-layouts! (native-library-profile) (native-layout-sizes))', source)
        self.assertIn('(for ([entry (in-list (reverse native-bindings))])', source)
        self.assertIn('lifetime-native-call', source)
    def test_racket_suites_wired(self):
        source = (abi.ROOT / 'run-tests.rkt').read_text()
        self.assertIn('(run-tests native-abi-pure-tests)', source)
        self.assertIn("dynamic-require native-abi-native-tests-file 'native-abi-native-tests", source)
    def test_ci_candidate_is_required_on_linux(self):
        source = (abi.ROOT / 'tools/ci.py').read_text()
        self.assertIn("if row['id'] == 'linux-x64':", source)
        self.assertIn("'--candidate', '--racket', racket", source)
        self.assertIn("report['checks']['candidate_abi_rejection'] = True", source)
        workflow = (abi.ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn('needs: [source, cpu, egl, d3d12, dxgi, canvas]', workflow)
        self.assertNotIn('continue-on-error', workflow)
    def test_default_pin_single_runtime_source(self):
        self.assertIn('native-default-version.txt', (abi.ROOT / 'tools/install-native.sh').read_text())
        self.assertIn('default_version()', (abi.ROOT / 'tools/install-native-windows.py').read_text())
    def test_no_native_payload_in_new_tools(self):
        self.assertNotIn('extractall(', (abi.ROOT / 'tools/native_abi.py').read_text())
        self.assertIn("output.mkdir(parents=True, exist_ok=False)", (abi.ROOT / 'tools/native_abi.py').read_text())


if __name__ == '__main__': unittest.main(verbosity=2)
