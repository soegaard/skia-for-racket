#!/usr/bin/env python3
"""CI infrastructure regressions; no Racket/native/GPU success is inferred.

Filesystem/ZIP/Git and subprocess-log tests really execute locally. Package,
installer and GPU invocations in orchestration tests are explicitly mocked.
"""
from __future__ import annotations
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ci
import ci_matrix


def quiet():
    return contextlib.redirect_stdout(io.StringIO())


def git(root, *args):
    return subprocess.check_output(['git', '-c', 'core.autocrlf=false', *args], cwd=root, stderr=subprocess.STDOUT)


def fixture(root: Path):
    root.mkdir(parents=True, exist_ok=True)
    git(root, 'init', '-q')
    for name, content in {'.gitignore': 'output/\ncompiled/\n__pycache__/\n/chocopkg/\n',
                          'info.rkt': '#lang info\n(define collection "skia")\n',
                          'main.rkt': '#lang racket/base\n',
                          'tools/example.rkt': '#lang racket/base\n'}.items():
        p = root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(content)
    ci.manifest.update(root)
    return root


def headless_fixture(root: Path, surface='surfaceless'):
    root.mkdir(parents=True, exist_ok=True)
    report = dict(status='passed-selected-checks', stage='0.46', validation_run=root.name,
                  gpu_mode='required', skips=[], egl_platform='surfaceless', egl_surface=surface,
                  headless_rendering_verified=True, gl_interop_verified=True,
                  gpu_document_output_verified=True, performance_measurements_verified=True,
                  window_created=False, presentation_verified=False,
                  display_variables_removed=list(ci.DISPLAY_KEYS))
    ci.write_json(root / 'validation.json', report)
    context = dict(renderer_class='software', renderer='llvmpipe (LLVM test)',
                   interface_factory='assembled-desktop-gl', display_server_free=True, requires_glx=False)
    lifecycle = dict(status='passed', validation_run=root.name, required=True, display_environment_unset=True,
                     cycles=[dict(initial_context=copy.deepcopy(context)) for _ in range(3)])
    ci.write_json(root / 'egl-lifecycle.diagnostic.json', lifecycle)
    for name in ('headless', 'output-egl', 'performance-opengl'):
        ci.write_json(root / (name + '.inspection.json'), dict(status='passed', validation_run=root.name))
    return report, lifecycle


