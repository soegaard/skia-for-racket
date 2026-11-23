#!/usr/bin/env python3
"""Acquire/check already locked inputs; never generate or accept new lock hashes.

This preparation tool is separate from the network-free builder. A local input
directory works without network. Pending-review observations can be checked for
local experiments but cannot authorize publication.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import tempfile
import urllib.request

from repository_layout import documentation_root
from native_packages import (ROOT, MAX_ARCHIVE, need, read_json, validate_observations,
                             check_locked_input, json_bytes, sha256,
                             validate_distribution_lock, check_font_input, MAX_FONT)


class HTTPSOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        need(newurl.startswith('https://'), 'refusing insecure input redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def prepare(lock_path, cache, *, source=None, font_source=None):
    lock = read_json(lock_path)
    (validate_distribution_lock if 'documentation_fonts' in lock else validate_observations)(lock)
    need(not cache.exists(), 'cache must be a new directory')
    cache.parent.mkdir(parents=True, exist_ok=True)
    # Entire acquisition validates before a verified cache becomes visible.
    with tempfile.TemporaryDirectory(prefix='.prepare-native-', dir=cache.parent) as tmp:
        staging = Path(tmp) / 'verified'
        staging.mkdir()
        for name, record in sorted(lock['archives'].items()):
            destination = staging / name
            if source is not None:
                path = source / name
                check_locked_input(path, record)
                destination.write_bytes(path.read_bytes())
            else:
                opener = urllib.request.build_opener(HTTPSOnly())
                with opener.open(record['url'], timeout=120) as response, destination.open('xb') as output:
                    need(response.geturl().startswith('https://'), 'insecure final input URL')
                    size = 0
                    while chunk := response.read(1024 * 1024):
                        size += len(chunk)
                        need(size <= min(MAX_ARCHIVE, record['size']), 'native input exceeds locked size')
                        output.write(chunk)
                check_locked_input(destination, record)
        for record in lock.get('documentation_fonts', {}).get('files', []):
            name = record['filename']
            destination = staging / name
            # These source assets belong to skia-doc. Candidate preparation
            # checks/copies the committed files; it never reacquires fonts.
            path = (font_source or documentation_root(ROOT) / 'fonts') / name
            destination.write_bytes(check_font_input(path, record))
        (staging / 'verified-inputs.json').write_bytes(json_bytes(dict(
            schema=1, lock_sha256=sha256(lock_path.read_bytes()),
            archives={n: r['sha256'] for n, r in lock['archives'].items()},
            redistribution_approved=False, catalog_candidate_validated=False)))
        staging.rename(cache)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lock', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--from-directory', type=Path)
    parser.add_argument('--font-directory', type=Path)
    args = parser.parse_args()
    prepare(args.lock, args.cache, source=args.from_directory, font_source=args.font_directory)


if __name__ == '__main__':
    main()
