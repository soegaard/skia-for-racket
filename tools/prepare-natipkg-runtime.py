#!/usr/bin/env python3
"""Stage a hash-pinned official Linux pkg-build runtime in a new CI directory."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import urllib.error
import urllib.request
from native_packages import ROOT, need, read_json, json_bytes

MAX_INSTALLER = 300 * 1024 * 1024


class HTTPSOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        need(newurl.startswith('https://'), 'refusing insecure runtime redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def acquire(pin, installer, report):
    """Try only locked official URLs; every accepted byte uses the same digest."""
    mirrors = pin.get('mirrors', [])
    need(type(mirrors) is list and len(mirrors) <= 2, 'invalid runtime mirror set')
    urls = [pin['url'], *mirrors]
    need(all(type(url) is str and url.startswith('https://') for url in urls),
         'runtime URLs must use HTTPS')
    need(not installer.exists(), 'installer destination must be new')
    report.update(expected_sha256=pin['sha256'], attempts=[])
    opener = urllib.request.build_opener(HTTPSOnly())
    for url in urls:
        attempt = dict(url=url)
        report['attempts'].append(attempt)
        try:
            with opener.open(url, timeout=120) as response, installer.open('xb') as output:
                need(response.geturl().startswith('https://'), 'insecure final runtime URL')
                digest = hashlib.sha256()
                size = 0
                while data := response.read(1024 * 1024):
                    size += len(data)
                    need(size <= MAX_INSTALLER, 'runtime download exceeds limit')
                    digest.update(data)
                    output.write(data)
                attempt.update(final_url=response.geturl(), size=size, sha256=digest.hexdigest())
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as error:
            # Transport failures may try the next reviewed mirror. Changed or
            # oversized bytes fail immediately instead of being hidden by retry.
            attempt.update(status='transport-failed', error=str(error))
            installer.unlink(missing_ok=True)
            continue
        need(attempt['sha256'] == pin['sha256'], 'official runtime digest differs from reviewed pin')
        attempt['status'] = 'verified'
        report.update(status='download-verified', selected_url=attempt['final_url'],
                      sha256=attempt['sha256'], size=attempt['size'])
        return
    raise ValueError('all locked official runtime URLs failed: ' +
                     '; '.join(a['url'] + ': ' + a['error'] for a in report['attempts']))


def prepare(version, directory, *, lock_path=ROOT / 'packaging/racket-runtimes.json'):
    need(not directory.exists(), 'runtime directory must be new')
    installer = directory.with_suffix('.sh')
    receipt = directory.with_suffix('.acquisition.json')
    need(not installer.exists() and not receipt.exists(), 'runtime preparation destinations must be new')
    pin = read_json(lock_path)['natipkg'][version]
    directory.parent.mkdir(parents=True, exist_ok=True)
    report = dict(schema=1, version=version, status='preparing', runtime=str(directory.resolve()),
                  catalog_candidate_validated=False)
    receipt.write_bytes(json_bytes(report))
    try:
        acquire(pin, installer, report)
        subprocess.run(['sh', str(installer), '--in-place', '--dest', str(directory)], check=True)
        report['status'] = 'installed'
    except Exception as error:
        report.update(status='failed', error=str(error))
        raise
    finally:
        receipt.write_bytes(json_bytes(report))
    return report

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version', choices=('8.18', '9.3'), required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    report = prepare(args.version, args.output)
    print('Installed exact pinned pkg-build runtime from ' + report['selected_url'])
