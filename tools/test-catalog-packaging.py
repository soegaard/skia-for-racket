#!/usr/bin/env python3
"""Catalog evidence must reject partial, mismatched and fabricated receipts."""
import copy
import hashlib
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
import catalog_release as c
import native_packages as n
from catalog_execution import RUNTIME_ENVIRONMENTS, windows_network_programs

SHA = 'a'*64
COMMIT = 'b'*40


def fixtures():
    native = dict(origin='managed', absolute_path='/home/test/lib/skia-native-1/lib.so',
                  managed_directory='/home/test/lib/skia-native-1', installed_sha256=SHA,
                  manifest=dict(lock_sha256=SHA, files={k:dict(sha256=SHA) for k in ('skia','harfbuzz')}))
    smokes = [dict(status='passed', source_version='0.79', text_load_order=order,
                   skia=dict(loader=copy.deepcopy(native)), harfbuzz=copy.deepcopy(native))
              for order in ('skia-first','draw-first')]
    report = dict(status='passed-local-selected-checks', checks={key:True for key in c.REQUIRED_CHECKS},
                  identity=dict(version='9.3', target='x86_64-linux'), drdr_seconds=37.4,
                  network_denial=[dict(address=address,errno=101) for address in ('1.1.1.1','8.8.8.8')],
                  smoke=smokes, rebuilt_smoke={form:copy.deepcopy(smokes) for form in ('source','built','binary-lib')})
    staging = dict(lock_sha256=SHA, snapshot_candidates_preserved=True, source=dict(sha256=SHA, source_worktree_clean=True, source_commit_observed=COMMIT),
                   dependency_snapshot=dict(packages=[dict(package='base', sha256=SHA)], catalog_racket_datum='#hash()',
                                            catalog_sha256=hashlib.sha256(b'#hash()').hexdigest()),
                   identity=report['identity'], artifacts=dict(artifacts=[dict(archive='native.zip',sha256=SHA)]))
    return report, staging


class Evidence(unittest.TestCase):
    def verify(self, report, staging):
        return c.verify_lane(report, staging, source_sha256=SHA, artifacts={'native.zip':SHA}, lock_sha256=SHA, commit=COMMIT)
    def test_complete_selected_receipt(self):
        self.assertEqual(self.verify(*fixtures()), ('x86_64-linux','9.3'))
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
        with self.assertRaises(ValueError): self.verify(report,stage)
        for group in [report['smoke'], *report['rebuilt_smoke'].values()]:
            for smoke in group:
                smoke['skia']['loader']['manifest']['support_configuration']={'sha256':SHA}
                smoke['skia'].update(support_library='/home/test/lib/libfontconfig.so.1',support_library_sha256=SHA,
                    fontconfig=dict(origin='managed-cache',template_sha256=SHA,materialized_sha256=SHA))
        self.assertEqual(self.verify(report,stage), ('x86_64-linux-natipkg','9.3'))
    def test_timeout_is_not_os_network_denial(self):
        report, stage = fixtures(); report['network_denial'][0]['errno']=None
        with self.assertRaises(ValueError): self.verify(report,stage)
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


if __name__ == '__main__': unittest.main()
