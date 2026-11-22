"""Pinned, explicit Windows NuGet acquisition outside Racket package contents.

Acquisition has no native execution. Setup and loaders never call it. The
installer owns one paired directory; Racket package creation cannot collect it.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile

from native_packages import (ROOT, MAX_ARCHIVE, MAX_METADATA, bounded_member,
                             check_locked_input, json_bytes, need, read_json,
                             safe_name, sha256, validate_observations, zip_index)

DIRECTORY = 'skia-upstream-1'
IDENTITY = 'skia-upstream-win32-x86_64-1'
ROUTE = 'direct-nuget'


class NuGetHTTPS(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def check_url(url):
    parsed = urllib.parse.urlsplit(url)
    need(parsed.scheme == 'https' and parsed.hostname in ('api.nuget.org', 'globalcdn.nuget.org')
         and not parsed.username and not parsed.password and parsed.port in (None, 443),
         'Windows input URL must remain on the official HTTPS NuGet hosts')


def records(lock):
    validate_observations(lock)
    selected = {name: row for name, row in lock['archives'].items() if row['target'] == 'win32'}
    need(sorted(row['kind'] for row in selected.values()) == ['harfbuzz', 'skia'], 'incomplete Windows pair')
    return selected


def checked_input(path, record):
    need(path.is_file() and not linked(path) and path.stat().st_size == record['size']
         and path.stat().st_size <= MAX_ARCHIVE, 'Windows archive size/type differs from lock')
    need(sha256(path.read_bytes()) == record['sha256'], 'Windows archive SHA-256 differs from lock')
    return check_locked_input(path, record)


def acquire(lock_path, destination, *, source=None):
    """Acquire the exact two raw NuGets, or verify an explicit offline cache."""
    lock = read_json(lock_path)
    selected = records(lock)
    need(not destination.exists(), 'Windows input cache must be new')
    destination.parent.mkdir(parents=True, exist_ok=True)
    receipt = dict(schema=1, route=ROUTE, lock_sha256=sha256(lock_path.read_bytes()), archives=[])
    with tempfile.TemporaryDirectory(prefix='.windows-inputs-', dir=destination.parent) as temporary:
        stage = Path(temporary) / 'inputs'
        stage.mkdir()
        for name, record in sorted(selected.items()):
            path = stage / name
            final_url = record['url']
            if source is None:
                check_url(record['url'])
                opener = urllib.request.build_opener(NuGetHTTPS())
                with opener.open(record['url'], timeout=120) as response, path.open('xb') as stream:
                    final_url = response.geturl()
                    check_url(final_url)
                    size = 0
                    while chunk := response.read(1024 * 1024):
                        size += len(chunk)
                        need(size <= min(MAX_ARCHIVE, record['size']), 'Windows input exceeds locked size')
                        stream.write(chunk)
            else:
                checked_input(source / name, record)
                shutil.copyfile(source / name, path)
            checked_input(path, record)
            receipt['archives'].append(dict(name=name, package=record['package'], version=record['version'],
                                             url=record['url'], final_url=final_url, size=record['size'],
                                             sha256=record['sha256'], kind=record['kind'],
                                             member=record['library_member'],
                                             member_sha256=record['members'][record['library_member']]['sha256'],
                                             obtained_by='nuget-download' if source is None else 'verified-local-archive'))
        (stage / 'acquisition.json').write_bytes(json_bytes(receipt))
        stage.rename(destination)
    return receipt


def locations(racket, *, env=None):
    need(sys.version_info >= (3, 12), 'direct Windows installation requires Python 3.12 or later')
    expression = '''(begin (require json setup/dirs)
      (write-json (hasheq 'target (path->string (system-library-subpath #f))
                         'vm (symbol->string (system-type 'vm)) 'bits (system-type 'word)
                         'user (path->string (find-user-lib-dir))
                         'installation (path->string (find-lib-dir)))))'''
    result = json.loads(subprocess.check_output([str(racket), '-e', expression], env=env,
                                               text=True, encoding='utf-8'))
    need(result['target'] == 'win32\\x86_64' and result['vm'] == 'chez-scheme' and result['bits'] == 64,
         'direct Windows installation requires a Windows x86-64 Racket CS interpreter')
    return {scope: Path(result[scope]) / DIRECTORY for scope in ('user', 'installation')}


def linked(path):
    return path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction())


def safe_directory(directory):
    need(directory.name == DIRECTORY and directory.is_absolute(), 'unexpected Windows native directory')
    need(not any(linked(p) for p in (directory, *directory.parents)),
         'linked/junction Windows native directory or ancestor')


def owned(directory, *, verify=True):
    safe_directory(directory)
    manifest = read_json(directory / 'manifest.json')
    need(manifest.get('package') == IDENTITY and manifest.get('acquisition', {}).get('route') == ROUTE,
         'refusing to modify a directory not owned by the direct Windows installer')
    files = manifest.get('installed_files', {})
    need(isinstance(files, dict) and files, 'missing Windows installation ownership inventory')
    actual = set()
    for path in directory.rglob('*'):
        need(not linked(path), 'linked/junction entry in Windows native installation')
        if path.is_file():
            actual.add(path.relative_to(directory).as_posix())
    expected = set(files) | {'manifest.json'}
    need(actual == expected if verify else actual <= expected, 'unowned files in Windows native directory')
    for name, identity in files.items():
        safe_name(name)
        path = directory / name
        if verify:
            need(path.stat().st_size == identity['size'] and sha256(path.read_bytes()) == identity['sha256'],
                 'changed Windows installation member: ' + name)
    return manifest


def install(lock_path, inputs, directory, *, revision='1.0'):
    """Validate the full pair, then replace one owned generation atomically."""
    safe_directory(directory)
    lock = read_json(lock_path)
    selected = records(lock)
    members, files = {}, {}
    for name, record in sorted(selected.items()):
        path = inputs / name
        checked_input(path, record)
        with zipfile.ZipFile(path) as archive:
            index = zip_index(archive)
            filename = record['library_filename']
            data = bounded_member(archive, index, record['library_member'])
            members[filename] = data
            files[record['kind']] = dict(filename=filename, sha256=sha256(data), size=len(data),
                                          asset_version=record['version'], archive_sha256=record['sha256'])
            for notice in ('LICENSE.txt', 'THIRD-PARTY-NOTICES.txt', record['nuspec']):
                members['licenses/' + record['kind'] + '/' + notice] = bounded_member(archive, index, notice, MAX_METADATA)
    # Preserve the project's collected component texts alongside the original
    # upstream notices. This installer does not declare redistribution approval.
    for key, record in lock.get('supplemental_notices', {}).items():
        if key not in ('noto-ofl', 'cjk-ofl'):
            path = ROOT / record['path']
            data = path.read_bytes()
            need(len(data) == record['size'] and sha256(data) == record['sha256'], 'component notice drift: ' + key)
            members['licenses/components/' + key + '.txt'] = data
    members['README.txt'] = (b'Explicit user download of the pinned upstream Windows libraries.\n'
                            b'Not a Racket native dependency package. See licenses/ and manifest.json.\n'
                            b'This product includes DNG technology under license by Adobe Systems Incorporated.\n')
    acquisition = dict(route=ROUTE, archives=[dict(name=name, url=r['url'], sha256=r['sha256'], size=r['size'])
                                             for name, r in sorted(selected.items())])
    manifest = dict(schema=1, generation=1, package=IDENTITY, package_version=revision, target='win32',
                    upstream_versions=lock['upstream_versions'], files=files, acquisition=acquisition,
                    lock_sha256=sha256(lock_path.read_bytes()), transformations=[],
                    installed_files={name: dict(size=len(data), sha256=sha256(data)) for name, data in members.items()})
    members['manifest.json'] = json_bytes(manifest)
    if directory.exists():
        owned(directory, verify=False)
    directory.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.windows-pair-', dir=directory.parent) as temporary:
        temporary = Path(temporary)
        payload, previous = temporary / 'payload', temporary / 'previous'
        payload.mkdir()
        for name, data in members.items():
            path = payload / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        if directory.exists():
            directory.rename(previous)
        try:
            payload.rename(directory)
        except OSError:
            if previous.exists():
                previous.rename(directory)
            raise
    return manifest


def remove(directory):
    owned(directory, verify=False)
    shutil.rmtree(directory)
