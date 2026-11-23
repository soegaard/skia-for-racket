"""Strict same-candidate catalog receipts; no execution, mutation or publication."""
from __future__ import annotations
from repository_layout import source_path, library_root, documentation_root
import hashlib
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import zipfile
from catalog_execution import PKG_BUILD_PROFILE, RUNTIME_ENVIRONMENTS, verify_drdr_child
from repository_layout import SOURCE_PACKAGES
from native_packages import ROOT, DISTRIBUTED_TARGETS, TARGETS, read_json, validate_distribution_lock
from release_graph import need, json_data

REQUIRED_CHECKS = ('registered_manual_navigation', 'five_directory_sources_match_candidate_archives', 'library_only_without_documentation_or_fonts',
                   'documentation_added_to_existing_library', 'independent_documentation_removal',
                   'documentation_multilingual_tests', 'git_layout_without_generated_source_identity',
                   'ordinary_setup_with_documentation', 'package_dependencies_and_registered_manuals',
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
WINDOWS_CHECKS = ('windows_explicit_installer_before_offline_setup',
                  'windows_rebuilt_packages_exclude_downloaded_payload')


def verify_windows_acquisition(report, lock, lock_sha256):
    from windows_native import ROUTE, check_url, records
    acquisition = report.get('windows_upstream_acquisition') or {}
    need(acquisition.get('route') == ROUTE and acquisition.get('lock_sha256') == lock_sha256,
         'Windows direct NuGet acquisition identity is missing or differs')
    rows = acquisition.get('archives') or []
    expected = records(lock)
    need(len(rows) == 2 and {row.get('name') for row in rows} == set(expected), 'Windows acquisition must name exactly both locked NuGets')
    for row in rows:
        source = expected[row['name']]
        need(all(row.get(key) == source[key] for key in ('package', 'version', 'url', 'size', 'sha256', 'kind'))
             and row.get('member') == source['library_member']
             and row.get('member_sha256') == source['members'][source['library_member']]['sha256']
             and row.get('obtained_by') == 'nuget-download', 'Windows upstream acquisition differs from locked inputs')
        check_url(row.get('final_url', ''))
    need(all(report.get('checks', {}).get(key) is True for key in WINDOWS_CHECKS),
         'Windows exception omitted explicit installer or binary exclusion checks')
    lifecycle = report.get('windows_upstream_lifecycle') or {}
    need(lifecycle.get('compatible_revision') == '1.1' and lifecycle.get('rollback_revision') == '1.0'
         and all(lifecycle.get(key) is True for key in ('user_scope_removed', 'installation_scope_removed',
                                                       'partial_shadow_rejected', 'unrelated_sentinel_preserved')),
         'Windows upstream lifecycle evidence is incomplete')
    return expected


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


def verify_lane(report, staging, *, source_sha256, artifacts, lock_sha256, commit, native_lock=None):
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
    windows = identity['target'] == 'win32\\x86_64'
    windows_records = verify_windows_acquisition(report, native_lock or read_json(ROOT / 'packaging/native-assets.json'), lock_sha256) if windows else None
    if identity['target'].startswith('x86_64-linux'):
        need(type(report.get('execution_uid')) is int and report['execution_uid'] > 0,
             'Linux read-only qualification requires an unprivileged execution UID')
    need(identity['version'] == staging['identity']['version'] and identity['target'] == staging['identity']['target'],
         'catalog acquisition/execution target differs')
    if identity['target'] == 'x86_64-linux-natipkg':
        need(report.get('runtime_profile') == PKG_BUILD_PROFILE and
             staging.get('runtime_profile') == PKG_BUILD_PROFILE and
             identity.get('compile_target_machine', 'missing') is False and
             staging['identity'].get('compile_target_machine', 'missing') is False,
             'natipkg qualification omitted the pkg-build machine-independent execution profile')
        relocations = report.get('runtime_cache_relocations') or []
        need(len(relocations) == len(RUNTIME_ENVIRONMENTS) and
             {row.get('environment') for row in relocations} == set(RUNTIME_ENVIRONMENTS),
             'natipkg qualification omitted a copied runtime cache relocation')
        for row in relocations:
            source = PurePosixPath(row['source_runtime'])
            copied = PurePosixPath(row['copied_runtime'])
            need(source.is_absolute() and copied.is_absolute() and source != copied and
                 copied.name == 'Racket runtime' and copied.parent.name == row['environment'] and
                 row['source_runtime'] == report.get('runtime_source') and
                 row.get('old_cache') == str(copied / 'zo' / source.relative_to('/')) and
                 row.get('new_cache') == str(copied / 'zo' / copied.relative_to('/')) and
                 type(row.get('bytecode_files')) is int and row['bytecode_files'] > 0,
                 'natipkg copied runtime cache was not rekeyed for its new absolute path')
        first = next(row for row in relocations if row['environment'] == 'source installation')
        verify_drdr_child(report.get('drdr_child_runtime'), first['copied_runtime'],
                          version=identity['version'], target=identity['target'])
        drdr = [row for row in report.get('commands', [])
                if row.get('command', [])[-5:] == ['test', '--drdr', '--package', 'skia-lib', 'skia-doc']]
        need(len(drdr) == 1 and drdr[0].get('exit_code') == 0 and
             drdr[0].get('runtime_child_environment') == {
                 'PLTCOMPILEDROOTS': str(PurePosixPath(first['copied_runtime']) / 'zo') + ':'},
             'natipkg DrDr package command omitted the reviewed inherited cache environment')
    need(set(report.get('rebuilt_smoke', {})) == {'source', 'built', 'binary-lib'}, 'catalog rebuilt package proof missing')
    groups = [report.get('smoke', [])] + list(report['rebuilt_smoke'].values())
    need(all({s['text_load_order'] for s in group} == {'skia-first', 'draw-first'} for group in groups), 'catalog text load order missing')
    for smoke in [s for group in groups for s in group]:
        need(smoke.get('status') == 'passed' and smoke.get('source_version') == '0.79', 'catalog native smoke missing')
        for kind in ('skia', 'harfbuzz'):
            native = smoke[kind]['loader'] if kind == 'skia' else smoke[kind]
            need(native.get('origin') == ('upstream-download' if windows else 'managed') and native.get('absolute_path') and
                 native.get('installed_sha256') == native['manifest']['files'][kind]['sha256'] and
                 native['manifest']['lock_sha256'] == lock_sha256, 'catalog native provenance differs')
            path_type = PureWindowsPath if re.match(r'^[A-Za-z]:', native['absolute_path']) else PurePosixPath
            path = path_type(native['absolute_path'])
            directory = native.get('download_directory') if windows else native.get('managed_directory')
            need(directory and path.is_absolute() and path.parent == path_type(directory), 'catalog library escaped its generation')
            if windows:
                source = next(row for row in windows_records.values() if row['kind'] == kind)
                member = source['members'][source['library_member']]
                record = native['manifest']['files'][kind]
                need(path.parent.name == 'skia-upstream-1' and native.get('managed_directory') in (None, False)
                     and native['manifest'].get('package') == 'skia-upstream-win32-x86_64-1'
                     and native['manifest'].get('upstream_versions') == (native_lock or read_json(ROOT / 'packaging/native-assets.json'))['upstream_versions']
                     and native['manifest'].get('acquisition', {}).get('route') == 'direct-nuget'
                     and record.get('sha256') == member['sha256'] and record.get('size') == member['size']
                     and record.get('filename') == source['library_filename']
                     and record.get('asset_version') == source['version']
                     and record.get('archive_sha256') == source['sha256'], 'Windows installed DLL provenance differs from pinned upstream')
                expected_acquisition = dict(route='direct-nuget', archives=[
                    dict(name=name, url=row['url'], sha256=row['sha256'], size=row['size'])
                    for name, row in sorted(windows_records.items())])
                need(native['manifest'].get('acquisition') == expected_acquisition,
                     'Windows installed acquisition manifest differs from locked NuGets')
        if identity['target'] == 'x86_64-linux-natipkg':
            configuration = smoke['skia'].get('fontconfig') or {}
            need(configuration.get('origin') == 'managed-cache' and
                 configuration.get('template_sha256') == smoke['skia']['loader']['manifest']['support_configuration']['sha256'] and
                 re.fullmatch('[a-f0-9]{64}', configuration.get('materialized_sha256', '')),
                 'natipkg managed configuration provenance is missing')
            need(re.fullmatch('[a-f0-9]{64}', smoke['skia'].get('support_library_sha256', '')) and
                 PurePosixPath(smoke['skia'].get('support_library', '')).is_absolute(),
                 'natipkg support-library provenance is missing')
    need(set(report.get('rebuilt_documentation_smoke', {})) == {'source', 'built', 'binary-lib'},
         'rebuilt documentation proof missing')
    expected_fonts = {r['filename']: r['sha256'] for r in
                      (native_lock or read_json(ROOT / 'packaging/native-assets.json'))['documentation_fonts']['files']}
    docs = [report.get('documentation_smoke'), report.get('added_documentation_smoke')]
    docs += list(report['rebuilt_documentation_smoke'].values())
    need(all(isinstance(d, dict) and d.get('status') == 'passed' and len(d.get('shapes', [])) == 4 and
             {r.get('font'): r.get('font_sha256') for r in d['shapes']} == expected_fonts and
             all(r['glyphs'] and all(g > 0 for g in r['glyphs']) and r['advance'] > 0 for r in d['shapes'])
             for d in docs), 'documentation font coverage/provenance missing')
    need(all(s.get('source_identity') is False and len(s.get('shapes', [])) == 1 and
             s['shapes'][0].get('font') == 'procedural-AV' and s['shapes'][0].get('glyphs') == [2, 3]
             and s.get('default_font_verified') is True for s in [s for g in groups for s in g]),
         'core test depends on documentation fonts or generated identity')
    navigation = report.get('documentation_navigation') or {}
    need(set(navigation) == {'source', 'rebuilt-source', 'rebuilt-built', 'rebuilt-binary-lib'} and
         all(navigation[k].get('status') == 'passed' and navigation[k].get('tutorials') == 22
             and navigation[k].get('landing_checked') is True
             for k in ('source','rebuilt-source','rebuilt-built')), 'registered manual navigation proof missing')
    binary = navigation['rebuilt-binary-lib']
    need(binary.get('status') == 'racket-binary-lib-documentation-omitted' and binary.get('manuals') == 0
         and binary.get('content_state', '').startswith('(binary-lib ')
         and binary.get('fonts_and_editable_assets_checked_separately') is True,
         'binary-library format semantics/retention proof missing')
    return identity['target'], identity['version']


def verify(root, directory, *, commit, attempt):
    lock, digest = reviewed_lock(root)
    index = json_data((directory / 'artifact-index.json').read_text())
    assets = index.get('catalog-assets-' + str(attempt))
    need(assets is not None, 'catalog artifact set missing')
    with zipfile.ZipFile(directory / assets['file']) as archive:
        receipts = member_json(archive, 'native-artifacts.json')['artifacts']
        expected = {TARGETS[name]['package'] + '.zip' for name in DISTRIBUTED_TARGETS}
        need(len(receipts) == len(expected) and {r.get('archive') for r in receipts} == expected,
             'catalog artifacts must exclude the Windows direct-download payload')
        allowed = {'native-artifacts.json', 'source-packages.json'}
        for name in SOURCE_PACKAGES:
            allowed.update((name + '.zip', name + '.zip.CHECKSUM'))
        for name in expected:
            allowed.update((name, name + '.CHECKSUM', name.removesuffix('.zip') + '.receipt.json'))
        need(set(archive.namelist()) == allowed, 'unexpected candidate payload or file in catalog artifact set')
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
        need(len(artifacts) == 2, 'incomplete native set')
        source = member_json(archive, 'source-packages.json')
        sources = source.get('packages') or []
        need(len(sources) == 3 and {r.get('package') for r in sources} == set(SOURCE_PACKAGES), 'incomplete source set')
        from native_packages import json_bytes
        source_sha = hashlib.sha256(json_bytes(sources)).hexdigest()
        need(source.get('sha256') == source_sha and source.get('source_worktree_clean') is True
             and source.get('source_commit_observed') == commit, 'source-set identity differs')
        for row in sources:
            name = row['package'] + '.zip'
            data = archive.read(name)
            need(row.get('source_worktree_clean') is True and row.get('source_commit_observed') == commit
                 and len(data) == row['size'] and hashlib.sha256(data).hexdigest() == row['sha256']
                 and hashlib.sha1(data).hexdigest() == row['sha1']
                 and archive.read(name + '.CHECKSUM') == row['sha1'].encode('ascii'), 'source archive identity differs')
    targets = set()
    for name, record in index.items():
        if name.startswith('catalog-') and not name.startswith('catalog-assets-'):
            with zipfile.ZipFile(directory / record['file']) as archive:
                targets.add(verify_lane(member_json(archive, 'result.json'), member_json(archive, 'staging-receipt.json'),
                                        source_sha256=source_sha, artifacts=artifacts, lock_sha256=digest, commit=commit,
                                        native_lock=lock))
    expected = {(target, version) for target in ('aarch64-macosx', 'x86_64-macosx', 'win32\\x86_64',
                                                 'x86_64-linux', 'x86_64-linux-natipkg') for version in ('8.18', '9.3')}
    need(targets == expected, 'catalog platform/version qualification is incomplete: ' + repr(sorted(expected - targets)))
    return dict(catalog_candidate_validated=True, native_lock_sha256=digest, catalog_source_sha256=source_sha,
                catalog_artifacts=artifacts, catalog_lanes_verified=len(targets))
