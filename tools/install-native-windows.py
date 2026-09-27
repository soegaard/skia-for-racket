#!/usr/bin/env python3
"""Install pinned Windows x64 Skia/HarfBuzz assets without executing their code.

Network authenticity relies on HTTPS/NuGet, as in the existing Unix installers.
Recorded SHA-256 values are provenance, not independent authenticity proof.
An optional expected SHA-256 can authenticate a separately obtained archive.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import urllib.request
import zipfile
import xml.etree.ElementTree as ET

PACKAGES = {
    'skia': ('skiasharp.nativeassets.win32', '3.119.1', 'libSkiaSharp.dll'),
    'harfbuzz': ('harfbuzzsharp.nativeassets.win32', '8.3.1.2', 'libHarfBuzzSharp.dll'),
}
MAX_ARCHIVE = 180 * 1024 * 1024
MAX_DLL = 100 * 1024 * 1024

def validate_archive(data: bytes, kind: str, expected_sha256: str | None = None) -> tuple[bytes, bytes, dict]:
    package, version, filename = PACKAGES[kind]
    digest = hashlib.sha256(data).hexdigest()
    if len(data) > MAX_ARCHIVE:
        raise ValueError('native archive exceeds size limit')
    if expected_sha256 is not None and digest.lower() != expected_sha256.lower():
        raise ValueError('archive SHA-256 does not match supplied expectation')
    member = f'runtimes/win-x64/native/{filename}'
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('duplicate archive entries')
        specs = [n for n in names if n.lower().endswith('.nuspec') and '/' not in n]
        if len(specs) != 1:
            raise ValueError('expected exactly one root NuGet manifest')
        if archive.getinfo(specs[0]).file_size > 1024 * 1024:
            raise ValueError('oversized NuGet manifest')
        manifest = archive.read(specs[0])
        if b'<!DOCTYPE' in manifest.upper() or b'<!ENTITY' in manifest.upper():
            raise ValueError('DTD/entity declarations are not accepted')
        root = ET.fromstring(manifest)
        values = {}
        for node in root.iter():
            name = node.tag.rsplit('}', 1)[-1]
            if name in ('id', 'version'):
                if name in values:
                    raise ValueError(f'duplicate {name} in NuGet manifest')
                values[name] = (node.text or '').strip()
        if values.get('id', '').lower() != package or values.get('version') != version:
            raise ValueError(f'expected {package} {version}, got {values}')
        try:
            info = archive.getinfo(member)
        except KeyError as exc:
            raise ValueError(f'missing native member {member}') from exc
        if not 0 < info.file_size <= MAX_DLL:
            raise ValueError('invalid native DLL size')
        dll = archive.read(info)  # zipfile checks this member's CRC; never extractall.
    if len(dll) < 64 or dll[:2] != b'MZ':
        raise ValueError('native member is not a PE DLL')
    offset = struct.unpack_from('<I', dll, 0x3c)[0]
    if offset > len(dll) - 24 or dll[offset:offset+4] != b'PE\0\0':
        raise ValueError('invalid PE header offset/signature')
    if struct.unpack_from('<H', dll, offset+4)[0] != 0x8664:
        raise ValueError('native DLL is not Windows AMD64/x64')
    if not struct.unpack_from('<H', dll, offset+22)[0] & 0x2000:
        raise ValueError('PE image is not marked as a DLL')
    return dll, manifest, {'package': package, 'version': version, 'rid': 'win-x64',
                          'member': member, 'archive_sha256': digest,
                          'dll_sha256': hashlib.sha256(dll).hexdigest(),
                          'independent_hash_checked': expected_sha256 is not None}

def read_source(kind: str, archive: Path | None) -> tuple[bytes, str]:
    if archive is not None:
        if archive.stat().st_size > MAX_ARCHIVE:
            raise ValueError('native archive exceeds size limit')
        return archive.read_bytes(), str(archive.resolve())
    package, version, _ = PACKAGES[kind]
    url = f'https://api.nuget.org/v3-flatcontainer/{package}/{version}/{package}.{version}.nupkg'
    with urllib.request.urlopen(url, timeout=120) as response:
        if not response.geturl().startswith('https://'):
            raise ValueError('refusing an insecure package redirect')
        data = response.read(MAX_ARCHIVE + 1)
    if len(data) > MAX_ARCHIVE:
        raise ValueError('download exceeds archive size limit')
    return data, url

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket', default=os.environ.get('RACKET', 'racket'))
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--library', choices=['both', *PACKAGES], default='both')
    for kind in PACKAGES:
        parser.add_argument(f'--{kind}-archive', type=Path)
        parser.add_argument(f'--{kind}-sha256')
    args = parser.parse_args()
    # Select the interpreter's architecture, not Python's or the host shell's.
    platform = subprocess.check_output(
        [args.racket, '-e', '(printf "~a/~a" (system-type (quote os)) (system-type (quote arch)))'], text=True).strip()
    if platform != 'windows/x86_64':
        raise SystemExit(f'Windows installer requires Windows x64 Racket; selected {platform}')
    native = args.root / 'native'
    native.mkdir(parents=True, exist_ok=True)
    selected = list(PACKAGES) if args.library == 'both' else [args.library]
    # Download/validate every requested package before touching installed DLLs.
    prepared = []
    for kind in selected:
        data, source = read_source(kind, getattr(args, kind + '_archive'))
        dll, manifest, record = validate_archive(data, kind, getattr(args, kind + '_sha256'))
        record['source'] = source
        prepared.append((kind, data, dll, manifest, record))
    destination = native / 'win-x64'
    destination.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.windows-install-', dir=native) as tmp:
        staging = Path(tmp)
        for kind, data, dll, manifest, record in prepared:
            filename = PACKAGES[kind][2]
            files = {filename: dll, kind + '.nupkg': data, kind + '.nuspec': manifest,
                     kind + '.source.json': (json.dumps(record, indent=2) + '\n').encode()}
            for name, content in files.items():
                (staging / name).write_bytes(content)
            # Each replacement is atomic, not a transaction across packages.
            # Stop applications first: Windows refuses replacement of loaded DLLs.
            for name in files:
                os.replace(staging / name, destination / name)
            print(f'Installed {destination / filename}')
    print('Next: selected Racket tools/doctor.rkt, then tools/validate-gpu.ps1')
    print('Loader errors 126/193 can indicate dependent DLLs or an architecture mismatch; see docs/GPU-TESTING.md.')

if __name__ == '__main__':
    main()
