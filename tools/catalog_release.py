"""Strict same-candidate catalog receipts; no execution, mutation or publication."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import zipfile
from native_packages import validate_distribution_lock
from release_graph import need, json_data

REQUIRED_CHECKS = ('ordinary_setup_with_documentation', 'package_dependencies_and_registered_manuals',
                   'staged_dependency_snapshot_verified',
                   'lazy_imports_invalid_overrides', 'invalid_override_exclusive',
                   'bounded_cpu_catalog_tests', 'managed_payload_negative_cases', 'actual_drdr_traversal_under_600_seconds',
                   'readonly_source_first_use', 'advertised_example_copier',
                   'advertised_example_sources_preserved',
                   'compatible_update_and_explicit_rollback', 'scopes_removal_and_unrelated_sentinel',
                   'foreign_target_setup_and_binary_preservation',
                   'original_environment_and_candidate_archives_removed',
                   'rebuilt_native_metadata_semantics',
                   'source_built_binary_lib_roundtrips_and_removal')


def reviewed_lock(root):
    path = root / 'packaging/native-assets.json'
    lock = json_data(path.read_text())
    validate_distribution_lock(lock, root)
    review = lock['review']
    need(review.get('status') == 'approved' and all(review.get(k) is True for k in
         ('redistribution_approved', 'component_license_mapping_complete', 'transitive_resolution_qualified')),
         'catalog candidate blocked: maintainer redistribution/component and transitive qualification review is pending')
    return lock, hashlib.sha256(path.read_bytes()).hexdigest()


def member_json(archive, name):
    need(name in archive.namelist() and archive.getinfo(name).file_size <= 16 * 1024 * 1024, 'missing/oversized catalog receipt: ' + name)
    return json_data(archive.read(name).decode('utf-8'))


def verify_lane(report, staging, *, source_sha256, artifacts, lock_sha256, commit):
    need(report.get('status') == 'passed-local-selected-checks', 'catalog execution did not pass')
    need(not report.get('continued_existing_installation'), 'catalog final qualification requires one complete fresh run')
    need(not report.get('cleanup_leftovers'), 'catalog disposable environment cleanup was incomplete')
    need(all(report.get('checks', {}).get(key) is True for key in REQUIRED_CHECKS), 'catalog lane omitted a required execution check')
    need(type(report.get('drdr_seconds')) in (int, float) and 0 < report['drdr_seconds'] < 600, 'catalog DrDr timing is missing/too slow')
    need(len(report.get('network_denial', [])) == 2, 'catalog network-denial evidence missing')
    need({f.get('address') for f in report['network_denial']} == {'1.1.1.1', '8.8.8.8'} and
         all(f.get('errno') in (1, 13, 101, 113) or f.get('winerror') == 10013 for f in report['network_denial']),
         'catalog evidence does not establish OS network denial')
    need(staging.get('lock_sha256') == lock_sha256 and staging.get('source', {}).get('sha256') == source_sha256,
         'catalog lane used a different lock/source archive')
    need(staging.get('snapshot_candidates_preserved') is True, 'staging repacked the candidate archives')
    snapshot = staging.get('dependency_snapshot') or {}
    need(snapshot.get('packages') and snapshot.get('catalog_racket_datum') and
         hashlib.sha256(snapshot['catalog_racket_datum'].encode('utf-8')).hexdigest() == snapshot.get('catalog_sha256'),
         'staged dependency graph/inventory is missing or corrupt')
    need(staging['source'].get('source_worktree_clean') is True and staging['source'].get('source_commit_observed') == commit,
         'catalog lane is not the committed candidate')
    actual = {r['archive']:r['sha256'] for r in staging['artifacts']['artifacts']}
    need(actual == artifacts, 'catalog lane used different native/font archives')
    identity = report['identity']
    need(identity['version'] == staging['identity']['version'] and identity['target'] == staging['identity']['target'],
         'catalog acquisition/execution target differs')
    need(set(report.get('rebuilt_smoke', {})) == {'source', 'built', 'binary-lib'}, 'catalog rebuilt package proof missing')
    groups = [report.get('smoke', [])] + list(report['rebuilt_smoke'].values())
    need(all({s['text_load_order'] for s in group} == {'skia-first', 'draw-first'} for group in groups), 'catalog text load order missing')
    for smoke in [s for group in groups for s in group]:
        need(smoke.get('status') == 'passed' and smoke.get('source_version') == '0.79', 'catalog native smoke missing')
        for kind in ('skia', 'harfbuzz'):
            native = smoke[kind]['loader'] if kind == 'skia' else smoke[kind]
            need(native.get('origin') == 'managed' and native.get('absolute_path') and
                 native.get('installed_sha256') == native['manifest']['files'][kind]['sha256'] and
                 native['manifest']['lock_sha256'] == lock_sha256, 'catalog native provenance differs')
            path_type = PureWindowsPath if re.match(r'^[A-Za-z]:', native['absolute_path']) else PurePosixPath
            path = path_type(native['absolute_path'])
            need(path.is_absolute() and path.parent == path_type(native['managed_directory']), 'catalog library escaped its generation')
        if identity['target'] == 'x86_64-linux-natipkg':
            configuration = smoke['skia'].get('fontconfig') or {}
            need(configuration.get('origin') == 'managed-cache' and
                 configuration.get('template_sha256') == smoke['skia']['loader']['manifest']['support_configuration']['sha256'] and
                 re.fullmatch('[a-f0-9]{64}', configuration.get('materialized_sha256', '')),
                 'natipkg managed configuration provenance is missing')
            need(re.fullmatch('[a-f0-9]{64}', smoke['skia'].get('support_library_sha256', '')) and
                 PurePosixPath(smoke['skia'].get('support_library', '')).is_absolute(),
                 'natipkg support-library provenance is missing')
    return identity['target'], identity['version']


def verify(root, directory, *, commit, attempt):
    lock, digest = reviewed_lock(root)
    index = json_data((directory / 'artifact-index.json').read_text())
    assets = index.get('catalog-assets-' + str(attempt))
    need(assets is not None, 'catalog artifact set missing')
    with zipfile.ZipFile(directory / assets['file']) as archive:
        receipts = member_json(archive, 'native-artifacts.json')['artifacts']
        artifacts = {}
        for receipt in receipts:
            name = receipt['archive']
            need(archive.getinfo(name).file_size == receipt['size'], 'catalog archive size differs')
            data = archive.read(name)
            need(hashlib.sha256(data).hexdigest() == receipt['sha256'] and
                 hashlib.sha1(data).hexdigest() == receipt['sha1'] and
                 archive.read(name + '.CHECKSUM') == receipt['sha1'].encode('ascii'), 'catalog archive checksum differs')
            need(receipt['lock_sha256'] == digest and receipt['source_commit_observed'] == commit, 'catalog asset provenance differs')
            artifacts[name] = receipt['sha256']
        need(len(artifacts) == 4, 'incomplete catalog native/font set')
        source_sha = hashlib.sha256(archive.read('skia.zip')).hexdigest()
    targets = set()
    for name, record in index.items():
        if name.startswith('catalog-') and not name.startswith('catalog-assets-'):
            with zipfile.ZipFile(directory / record['file']) as archive:
                targets.add(verify_lane(member_json(archive, 'result.json'), member_json(archive, 'staging-receipt.json'),
                                        source_sha256=source_sha, artifacts=artifacts, lock_sha256=digest, commit=commit))
    expected = {(target, version) for target in ('aarch64-macosx', 'x86_64-macosx', 'win32\\x86_64',
                                                 'x86_64-linux', 'x86_64-linux-natipkg') for version in ('8.18', '9.3')}
    need(targets == expected, 'catalog platform/version qualification is incomplete: ' + repr(sorted(expected - targets)))
    return dict(catalog_candidate_validated=True, native_lock_sha256=digest, catalog_source_sha256=source_sha,
                catalog_artifacts=artifacts, catalog_lanes_verified=len(targets))