class Matrix(unittest.TestCase):
    def bad(self, change):
        data = copy.deepcopy(ci_matrix.load_matrix()); change(data)
        with tempfile.TemporaryDirectory() as t:
            path = Path(t) / 'matrix.json'; ci.write_json(path, data)
            with self.assertRaises((ValueError, TypeError)): ci_matrix.load_matrix(path)
    def test_core_targets(self):
        m = ci_matrix.load_matrix(); self.assertEqual(len(m['cpu']), 5); self.assertEqual(len(m['egl']), 2)
    def test_missing_windows(self): self.bad(lambda m: m['cpu'].pop(3))
    def test_missing_minimum(self): self.bad(lambda m: m['cpu'].pop(4))
    def test_missing_pbuffer(self): self.bad(lambda m: m['egl'].pop())
    def test_wrong_architecture(self): self.bad(lambda m: m['cpu'][1].update(architecture='x64'))
    def test_latest_runner(self): self.bad(lambda m: m['cpu'][0].update(runner='ubuntu-latest'))
    def test_mutable_racket(self): self.bad(lambda m: m['cpu'][0].update(racket='stable'))
    def test_native_migration_not_implicit(self): self.bad(lambda m: m['native_packages'].update(skia='4.0.0'))
    def test_variant(self): self.bad(lambda m: m.update(racket_variant='BC'))
    def test_schema(self): self.bad(lambda m: m.update(stage='0.45'))
    def test_unknown_row_field(self): self.bad(lambda m: m['cpu'][0].update(allow_failure=True))
    def test_duplicate_id(self): self.bad(lambda m: m['egl'][0].update(id=m['cpu'][0]['id']))
    def test_unsafe_id(self): self.bad(lambda m: m['cpu'][0].update(id='../elsewhere'))
    def test_github_outputs_are_json_not_shell(self):
        with tempfile.TemporaryDirectory() as t:
            path = Path(t) / 'output'
            with patch.dict(os.environ, {'GITHUB_OUTPUT': str(path)}), patch.object(sys, 'argv', ['matrix', '--github-output']), quiet():
                ci_matrix.main()
            rows = dict(line.split('=', 1) for line in path.read_text().splitlines())
            self.assertEqual(len(json.loads(rows['cpu'])['include']), 5)
            self.assertEqual(len(json.loads(rows['egl'])['include']), 2)
    def test_no_missing_output_fallback(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(sys, 'argv', ['matrix', '--github-output']):
            with self.assertRaises(ValueError): ci_matrix.main()


class Manifest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = fixture(Path(self.temp.name) / 'source root')
    def test_valid(self): self.assertEqual(ci.manifest.check(self.root), 4)
    def test_update_is_deterministic(self):
        before = (self.root / ci.manifest.NAME).read_bytes(); ci.manifest.update(self.root)
        self.assertEqual(before, (self.root / ci.manifest.NAME).read_bytes())
    def test_check_never_rewrites_mismatch(self):
        before = (self.root / ci.manifest.NAME).read_bytes(); (self.root / 'main.rkt').write_text('changed')
        with self.assertRaises(ValueError): ci.manifest.check(self.root)
        self.assertEqual(before, (self.root / ci.manifest.NAME).read_bytes())
    def test_added_source_not_silent(self):
        (self.root / 'new-file').write_text('new')
        with self.assertRaises(ValueError): ci.manifest.check(self.root)
    def test_ignored_generated_is_not_source(self):
        (self.root / 'compiled').mkdir(); (self.root / 'compiled/a.zo').write_bytes(b'compiled')
        self.assertEqual(ci.manifest.check(self.root), 4)
    def test_setup_racket_windows_scratch_is_not_source(self):
        (self.root / 'chocopkg/tools').mkdir(parents=True)
        (self.root / 'chocopkg/racket.nuspec').write_text('runner scratch')
        (self.root / 'chocopkg/tools/chocolateyInstall.ps1').write_text('runner scratch')
        self.assertEqual(ci.manifest.check(self.root), 4)
    def test_tracked_deletion_requires_staging(self):
        git(self.root, 'add', 'main.rkt'); (self.root / 'main.rkt').unlink()
        with self.assertRaises(ValueError): ci.manifest.update(self.root)
    def test_manifest_only_copy_without_git(self):
        target = Path(self.temp.name) / 'copy'; shutil.copytree(self.root, target, ignore=shutil.ignore_patterns('.git'))
        self.assertEqual(ci.manifest.check(target, manifest_only=True), 4)
        with self.assertRaises(subprocess.CalledProcessError): ci.manifest.check(target)
    def test_manifest_only_still_checks_bytes(self):
        (self.root / 'main.rkt').write_text('changed')
        with self.assertRaises(ValueError): ci.manifest.check(self.root, manifest_only=True)
    def test_duplicate_entries(self):
        p = self.root / ci.manifest.NAME; p.write_text(p.read_text() * 2)
        with self.assertRaises(ValueError): ci.manifest.check(self.root)
    def test_empty_manifest(self):
        (self.root / ci.manifest.NAME).write_text('')
        with self.assertRaises(ValueError): ci.manifest.read_manifest(self.root)
    def test_self_reference(self):
        (self.root / ci.manifest.NAME).write_text('0' * 64 + '  ' + ci.manifest.NAME + '\n')
        with self.assertRaises(ValueError): ci.manifest.read_manifest(self.root)
    def test_malformed_digest(self):
        (self.root / ci.manifest.NAME).write_text('not-a-hash  main.rkt\n')
        with self.assertRaises(ValueError): ci.manifest.read_manifest(self.root)
    def test_unsafe_paths(self):
        for name in ('../secret', '/absolute', 'x/../y', 'x//y', './x', 'C:/x', 'x\\y', 'x\ny'):
            with self.subTest(name=name), self.assertRaises(ValueError): ci.manifest.safe_path(self.root, name)
    def test_symlink_is_rejected(self):
        # Windows developer mode/elevation may be needed; use the path probe in
        # that environment only when an actual symlink can be created.
        target = self.root / 'alias'
        try: target.symlink_to(self.root / 'main.rkt')
        except (OSError, NotImplementedError): self.skipTest('host cannot create a test symlink')
        with self.assertRaises(ValueError): ci.manifest.safe_path(self.root, 'alias')
    def test_cli_environment_readonly_mode(self):
        with patch.object(ci.manifest, 'ROOT', self.root), patch.dict(os.environ,
             {'SKIA_SOURCE_SUMS_MODE': 'check', 'SKIA_SOURCE_SUMS_MANIFEST_ONLY': '1'}), quiet():
            self.assertEqual(ci.manifest.main([]), 0)
    def test_manifest_only_cannot_update(self):
        with patch.dict(os.environ, {'SKIA_SOURCE_SUMS_MODE': 'update', 'SKIA_SOURCE_SUMS_MANIFEST_ONLY': '1'}):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit): ci.manifest.main([])
    def test_invalid_environment_is_not_update(self):
        with patch.dict(os.environ, {'SKIA_SOURCE_SUMS_MODE': 'maybe'}):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit): ci.manifest.main([])
    def test_subdirectory_not_a_root(self):
        with self.assertRaises(ValueError): ci.manifest.git_paths(self.root / 'tools')


