#!/usr/bin/env python3
"""Single, fail-closed portability matrix. No network or Racket execution."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
# Deliberately named images, not mutable -latest architecture aliases.
RUNNERS = {
    'ubuntu-24.04': ('unix', 'x86_64', 'x64'),
    'macos-15': ('macosx', 'aarch64', 'arm64'),
    'macos-15-intel': ('macosx', 'x86_64', 'x64'),
    'windows-2022': ('windows', 'x86_64', 'x64'),
}


def load_matrix(path: Path = HERE / 'ci-matrix.json') -> dict:
    data = json.loads(path.read_text(encoding='utf-8'))
    if data.get('schema_version') != 1 or data.get('stage') != '0.46':
        raise ValueError('unsupported CI matrix schema/stage')
    if data.get('racket_variant') != 'CS' or data.get('python') != '3.12':
        raise ValueError('matrix requires the reviewed CS/Python toolchain')
    if data.get('native_packages') != {'skia': '3.119.1', 'harfbuzz': '8.3.1.2'}:
        raise ValueError('native package migration requires a separate review')
    ids = set()
    for profile in ('cpu', 'egl'):
        rows = data.get(profile)
        if not isinstance(rows, list) or not rows:
            raise ValueError(f'empty {profile} matrix')
        for row in rows:
            fields = {'id', 'runner', 'architecture', 'os', 'racket_arch', 'racket'}
            if profile == 'egl':
                fields.add('surface')
            if not isinstance(row, dict) or set(row) != fields:
                raise ValueError(f'invalid {profile} row fields')
            name = row['id']
            if not isinstance(name, str) or not re.fullmatch(r'[a-z][a-z0-9-]{0,47}', name) or name in ids:
                raise ValueError('invalid/duplicate matrix id')
            ids.add(name)
            if RUNNERS.get(row['runner']) != (row['os'], row['racket_arch'], row['architecture']):
                raise ValueError('runner and interpreter architecture disagree')
            if row['racket'] not in ('8.18', '9.3'):
                raise ValueError('use an explicit reviewed Racket release, not stable/current')
            if profile == 'egl' and (row['runner'] != 'ubuntu-24.04' or
                                     row['racket'] != '9.3' or
                                     row['surface'] not in ('surfaceless', 'pbuffer')):
                raise ValueError('EGL lanes require Linux x64 / Racket 9.3 and an explicit binding surface')
    targets = {(r['os'], r['racket_arch']) for r in data['cpu'] if r['racket'] == '9.3'}
    if targets != {('unix', 'x86_64'), ('macosx', 'aarch64'),
                   ('macosx', 'x86_64'), ('windows', 'x86_64')}:
        raise ValueError('missing core CPU portability target')
    if not any(r['racket'] == '8.18' and r['os'] == 'unix' for r in data['cpu']):
        raise ValueError('declared minimum Racket version is not tested')
    if {r['surface'] for r in data['egl']} != {'surfaceless', 'pbuffer'}:
        raise ValueError('both headless EGL binding modes must be required')
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--github-output', action='store_true')
    args = parser.parse_args()
    data = load_matrix()
    if args.github_output:
        output = os.environ.get('GITHUB_OUTPUT')
        if not output:
            raise ValueError('GITHUB_OUTPUT is absent')
        with open(output, 'a', encoding='utf-8', newline='\n') as out:
            for key in ('cpu', 'egl'):
                out.write(key + '=' + json.dumps({'include': data[key]}, separators=(',', ':')) + '\n')
    print(json.dumps(data, indent=2))


if __name__ == '__main__':
    main()
