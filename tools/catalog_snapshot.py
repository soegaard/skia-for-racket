"""Bounded, offline identities for a Racket catalog's complete staged closure."""
from __future__ import annotations
import hashlib
from pathlib import Path
import re
import ssl
import subprocess
import sys
import time
from native_packages import ROOT, need, json_bytes

STAGING_ATTEMPTS = 3
STAGING_TIMEOUT = 15 * 60
STAGING_RETRY_DELAY = 2
MAX_TRUST_BUNDLE = 16 * 1024 * 1024


def catalog_digest(directory: Path):
    """Bind every metadata file, without SQLite's updates on read connections."""
    need(directory.is_dir() and not directory.is_symlink() and (directory / 'pkgs-all').is_file(),
         'missing/unsafe frozen dependency catalog')
    rows, total = [], 0
    for path in sorted(directory.rglob('*')):
        need(not path.is_symlink(), 'symlink in frozen dependency catalog')
        if path.is_dir():
            continue
        size = path.stat().st_size
        total += size
        need(path.is_file() and size <= 16 * 1024 * 1024 and total <= 64 * 1024 * 1024 and len(rows) < 8192,
             'oversized/unsafe frozen dependency catalog')
        rows.append(dict(path=path.relative_to(directory).as_posix(), size=size,
                         sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    return hashlib.sha256(json_bytes(rows)).hexdigest()


def export_trusted_roots(destination: Path):
    """Use Python's verified roots, avoiding Racket's failing Windows store reader."""
    context = ssl.create_default_context()
    roots = sorted(set(context.get_ca_certs(binary_form=True)))
    need(0 < len(roots) <= 4096 and all(type(root) is bytes and 0 < len(root) <= 65536 for root in roots),
         'missing/oversized trusted certificate roots')
    data = ''.join(ssl.DER_cert_to_PEM_cert(root) for root in roots).encode('ascii')
    need(len(data) <= MAX_TRUST_BUNDLE, 'trusted certificate bundle exceeds size bound')
    with destination.open('xb') as stream:
        stream.write(data)
    return dict(source='python-default-verified-roots', certificates=len(roots), size=len(data),
                sha256=hashlib.sha256(data).hexdigest())


def stage_dependencies(prefix, output: Path, identity, candidate_catalog, base_catalog, environment):
    """Freeze catalog metadata once, then resume only checksum-verified packages.

    A retry never adopts a new catalog checksum. Racket removes a failed download
    from its cache; --state reuses only already successful, checksum-checked ZIPs.
    The addon/cache and optional PEM bundle belong to this disposable staging tree.
    """
    need('PLT_PKG_SSL_NO_VERIFY' not in environment and 'GIT_SSL_NO_VERIFY' not in environment,
         'dependency staging requires HTTPS certificate verification')
    work = output / 'dependency-staging'
    work.mkdir()
    child_environment = dict(environment, PLTADDONDIR=str(work / 'addon'), PLTUSERHOME=str(work / 'user'))
    receipt_path = output / 'dependency-staging.json'
    log_path = output / 'dependency-staging.log'
    report = dict(schema=1, status='failed', attempts=[], max_attempts_per_phase=STAGING_ATTEMPTS,
                  timeout_seconds_per_attempt=STAGING_TIMEOUT, certificate_verification=True,
                  trust=dict(source='racket-platform-defaults'), publication_performed=False)
    try:
        roots_argument = '-'
        if sys.platform == 'win32':
            roots = work / 'trusted-roots.pem'
            report['trust'] = export_trusted_roots(roots)
            roots_argument = str(roots)
        raco = [*prefix, str(ROOT / 'tools/catalog-raco.rkt'), str(work / 'downloads'), roots_argument]

        # Racket can update a SQLite catalog even through a read connection.
        # A directory catalog stays byte-stable across actual archive attempts.
        frozen = work / 'source-catalog'

        def run(phase, command):
            for attempt in range(1, STAGING_ATTEMPTS + 1):
                if phase == 'archives':
                    need(catalog_digest(frozen) == report['source_catalog_sha256'],
                         'frozen dependency catalog changed between attempts')
                row = dict(phase=phase, attempt=attempt, command=command)
                report['attempts'].append(row)
                print(f'Dependency staging: {phase}, attempt {attempt}/{STAGING_ATTEMPTS}', flush=True)
                with log_path.open('ab') as log:
                    log.write(f'\n=== {phase}: attempt {attempt}/{STAGING_ATTEMPTS} ===\n'.encode('ascii'))
                    log.flush()
                    try:
                        subprocess.run(command, env=child_environment, stdout=log, stderr=subprocess.STDOUT,
                                       check=True, timeout=STAGING_TIMEOUT)
                    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                        row.update(exit_code=getattr(error, 'returncode', None),
                                   timed_out=isinstance(error, subprocess.TimeoutExpired))
                        if attempt == STAGING_ATTEMPTS:
                            raise
                    else:
                        row['exit_code'] = 0
                        return
                time.sleep(STAGING_RETRY_DELAY)

        # Retrying acquisition may replace an incomplete metadata file. After
        # success, only this frozen catalog is used by every archive attempt.
        run('catalog', [*raco, 'pkg', 'catalog-copy', '--version', identity['version'], '--force',
                        str(candidate_catalog), str(base_catalog), str(frozen)])
        report['source_catalog_sha256'] = catalog_digest(frozen)
        command = [*raco, 'pkg', 'catalog-archive', '--fast-file-copy', '--state', str(work / 'state.sqlite'),
                   '--include', 'skia', '--include-deps', '--include-deps-platform',
                   identity['os'], identity['target'], '--relative', '--version', identity['version'],
                   str(output / 'snapshot'), str(frozen)]
        run('archives', command)
        need(catalog_digest(frozen) == report['source_catalog_sha256'],
             'frozen dependency catalog changed during staging')
        report['status'] = 'passed'
        return report
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        receipt_path.write_bytes(json_bytes(report))


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
