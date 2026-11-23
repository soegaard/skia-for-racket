#!/usr/bin/env python3
"""Prepare exact unpublished source/native archives and a disposable catalog.

Network preparation is explicit. --snapshot stages the selected platform's
complete dependency closure from one released Racket catalog, for a subsequent
network-denied validator. This never changes the normal user's catalog config.
"""
from __future__ import annotations
from repository_layout import source_path

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

from native_packages import ROOT, need, sha256, read_json, json_bytes, write_zip, zip_index, check_font_input
from repository_layout import SOURCE_PACKAGES
from catalog_snapshot import inventory, stage_dependencies
from catalog_execution import racket_command, runtime_child_environment, runtime_profile


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'tools' / (name + '.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def source_archive(root, destination, *, allow_dirty=False, package='skia'):
    need(package in SOURCE_PACKAGES, 'unknown source package')
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root))
    need(allow_dirty or not dirty, 'candidate source must be clean/committed; use --allow-dirty only for labelled local validation')
    args = ['git', 'ls-files', '--cached', '-z', '--', package]
    if allow_dirty:
        args = ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', package]
    names = sorted(set(n for n in subprocess.check_output(args, cwd=root).decode().split('\0') if n))
    fonts = {f['filename']: f for f in read_json(root / 'packaging/native-assets.json')['documentation_fonts']['files']}
    members = {}
    for name in names:
        path = source_path(root, name)
        if allow_dirty and not path.exists():
            continue  # A tracked rename is represented by its new untracked path.
        need(path.is_file() and not path.is_symlink(), 'unsafe/missing source member: ' + name)
        relative = path.relative_to(source_path(root, package)).as_posix()
        need(not any(p in ('.git', 'compiled', '__pycache__', 'output', 'downloads', 'doc', 'html') for p in Path(relative).parts)
             and not relative.lower().endswith(('.nupkg', '.so', '.dylib', '.dll', '.exe', '.zo', '.pyc')),
             'binary/generated file in source archive: ' + name)
        need(relative != 'private/source-identity.json', 'Git sources must not require generated source identity')
        if relative.lower().endswith(('.ttf', '.otf', '.ttc')):
            need(package == 'skia-doc' and relative.startswith('fonts/') and Path(relative).name in fonts,
                 'unapproved font or font outside documentation: ' + name)
            check_font_input(path, fonts[Path(relative).name])
        members[relative] = path.read_bytes()
    need('info.rkt' in members and 'LICENSE' in members, 'incomplete source package: ' + package)
    if package == 'skia-doc':
        need({n for n in members if n.lower().endswith(('.ttf','.otf','.ttc'))} ==
             {'fonts/' + f for f in fonts}, 'documentation must retain exactly four approved fonts')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    identity = write_zip(destination, members)
    return dict(**identity, package=package, archive=destination.name, source_worktree_clean=not dirty,
                source_commit_observed=commit, files=len(members), contains_native_binaries=False,
                contains_fonts=package == 'skia-doc', generated_source_identity=False)


def source_archives(root, artifacts, *, allow_dirty=False):
    rows = [source_archive(root, artifacts / (name + '.zip'), allow_dirty=allow_dirty, package=name)
            for name in SOURCE_PACKAGES]
    report = dict(schema=1, packages=rows, source_worktree_clean=all(r['source_worktree_clean'] for r in rows),
                  source_commit_observed=rows[0]['source_commit_observed'])
    # Bind the complete package set outside the installable packages. Ordinary
    # Git installations have no archive-injected identity file.
    report['sha256'] = sha256(json_bytes(rows))
    (artifacts / 'source-packages.json').write_bytes(json_bytes(report))
    return report


