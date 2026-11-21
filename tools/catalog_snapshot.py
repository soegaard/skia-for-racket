"""Bounded, offline identities for a Racket catalog's complete staged closure."""
from __future__ import annotations
import hashlib
from pathlib import Path
import re
from native_packages import need


def inventory(snapshot: Path):
    catalog = snapshot / 'catalog/pkgs-all'
    need(catalog.is_file() and not catalog.is_symlink() and catalog.stat().st_size <= 16 * 1024 * 1024,
         'missing/oversized staged dependency graph')
    datum = catalog.read_bytes()
    archives = sorted((snapshot / 'pkgs').glob('*.zip'))
    need(0 < len(archives) <= 1024, 'staged dependency package count exceeds bound')
    packages = []
    total = 0
    for archive in archives:
        need(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9+_.-]*', archive.stem) is not None and
             archive.is_file() and not archive.is_symlink() and archive.stat().st_size <= 256 * 1024 * 1024,
             'unsafe/oversized staged dependency archive')
        total += archive.stat().st_size
        need(total <= 2 * 1024 * 1024 * 1024, 'staged dependency closure exceeds size bound')
        sha1, sha256 = hashlib.sha1(), hashlib.sha256()
        with archive.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                sha1.update(chunk)
                sha256.update(chunk)
        checksum = archive.with_suffix('.zip.CHECKSUM')
        need(checksum.is_file() and not checksum.is_symlink() and checksum.stat().st_size == 40 and
             checksum.read_bytes() == sha1.hexdigest().encode('ascii'), 'staged dependency checksum differs')
        packages.append(dict(package=archive.stem, size=archive.stat().st_size,
                             sha1=sha1.hexdigest(), sha256=sha256.hexdigest()))
    return dict(schema=1, packages=packages, bytes=total,
                catalog_racket_datum=datum.decode('utf-8'), catalog_sha256=hashlib.sha256(datum).hexdigest())
