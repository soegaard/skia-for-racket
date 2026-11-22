#!/usr/bin/env python3
"""Catalog evidence must reject partial, mismatched and fabricated receipts."""
import copy
import hashlib
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath, PureWindowsPath
from types import SimpleNamespace
from unittest.mock import patch
import catalog_release as c
import catalog_asset_evidence as asset_evidence
import native_packages as n
from catalog_execution import (PKG_BUILD_PROFILE, PROFILE_FILE, RUNTIME_ENVIRONMENTS,
                               preserved_package_files, racket_command,
                               relocatable_runtime, relocate_runtime_cache,
                               runtime_child_environment, windows_network_programs)

SHA = 'a'*64
COMMIT = 'b'*40


def tool(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), n.ROOT / 'tools' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixtures():
    native = dict(origin='managed', absolute_path='/home/test/lib/skia-native-1/lib.so',
                  managed_directory='/home/test/lib/skia-native-1', installed_sha256=SHA,
                  manifest=dict(lock_sha256=SHA, files={k:dict(sha256=SHA) for k in ('skia','harfbuzz')}))
    smokes = [dict(status='passed', source_version='0.79', text_load_order=order,
                   skia=dict(loader=copy.deepcopy(native)), harfbuzz=copy.deepcopy(native))
              for order in ('skia-first','draw-first')]
    report = dict(status='passed-local-selected-checks', checks={key:True for key in c.REQUIRED_CHECKS},
                  execution_uid=1001,
                  identity=dict(version='9.3', target='x86_64-linux'), drdr_seconds=37.4,
                  network_denial=[dict(address=address,errno=101) for address in ('1.1.1.1','8.8.8.8')],
                  smoke=smokes, rebuilt_smoke={form:copy.deepcopy(smokes) for form in ('source','built','binary-lib')})
    staging = dict(lock_sha256=SHA, snapshot_candidates_preserved=True, source=dict(sha256=SHA, source_worktree_clean=True, source_commit_observed=COMMIT),
                   dependency_snapshot=dict(packages=[dict(package='base', sha256=SHA)], catalog_racket_datum='#hash()',
                                            catalog_sha256=hashlib.sha256(b'#hash()').hexdigest()),
                   identity=report['identity'], artifacts=dict(artifacts=[dict(archive='native.zip',sha256=SHA)]))
    return report, staging


def cache_fixture(report):
    source = PurePosixPath('/qualification/prepared runtime')
    report['runtime_source'] = str(source)
    report['runtime_cache_relocations'] = []
    for name in RUNTIME_ENVIRONMENTS:
        copied = PurePosixPath('/qualification/execution') / name / 'Racket runtime'
        report['runtime_cache_relocations'].append(dict(
            environment=name, source_runtime=str(source), copied_runtime=str(copied),
            old_cache=str(copied / 'zo' / source.relative_to('/')),
            new_cache=str(copied / 'zo' / copied.relative_to('/')), bytecode_files=143))
    first = PurePosixPath(report['runtime_cache_relocations'][0]['copied_runtime'])
    report['drdr_child_runtime'] = dict(version=report['identity']['version'], target='x86_64-linux-natipkg',
        running_machine='ta6le', compile_target_machine='ta6le', executable=str(first / 'bin/racket'),
        compiled_roots=[str(first / 'zo'), 'same'], compiled_roots_environment=str(first / 'zo') + ':')
    report['commands'] = [dict(command=[str(first / 'bin/racket'), '-MCR', str(first / 'zo') + ':',
                                       '-l', 'raco', 'test', '--drdr', '--package', 'skia'],
                              exit_code=0, runtime_child_environment={
                                  'PLTCOMPILEDROOTS': str(first / 'zo') + ':'})]


def windows_fixture():
    import windows_native as w
    report, staging = fixtures()
    report['identity']['target'] = 'win32\\x86_64'
    lock = n.read_json(n.ROOT / 'packaging/native-assets.json')
    records = w.records(lock)
    acquisition = dict(route=w.ROUTE, archives=[dict(name=name, url=row['url'], sha256=row['sha256'], size=row['size'])
                                              for name, row in sorted(records.items())])
    files = {}
    for row in records.values():
        member = row['members'][row['library_member']]
        files[row['kind']] = dict(member, filename=row['library_filename'], asset_version=row['version'], archive_sha256=row['sha256'])
    manifest = dict(package=w.IDENTITY, lock_sha256=SHA, upstream_versions=lock['upstream_versions'], files=files, acquisition=acquisition)
    for group in [report['smoke'], *report['rebuilt_smoke'].values()]:
        for smoke in group:
            for kind in ('skia', 'harfbuzz'):
                value = smoke['skia']['loader'] if kind == 'skia' else smoke['harfbuzz']
                value.update(origin='upstream-download', managed_directory=False,
                             download_directory='C:/qualification/lib/skia-upstream-1',
                             absolute_path='C:/qualification/lib/skia-upstream-1/' + files[kind]['filename'],
                             installed_sha256=files[kind]['sha256'], manifest=copy.deepcopy(manifest))
    report['checks'].update({key: True for key in c.WINDOWS_CHECKS})
    report['windows_upstream_lifecycle'] = dict(compatible_revision='1.1', rollback_revision='1.0',
        user_scope_removed=True, installation_scope_removed=True, partial_shadow_rejected=True, unrelated_sentinel_preserved=True)
    report['windows_upstream_acquisition'] = dict(route=w.ROUTE, lock_sha256=SHA, archives=[
        dict(name=name, package=row['package'], version=row['version'], url=row['url'], final_url=row['url'],
             sha256=row['sha256'], size=row['size'], kind=row['kind'], member=row['library_member'],
             member_sha256=row['members'][row['library_member']]['sha256'], obtained_by='nuget-download')
        for name, row in sorted(records.items())])
    return report, staging