class Packaging(unittest.TestCase):
    setUp = Manifest.setUp
    def test_archive_reproducible(self):
        a = Path(self.temp.name) / 'a.zip'; b = a.with_name('b.zip')
        ci.make_source_archive(self.root, a); ci.make_source_archive(self.root, b)
        self.assertEqual(a.read_bytes(), b.read_bytes())
    def test_installed_copy_works_without_staging(self):
        home = Path(self.temp.name) / 'home'; installed = home / 'addon/skia'; installed.mkdir(parents=True)
        archive = Path(self.temp.name) / 'source.zip'; ci.make_source_archive(self.root, archive)
        with zipfile.ZipFile(archive) as z: z.extractall(installed)
        archive.unlink(); ci.verify_install(self.root, installed, home, archive)
    def test_checkout_link_rejected(self):
        with self.assertRaises(ValueError): ci.verify_install(self.root, self.root, self.root.parent / 'home', self.root.parent / 'source.zip')
    def test_changed_installed_file_rejected(self):
        home = Path(self.temp.name) / 'home'; installed = home / 'skia'; shutil.copytree(self.root, installed)
        (installed / 'main.rkt').write_text('changed')
        with self.assertRaises(ValueError): ci.verify_install(self.root, installed, home, home / 'source.zip')
    def test_native_binary_not_packaged(self):
        (self.root / 'leaked.dll').write_bytes(b'not executable'); ci.manifest.update(self.root)
        with self.assertRaises(ValueError): ci.make_source_archive(self.root, self.root.parent / 'source.zip')
    def test_archive_changed_sources_rejected(self):
        (self.root / 'main.rkt').write_text('changed')
        with self.assertRaises(ValueError): ci.make_source_archive(self.root, self.root.parent / 'source.zip')
    def test_windows_uses_existing_installer_and_exact_racket(self):
        commands = ci.install_commands(Path('installed'), '/selected Racket/racket.exe', 'windows')
        self.assertEqual(len(commands), 1); self.assertIn('install-native-windows.py', commands[0][1])
        self.assertEqual(commands[0][-1], '/selected Racket/racket.exe')
    def test_unix_uses_both_existing_installers(self):
        commands = ci.install_commands(Path('installed'), '/selected/racket', 'unix')
        self.assertEqual([Path(c[1]).name for c in commands], ['install-native.sh', 'install-harfbuzz.sh'])

