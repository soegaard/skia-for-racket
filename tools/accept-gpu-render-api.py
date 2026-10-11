#!/usr/bin/env python3
"""Observe, and explicitly approve, only the new one-shot GPU-render export.

This is a narrow maintainer migration, not an auto-approve mode for the API
validator. Expected snapshots are written only from a fresh Racket observation.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
ENTRY = dict(name='render-gpu->raster-image', phase='0', export_kind='value',
             kind='procedure', arity_mask='8', required_keywords=['backend'],
             allowed_keywords=['adapter', 'adapter-index', 'backend', 'background', 'provider'])
ADDITION = dict(module='gpu.rkt', phase='0', name=ENTRY['name'], export_kind='value',
                change='added', before=None, after=ENTRY)


def validate_changes(changes: list[dict], actual_entry: dict | None) -> bool:
    """This declaration constrains real reflection; it is not a runtime receipt."""
    if not isinstance(actual_entry, dict):
        raise ValueError('the new function was not observed')
    binding = actual_entry.get('export_kind')
    # Racket can expose a keyword callable through a syntax-backed binding.
    # Preserve the actual reflected category instead of fabricating one.
    expected = dict(ENTRY, export_kind=binding)
    if binding not in ('value', 'syntax') or actual_entry != expected:
        raise ValueError('the observed render-gpu->raster-image signature differs from this addition')
    if not changes:
        return False
    addition = dict(ADDITION, export_kind=binding, after=expected)
    if changes != [addition]:
        raise ValueError('unrelated API drift; refusing to approve anything '
                         'except the single addition')
    return True


def atomic_text(path: Path, text: str) -> None:
    if path.is_symlink():
        raise ValueError('refusing a symlink output: ' + str(path))
    descriptor, name = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8', newline='\n') as stream:
            stream.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def baseline_bytes(root: Path, commit: str, name: str) -> bytes | None:
    result = subprocess.run(['git', 'show', f'{commit}:{name}'], cwd=root,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    return result.stdout if result.returncode == 0 else None


def verify_source_edits(root: Path, declaration: dict) -> tuple[dict, dict]:
    """Check this patch's bytes/edits, not arbitrary source changes by pathname."""
    if declaration.get('schema') != 1:
        raise ValueError('unrecognized addition-review schema')
    commit = declaration['base_commit']
    if commit != 'f8cc4bef5a1a481b7b3823d52e703a9a8c7fd932':
        raise ValueError('wrong reviewed implementation baseline')
    subprocess.run(['git', 'cat-file', '-e', commit + '^{commit}'], cwd=root, check=True)
    names = set(declaration['source_hashes']) | set(declaration['edits'])
    before, after = {}, {}
    for name in sorted(names):
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts or '\\' in name:
            raise ValueError('unsafe reviewed path')
        path = root / relative
        if path.is_symlink() or not path.is_file():
            raise ValueError('missing or symlink reviewed file: ' + name)
        base = baseline_bytes(root, commit, name)
        current = path.read_bytes()
        if name in declaration['edits']:
            if base is None:
                raise ValueError('missing edit baseline: ' + name)
            expected = base.decode('utf-8')
            for old, new in declaration['edits'][name]:
                if expected.count(old) != 1:
                    raise ValueError('reviewed edit context differs: ' + name)
                expected = expected.replace(old, new, 1)
            if current != expected.encode('utf-8'):
                raise ValueError('unreviewed additional edit: ' + name)
        elif digest(current) != declaration['source_hashes'][name]:
            raise ValueError('source differs from this reviewed patch: ' + name)
        before[name] = None if base is None else digest(base)
        after[name] = digest(current)
    return before, after


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket', required=True, help='full Racket CS executable')
    parser.add_argument('--accept', action='store_true', help='publish this one reviewed addition')
    args = parser.parse_args(argv)
    try:
        # Import here: the guard's Python tests need neither Racket nor a checkout.
        import public_api as api
        import api_inventory as inventory
        import release_scope as scope
        root = ROOT.resolve()
        top = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], cwd=root,
                                      text=True).strip()
        api.need(Path(top).resolve() == root, 'run from a complete Git checkout')
        racket = shutil.which(args.racket)
        api.need(racket is not None, 'Racket executable not found: ' + args.racket)
        declaration_path = root / 'api/gpu-render-addition.json'
        declaration = api.read_json(declaration_path)
        old_sources, reviewed_sources = verify_source_edits(root, declaration)
        policy = api.read_json(root / api.POLICY)
        snapshots = {g: api.checked_snapshot(api.read_json(root / path), policy, g)
                     for g, path in api.SNAPSHOTS.items()}
        api.need((root / api.REPORT).read_text(encoding='utf-8') ==
                 api.generated_report(policy, snapshots), 'existing generated API index has drifted')
        protected = [api.POLICY, api.REPORT, *api.SNAPSHOTS.values(),
                     scope.POLICY, scope.REVIEW, scope.REPORT, 'api/gpu-render-addition.json']
        frozen = {p: api.file_hash(root / p) for p in protected}
        catalog = inventory.load_catalog(root)
        inventory.validate_catalog(catalog)
        source_graph = inventory.validate_sources(root, catalog)
        inventory.check_report(root, catalog)
        hashes = scope.review_inputs(root, catalog, source_graph['source_hashes'])
        review = scope.read_json(root / scope.REVIEW)
        release_policy = scope.read_json(root / scope.POLICY)
        token = uuid.uuid4().hex
        directory = root / 'output' / ('gpu-render-api-' + token)
        directory.mkdir(parents=True, exist_ok=False)
        observation = api.reflect_group(root, root / api.POLICY, 'headless', racket,
                                        directory, token)
        actual = api.snapshot_from_observation(observation, policy, 'headless', token)
        changes = api.differences(snapshots['headless'], actual)
        (directory / 'diff.json').write_text(api.json_text(changes), encoding='utf-8')
        entries = [e for m in actual['modules'] if m['path'] == 'gpu.rkt'
                   for e in m['exports'] if e['name'] == ENTRY['name'] and e['phase'] == '0']
        api.need(len(entries) == 1, 'the requested public function was not observed exactly once')
        api_update = validate_changes(changes, entries[0])
        api.need(frozen == {p: api.file_hash(root / p) for p in protected},
                 'API or release baseline changed during reflection')
        api.need(reviewed_sources == verify_source_edits(root, declaration)[1],
                 'reviewed source changed during reflection')
        new_graph = inventory.validate_sources(root, catalog)
        api.need(hashes == scope.review_inputs(root, catalog, new_graph['source_hashes']),
                 'release input changed during reflection')
        snapshots['headless'] = actual
        outputs = {api.SNAPSHOTS['headless']: api.json_text(actual),
                   api.REPORT: api.generated_report(policy, snapshots)}
        candidate_hashes = dict(hashes)
        for name, text in outputs.items():
            candidate_hashes[name] = digest(text.encode('utf-8'))
        # The source review is also frozen. Approve only these authored source
        # changes and the two files produced by actual reflection above.
        changed = sorted(name for name in set(candidate_hashes) | set(review['source_hashes'])
                         if candidate_hashes.get(name) != review['source_hashes'].get(name))
        for name in changed:
            previous = review['source_hashes'].get(name)
            if name in reviewed_sources:
                api.need(previous in (old_sources[name], reviewed_sources[name]),
                         'unreviewed previous source hash: ' + name)
            elif name in outputs:
                base = baseline_bytes(root, declaration['base_commit'], name)
                api.need(base is not None and previous in (digest(base), candidate_hashes[name]),
                         'unreviewed previous API snapshot/index: ' + name)
            else:
                raise ValueError('unrelated release input drift: ' + name)
        updated_review = copy.deepcopy(review)
        updated_review['source_hashes'] = dict(sorted(candidate_hashes.items()))
        summary = scope.validate_review(catalog, candidate_hashes, updated_review, release_policy)
        outputs[scope.REVIEW] = scope.json_text(updated_review)
        outputs[scope.REPORT] = scope.generated_report(catalog, updated_review, summary)
        (directory / 'release-input-diff.json').write_text(api.json_text(changed), encoding='utf-8')
        print(f'Actual Racket reflection and reviewed diffs: {directory}')
        if not api_update and not changed:
            print('The addition is already accepted; no expected files changed.')
            return 0
        if not args.accept:
            print('Only the intended addition and its reviewed source changes were observed.')
            print('Review the diffs, then rerun with --accept. No expected files changed.')
            return 0
        originals = {name: (root / name).read_text(encoding='utf-8') for name in outputs}
        try:
            for name, text in outputs.items():
                atomic_text(root / name, text)
        except Exception:
            # Ordinary write failures roll back the pair of baselines and reports.
            # A power loss is not a multi-file transaction; the checker detects drift.
            for name, text in originals.items():
                atomic_text(root / name, text)
            raise
        print('Updated the reflected API snapshot/index and the reviewed source ledger/report.')
        print('Review and commit these files. Regenerate SOURCE-SHA256SUMS.txt, then run')
        print('tools/validate-public-api.py for the full headless + GUI check.')
        return 0
    except Exception as error:
        print(f'GPU-render API approval failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
