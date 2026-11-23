#!/usr/bin/env python3
"""Build locked data-only packages offline; unreviewed local experiments are labelled.

This tool has no network code. Release assembly requires completed input,
component-license and transitive-library review. --local-candidate is only for
disposable validation; its receipt can never certify a release candidate.
"""
from __future__ import annotations
from repository_layout import source_path, library_root, documentation_root

import argparse
from pathlib import Path
import subprocess
import zipfile

from native_packages import (ROOT, GENERATOR_VERSION, DISTRIBUTED_TARGETS, check_locked_input,
                             json_bytes, read_json, need, sha256, write_zip,
                             zip_index, bounded_member, MAX_METADATA, validate_observations,
                             validate_distribution_lock, check_font_input)


def native_info(target, version, *, reviewed, lock=None):
    # Preserve the entire directory and notices in every Racket package form.
    # Templates are generated text, never nested info.rkt modules in this repo.
    support = ''.join(f' ("{d["name"]}" #:platform {d["platform"]})'
                      for d in (lock or {}).get('support_dependencies', {}).get(target.get('id'), []))
    license = (lock or {}).get('native_license', {}).get(target.get('id'), 'MIT')
    return f'''#lang info
(define collection "{target['package']}")
(define version "{version}")
(define pkg-desc "Pinned SkiaSharp and HarfBuzzSharp native libraries (generation 1)")
(define pkg-authors '(soegaard))
(define deps '(("base" #:version "8.18"){support}))
(define license '{license})
(define install-platform {target['selector']})
(define copy-foreign-libs '("skia-native-1"))
(define compile-omit-paths '("skia-native-1" "licenses"))
(define test-omit-paths '("skia-native-1" "licenses"))
(define source-keep-files '("skia-native-1" "licenses" "README.md"))
(define binary-keep-files '("skia-native-1" "licenses" "README.md"))
(define binary-lib-keep-files '("skia-native-1" "licenses" "README.md"))
(define distribution-preference 'binary)
; Redistribution review: {'approved' if reviewed else 'PENDING: LOCAL EXPERIMENT ONLY'}.
; The component/license expression is taken from the reviewed input inventory.
'''.encode()


