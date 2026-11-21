#!/usr/bin/env python3
"""Run the Stage A ordinary/natipkg bootstrap probes inside an offline container.

Requires staged, checksum-verified official Racket 9.3 distributions, the
unmodified NuGet inputs, and the local experimental native ZIPs. This checks
feasibility; it cannot certify a catalog candidate or an earlier glibc baseline.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import zipfile

from native_packages import (need, sha256, json_bytes, read_json, check_locked_input,
                             zip_index, bounded_member, TARGETS)

RUNTIMES = {
    'ordinary': ('racket-minimal-9.3-x86_64-linux-buster-cs.tgz',
                 '8f469b7e93645fc876594470d884775aafff7688f530fd38be873fb44c71ca6a'),
    'natipkg': ('racket-9.3-x86_64-linux-natipkg-buster-pkg-build-cs.sh',
                '2d2daf7afd6656641b13b52663f027e1f9717abc1e2d134fb73bb5df22f0daca'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--archives', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    need(sys.platform.startswith('linux') and os.uname().machine == 'x86_64', 'expected real Linux x86-64 process')
    need(not args.work.exists(), 'work directory must not exist')
    args.work.mkdir(parents=True)
    args.evidence.mkdir(parents=True, exist_ok=True)
    report = dict(schema=1, catalog_candidate_validated=False, status='running',
                  uname=list(os.uname()), commands=[], probes={})
    def save():
        (args.evidence / 'result.json').write_bytes(json_bytes(report))
    def run(command, *, env=None, label=None):
        result = subprocess.run(list(map(str, command)), stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, cwd=args.work, env=env, timeout=600)
        name = f'{len(report["commands"]) + 1:03}-{label or "command"}.log'
        (args.evidence / name).write_bytes(result.stdout)
        report['commands'].append(dict(command=list(map(str, command)), exit_code=result.returncode, log=name))
        save()
        return result
    try:
        report['os_release'] = Path('/etc/os-release').read_text()
        report['network_interfaces'] = {
            name: int((Path('/sys/class/net') / name / 'flags').read_text().strip(), 16)
            for _, name in socket.if_nameindex()}
        # Docker's kernel can expose inactive tunnel devices even in a new
        # network namespace. Require every non-loopback interface to be DOWN,
        # and no IPv4 route. Never infer isolation from failed DNS alone.
        need(all(name == 'lo' or not flags & 1 for name, flags in report['network_interfaces'].items()),
             'execution container has an active external network interface')
        report['ipv4_routes'] = Path('/proc/net/route').read_text()
        need(len(report['ipv4_routes'].splitlines()) == 1, 'execution container has an IPv4 route')
        inventory = run(['dpkg-query', '-W'], label='system-inventory')
        need(inventory.returncode == 0, 'missing system package inventory')
        # Obtain an independent readelf observation before attempting Racket.
        # The receipt names the locked unmodified upstream members.
        receipt = read_json(args.archives / (TARGETS['linux']['package'] + '.receipt.json'))
        inspected = args.work / 'elf-inputs'
        inspected.mkdir()
        for name, record in receipt['upstream_archives'].items():
            need(Path(name).name == name, 'unsafe locked archive name')
            check_locked_input(args.inputs / name, record)
            with zipfile.ZipFile(args.inputs / name) as archive:
                data = bounded_member(archive, zip_index(archive), record['library_member'])
            binary = inspected / record['library_filename']
            binary.write_bytes(data)
            result = run(['readelf', '-d', '-V', '-h', binary], label=record['kind'] + '-upstream-elf')
            need(result.returncode == 0, 'upstream readelf inspection failed')
        for mode, (filename, digest) in RUNTIMES.items():
            source = args.inputs / filename
            need(sha256(source.read_bytes()) == digest, 'Racket distribution checksum differs')
            root = args.work / mode
            root.mkdir()
            runtime = root / 'racket'
            if mode == 'ordinary':
                result = run(['tar', '-xzf', source, '-C', root], label='unpack-ordinary')
            else:
                result = run(['sh', source, '--in-place', '--dest', runtime], label='install-natipkg')
            need(result.returncode == 0, 'Racket distribution installation failed')
            racket = runtime / 'bin/racket'
            home = root / 'home with spaces æ'
            home.mkdir()
            env = {k: v for k, v in os.environ.items() if not k.startswith(('RACKET_', 'PLT', 'LD_', 'DYLD_'))}
            env.update(HOME=str(home), PLTADDONDIR=str(home / 'addon'))
            identity = run([racket, '-e', '(begin (require json setup/dirs) (write-json (hasheq '
                            "'version (version) 'target (path->string (system-library-subpath #f)) "
                            "'library_dirs (map path->string (get-lib-search-dirs)))))"],
                           env=env, label=mode + '-identity')
            need(identity.returncode == 0, 'interpreter identity failed')
            observed = json.loads(identity.stdout)
            need(observed['version'] == '9.3' and observed['target'] == 'x86_64-linux' + ('-natipkg' if mode == 'natipkg' else ''),
                 'wrong interpreter target; setting an environment platform is not qualification')
            result = run([racket, '-l', 'raco', 'pkg', 'install', '--auto', '--batch',
                          args.archives / (TARGETS['linux']['package'] + '.zip')], env=env, label=mode + '-native-install')
            need(result.returncode == 0, 'native package setup failed')
            libdir = run([racket, '-e', '(begin (require setup/dirs) (display (find-user-lib-dir)))'],
                         env=env, label=mode + '-managed-lib-dir')
            pair = Path(libdir.stdout.decode().strip()) / 'skia-native-1'
            original_manifest = (pair / 'manifest.json').read_bytes()
            foreign = run([racket, '-l', 'raco', 'pkg', 'install', '--auto', '--batch',
                           args.archives / (TARGETS['macos']['package'] + '.zip')],
                          env=env, label=mode + '-foreign-target-install')
            need(foreign.returncode == 0 and (pair / 'manifest.json').read_bytes() == original_manifest,
                 'foreign-target package executed or replaced native data')
            foreign_remove = run([racket, '-l', 'raco', 'pkg', 'remove', '--batch', TARGETS['macos']['package']],
                                 env=env, label=mode + '-foreign-target-remove')
            need(foreign_remove.returncode == 0 and (pair / 'manifest.json').read_bytes() == original_manifest,
                 'foreign-target removal damaged matching payload')
            for filename in ('libSkiaSharp.so', 'libHarfBuzzSharp.so'):
                result = run(['readelf', '-d', '-V', '-h', pair / filename], label=mode + '-' + filename + '-elf')
                need(result.returncode == 0, 'readelf inspection failed')
            code = f'''(begin (require ffi/unsafe)
              (define sk (ffi-lib {json.dumps(str(pair / 'libSkiaSharp.so'))}))
              (define hb (ffi-lib {json.dumps(str(pair / 'libHarfBuzzSharp.so'))} #:global? #f))
              (display (list ((get-ffi-obj "sk_version_get_milestone" sk (_fun -> _int)))
                             ((get-ffi-obj "hb_version_string" hb (_fun -> _string/utf-8))))))'''
            direct = run([racket, '-e', code], env=env, label=mode + '-direct-load')
            probe = dict(identity=observed, direct_load_exit=direct.returncode,
                         direct_load_output=direct.stdout.decode('utf-8', 'replace'),
                         installation_passed=True, foreign_target_inert=True,
                         fontconfig_route_qualified=False)
            if mode == 'natipkg':
                # A proposed explicit preload uses Racket's installed fontconfig
                # from the support package. Retain it for the lifetime of Skia.
                preload = '''(require setup/dirs)
                  (define fc-path (for/first ([d (in-list (get-lib-search-dirs))]
                                             #:when (file-exists? (build-path d "libfontconfig.so.1")))
                                    (build-path d "libfontconfig.so.1")))
                  (unless fc-path (error 'probe "no packaged fontconfig"))
                  (define fc (ffi-lib fc-path))'''
                repaired = run([racket, '-e', code.replace('(require ffi/unsafe)', '(require ffi/unsafe) ' + preload)],
                               env=env, label='natipkg-proposed-fontconfig-preload')
                probe.update(proposed_preload_exit=repaired.returncode,
                             proposed_preload_output=repaired.stdout.decode('utf-8', 'replace'))
                run([racket, '-l', 'raco', 'pkg', 'show', '--all'], env=env, label='natipkg-package-inventory')
            report['probes'][mode] = probe
            save()
        report.update(status='observed', full_documentation_qualified=False,
                      rendering_shaping_qualified=False, catalog_candidate_validated=False)
        save()
    except Exception as exc:
        report.update(status='failed', error=str(exc))
        save()
        raise


if __name__ == '__main__':
    main()
