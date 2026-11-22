"""Bounded catalog asset receipts for CI that does not upload native payloads."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import zipfile

from native_packages import (MAX_ARCHIVE, MAX_METADATA, TARGETS, DISTRIBUTED_TARGETS, bounded_member,
                             json_bytes, need, read_json, unique, zip_index)


def archive_identity(path: Path) -> dict:
    need(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= MAX_ARCHIVE,
         'missing/unsafe/oversized candidate archive: ' + path.name)
    sha1, sha256, size = hashlib.sha1(), hashlib.sha256(), 0
    with path.open('rb') as stream:
        while data := stream.read(1024 * 1024):
            size += len(data)
            need(size <= MAX_ARCHIVE, 'candidate archive grew beyond the size bound')
            sha1.update(data)
            sha256.update(data)
    checksum = path.with_suffix('.zip.CHECKSUM')
    need(checksum.is_file() and not checksum.is_symlink() and checksum.stat().st_size == 40,
         'missing/unsafe Racket checksum: ' + path.name)
    need(checksum.read_bytes() == sha1.hexdigest().encode('ascii'),
         'Racket checksum differs from archive: ' + path.name)
    return dict(archive=path.name, size=size,
                sha1=sha1.hexdigest(), sha256=sha256.hexdigest())


def collect(artifacts: Path, output: Path) -> dict:
    need(artifacts.is_dir() and not artifacts.is_symlink(), 'unsafe/missing artifact directory')
    need(not output.exists(), 'receipt output must be a new directory')
    native = read_json(artifacts / 'native-artifacts.json')
    need(type(native) is dict and native.get('schema') == 1, 'invalid native artifact index')
    expected = {TARGETS[name]['package'] + '.zip' for name in DISTRIBUTED_TARGETS} | {'skia-fonts-1.zip'}
    rows = native.get('artifacts')
    need(type(rows) is list and len(rows) == len(expected), 'incomplete native/font receipt set')
    need(all(type(row) is dict and type(row.get('archive')) is str
             and row['archive'] in expected for row in rows)
         and {row['archive'] for row in rows} == expected, 'unknown/duplicate native/font archive')
    receipts, identities = {}, []
    for row in rows:
        name = row['archive']
        identity = archive_identity(artifacts / name)
        need(all(row.get(key) == identity[key] for key in ('size', 'sha1', 'sha256')),
             'candidate archive differs from receipt: ' + name)
        receipt_name = name.removesuffix('.zip') + '.receipt.json'
        receipt = read_json(artifacts / receipt_name)
        need(receipt == row, 'individual and aggregate receipts differ: ' + name)
        receipts[receipt_name] = json_bytes(receipt)
        identities.append(identity)
    source = artifacts / 'skia.zip'
    identities.append(archive_identity(source))
    with zipfile.ZipFile(source) as archive:
        index = zip_index(archive)
        data = bounded_member(archive, index, 'private/source-identity.json', MAX_METADATA)
    source_identity = json.loads(data, object_pairs_hook=unique,
                                 parse_constant=lambda value: need(False, 'nonfinite source identity'))
    need(type(source_identity) is dict and set(source_identity) == {
        'schema', 'source_commit_observed', 'source_worktree_clean'}, 'invalid source identity fields')
    commit = source_identity.get('source_commit_observed')
    need(source_identity.get('schema') == 1 and source_identity.get('source_worktree_clean') is True
         and type(commit) is str and re.fullmatch('[0-9a-f]{40}', commit),
         'source archive is not a clean committed candidate')
    need(all(row.get('source_commit_observed') == commit for row in rows),
         'source and data packages identify different commits')
    need(all(row.get('source_worktree_clean', True) is True for row in rows),
         'data package receipts identify a dirty worktree')
    report = dict(schema=1, mode='receipts-only', source=source_identity,
                  archives=sorted(identities, key=lambda row: row['archive']),
                  native_payloads_uploaded=False, catalog_candidate_validated=False)
    receipts['native-artifacts.json'] = json_bytes(native)
    receipts['artifact-digests.json'] = json_bytes(report)
    # Finish verification before writing. The output allowlist contains JSON
    # receipts/digests only, never copies an input directory or archive member.
    output.mkdir(parents=True)
    for name, data in receipts.items():
        (output / name).write_bytes(data)
    return report