def stage(racket, output, *, cache=None, snapshot=False, allow_dirty=False, base_catalog=None):
    need(not output.exists(), 'staging output must be new')
    output.mkdir(parents=True)
    output = output.resolve()
    racket = str(Path(shutil.which(racket) or racket).resolve())
    prefix = racket_command(Path(racket))
    environment = dict(os.environ, **runtime_child_environment(Path(racket)))
    lock = ROOT / 'packaging/native-assets.json'
    need(Path(racket).is_file(), 'selected Racket executable is absent')
    identity = json.loads(subprocess.check_output([*prefix, '-e',
        '(begin (require json) (write-json (hasheq \'version (version) \'os (symbol->string (system-type \'os)) \'target (path->string (system-library-subpath #f)) \'compile_target_machine (let ([m (current-compile-target-machine)]) (and m (symbol->string m))))))'], env=environment, text=True, encoding='utf-8'))
    need(identity['version'] in ('8.18', '9.3'), 'candidate qualification requires released Racket 8.18 or 9.3')
    if cache is None:
        cache = output / 'inputs'
        module('prepare-native-packages').prepare(lock, cache)
    artifacts = output / 'artifacts'
    module('build-native-packages').build(lock, cache, artifacts, local_candidate=True)
    source = source_archives(ROOT, artifacts, allow_dirty=allow_dirty)
    native = read_json(artifacts / 'native-artifacts.json')
    metadata = output / 'metadata'
    metadata.mkdir()
    rows = [dict(name=r['package'], archive=str(artifacts / r['archive']),
                 metadata_directory=str(source_path(ROOT, r['package'])), sha1=r['sha1']) for r in source['packages']]
    for receipt in native['artifacts']:
        name = receipt['package']
        folder = metadata / name
        folder.mkdir()
        archive = artifacts / receipt['archive']
        need(sha256(archive.read_bytes()) == receipt['sha256'], 'candidate artifact digest differs')
        with zipfile.ZipFile(archive) as z:
            zip_index(z)
            (folder / 'info.rkt').write_bytes(z.read('info.rkt'))
        rows.append(dict(name=name, archive=str(archive), metadata_directory=str(folder), sha1=receipt['sha1']))
    request = output / 'catalog-request.json'
    request.write_bytes(json_bytes(rows))
    with (output / 'catalog-metadata.log').open('wb') as log:
        subprocess.run([*prefix, str(ROOT / 'tools/write-staging-catalog.rkt'), str(request), str(output / 'catalog')],
                       env=environment, stdout=log, stderr=subprocess.STDOUT, check=True)
    report = dict(schema=1, identity=identity, source=source, artifacts=native,
                  runtime_profile=runtime_profile(Path(racket)),
                  catalog=str(output / 'catalog'), lock_sha256=sha256(lock.read_bytes()),
                  catalog_candidate_validated=False, publication_performed=False)
    (output / 'staging-receipt.json').write_bytes(json_bytes(report))
    if snapshot:
        target = output / 'snapshot'
        report['dependency_staging'] = stage_dependencies(prefix, output, identity, output / 'catalog',
            base_catalog or ('https://download.racket-lang.org/releases/' + identity['version'] + '/catalog/'), environment)
        # Racket's catalog-archive repacks even local archives. Restore the
        # original candidate bytes AND their catalog checksums after staging
        # the standard closure; otherwise execution tests different ZIPs.
        candidates = {}
        for row in rows:
            archive = Path(row['archive'])
            destination = target / 'pkgs' / archive.name
            shutil.copyfile(archive, destination)
            shutil.copyfile(archive.with_suffix('.zip.CHECKSUM'), destination.with_suffix('.zip.CHECKSUM'))
            need(destination.read_bytes() == archive.read_bytes(), 'snapshot changed candidate archive bytes')
            candidates[row['name']] = dict(sha1=row['sha1'], sha256=sha256(destination.read_bytes()), size=destination.stat().st_size)
        subprocess.run([*prefix, str(ROOT / 'tools/overlay-candidate-catalog.rkt'), str(output / 'catalog'), str(target / 'catalog')], env=environment, check=True)
        report['snapshot_catalog'] = str(target / 'catalog')
        report['snapshot_candidates_preserved'] = True
        report['snapshot_candidates'] = candidates
        report['dependency_snapshot'] = inventory(target)
        report['dependency_staging_command'] = report['dependency_staging']['attempts'][-1]['command']
        (output / 'staging-receipt.json').write_bytes(json_bytes(report))
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--racket', default=os.environ.get('RACKET', 'racket'))
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--cache', type=Path)
    p.add_argument('--snapshot', action='store_true')
    p.add_argument('--base-catalog', help='already staged dependency catalog, or the selected official release catalog')
    p.add_argument('--allow-dirty', action='store_true')
    args = p.parse_args()
    stage(args.racket, args.output, cache=args.cache, snapshot=args.snapshot, allow_dirty=args.allow_dirty,
          base_catalog=args.base_catalog)


if __name__ == '__main__':
    main()