class Evidence(unittest.TestCase):
    def verify(self, report, staging):
        return c.verify_lane(report, staging, source_sha256=SHA, artifacts={'native.zip':SHA}, lock_sha256=SHA, commit=COMMIT)
    def test_complete_selected_receipt(self):
        self.assertEqual(self.verify(*fixtures()), ('x86_64-linux','9.3'))
    def test_complete_windows_exception_receipt(self):
        self.assertEqual(self.verify(*windows_fixture()), ('win32\\x86_64', '9.3'))
    def test_windows_exception_never_applies_to_linux(self):
        report, stage = fixtures()
        report['smoke'][0]['harfbuzz']['origin'] = 'upstream-download'
        with self.assertRaises(ValueError): self.verify(report, stage)
    def test_windows_requires_each_extra_check_and_lifecycle(self):
        for key in c.WINDOWS_CHECKS:
            report, stage = windows_fixture()
            report['checks'][key] = False
            with self.subTest(key=key), self.assertRaises(ValueError): self.verify(report, stage)
        report, stage = windows_fixture()
        del report['windows_upstream_lifecycle']
        with self.assertRaises(ValueError): self.verify(report, stage)
    def test_windows_acquisition_cannot_be_forged_or_replaced_by_a_local_cache_claim(self):
        for change in (dict(sha256='0'*64), dict(url='https://example.com/input'),
                       dict(obtained_by='verified-local-archive'), dict(member_sha256='0'*64),
                       dict(final_url='http://api.nuget.org/input')):
            report, stage = windows_fixture()
            report['windows_upstream_acquisition']['archives'][0].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError): self.verify(report, stage)
    def test_windows_rebuilt_smoke_must_use_the_exact_downloaded_members(self):
        for defect in ('managed', 'wrong-bytes', 'relative-path', 'wrong-url'):
            report, stage = windows_fixture()
            native = report['rebuilt_smoke']['binary-lib'][0]['harfbuzz']
            if defect == 'managed': native['origin'] = 'managed'
            elif defect == 'wrong-bytes':
                native['installed_sha256'] = native['manifest']['files']['harfbuzz']['sha256'] = '0'*64
            elif defect == 'relative-path': native['absolute_path'] = 'libHarfBuzzSharp.dll'
            else: native['manifest']['acquisition']['archives'][0]['url'] = 'https://example.com/input'
            with self.subTest(defect=defect), self.assertRaises(ValueError): self.verify(report, stage)
    def test_each_required_check_must_be_true(self):
        for key in c.REQUIRED_CHECKS:
            for value in (False, 'unrun', 'true', None):
                report, stage = fixtures()
                report['checks'][key] = value
                with self.subTest(key=key,value=value), self.assertRaises(ValueError): self.verify(report,stage)
    def test_missing_form_is_not_a_roundtrip(self):
        report, stage = fixtures(); del report['rebuilt_smoke']['binary-lib']
        with self.assertRaises(ValueError): self.verify(report,stage)
    def test_rebuilt_form_must_really_select_managed(self):
        report, stage = fixtures(); report['rebuilt_smoke']['binary-lib'][0]['harfbuzz']['origin']='system'
        with self.assertRaises(ValueError): self.verify(report,stage)
    def test_missing_order_is_not_proof(self):
        report, stage = fixtures(); report['smoke'] = report['smoke'][:1]
        with self.assertRaises(ValueError): self.verify(report,stage)
    def test_bare_search_string_is_not_an_absolute_library(self):
        report, stage = fixtures(); report['smoke'][0]['harfbuzz']['absolute_path']='libHarfBuzzSharp'
        with self.assertRaises(ValueError): self.verify(report,stage)
    def test_other_generation_path_is_not_accepted(self):
        report, stage = fixtures(); report['smoke'][0]['harfbuzz']['absolute_path']='/host/lib.so'
        with self.assertRaises(ValueError): self.verify(report,stage)
    def test_wrong_candidate_sha(self):
        report, stage = fixtures(); stage['source']['sha256']='c'*64
        with self.assertRaises(ValueError): self.verify(report,stage)
    def test_repacked_snapshot_is_rejected(self):
        report, stage = fixtures(); stage['snapshot_candidates_preserved']=False
        with self.assertRaises(ValueError): self.verify(report,stage)
    def test_dependency_graph_receipt_is_bound_to_its_bytes(self):
        report, stage = fixtures(); stage['dependency_snapshot']['catalog_racket_datum'] += 'changed'
        with self.assertRaises(ValueError): self.verify(report,stage)
    def test_dirty_source_is_not_same_commit(self):
        report, stage = fixtures(); stage['source']['source_worktree_clean']=False
        with self.assertRaises(ValueError): self.verify(report,stage)
    def test_dependency_snapshot_target_must_match(self):
        report, stage = fixtures(); stage['identity']=dict(version='9.3',target='x86_64-linux-natipkg')
        with self.assertRaises(ValueError): self.verify(report,stage)
    def test_natipkg_requires_derived_configuration_and_support_provenance(self):
        report, stage = fixtures()
        report['identity']['target']='x86_64-linux-natipkg'
        report['identity']['compile_target_machine']=False
        report['runtime_profile']=stage['runtime_profile']=copy.deepcopy(PKG_BUILD_PROFILE)
        cache_fixture(report)
        with self.assertRaises(ValueError): self.verify(report,stage)
        for group in [report['smoke'], *report['rebuilt_smoke'].values()]:
            for smoke in group:
                smoke['skia']['loader']['manifest']['support_configuration']={'sha256':SHA}
                smoke['skia'].update(support_library='/home/test/lib/libfontconfig.so.1',support_library_sha256=SHA,
                    fontconfig=dict(origin='managed-cache',template_sha256=SHA,materialized_sha256=SHA))
        self.assertEqual(self.verify(report,stage), ('x86_64-linux-natipkg','9.3'))
    def test_natipkg_copied_caches_cannot_be_missing_or_keyed_to_an_old_runtime(self):
        for defect in ('missing', 'old-key', 'source-mismatch', 'empty'):
            report, stage = fixtures()
            report['identity'].update(target='x86_64-linux-natipkg', compile_target_machine=False)
            report['runtime_profile']=stage['runtime_profile']=copy.deepcopy(PKG_BUILD_PROFILE)
            cache_fixture(report)
            rows = report['runtime_cache_relocations']
            if defect == 'missing': rows.pop()
            elif defect == 'old-key': rows[0]['new_cache'] = rows[0]['old_cache']
            elif defect == 'source-mismatch': rows[0]['source_runtime'] = '/another runtime'
            elif defect == 'empty': rows[0]['bytecode_files'] = 0
            with self.subTest(defect=defect), self.assertRaisesRegex(ValueError, 'runtime cache'):
                self.verify(report, stage)
    def test_timeout_is_not_os_network_denial(self):
        report, stage = fixtures(); report['network_denial'][0]['errno']=None
        with self.assertRaises(ValueError): self.verify(report,stage)
    def test_natipkg_drdr_requires_observed_child_cache_reuse(self):
        for defect in ('missing', 'roots', 'target', 'executable', 'version'):
            report, stage = fixtures()
            report['identity'].update(target='x86_64-linux-natipkg', compile_target_machine=False)
            report['runtime_profile']=stage['runtime_profile']=copy.deepcopy(PKG_BUILD_PROFILE)
            cache_fixture(report)
            child = report['drdr_child_runtime']
            if defect == 'missing': del report['drdr_child_runtime']
            elif defect == 'roots': child['compiled_roots'] = ['same']
            elif defect == 'target': child['compile_target_machine'] = False
            elif defect == 'executable': child['executable'] = '/unrelated/racket'
            elif defect == 'version': child['version'] = '9.3.0.8'
            with self.subTest(defect=defect), self.assertRaisesRegex(ValueError, 'DrDr subprocess'):
                self.verify(report, stage)
    def test_natipkg_full_drdr_cannot_drop_the_preflight_environment(self):
        report, stage = fixtures()
        report['identity'].update(target='x86_64-linux-natipkg', compile_target_machine=False)
        report['runtime_profile']=stage['runtime_profile']=copy.deepcopy(PKG_BUILD_PROFILE)
        cache_fixture(report)
        del report['commands'][0]['runtime_child_environment']
        with self.assertRaisesRegex(ValueError, 'DrDr package command'):
            self.verify(report, stage)
    def test_linux_root_cannot_claim_readonly_qualification(self):
        for uid in (0, None, '1001', True):
            report, stage = fixtures(); report['execution_uid'] = uid
            with self.subTest(uid=uid), self.assertRaisesRegex(ValueError, 'unprivileged execution UID'):
                self.verify(report, stage)
    def test_natipkg_plain_or_unobserved_compilation_mode_is_not_service_evidence(self):
        for profile, machine in ((None, False), (PKG_BUILD_PROFILE, 'ta6le'),
                                 (dict(PKG_BUILD_PROFILE, upstream_commit='0'*40), False)):
            report, stage = fixtures()
            report['identity'].update(target='x86_64-linux-natipkg', compile_target_machine=machine)
            report['runtime_profile']=stage['runtime_profile']=profile
            with self.subTest(profile=profile,machine=machine), self.assertRaisesRegex(ValueError, 'machine-independent execution profile'):
                self.verify(report, stage)
    def test_partial_review_cannot_approve_this_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copytree(n.ROOT/'packaging',root/'packaging')
            path = root/'packaging/native-assets.json'
            lock = n.read_json(path)
            lock['review']['redistribution_approved']=False
            path.write_text(json.dumps(lock))
            with self.assertRaisesRegex(ValueError,'review is pending'): c.reviewed_lock(root)