class Evidence(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'gpu-0.46-headless-test'; headless_fixture(self.root)
    def modify(self, filename, fn):
        path = self.root / filename; data = json.loads(path.read_text()); fn(data); ci.write_json(path, data)
        with self.assertRaises((ValueError, KeyError)): ci.validate_headless(self.root, 'surfaceless')
    def test_software_result(self):
        result = ci.validate_headless(self.root, 'surfaceless')
        self.assertEqual(result['status'], 'passed'); self.assertFalse(result['hardware_performance_claimed'])
    def test_explicit_pbuffer(self):
        headless_fixture(self.root, 'pbuffer'); self.assertEqual(ci.validate_headless(self.root, 'pbuffer')['binding_surface'], 'pbuffer')
    def test_wrong_binding_mode(self):
        with self.assertRaises(ValueError): ci.validate_headless(self.root, 'pbuffer')
    def test_failed_run(self): self.modify('validation.json', lambda x: x.update(status='failed'))
    def test_old_stage(self): self.modify('validation.json', lambda x: x.update(stage='0.45'))
    def test_foreign_run(self): self.modify('validation.json', lambda x: x.update(validation_run='foreign'))
    def test_optional_not_accepted(self): self.modify('validation.json', lambda x: x.update(gpu_mode='optional'))
    def test_skip_not_accepted(self): self.modify('validation.json', lambda x: x.update(skips=['GPU unavailable']))
    def test_no_window_allowed(self): self.modify('validation.json', lambda x: x.update(window_created=True))
    def test_no_display_claim(self): self.modify('validation.json', lambda x: x.update(presentation_verified=True))
    def test_missing_completion_gate(self): self.modify('validation.json', lambda x: x.update(performance_measurements_verified=False))
    def test_missing_document_gate(self): self.modify('validation.json', lambda x: x.update(gpu_document_output_verified=False))
    def test_missing_display_removal(self): self.modify('validation.json', lambda x: x.update(display_variables_removed=['DISPLAY']))
    def test_lifecycle_foreign(self): self.modify('egl-lifecycle.diagnostic.json', lambda x: x.update(validation_run='foreign'))
    def test_lifecycle_optional(self): self.modify('egl-lifecycle.diagnostic.json', lambda x: x.update(required=False))
    def test_display_still_present(self): self.modify('egl-lifecycle.diagnostic.json', lambda x: x.update(display_environment_unset=False))
    def test_construction_only_not_enough(self): self.modify('egl-lifecycle.diagnostic.json', lambda x: x.update(cycles=[]))
    def test_hardware_renderer_not_this_lane(self):
        self.modify('egl-lifecycle.diagnostic.json', lambda x: x['cycles'][0]['initial_context'].update(renderer_class='hardware-reported'))
    def test_non_mesa_renderer(self):
        self.modify('egl-lifecycle.diagnostic.json', lambda x: x['cycles'][0]['initial_context'].update(renderer='another renderer'))
    def test_glx_not_egl(self):
        self.modify('egl-lifecycle.diagnostic.json', lambda x: x['cycles'][0]['initial_context'].update(interface_factory='native'))
    def test_hidden_gui_not_headless(self):
        self.modify('egl-lifecycle.diagnostic.json', lambda x: x['cycles'][0]['initial_context'].update(requires_glx=True))
    def test_inspector_failure(self): self.modify('output-egl.inspection.json', lambda x: x.update(status='failed'))
    def test_inspector_mixed_run(self): self.modify('headless.inspection.json', lambda x: x.update(validation_run='foreign'))
    def test_missing_inspection(self):
        (self.root / 'performance-opengl.inspection.json').unlink()
        with self.assertRaises(OSError): ci.validate_headless(self.root, 'surfaceless')


class EnvironmentAndIdentity(unittest.TestCase):
    def test_overrides_are_removed(self):
        dirty = {k: 'dangerous' for k in (*ci.OVERRIDE_KEYS, *ci.DISPLAY_KEYS)}
        dirty.update(GPU_MODE='off', REQUIRE_HARDWARE='1', GPU_STRESS_FRAMES='1', SKIP_C_ABI='1',
                     GPU_BENCH_SAMPLES='1', SKIA_EGL_PLATFORM='other')
        clean = ci.clean_environment(dirty)
        for k in (*ci.OVERRIDE_KEYS, *ci.DISPLAY_KEYS, 'GPU_STRESS_FRAMES', 'SKIP_C_ABI', 'SKIA_EGL_PLATFORM'):
            self.assertNotIn(k, clean)
        self.assertEqual(clean['GPU_MODE'], 'required'); self.assertEqual(clean['SKIA_SOURCE_SUMS_MODE'], 'check')
    def test_isolated_home_and_addon(self):
        home = Path('/isolated/home'); env = ci.clean_environment({'PLTADDONDIR': 'old'}, home)
        self.assertEqual(env['PLTUSERHOME'], str(home)); self.assertEqual(env['PLTADDONDIR'], str(home / 'addon'))
    def test_selected_racket_identity(self):
        r = ci_matrix.load_matrix()['cpu'][0]
        ci.validate_identity(dict(os='unix', architecture='x86_64', vm='chez-scheme', version='9.3', pointer_bytes=8), r)
    def test_identity_mismatches(self):
        r = ci_matrix.load_matrix()['cpu'][0]
        for field, value in [('os', 'windows'), ('architecture', 'aarch64'), ('vm', 'racket'),
                             ('version', '9.3.0.2'), ('pointer_bytes', True), ('pointer_bytes', 4)]:
            d = dict(os='unix', architecture='x86_64', vm='chez-scheme', version='9.3', pointer_bytes=8); d[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): ci.validate_identity(d, r)
    def test_loaded_native_path_receipt(self):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t); (root / 'native').mkdir()
            libraries = {}
            for n in ('skia', 'harfbuzz'):
                p = root / 'native' / n; p.write_bytes(b'receipt test only'); libraries[n] = str(p)
            smoke = dict(status='passed', collection=str(root), native_package_versions={'skia': '3.119.1', 'harfbuzz': '8.3.1.2'},
                         native_versions={'skia': '119.0', 'harfbuzz': '8.3.1'}, libraries=libraries,
                         pixels_verified=True, encoded_roundtrip_verified=True)
            self.assertEqual(len(ci.verify_native_smoke(smoke, root)), 2)
            smoke['libraries']['skia'] = str(root / 'foreign')
            with self.assertRaises(ValueError): ci.verify_native_smoke(smoke, root)
    def test_artifacts_exclude_native_and_compiled(self):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t) / 'installed'; output = Path(t) / 'evidence'; run = root / 'output/gpu-failed'
            run.mkdir(parents=True); native = root / 'native/linux-x64'; native.mkdir(parents=True)
            for name in ('validation.failed.json', 'image.png', 'foo.zo', 'font.ttf', 'archive.nupkg'):
                (run / name).write_bytes(b'test')
            for name in ('SOURCE.txt', 'package.nuspec', 'libSkiaSharp.so', 'font.otf'):
                (native / name).write_bytes(b'test')
            ci.copy_artifacts(root, output)
            names = {p.name for p in output.rglob('*') if p.is_file()}
            self.assertEqual(names, {'validation.failed.json', 'image.png', 'SOURCE.txt', 'package.nuspec'})


