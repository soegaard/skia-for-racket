#!/usr/bin/env python3
"""Source manifest maintenance; CI checks it without rewriting it.

Default: update, only from a Git checkout. --check (or
SKIA_SOURCE_SUMS_MODE=check) verifies an existing manifest. --manifest-only is
for installed source copies without Git metadata: every listed byte is checked,
but no claim of an independent Git inventory is made in that mode.
"""
from __future__ import annotations
import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NAME = 'SOURCE-SHA256SUMS.txt'


def safe_path(root: Path, name: str) -> Path:
    path = PurePosixPath(name)
    if (not name or path.is_absolute() or '\\' in name or ':' in name or
            any(p in ('', '.', '..') for p in name.split('/')) or
            any(ord(c) < 32 for c in name)):
        raise ValueError(f'unsafe manifest path: {name!r}')
    result = root.joinpath(*path.parts)
    # Check only in-root ancestors; macOS's system /tmp alias is harmless.
    cursor = result
    while cursor != root:
        if cursor.is_symlink():
            raise ValueError(f'symlink in source path: {name}')
        cursor = cursor.parent
    if not result.resolve().is_relative_to(root.resolve()):
        raise ValueError(f'path escapes source root: {name}')
    return result


def read_manifest(root: Path) -> dict[str, str]:
    rows = {}
    for line in (root / NAME).read_text(encoding='utf-8').splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        if not match:
            raise ValueError('malformed source manifest line')
        digest, name = match.groups()
        safe_path(root, name)
        if name == NAME or name in rows:
            raise ValueError(f'duplicate/self-referential source path: {name}')
        rows[name] = digest
    if not rows:
        raise ValueError('empty source manifest')
    return rows


def git_paths(root: Path) -> list[str]:
    top = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], cwd=root, text=True).strip()
    if Path(top).resolve() != root.resolve():
        raise ValueError('source root must be the Git checkout root')
    raw = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root)
    paths = set()
    for name in raw.decode('utf-8').split('\0'):
        if name and name != NAME:
            path = safe_path(root, name)
            if path.is_file():
                paths.add(name)
            elif not path.exists():
                # A deleted tracked path must be staged with git add -u before
                # publishing a new source manifest; never silently omit it.
                raise ValueError(f'Git-listed source file is missing: {name}')
            else:
                raise ValueError(f'Git-listed path is not a regular file: {name}')
    return sorted(paths)


def check(root: Path, *, manifest_only: bool = False) -> int:
    expected = read_manifest(root)
    if not manifest_only:
        actual = set(git_paths(root))
        if actual != set(expected):
            raise ValueError('source manifest inventory differs: missing=' +
                             repr(sorted(actual - set(expected))) + ' extra=' +
                             repr(sorted(set(expected) - actual)))
    for name, digest in expected.items():
        path = safe_path(root, name)
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f'source checksum mismatch: {name}')
    return len(expected)


def update(root: Path) -> int:
    paths = git_paths(root)
    text = ''.join(hashlib.sha256(safe_path(root, p).read_bytes()).hexdigest() + '  ' + p + '\n'
                   for p in paths)
    fd, temporary = tempfile.mkstemp(prefix='.source-sums-', dir=root)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as out:
            out.write(text)
        os.replace(temporary, root / NAME)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return len(paths)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--manifest-only', action='store_true',
                        default=os.environ.get('SKIA_SOURCE_SUMS_MANIFEST_ONLY') == '1')
    args = parser.parse_args(argv)
    if os.environ.get('SKIA_SOURCE_SUMS_MANIFEST_ONLY', '0') not in ('0', '1'):
        parser.error('SKIA_SOURCE_SUMS_MANIFEST_ONLY must be 0 or 1')
    mode = os.environ.get('SKIA_SOURCE_SUMS_MODE', 'update')
    if mode not in ('check', 'update'):
        parser.error('SKIA_SOURCE_SUMS_MODE must be check or update')
    checking = args.check or mode == 'check'
    if args.manifest_only and not checking:
        parser.error('--manifest-only requires --check')
    try:
        n = check(ROOT, manifest_only=args.manifest_only) if checking else update(ROOT)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f'Source manifest FAILED: {exc}')
        return 1
    print(f'{"Verified" if checking else "Wrote"} {NAME} ({n} files' +
          ('; manifest-only, no Git inventory' if args.manifest_only else '') + ')')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