class Lock(unittest.TestCase):
    def test_build_evidence_and_review_text_are_bound_before_assembly(self):
        for key in ('component_build_evidence', 'redistribution_review_document'):
            lock = n.read_json(n.ROOT/'packaging/native-assets.json')
            lock[key]['sha256'] = '0' * 64
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'build evidence differs'):
                n.validate_distribution_lock(lock)

    def test_configuration_template_must_match_lock(self):
        lock = n.read_json(n.ROOT/'packaging/native-assets.json')
        lock['configurations']['linux-fontconfig']['sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'configuration differs'): n.validate_distribution_lock(lock)
    def test_all_notice_hashes_and_font_provenance_are_checked(self):
        lock = n.read_json(n.ROOT/'packaging/native-assets.json')
        n.validate_distribution_lock(lock)
        lock['supplemental_notices']['wuffs']['sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'notice drift'): n.validate_distribution_lock(lock)
    def test_supplemental_notice_cannot_be_omitted(self):
        lock = n.read_json(n.ROOT/'packaging/native-assets.json')
        del lock['supplemental_notices']['dng-PATENTS']
        with self.assertRaisesRegex(ValueError,'notice set'): n.validate_distribution_lock(lock)
    def test_unpinned_font_source_is_rejected(self):
        lock = n.read_json(n.ROOT/'packaging/native-assets.json')
        lock['font_package']['files'][0]['url']='https://example.com/latest.ttf'
        with self.assertRaisesRegex(ValueError,'not immutable'): n.validate_distribution_lock(lock)


class WindowsNetworkCoverage(unittest.TestCase):
    def test_foreign_target_and_all_rebuilt_runtimes_are_denied(self):
        output = Path('/disposable CI output with spaces æ')
        python = Path('/selected Python/python.exe')
        programs = windows_network_programs(output, python)
        self.assertEqual(programs[0], python)
        for name in ('source installation', 'scope lifecycle', 'foreign target data',
                     'reinstalled source', 'reinstalled built', 'reinstalled binary-lib'):
            for executable in ('Racket.exe', 'racket.exe'):
                self.assertIn(output / 'execution' / name / 'Racket runtime' / executable, programs)
        self.assertEqual(len(programs), 13)

    def test_unregistered_runtime_is_rejected_before_filesystem_changes(self):
        spec = importlib.util.spec_from_file_location('catalog_validator_network_test',
                                                     n.ROOT / 'tools/validate-catalog-package.py')
        validator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(validator)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'must not be created'
            instance = SimpleNamespace(root=root, runtime=Path(temporary) / 'unused')
            with self.assertRaisesRegex(ValueError, 'network-denial coverage'):
                validator.Validator.environment(instance, 'a future uncovered runtime')
            self.assertFalse(root.exists())

    def test_runtime_names_are_distinct_safe_directory_components(self):
        self.assertEqual(len(RUNTIME_ENVIRONMENTS), len(set(RUNTIME_ENVIRONMENTS)))
        self.assertTrue(all(Path(name).name == name and name not in ('.', '..')
                            for name in RUNTIME_ENVIRONMENTS))


class CatalogRuntime(unittest.TestCase):
    def test_profile_child_cache_environment_relocates_without_changing_child_compile_mode(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'Racket runtime æ'
            executable = root / 'bin/racket'
            self.assertEqual(runtime_child_environment(executable), {})
            self.assertEqual(runtime_child_environment(executable, profile=PKG_BUILD_PROFILE),
                             {'PLTCOMPILEDROOTS': str(root / 'zo') + os.pathsep})
            (root / 'etc').mkdir(parents=True)
            (root / PROFILE_FILE).write_bytes(n.json_bytes(PKG_BUILD_PROFILE))
            moved = root.with_name('copied runtime with spaces æ')
            shutil.copytree(root, moved)
            self.assertEqual(runtime_child_environment(moved / 'bin/racket'),
                             {'PLTCOMPILEDROOTS': str(moved / 'zo') + os.pathsep})

    def test_runtime_child_cache_reaches_real_descendants_over_ambient_values(self):
        validator = tool('validate-catalog-package')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'etc').mkdir()
            (root / PROFILE_FILE).write_bytes(n.json_bytes(PKG_BUILD_PROFILE))
            instance = object.__new__(validator.Validator)
            instance.root = instance.away = root
            instance.report = dict(commands=[])
            code = 'import os,subprocess,sys; subprocess.run([sys.executable,"-c","import os; print(os.environ[\\\"PLTCOMPILEDROOTS\\\"])"])'
            with patch.object(validator, 'racket_command', return_value=[sys.executable]):
                output = instance.run((root / 'bin/racket', dict(os.environ), root), '-c', code,
                                      extra_env={'PLTCOMPILEDROOTS': 'unreviewed ambient cache'})
            self.assertEqual(output.strip(), str(root / 'zo') + os.pathsep)
            self.assertEqual(instance.report['commands'][0]['runtime_child_environment'],
                             {'PLTCOMPILEDROOTS': str(root / 'zo') + os.pathsep})

    def test_runtime_cache_copy_survives_original_removal_without_changing_bytecode(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary).resolve() / 'prepared runtime æ'
            (source / 'etc').mkdir(parents=True)
            (source / PROFILE_FILE).write_bytes(n.json_bytes(PKG_BUILD_PROFILE))
            relative = source.relative_to(source.anchor) / 'collects/racket/compiled/base_rkt.zo'
            original = source / 'zo' / relative
            original.parent.mkdir(parents=True)
            original.write_bytes(b'opaque compiled fixture, never executed')
            copied = source.with_name('copied runtime with spaces æ')
            shutil.copytree(source, copied)
            relocation = relocate_runtime_cache(source, copied)
            self.assertEqual(relocation['bytecode_files'], 1)
            self.assertFalse((copied / 'zo' / relative).exists())
            moved = Path(relocation['new_cache']) / 'collects/racket/compiled/base_rkt.zo'
            self.assertEqual(moved.read_bytes(), original.read_bytes())
            shutil.rmtree(source)
            self.assertEqual(moved.read_bytes(), b'opaque compiled fixture, never executed')
            self.assertEqual(racket_command(copied / 'bin/racket')[-1], str(copied / 'zo') + os.pathsep)

    def test_runtime_cache_copy_rejects_collision_and_symlinks(self):
        for defect in ('collision', 'symlink', 'missing-cache'):
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                source, copied = root / 'prepared', root / 'copied'
                (source / 'etc').mkdir(parents=True)
                (source / PROFILE_FILE).write_bytes(n.json_bytes(PKG_BUILD_PROFILE))
                shutil.copytree(source, copied)
                old = copied / 'zo' / source.relative_to(source.anchor)
                old.mkdir(parents=True)
                if defect != 'missing-cache':
                    (old / 'module.zo').write_bytes(b'fixture')
                if defect == 'collision':
                    (copied / 'zo' / copied.relative_to(copied.anchor)).mkdir(parents=True)
                elif defect == 'symlink':
                    (old / 'escaped.dep').symlink_to(root / 'outside')
                with self.assertRaises(ValueError):
                    relocate_runtime_cache(source, copied)
                self.assertTrue(old.exists())

    def test_plain_runtime_needs_no_separate_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertIsNone(relocate_runtime_cache(root / 'plain', root / 'copy'))

    def test_pkg_build_profile_uses_upstream_flags_and_a_relocatable_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'Racket runtime æ'
            (root / 'etc').mkdir(parents=True)
            executable = root / 'bin/racket'
            self.assertEqual(racket_command(executable), [str(executable)])
            (root / PROFILE_FILE).write_bytes(n.json_bytes(PKG_BUILD_PROFILE))
            self.assertEqual(racket_command(executable),
                             [str(executable), '-MCR', str(root / 'zo') + os.pathsep])
            moved = root.with_name('copied Racket runtime æ')
            shutil.copytree(root, moved)
            self.assertEqual(racket_command(moved / 'bin/racket')[-1], str(moved / 'zo') + os.pathsep)

    def test_unknown_runtime_profile_cannot_inject_flags_or_silently_fall_back(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'etc').mkdir()
            profile = dict(PKG_BUILD_PROFILE, arguments=['--no-docs'])
            (root / PROFILE_FILE).write_bytes(n.json_bytes(profile))
            with self.assertRaisesRegex(ValueError, 'unreviewed catalog runtime execution profile'):
                racket_command(root / 'bin/racket')
            with self.assertRaisesRegex(ValueError, 'unreviewed catalog runtime execution profile'):
                runtime_child_environment(root / 'bin/racket')

    def test_staging_failure_retains_bounded_cause_without_native_archives(self):
        runner = tool('run-catalog-ci')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = root / 'runtime'
            (runtime / 'bin').mkdir(parents=True)
            executable = runtime / 'bin/racket'
            executable.write_bytes(b'fixture, never executed')
            (runtime / 'collects/racket').mkdir(parents=True)
            (runtime / 'collects/racket/base.rkt').write_bytes(b'#lang racket/base\n')
            output = root / 'ci'
            def fail_staging(*args, **kwargs):
                stage = output / 'staged'
                stage.mkdir()
                (stage / 'catalog-metadata.log').write_bytes(b'compile: fixture failure\n')
                (stage / 'native.zip').write_bytes(b'never upload this payload')
                raise ValueError('fixture metadata failed')
            with patch.object(runner, 'load', return_value=SimpleNamespace(stage=fail_staging)):
                with self.assertRaisesRegex(ValueError, 'fixture metadata failed'):
                    runner.execute(str(executable), output, runtime)
            evidence = output / 'evidence'
            report = n.read_json(evidence / 'preparation-failure.json')
            self.assertEqual(report['status'], 'failed-preparation')
            self.assertFalse(report['catalog_candidate_validated'])
            self.assertEqual((evidence / 'catalog-metadata.log').read_bytes(), b'compile: fixture failure\n')
            self.assertFalse(any(path.suffix == '.zip' for path in evidence.iterdir()))

    def test_windows_relative_files_are_checked_with_full_zip_member_names(self):
        class WindowsRelativePath(type(Path())):
            def relative_to(self, *args, **kwargs):
                return PureWindowsPath(super().relative_to(*args, **kwargs))

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = WindowsRelativePath(root / 'package')
            members = {'skia-native-1/library.dll': b'fixture library, never loaded',
                       'licenses/skia/LICENSE.txt': b'Skia notice',
                       'licenses/harfbuzz/LICENSE.txt': b'HarfBuzz notice',
                       'licenses/BUILD-EVIDENCE.json': b'{"fixture":true}'}
            for name, data in {**members, 'info.rkt':b'#lang info\n',
                               'compiled/metadata.zo':b'bytecode', 'compiled/metadata.dep':b'dependencies'}.items():
                path = package / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            expected = preserved_package_files(package)
            self.assertEqual(set(expected), set(members))
            archive = root / 'rebuilt.zip'
            n.write_zip(archive, members)
            with zipfile.ZipFile(archive) as rebuilt:
                for name, digest in expected.items():
                    self.assertEqual(hashlib.sha256(rebuilt.read(name)).hexdigest(), digest)

    def test_linux_root_is_rejected_before_any_installation(self):
        validator = tool('validate-catalog-package')
        instance = object.__new__(validator.Validator)
        instance.report = {}
        with patch.object(validator.sys, 'platform', 'linux'), \
             patch.object(validator.os, 'geteuid', return_value=0, create=True):
            with self.assertRaisesRegex(ValueError, 'must run unprivileged'):
                instance.execute()
        self.assertEqual(instance.report['execution_uid'], 0)

    def test_system_prefix_is_rejected_before_creating_an_execution_tree(self):
        validator = tool('validate-catalog-package')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            work = root / 'must not be created'
            with self.assertRaisesRegex(ValueError, 'self-contained relocatable Racket'):
                validator.Validator(Path('/usr'), root / 'catalog', work)
            self.assertFalse(work.exists())

    def test_self_contained_runtime_is_accepted(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'bin').mkdir()
            (root / 'bin/racket').write_bytes(b'fixture executable')
            (root / 'collects/racket').mkdir(parents=True)
            (root / 'collects/racket/base.rkt').write_bytes(b'#lang racket/base\n')
            self.assertEqual(relocatable_runtime(root), root.resolve())

    def test_utf8_command_paths_survive_a_windows_default_text_encoding(self):
        validator = tool('validate-catalog-package')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload = root / 'user home with spaces æ' / 'libSkiaSharp.dll'
            payload.parent.mkdir()
            payload.write_bytes(b'path fixture, never loaded')
            instance = object.__new__(validator.Validator)
            instance.root = instance.away = root
            instance.report = dict(commands=[])
            data = json.dumps(dict(absolute_path=str(payload)), ensure_ascii=False).encode('utf-8')
            code = 'import sys; sys.stdout.buffer.write(' + repr(data) + ')'
            # Exercise real subprocess output while simulating Python 3.12's
            # default Windows text codec, independently of this test host.
            with patch('io.text_encoding', side_effect=lambda encoding, *args:
                       'cp1252' if encoding in (None, 'locale') else encoding):
                report = json.loads(instance.run((Path(sys.executable), dict(os.environ), root), '-c', code))
            self.assertEqual(report['absolute_path'], str(payload))
            self.assertTrue(Path(report['absolute_path']).is_file())
            self.assertNotEqual(json.loads((root / '001.log').read_text(encoding='cp1252'))['absolute_path'],
                                str(payload))


class RuntimeAcquisition(unittest.TestCase):
    class Response(io.BytesIO):
        def __init__(self, data, url):
            super().__init__(data)
            self.url = url

        def geturl(self):
            return self.url

    def fixture(self, root):
        module = tool('prepare-natipkg-runtime')
        data = b'hash-pinned installer fixture, never executed'
        pin = dict(url='https://primary.example/runtime.sh', mirrors=['https://mirror.example/runtime.sh'],
                   sha256=hashlib.sha256(data).hexdigest())
        lock = root / 'runtimes.json'
        lock.write_bytes(n.json_bytes(dict(natipkg={'9.3':pin}, execution_profile=PKG_BUILD_PROFILE)))
        return module, data, pin, lock

    def test_transport_failure_uses_only_a_locked_mirror_before_installing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module, data, pin, lock = self.fixture(root)
            with patch.object(module.urllib.request, 'build_opener') as make_opener, \
                 patch.object(module.subprocess, 'run') as install:
                def installed_runtime(command, **kwargs):
                    if command[0] == 'sh':
                        (root / 'runtime/etc').mkdir(parents=True)
                    return SimpleNamespace(returncode=0)
                install.side_effect = installed_runtime
                make_opener.return_value.open.side_effect = [
                    urllib.error.HTTPError(pin['url'], 403, 'Forbidden', None, None),
                    self.Response(data, pin['mirrors'][0])]
                report = module.prepare('9.3', root / 'runtime', lock_path=lock)
                self.assertEqual([call.args[0] for call in make_opener.return_value.open.call_args_list],
                                 [pin['url'], *pin['mirrors']])
                self.assertEqual(install.call_count, 3)
                self.assertEqual(install.call_args_list[1].args[0][-4:], ['-l-', 'raco', 'setup', '--recompile-only'])
                self.assertIn('-MCR', install.call_args_list[2].args[0])
                self.assertTrue(Path(install.call_args_list[1].kwargs['env']['PLTADDONDIR']).is_absolute())
                self.assertEqual(install.call_args_list[1].kwargs['env']['PLTCOMPILEDROOTS'],
                                 str(root.resolve() / 'runtime/zo') + os.pathsep)
            self.assertEqual(report['status'], 'installed')
            self.assertEqual(report['sha256'], pin['sha256'])
            self.assertEqual(report['selected_url'], pin['mirrors'][0])
            self.assertEqual(report['attempts'][0]['status'], 'transport-failed')
            self.assertFalse(report['catalog_candidate_validated'])
            self.assertEqual(n.read_json(root / 'runtime.acquisition.json'), report)

    def test_changed_bytes_are_never_executed_or_hidden_by_mirror_retry(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module, data, pin, lock = self.fixture(root)
            with patch.object(module.urllib.request, 'build_opener') as make_opener, \
                 patch.object(module.subprocess, 'run') as install:
                make_opener.return_value.open.return_value = self.Response(data + b'changed', pin['url'])
                with self.assertRaisesRegex(ValueError, 'digest differs'):
                    module.prepare('9.3', root / 'runtime', lock_path=lock)
                install.assert_not_called()
                self.assertEqual(make_opener.return_value.open.call_count, 1)
            self.assertEqual(n.read_json(root / 'runtime.acquisition.json')['status'], 'failed')
            self.assertFalse((root / 'runtime').exists())

    def test_failed_bootstrap_never_publishes_a_ready_runtime_profile(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module, data, pin, lock = self.fixture(root)
            def run(command, **kwargs):
                if command[0] == 'sh':
                    (root / 'runtime/etc').mkdir(parents=True)
                    return SimpleNamespace(returncode=0)
                kwargs['stdout'].write(b'fixture bootstrap failed\n')
                raise module.subprocess.CalledProcessError(1, command)
            with patch.object(module.urllib.request, 'build_opener') as make_opener, \
                 patch.object(module.subprocess, 'run', side_effect=run):
                make_opener.return_value.open.return_value = self.Response(data, pin['url'])
                with self.assertRaises(module.subprocess.CalledProcessError):
                    module.prepare('9.3', root / 'runtime', lock_path=lock)
            self.assertFalse((root / 'runtime' / PROFILE_FILE).exists())
            receipt = n.read_json(root / 'runtime.acquisition.json')
            self.assertEqual(receipt['status'], 'failed')
            self.assertIn('fixture bootstrap failed', receipt['bootstrap.log_tail'])

    def test_oversized_bytes_fail_before_installing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module, data, pin, lock = self.fixture(root)
            with patch.object(module.urllib.request, 'build_opener') as make_opener, \
                 patch.object(module.subprocess, 'run') as install, \
                 patch.object(module, 'MAX_INSTALLER', len(data) - 1):
                make_opener.return_value.open.return_value = self.Response(data, pin['url'])
                with self.assertRaisesRegex(ValueError, 'exceeds limit'):
                    module.prepare('9.3', root / 'runtime', lock_path=lock)
                install.assert_not_called()
                self.assertEqual(make_opener.return_value.open.call_count, 1)

    def test_existing_installer_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module, _, _, lock = self.fixture(root)
            installer = root / 'runtime.sh'
            installer.write_bytes(b'keep this unrelated file')
            with patch.object(module.urllib.request, 'build_opener') as make_opener:
                with self.assertRaisesRegex(ValueError, 'must be new'):
                    module.prepare('9.3', root / 'runtime', lock_path=lock)
                make_opener.assert_not_called()
            self.assertEqual(installer.read_bytes(), b'keep this unrelated file')

    def test_http_redirect_is_rejected_before_it_can_be_followed(self):
        module = tool('prepare-natipkg-runtime')
        request = urllib.request.Request('https://primary.example/runtime.sh')
        with self.assertRaisesRegex(ValueError, 'insecure runtime redirect'):
            module.HTTPSOnly().redirect_request(request, None, 302, 'Moved', {}, 'http://mirror.example/runtime.sh')


class ReceiptOnlyAssets(unittest.TestCase):
    def assets(self, root, *, clean=True, source_commit=COMMIT):
        folder = root / 'artifacts'
        folder.mkdir()
        rows = []
        names = [n.TARGETS[name]['package'] for name in n.DISTRIBUTED_TARGETS] + ['skia-fonts-1']
        for name in names:
            archive = folder / (name + '.zip')
            identity = n.write_zip(archive, {'payload/private-library.dll': b'NATIVE-PAYLOAD-SENTINEL'})
            row = dict(identity, archive=archive.name, source_commit_observed=COMMIT,
                       catalog_candidate_validated=False)
            (folder / (name + '.receipt.json')).write_bytes(n.json_bytes(row))
            rows.append(row)
        (folder / 'native-artifacts.json').write_bytes(n.json_bytes(dict(schema=1, artifacts=rows)))
        n.write_zip(folder / 'skia.zip', {
            'private/source-identity.json': n.json_bytes(dict(
                schema=1, source_commit_observed=source_commit, source_worktree_clean=clean)),
            'source.rkt': b'#lang racket/base\n'})
        return folder

    def test_only_receipts_and_digests_leave_the_artifact_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifacts = self.assets(root)
            (artifacts / 'extra.dll').write_bytes(b'NATIVE-PAYLOAD-SENTINEL')
            (artifacts / 'extra.json').write_text('{"do_not_copy": true}')
            output = root / 'evidence'
            report = asset_evidence.collect(artifacts, output)
            self.assertEqual({p.name for p in output.iterdir()}, {
                'skia-native-macos-1.receipt.json', 'skia-native-x86_64-linux-1.receipt.json',
                'skia-fonts-1.receipt.json', 'native-artifacts.json', 'artifact-digests.json'})
            self.assertTrue(all(p.suffix == '.json' for p in output.iterdir()))
            self.assertFalse((output / 'extra.json').exists())
            self.assertFalse(any(b'NATIVE-PAYLOAD-SENTINEL' in p.read_bytes() for p in output.iterdir()))
            self.assertEqual(len(report['archives']), 4)
            self.assertNotIn('skia-native-win32-x86_64-1.zip', {row['archive'] for row in report['archives']})
            self.assertEqual(report['source']['source_commit_observed'], COMMIT)
            self.assertFalse(report['catalog_candidate_validated'])
            self.assertFalse(report['native_payloads_uploaded'])

    def test_modified_archive_is_rejected_even_with_a_new_checksum(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifacts = self.assets(root)
            archive = next(p for p in artifacts.glob('*.zip') if p.name != 'skia.zip')
            data = archive.read_bytes() + b'changed'
            archive.write_bytes(data)
            archive.with_suffix('.zip.CHECKSUM').write_text(hashlib.sha1(data).hexdigest())
            with self.assertRaisesRegex(ValueError, 'differs from receipt'):
                asset_evidence.collect(artifacts, root / 'evidence')
            self.assertFalse((root / 'evidence').exists())

    def test_individual_and_aggregate_receipts_must_agree(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifacts = self.assets(root)
            receipt = next(artifacts.glob('*.receipt.json'))
            data = n.read_json(receipt)
            data['source_commit_observed'] = 'c' * 40
            receipt.write_bytes(n.json_bytes(data))
            with self.assertRaisesRegex(ValueError, 'receipts differ'):
                asset_evidence.collect(artifacts, root / 'evidence')

    def test_archive_names_cannot_escape_the_allowlist(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifacts = self.assets(root)
            manifest = n.read_json(artifacts / 'native-artifacts.json')
            manifest['artifacts'][0]['archive'] = '../outside.zip'
            (artifacts / 'native-artifacts.json').write_bytes(n.json_bytes(manifest))
            with self.assertRaisesRegex(ValueError, 'unknown/duplicate'):
                asset_evidence.collect(artifacts, root / 'evidence')
            self.assertFalse((root / 'evidence').exists())

    def test_dirty_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(ValueError, 'clean committed'):
                asset_evidence.collect(self.assets(root, clean=False), root / 'evidence')

    def test_data_and_source_must_name_the_same_commit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(ValueError, 'different commits'):
                asset_evidence.collect(self.assets(root, source_commit='c' * 40), root / 'evidence')

    def test_dirty_data_package_receipt_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifacts = self.assets(root)
            native = n.read_json(artifacts / 'native-artifacts.json')
            row = native['artifacts'][0]
            row['source_worktree_clean'] = False
            (artifacts / (row['archive'].removesuffix('.zip') + '.receipt.json')).write_bytes(n.json_bytes(row))
            (artifacts / 'native-artifacts.json').write_bytes(n.json_bytes(native))
            with self.assertRaisesRegex(ValueError, 'dirty worktree'):
                asset_evidence.collect(artifacts, root / 'evidence')
            self.assertFalse((root / 'evidence').exists())

    def test_receipt_only_artifact_cannot_replace_full_release_archives(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / 'evidence'
            asset_evidence.collect(self.assets(root), output)
            n.write_zip(root / 'receipt-only.zip', {p.name: p.read_bytes() for p in output.iterdir()})
            (root / 'artifact-index.json').write_text(json.dumps({'catalog-assets-1': {'file': 'receipt-only.zip'}}))
            with patch.object(c, 'reviewed_lock', return_value=({}, SHA)):
                with self.assertRaises((KeyError, ValueError)):
                    c.verify(root, root, commit=COMMIT, attempt=1)


if __name__ == '__main__': unittest.main()
