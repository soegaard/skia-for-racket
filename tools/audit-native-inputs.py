#!/usr/bin/env python3
"""Inspect explicitly acquired inputs. Emit observations, never approve a lock."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import zipfile

from native_packages import (ROOT, TARGETS, inspect_input, json_bytes, sha256,
                             bounded_member, zip_index, MAX_METADATA, need, native_pins)


def observe(inputs):
    versions = native_pins()
    records, components = {}, {}
    for target in TARGETS:
        for kind, version in versions.items():
            package = ('skiasharp' if kind == 'skia' else 'harfbuzzsharp') + '.nativeassets.' + target
            name = f'{package}.{version}.nupkg'
            record = inspect_input(inputs / name, kind, target, version)
            records[name] = record
            with zipfile.ZipFile(inputs / name) as archive:
                notices = bounded_member(archive, zip_index(archive), 'THIRD-PARTY-NOTICES.txt', MAX_METADATA)
            text = notices.decode('utf-8-sig')
            names = re.findall(r'^# ([^#\r\n]+)\r?$', text, re.M)
            for name in names:
                if name.startswith(('END:', 'http')):
                    continue
                components.setdefault(name, []).append(dict(archive=package, notices_sha256=sha256(notices)))
    return dict(schema=1, generation=1, directory='skia-native-1',
                proposed_source_version='0.79', native_package_version='1.0',
                upstream_versions=versions, targets=TARGETS, archives=records,
                notice_components=components,
                review=dict(status='pending',
                            authenticity_basis='HTTPS from NuGet; nuspec repository commit inspected; no independent signature verification',
                            redistribution_approved=False,
                            component_license_mapping_complete=False,
                            transitive_resolution_qualified=False),
                transformations=[],
                qualification=dict(catalog_candidate_validated=False,
                                   linux_natipkg='not-run', linux='not-run',
                                   macos_aarch64='not-run', macos_x86_64='not-run', win32='not-run'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    need(not args.output.exists(), 'refusing to overwrite audit evidence')
    report = observe(args.inputs)
    report['source_commit_observed'] = subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    args.output.write_bytes(json_bytes(report))
    print('Observed six archives; review remains pending:', args.output)


if __name__ == '__main__':
    main()
