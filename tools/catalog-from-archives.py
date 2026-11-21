#!/usr/bin/env python3
"""Index local candidate/rebuilt archives; never contact a public catalog."""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import subprocess
import zipfile
from native_packages import ROOT, need, zip_index, bounded_member, json_bytes


def create(racket, artifacts, output):
    need(not output.exists(), 'catalog output must be new')
    output.mkdir(parents=True)
    rows = []
    for archive in sorted(artifacts.glob('*.zip')):
        name = archive.stem
        metadata = output / 'metadata' / name
        metadata.mkdir(parents=True)
        with zipfile.ZipFile(archive) as z:
            # Built source packages include bytecode and generated manuals.
            # Native input archives retain their separate 2048-entry bound.
            index = zip_index(z, max_entries=8192)
            (metadata / 'info.rkt').write_bytes(bounded_member(z, index, 'info.rkt', 1024 * 1024))
        checksum = hashlib.sha1(archive.read_bytes()).hexdigest()
        need(archive.with_suffix('.zip.CHECKSUM').read_text() == checksum, 'wrong Racket archive checksum')
        rows.append(dict(name=name, archive=str(archive.resolve()), metadata_directory=str(metadata.resolve()), sha1=checksum))
    need(rows, 'no candidate archives')
    request = output / 'request.json'
    request.write_bytes(json_bytes(rows))
    subprocess.run([str(racket), str(ROOT / 'tools/write-staging-catalog.rkt'), str(request), str(output / 'catalog')], check=True)
    return output / 'catalog'


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--racket', required=True)
    p.add_argument('--artifacts', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    create(args.racket, args.artifacts, args.output)