def build(lock_path, inputs, output, *, local_candidate=False):
    lock = read_json(lock_path)
    need(lock.get('schema') == 1 and lock.get('generation') == 1
         and lock.get('directory') == 'skia-native-1', 'unsupported native lock')
    review = lock.get('review', {})
    reviewed = all(review.get(k) is True for k in ('redistribution_approved',
                                                  'component_license_mapping_complete',
                                                  'transitive_resolution_qualified'))
    reviewed = reviewed and review.get('status') == 'approved'
    need(reviewed or local_candidate,
         'native lock has unresolved redistribution/transitive review; release assembly refused')
    validate_distribution_lock(lock)
    need(not output.exists(), 'output must be a new directory')
    records = lock['archives']
    for name, record in records.items():
        need(Path(name).name == name, 'unsafe input filename')
        check_locked_input(inputs / name, record)
    # Validate all inputs before writing the first payload.
    output.mkdir(parents=True)
    lock_digest = sha256(lock_path.read_bytes())
    generator_digest = sha256(Path(__file__).read_bytes() + (ROOT / 'tools/native_packages.py').read_bytes())
    source_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    receipts = []
    for name, target in lock['targets'].items():
        if name not in DISTRIBUTED_TARGETS:
            continue
        selected = {n: r for n, r in records.items() if r['target'] == name}
        need(sorted(r['kind'] for r in selected.values()) == ['harfbuzz', 'skia'], 'incomplete native pair')
        members = {}
        files = {}
        for archive_name, record in selected.items():
            with zipfile.ZipFile(inputs / archive_name) as archive:
                index = zip_index(archive)
                filename = record['library_filename']
                library = bounded_member(archive, index, record['library_member'])
                members['skia-native-1/' + filename] = library
                files[record['kind']] = dict(filename=filename, sha256=sha256(library), size=len(library),
                                              asset_version=record['version'],
                                              archive_sha256=record['sha256'])
                for notice in ('LICENSE.txt', 'THIRD-PARTY-NOTICES.txt', record['nuspec']):
                    members[f"licenses/{record['kind']}/{notice}"] = bounded_member(archive, index, notice, MAX_METADATA)
        manifest = dict(schema=1, generation=1, package=target['package'],
                        package_version=lock['native_package_version'], target=name,
                        upstream_versions=lock['upstream_versions'], files=files,
                        lock_sha256=lock_digest, transformations=lock['transformations'],
                        redistribution_review='approved' if reviewed else 'pending', local_experiment=not reviewed,
                        support_dependencies=lock['support_dependencies'].get(name, []))
        if name == 'linux':
            configuration = lock['configurations']['linux-fontconfig']
            members['skia-native-1/' + configuration['filename']] = (source_path(ROOT, configuration['path'])).read_bytes()
            manifest['support_configuration'] = {k:configuration[k] for k in ('filename','sha256','size','license')}
        for key, record in lock['supplemental_notices'].items():
            if key not in ('noto-ofl', 'cjk-ofl'):
                members['licenses/components/' + key + '.txt'] = (source_path(ROOT, record['path'])).read_bytes()
        members['licenses/COMPONENTS.json'] = json_bytes(lock['component_inventory'])
        members['licenses/BUILD-EVIDENCE.json'] = (source_path(ROOT, lock['component_build_evidence']['path'])).read_bytes()
        members['licenses/REDISTRIBUTION-REVIEW.md'] = (source_path(ROOT, lock['redistribution_review_document']['path'])).read_bytes()
        members['licenses/skia-for-racket-MIT.txt'] = (ROOT / 'LICENSE').read_bytes()
        members['skia-native-1/manifest.json'] = json_bytes(manifest)
        members['info.rkt'] = native_info(dict(target, id=name), lock['native_package_version'], reviewed=reviewed, lock=lock)
        members['README.md'] = (f"# {target['package']} — native generation 1\n\n"
                               'This package redistributes unmodified binaries from the '
                               '[SkiaSharp project](https://github.com/mono/SkiaSharp).\n'
                               'Original licenses and third-party notices are included in licenses/.\n'
                               'Publication awaits the full manual release gate and separate authorization.\n'
                               'This product includes DNG technology under license by Adobe Systems Incorporated.\n'
                               'Portions of this software are copyright The FreeType Project (www.freetype.org). All rights reserved.\n').encode()
        if name != 'win32':
            members['README.md'] += b'Ordinary Linux requires OS fontconfig and glibc >= 2.27; natipkg support is declared in info.rkt.\n'
        if name == 'linux':
            members['README.md'] += (b'On natipkg the lazy loader materializes the verified fontconfig template with declared font/cache paths in the addon font cache.\n'
                                    b'It selects that file in the native process environment unless FONTCONFIG_FILE is already set. Native library bytes remain unmodified.\n')
        archive = output / (target['package'] + '.zip')
        identity = write_zip(archive, members)
        receipt = dict(schema=1, package=target['package'], archive=archive.name,
                       **identity, source_commit_observed=source_commit,
                       source_worktree_clean=not bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
                       generator_version=GENERATOR_VERSION, generator_sha256=generator_digest,
                       lock_sha256=lock_digest, upstream_archives=selected,
                       payload=manifest, local_experiment=not reviewed,
                       catalog_candidate_validated=False, redistribution_approved=reviewed)
        (output / (target['package'] + '.receipt.json')).write_bytes(json_bytes(receipt))
        receipts.append(receipt)
    (output / 'native-artifacts.json').write_bytes(json_bytes(dict(
        schema=1, artifacts=receipts, catalog_candidate_validated=False)))
    return receipts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lock', type=Path, required=True)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--local-candidate', action='store_true',
                        help='produce explicitly unreviewed local lifecycle fixtures; cannot validate a release')
    args = parser.parse_args()
    build(args.lock, args.inputs, args.output, local_candidate=args.local_candidate)


if __name__ == '__main__':
    main()