class Subprocesses(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.runner = ci.Runner(self.root, dict(os.environ), 5)
    def test_stdout_stderr_and_spaces(self):
        with quiet(): text = self.runner.run([sys.executable, '-c', 'import sys;print(sys.argv[1]);print("stderr",file=sys.stderr)', 'argument with spaces'], cwd=self.root)
        self.assertIn('argument with spaces', text); self.assertIn('stderr', text)
        self.assertEqual(self.runner.commands[0]['returncode'], 0)
    def test_failed_exit_keeps_log(self):
        with quiet(), self.assertRaises(RuntimeError):
            self.runner.run([sys.executable, '-c', 'print("before failure");raise SystemExit(7)'], cwd=self.root)
        self.assertEqual(self.runner.commands[0]['returncode'], 7)
        self.assertIn('before failure', (self.root / 'logs/001.log').read_text())
        self.assertTrue((self.root / 'commands.json').is_file())
    def test_timeout_never_passes(self):
        self.runner.timeout = 1
        with quiet(), self.assertRaises(RuntimeError):
            self.runner.run([sys.executable, '-c', 'import time;print("started",flush=True);time.sleep(30)'], cwd=self.root)
        self.assertTrue(self.runner.commands[0]['timed_out'])
        # A loaded CI host can kill the child before Python reaches its first
        # print. Log existence and a recorded nonzero timeout are the contract.
        self.assertTrue((self.root / 'logs/001.log').is_file())
        self.assertNotEqual(self.runner.commands[0]['returncode'], 0)
    def test_launch_failure_recorded(self):
        with quiet(), self.assertRaises(OSError): self.runner.run([str(self.root / 'missing executable')], cwd=self.root)
        self.assertIn('launch_error', self.runner.commands[0])


class WorkflowAndIntegration(unittest.TestCase):
    def test_action_pins_and_readonly_permissions(self):
        s = (HERE.parent / '.github/workflows/ci.yml').read_text()
        uses = re.findall(r'^\s*- uses: (\S+)', s, re.M) + re.findall(r'^\s*uses: (\S+)', s, re.M)
        self.assertTrue(uses)
        for action in uses: self.assertRegex(action, r'^[\w.-]+/[\w.-]+@[0-9a-f]{40}$')
        self.assertIn('contents: read', s); self.assertEqual(s.count('persist-credentials: false'), 5)
        uncommented = '\n'.join(l for l in s.splitlines() if not l.lstrip().startswith('#'))
        for bad in ('pull_request_target:', 'self-hosted', 'continue-on-error:', 'secrets.', 'xvfb-run', 'actions/cache'):
            self.assertNotIn(bad, uncommented)
    def test_required_aggregate_and_retained_artifacts(self):
        s = (HERE.parent / '.github/workflows/ci.yml').read_text()
        self.assertIn('needs: [source, cpu, egl, d3d12, dxgi]', s); self.assertIn('name: CI required\n    if: always()', s)
        for group in ('SOURCE', 'CPU', 'EGL', 'D3D12', 'DXGI'): self.assertIn(f'test "${group}_RESULT" = success', s)
        uploads = len(re.findall(r'^\s*uses: actions/upload-artifact@', s, re.M))
        self.assertGreaterEqual(uploads, 1)
        self.assertEqual(s.count('if: always()'), uploads + 1)
        self.assertEqual(s.count('fail-fast: false'), 2)
    def test_lf_and_python_ignore(self):
        self.assertIn('* text=auto eol=lf', (HERE.parent / '.gitattributes').read_text())
        self.assertIn('__pycache__/', (HERE.parent / '.gitignore').read_text())
        self.assertIn('/chocopkg/', (HERE.parent / '.gitignore').read_text())
    def test_racket_package_metadata_is_canonical_and_complete(self):
        text = (HERE.parent / 'info.rkt').read_text()
        self.assertIn('(define version "0.51")', text)
        self.assertIn('(define deps \'(("base" #:version "8.7") "draw-lib" "gui-lib" "rackunit-lib"))', text)
        self.assertNotIn('(define build-deps \'("rackunit-lib"))', text)
    def test_symbol_auditors_normalize_nm_formats(self):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t)
            tools = root / 'tools'; private = root / 'private'; bin_dir = root / 'bin'
            tools.mkdir(); private.mkdir(); bin_dir.mkdir()
            for name in ('audit-symbols.sh', 'audit-harfbuzz-symbols.sh'):
                shutil.copy2(HERE / name, tools / name)
            (private / 'native.rkt').write_text(
                '(define-native sk_canvas_clear ignored)\n'
                '(define-native sk_surface_unref ignored)\n')
            (private / 'harfbuzz-native.rkt').write_text(
                '(define-hb-native hb_shape ignored)\n'
                '(define-hb-native hb_version ignored)\n')
            nm = bin_dir / 'nm'
            nm.write_text(
                '#!/usr/bin/env sh\n'
                "printf '%s\\n' '00000000 T _sk_canvas_clear' "
                "'00000001 T sk_surface_unref@@SKIA_119' "
                "'00000002 T _hb_shape' '00000003 T hb_version@HB_8'\\n")
            uname = bin_dir / 'uname'
            uname.write_text("#!/usr/bin/env sh\nprintf '%s\\n' Linux\n")
            nm.chmod(0o755); uname.chmod(0o755)
            env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ.get('PATH', ''))
            for script, library in (('audit-symbols.sh', 'libSkiaSharp.so'),
                                    ('audit-harfbuzz-symbols.sh', 'libHarfBuzzSharp.so')):
                path = root / library; path.write_bytes(b'fake nm input only')
                result = subprocess.run(['bash', str(tools / script), str(path)],
                                        cwd=root, env=env, text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn('Missing required symbols: 0', result.stdout)
    def test_linux_native_installer_uses_fontconfig_build(self):
        text = (HERE / 'install-native.sh').read_text()
        self.assertIn('PACKAGE=skiasharp.nativeassets.linux\n', text)
        self.assertNotIn('skiasharp.nativeassets.linux.nodependencies', text)
        workflow = (HERE.parent / '.github/workflows/ci.yml').read_text()
        self.assertIn('fontconfig fonts-dejavu-core', workflow)
        self.assertEqual(workflow.count('fonts-noto-cjk'), 2)
    def test_stage_reports_do_not_claim_global_linux_ci_acceptance(self):
        for name in ('gpu-performance-doctor.rkt', 'gpu-output-doctor.rkt',
                     'inspect-gpu-output.py', 'inspect-gpu-performance.py'):
            text = (HERE / name).read_text()
            self.assertNotIn('linux_headless_baseline_status', text)
            self.assertNotIn('deferred-to-future-CI', text)
    def test_full_headless_stress_not_shortened(self):
        text = (HERE / 'ci.py').read_text()
        self.assertIn('tools/validate-gpu-headless.py', text)
        self.assertNotIn("GPU_STRESS_FRAMES='", text)
        self.assertIn("SKIA_SOURCE_SUMS_MANIFEST_ONLY='1'", text)
    def test_import_smoke_contract_matches_reader(self):
        self.assertIn("'gui_instantiated #f", (HERE / 'ci-import-smoke.rkt').read_text())
        self.assertIn("imports.get('gui_instantiated') is False", (HERE / 'ci.py').read_text())
    def test_cmake_lists_all_mirrors(self):
        s = (HERE / 'ci-abi/CMakeLists.txt').read_text()
        for name in ci.ABI_NAMES: self.assertIn(name, s)
        self.assertIn('if(MSVC)', s); self.assertIn('add_test', s)
    def test_local_runners_integrate_ci_and_keep_sums_last(self):
        for name in ('test-validate-gpu-images.py', 'test-validate-gpu-headless.py'):
            spec = importlib.util.spec_from_file_location('ci_integration_' + name, HERE / name)
            m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
            result = m.Checks().simulate()
            self.assertEqual(result[0], 0); calls = result[1]
            self.assertIn('tools/test-ci.py', [c[1] for c in calls])
            self.assertEqual(calls[-1][1], 'tools/update-source-sums.py')
            report = result[2] if name.endswith('images.py') else result[3]
            self.assertEqual(report['stage'], '0.46')


class Orchestration(unittest.TestCase):
    def simulate(self, profile='cpu', lane='linux-x64', fail=None):
        with tempfile.TemporaryDirectory() as t:
            temp = Path(t); root = fixture(temp / 'checkout'); output = temp / 'artifact'; output.mkdir()
            calls = []; saved_envs = []; seen_installed = []; report = {'checks': {}}
            row = next(r for r in ci_matrix.load_matrix()[profile] if r['id'] == lane)
            identity = dict(os=row['os'], architecture=row['racket_arch'], vm='chez-scheme', version=row['racket'], pointer_bytes=8)
            class Fake:
                env = ci.clean_environment(dict(os.environ))
                def run(self, argv, *, cwd, env=None):
                    a = [str(v) for v in argv]; calls.append(a); e = self.env if env is None else env; saved_envs.append(dict(e))
                    if fail and any(fail in v for v in a): raise RuntimeError('mocked command failure')
                    if a[1].endswith('ci-identity.rkt'): return json.dumps(identity)
                    if 'pkg' in a and 'install' in a:
                        home = Path(e['PLTUSERHOME']); installed = home / 'addon/pkgs/skia-for-racket'; installed.mkdir(parents=True)
                        with zipfile.ZipFile(a[-1]) as z: z.extractall(installed)
                        seen_installed.append(installed)
                    if '(collection-path "skia")' in a[-1]: return json.dumps(str(seen_installed[0]))
                    if a[-1] == 'skia/tools/ci-import-smoke': return json.dumps(dict(status='passed', gui_instantiated=False))
                    if 'install-native' in a[1] or 'install-harfbuzz' in a[1]:
                        n = seen_installed[0] / 'native'; n.mkdir(exist_ok=True)
                        for k in ('skia', 'harfbuzz'): (n / k).write_bytes(b'mocked native receipt, not executable')
                    if a[-1] == 'skia/tools/ci-package-smoke':
                        installed = seen_installed[0]
                        return json.dumps(dict(status='passed', collection=str(installed),
                            native_package_versions={'skia': '3.119.1', 'harfbuzz': '8.3.1.2'},
                            native_versions={'skia': '119.0', 'harfbuzz': '8.3.1'},
                            libraries={k: str(installed / 'native' / k) for k in ('skia', 'harfbuzz')},
                            pixels_verified=True, encoded_roundtrip_verified=True))
                    if a[1].endswith('native-abi-doctor.rkt'):
                        return json.dumps(dict(required_cpu_symbols_resolved=True, racket_layouts_checked=True))
                    if a[1].endswith('native-abi-lab.py'):
                        candidate_output = Path(a[a.index('--output') + 1])
                        candidate_output.mkdir(parents=True, exist_ok=False)
                        ci.write_json(candidate_output / 'report.json',
                                      dict(status='passed-investigation-candidate-rejected'))
                    if a[1].endswith('validate-gpu-headless.py'):
                        headless_fixture(seen_installed[0] / 'output/gpu-0.46-headless-mock', row['surface'])
                    return ''
            fake = Fake(); fake.output = output
            with patch.object(ci.shutil, 'which', return_value=str(temp / 'selected Racket/racket')), patch.object(ci.sys, 'platform', 'linux'):
                error = None
                try: ci.package_checks(fake, root, row, profile, report)
                except (RuntimeError, ValueError) as exc: error = str(exc)
            return calls, saved_envs, report, error, sorted(p.name for p in output.rglob('*') if p.is_file())
    def test_cpu_installed_package_order(self):
        c, envs, r, e, _ = self.simulate(); self.assertIsNone(e); self.assertTrue(r['checks']['cpu_regressions'])
        self.assertEqual(r['gpu']['status'], 'not-run')
        self.assertTrue(r['checks']['native_abi_preflight'])
        self.assertTrue(r['checks']['candidate_abi_rejection'])
        self.assertTrue(any(a[1].endswith('native-abi-lab.py') for a in c))
        self.assertIn('--no-cache', next(a for a in c if 'install' in a))
        self.assertTrue(any('--check-pkg-deps' in a for a in c)); self.assertTrue(any(a[0] == 'ctest' for a in c))
        self.assertEqual(c[-1][-2:], ['--check', '--manifest-only'])
        native = next(i for i, a in enumerate(c) if 'install-native' in a[1])
        pure = next(i for i, a in enumerate(c) if '--pure' in a)
        self.assertLess(pure, native)
    def test_candidate_failure_blocks_success(self):
        _, _, r, e, _ = self.simulate(fail='native-abi-lab.py')
        self.assertIsNotNone(e)
        self.assertNotIn('candidate_abi_rejection', r['checks'])
        self.assertNotIn('gpu', r)
    def test_selected_interpreter_every_raco(self):
        c, _, r, e, _ = self.simulate(); self.assertIsNone(e)
        for a in c:
            if 'raco' in a or a[1].endswith('.rkt') or a[-1].startswith('skia/tools/'):
                self.assertEqual(a[0], r['racket_executable'])
    def test_cpu_failure_no_success(self):
        _, _, r, e, _ = self.simulate(fail='run-tests.rkt'); self.assertIsNotNone(e)
        self.assertNotIn('cpu_regressions', r['checks']); self.assertNotIn('gpu', r)
    def test_setup_failure_not_ignored(self):
        _, _, r, e, _ = self.simulate(fail='--check-pkg-deps'); self.assertIsNotNone(e)
        self.assertNotIn('package_setup_and_dependencies', r['checks'])
    def test_installer_failure_not_ignored(self):
        _, _, r, e, _ = self.simulate(fail='install-native'); self.assertIsNotNone(e)
        self.assertNotIn('fresh_native_install', r['checks'])
    def test_egl_requires_software_and_no_display(self):
        c, envs, r, e, names = self.simulate('egl', 'egl-pbuffer'); self.assertIsNone(e)
        ix = next(i for i, a in enumerate(c) if a[1].endswith('validate-gpu-headless.py'))
        for k in ci.DISPLAY_KEYS: self.assertNotIn(k, envs[ix])
        for k, v in dict(GPU_MODE='required', GALLIUM_DRIVER='llvmpipe', LIBGL_ALWAYS_SOFTWARE='1', SKIA_EGL_SURFACE='pbuffer').items():
            self.assertEqual(envs[ix][k], v)
        self.assertEqual(r['gpu']['renderer_class'], 'software'); self.assertIn('validation.json', names)
    def test_egl_failure_not_skipped(self):
        _, _, r, e, _ = self.simulate('egl', 'egl-surfaceless', fail='validate-gpu-headless.py')
        self.assertIsNotNone(e); self.assertNotIn('gpu', r)
    def test_windows_uses_msvc_and_skips_unix_nm_only(self):
        c, _, r, e, _ = self.simulate('cpu', 'windows-x64'); self.assertIsNone(e)
        self.assertTrue(any('-A' in a and 'x64' in a for a in c))
        self.assertFalse(any('audit-symbols.sh' in a[1] for a in c)); self.assertTrue(r['checks']['cpu_regressions'])
        self.assertFalse(any(a[1].endswith('native-abi-lab.py') for a in c))


class DriverResults(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = fixture(Path(self.temp.name) / 'source')
        git(self.root, 'add', '.')
        git(self.root, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture')
    def run_driver(self, callback):
        with patch.object(ci, 'ROOT', self.root), patch.object(ci, 'source_checks', side_effect=callback), quiet(), contextlib.redirect_stderr(io.StringIO()):
            code = ci.main(['--profile', 'source', '--id', 'source'])
        result = json.loads((self.root / 'output/ci-source/ci-report.json').read_text())
        return code, result
    def test_success_keeps_manifest_and_disclaims_hardware(self):
        before = (self.root / ci.manifest.NAME).read_bytes()
        code, result = self.run_driver(lambda runner, root, report: report.update(gpu={'status': 'not-run'}))
        self.assertEqual(code, 0); self.assertEqual(result['status'], 'passed')
        self.assertFalse(result['hardware_performance_claimed'])
        self.assertEqual(before, (self.root / ci.manifest.NAME).read_bytes())
    def test_failure_has_machine_readable_report(self):
        def fail(*args): raise RuntimeError('explicit synthetic failure')
        code, result = self.run_driver(fail)
        self.assertEqual(code, 1); self.assertEqual(result['status'], 'failed')
        self.assertIn('synthetic failure', result['error'])
        self.assertTrue((self.root / 'output/ci-source/commands.json').is_file())
    def test_source_mutation_blocks_success(self):
        def mutate(runner, root, report): (root / 'main.rkt').write_text('mutated by simulated subprocess')
        code, result = self.run_driver(mutate)
        self.assertEqual(code, 1); self.assertEqual(result['status'], 'failed')
    def test_stale_directory_is_not_reused(self):
        self.run_driver(lambda *args: None)
        with self.assertRaises(FileExistsError): self.run_driver(lambda *args: None)
    def test_corrupt_installed_manifest_is_not_authoritative(self):
        home = Path(self.temp.name) / 'home'; installed = home / 'addon/skia'
        shutil.copytree(self.root, installed)
        (installed / ci.manifest.NAME).write_text('0' * 64 + '  main.rkt\n')
        with self.assertRaises(ValueError): ci.verify_install(self.root, installed, home, home / 'source.zip')


if __name__ == '__main__':
    unittest.main(verbosity=2)
