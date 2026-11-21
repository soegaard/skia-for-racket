#!/usr/bin/env python3
"""Stage a hash-pinned official Linux pkg-build runtime in a new CI directory."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request
from native_packages import ROOT, need

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version', choices=('8.18', '9.3'), required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    need(not args.output.exists(), 'runtime directory must be new')
    pin = json.loads((ROOT / 'packaging/racket-runtimes.json').read_text())['natipkg'][args.version]
    installer = args.output.with_suffix('.sh')
    need(not installer.exists(), 'installer destination must be new')
    with urllib.request.urlopen(pin['url'], timeout=120) as response, installer.open('xb') as output:
        need(response.geturl().startswith('https://'), 'insecure runtime redirect')
        digest = hashlib.sha256()
        size = 0
        while data := response.read(1024 * 1024):
            size += len(data)
            need(size <= 300 * 1024 * 1024, 'runtime download exceeds limit')
            digest.update(data)
            output.write(data)
    need(digest.hexdigest() == pin['sha256'], 'official runtime digest differs from reviewed pin')
    subprocess.run(['sh', str(installer), '--in-place', '--dest', str(args.output)], check=True)
