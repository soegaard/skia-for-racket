#!/usr/bin/env python3
"""Validate unpublished catalog packages in disposable runtime/user copies.

Run this process inside a network-denied OS sandbox/container AFTER staging the
catalog. It refuses to certify a run with an available outbound route. Native
bytes and standard dependencies come exclusively from the supplied catalogs.
Never changes the original runtime, real user home, or public catalog.
"""
from __future__ import annotations
import argparse
import errno
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import signal
import struct
import sys
import time
import tempfile
import zipfile
from native_packages import ROOT, need, json_bytes, sha256, write_zip
from catalog_snapshot import inventory
from catalog_execution import (RUNTIME_ENVIRONMENTS, preserved_package_files,
                               racket_command, relocatable_runtime, runtime_profile)


def network_evidence():
    failures = []
    for address in ('1.1.1.1', '8.8.8.8'):
        with socket.socket() as sock:
            sock.settimeout(3)
            try:
                sock.connect((address, 443))
            except OSError as e:
                failures.append(dict(address=address, errno=e.errno, winerror=getattr(e, 'winerror', None), message=str(e)))
            else:
                raise ValueError('outbound connection succeeded; execution must be OS-network-denied')
    need(all(f['errno'] in (errno.EPERM, errno.EACCES, errno.ENETUNREACH, errno.EHOSTUNREACH) or f['winerror'] == 10013 for f in failures),
         'timeouts/refused connections do not establish OS network denial')
    return failures


class Validator:
    def __init__(self, runtime, catalog, directory, *, base_catalog=None, forms=True, drdr=True, wrong_abi=None, owned_stage=None):
        runtime = relocatable_runtime(runtime)
        need(not directory.exists(), 'validation directory must be new')
        directory.mkdir(parents=True)
        self.root = directory.resolve()
        self.runtime = runtime
        self.catalog = catalog.resolve()
        self.base_catalog = base_catalog.resolve() if base_catalog else self.catalog
        self.forms = forms
        self.drdr = drdr
        self.wrong_abi = wrong_abi.resolve() if wrong_abi else None
        self.owned_stage = owned_stage.resolve() if owned_stage else None
        snapshot_verified = False
        if self.owned_stage:
            need(self.catalog == self.owned_stage / 'snapshot/catalog' and
                 (self.owned_stage / 'staging-receipt.json').is_file(), 'owned-stage must be this disposable candidate snapshot')
            staged = json.loads((self.owned_stage / 'staging-receipt.json').read_text())
            need(staged.get('snapshot_candidates_preserved') is True, 'staging did not preserve exact candidate archive bytes')
            need(staged.get('dependency_snapshot') == inventory(self.owned_stage / 'snapshot'),
                 'staged dependency closure/graph differs from acquisition receipt')
            snapshot_verified = True
            for name, identity in staged['snapshot_candidates'].items():
                archive = self.owned_stage / 'snapshot/pkgs' / (name + '.zip')
                need(sha256(archive.read_bytes()) == identity['sha256'] and
                     archive.with_suffix('.zip.CHECKSUM').read_text() == identity['sha1'],
                     'execution candidate archive differs from staging identity')
        self.report = dict(schema=1, status='running', commands=[], checks={},
                           runtime_profile=runtime_profile(self.runtime / 'bin/racket'),
                           catalog_candidate_validated=False, publication_performed=False,
                           runtime_source=str(self.runtime), catalog=str(self.catalog))
        self.report['checks']['staged_dependency_snapshot_verified'] = snapshot_verified
        self.away = Path(tempfile.mkdtemp(prefix='skia catalog outside checkout æ ')).resolve()
        self.report['execution_cwd'] = str(self.away)
        self.save()

    def save(self):
        (self.root / 'result.json').write_bytes(json_bytes(self.report))

    def environment(self, name):
        need(name in RUNTIME_ENVIRONMENTS,
             'unregistered disposable runtime; add its network-denial coverage before use')
        directory = self.root / name
        directory.mkdir()
        runtime = directory / 'Racket runtime'
        shutil.copytree(self.runtime, runtime, symlinks=True)
        home = directory / 'user home with spaces æ'
        home.mkdir()
        env = {k:v for k,v in os.environ.items()
               if not k.startswith(('PLT', 'RACKET_', 'DYLD_', 'LD_'))
               and k not in ('DISPLAY', 'WAYLAND_DISPLAY', 'MIR_SOCKET', 'FC_DEBUG')
               and not k.startswith('FONTCONFIG_')}
        env.update(HOME=str(home), USERPROFILE=str(home), PLTUSERHOME=str(home),
                   PLTADDONDIR=str(home / 'addon'), XDG_CONFIG_HOME=str(home / 'config'),
                   XDG_CACHE_HOME=str(home / 'cache'), PYTHONDONTWRITEBYTECODE='1')
        if sys.platform.startswith('linux'):
            env.update(LANG='C.UTF-8', LC_ALL='C.UTF-8')
        executable = runtime / ('Racket.exe' if os.name == 'nt' else 'bin/racket')
        if not executable.exists() and os.name == 'nt':
            executable = runtime / 'racket.exe'
        need(executable.is_file(), 'expected relocatable Racket runtime')
        if os.name == 'nt':
            system_root = Path(os.environ['SystemRoot'])
            env['PATH'] = os.pathsep.join(map(str, (runtime, runtime / 'lib', system_root / 'System32',
                                                  system_root, system_root / 'System32/Wbem')))
            self.report['windows_clean_path'] = env['PATH']
        return executable, env, directory

    def run(self, environment, *arguments, timeout=900, failure=False, extra_env=None):
        executable, env, _ = environment
        command = [*racket_command(executable), *map(str, arguments)]
        start = time.monotonic()
        number = len(self.report['commands']) + 1
        log = self.root / f'{number:03}.log'
        print(f'[{number:03}] ' + ' '.join(map(str, arguments[:7])), flush=True)
        with log.open('wb') as stream:
            process = subprocess.Popen(command, cwd=self.away, env=dict(env, **(extra_env or {})),
                                       stdout=stream, stderr=subprocess.STDOUT,
                                       start_new_session=os.name != 'nt')
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], stdout=stream, stderr=subprocess.STDOUT)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                code = 'timeout'
        self.report['commands'].append(dict(command=command, log=log.name, exit_code=code,
                                            seconds=round(time.monotonic()-start, 3)))
        self.save()
        need((isinstance(code, int) and code != 0) if failure else code == 0,
             f'unexpected exit {code}; see {log}')
        # Racket writes UTF-8. Windows' default Python 3.12 text encoding can
        # otherwise turn the deliberately non-ASCII disposable path into mojibake.
        return log.read_text(encoding='utf-8', errors='replace').strip()

    def raco(self, env, *args, **kw):
        return self.run(env, '-l', 'raco', *args, **kw)

    def remove_environment(self, environment, *, required=False):
        directory = environment[2]
        for attempt in range(3):
            try:
                shutil.rmtree(directory)
                return
            except FileNotFoundError:
                return
            except OSError as error:
                if attempt == 2:
                    if required: raise
                    # Cloud-folder helpers can recreate metadata while deleting
                    # an otherwise uninstalled disposable standard dependency tree.
                    self.report.setdefault('cleanup_leftovers', []).append(dict(path=str(directory), error=str(error)))
                    self.save()
                    return
                time.sleep(0.2)

    def install(self, environment, catalog):
        self.raco(environment, 'pkg', 'config', '--set', 'catalogs', catalog, self.base_catalog)
        # Intentionally ordinary dependency-driven setup, INCLUDING manuals.
        self.raco(environment, 'pkg', 'install', '--auto', '--batch', 'skia', timeout=3600)

    def smoke(self, environment):
        reports = []
        for order in ((), ('--draw-first',)):
            report = json.loads(self.run(environment, '-l', 'skia/tools/catalog-smoke', '--', *order))
            need(report['status'] == 'passed' and report['source_version'] == '0.79', 'incomplete installed smoke')
            collection = Path(report['collection']).resolve()
            need(collection.is_relative_to(environment[2]), 'collection escaped disposable installation')
            for kind in ('skia', 'harfbuzz'):
                library = report[kind]['loader'] if kind == 'skia' else report[kind]
                need(library['origin'] == 'managed', 'override/system/checkout supplied native smoke')
                path = Path(library['absolute_path']).resolve()
                need(path.is_relative_to(environment[2]), 'library escaped isolated runtime/home: ' + str(path))
                need(path.is_file(), 'reported managed library is absent: ' + str(path))
                need(path.parent == Path(library['managed_directory']).resolve(), 'mixed native pair directories')
                manifest = library['manifest']
                need(library['installed_sha256'] == manifest['files'][kind]['sha256'], 'installed payload bytes differ')
            if report['target'] == 'x86_64-linux-natipkg':
                support = Path(report['skia']['support_library']).resolve()
                need(support.is_relative_to(environment[2]) and support.is_file() and
                     sha256(support.read_bytes()) == report['skia']['support_library_sha256'],
                     'natipkg support escaped the isolated installation or changed bytes')
                configuration = report['skia']['fontconfig']
                need(configuration['origin'] == 'managed-cache', 'natipkg used an external fontconfig override')
                materialized = Path(configuration['materialized_path']).resolve()
                need(materialized.is_relative_to(Path(environment[1]['PLTADDONDIR']) / 'font-cache') and
                     sha256(materialized.read_bytes()) == configuration['materialized_sha256'],
                     'natipkg configuration escaped the derived font cache or changed bytes')
                need(configuration['template_sha256'] == report['skia']['loader']['manifest']['support_configuration']['sha256'] and
                     all(Path(p).resolve().is_relative_to(environment[2]) for p in configuration['font_directories']),
                     'natipkg configuration used undeclared host fonts/template')
            reports.append(report)
        return reports

    def negatives(self, environment, report):
        loader = report['skia']['loader']
        generation = Path(loader['managed_directory'])
        manifest = generation / 'manifest.json'
        original = manifest.read_bytes()
        harfbuzz = Path(report['harfbuzz']['absolute_path'])
        skia = Path(loader['absolute_path'])
        checks = []
        def replace_image(path, data):
            # Replacing a loaded/signed dylib by truncating its old inode can
            # hit macOS's cached code-signature state. Package updates create
            # a fresh file, so the test must do the same after each process exits.
            descriptor, temporary = tempfile.mkstemp(prefix='.native-rejection-', dir=path.parent)
            try:
                with os.fdopen(descriptor, 'wb') as stream:
                    stream.write(data)
                os.chmod(temporary, path.stat().st_mode & 0o777)
                os.replace(temporary, path)
            finally:
                if os.path.exists(temporary): os.unlink(temporary)
        def rejected(label, expected):
            message = self.run(environment, '-e', '(begin (require skia) (skia-check!))', failure=True)
            need(expected in message, 'negative check failed for an unrelated reason: ' + label)
            checks.append(label)
        quarantine = self.root / 'quarantined native member'
        harfbuzz.rename(quarantine)
        try:
            rejected('missing-paired-member', 'selected managed payload')
        finally:
            quarantine.rename(harfbuzz)
        for label, mutate, expected in (
            ('wrong-asset-pair', lambda m: m.update(upstream_versions={'skia':'0.0.0','harfbuzz':'8.3.1.2'}), 'upstream asset pair'),
            ('corrupt-digest', lambda m: m['files']['skia'].update(sha256='0'*64), 'SHA-256 mismatch'),
            ('wrong-generation', lambda m: m.update(generation=2), 'wrong generation'),
            ('wrong-target', lambda m: m.update(target='unqualified'), 'wrong generation')):
            try:
                value = json.loads(original)
                mutate(value)
                manifest.write_bytes(json_bytes(value))
                rejected(label, expected)
            finally:
                manifest.write_bytes(original)
        manifest.rename(quarantine)
        try:
            rejected('missing-manifest', 'manifest.json')
        finally:
            quarantine.rename(manifest)
        if 'support_configuration' in json.loads(original):
            template = generation / 'fontconfig/fonts.conf.in'
            template.rename(quarantine)
            try:
                rejected('missing-support-configuration', 'support configuration template')
            finally:
                quarantine.rename(template)
        # Digest-valid but unloadable selected payload must fail at the explicit
        # managed path, with no attempt to try a host Skia library afterwards.
        native = skia.read_bytes()
        try:
            invalid = b'This is deliberately not a loadable native image.\n'
            replace_image(skia, invalid)
            value = json.loads(original)
            value['files']['skia'].update(size=len(invalid), sha256=sha256(invalid))
            manifest.write_bytes(json_bytes(value))
            rejected('selected-unloadable-image', 'could not load selected managed library')
        finally:
            replace_image(skia, native)
            manifest.write_bytes(original)
        if self.wrong_abi:
            try:
                invalid = self.wrong_abi.read_bytes()
                architecture = bytearray(invalid)
                if invalid.startswith(b'\x7fELF'):
                    architecture[18:20] = struct.pack('<H' if invalid[5] == 1 else '>H', 183)  # AArch64, on Linux x86-64
                elif invalid.startswith(b'MZ'):
                    pe = struct.unpack_from('<I', invalid, 0x3c)[0]
                    architecture[pe + 4:pe + 6] = struct.pack('<H', 0x1c4)  # ARMNT, on Windows AMD64
                elif invalid.startswith(b'\xcf\xfa\xed\xfe'):
                    architecture[4:8] = struct.pack('<I', 0x01000012)  # PowerPC64, on both qualified Macs
                else:
                    raise ValueError('wrong-ABI fixture has an unrecognized native architecture header')
                replace_image(skia, architecture)
                value = json.loads(original)
                value['files']['skia'].update(size=len(architecture), sha256=sha256(architecture))
                manifest.write_bytes(json_bytes(value))
                rejected('selected-wrong-architecture', 'could not load selected managed library')
                replace_image(skia, invalid)
                value = json.loads(original)
                value['files']['skia'].update(size=len(invalid), sha256=sha256(invalid))
                manifest.write_bytes(json_bytes(value))
                rejected('selected-wrong-ABI', 'unsupported native ABI 999.0')
            finally:
                replace_image(skia, native)
                manifest.write_bytes(original)
        support = report['skia']['support_library']
        if support:
            support = Path(support)
            need(support.resolve().is_relative_to(environment[2]), 'refusing to mutate non-disposable support library')
            support.rename(quarantine)
            try:
                rejected('missing-declared-fontconfig', 'declared natipkg support library')
            finally:
                quarantine.rename(support)
        self.report['negative_checks'] = checks
        self.report['checks']['managed_payload_negative_cases'] = bool(self.wrong_abi)
        self.save()

    def native_lifecycle(self, environment, native, smoke):
        package = Path(self.run(environment, '-e', f'(begin (require pkg/lib) (display (pkg-directory "{native}")))'))
        archive_directory = self.root / 'native lifecycle archives'
        archive_directory.mkdir()
        self.raco(environment, 'pkg', 'create', '--from-install', '--source', '--dest', archive_directory, native)
        original = archive_directory / (native + '.zip')
        with zipfile.ZipFile(original) as archive:
            members = {n:archive.read(n) for n in archive.namelist() if not n.endswith('/')}
        members['info.rkt'] = members['info.rkt'].replace(b'(define version "1.0")', b'(define version "1.1")')
        manifest = json.loads(members['skia-native-1/manifest.json'])
        manifest['package_version'] = '1.1'
        members['skia-native-1/manifest.json'] = json_bytes(manifest)
        revision = archive_directory / 'revision'
        revision.mkdir()
        update = revision / original.name
        write_zip(update, members)
        self.raco(environment, 'pkg', 'update', '--batch', '--name', native, update, timeout=1800)
        need(self.smoke(environment)[0]['skia']['loader']['manifest']['package_version'] == '1.1', 'compatible update was not selected')
        self.raco(environment, 'pkg', 'update', '--batch', '--name', native, original, timeout=1800)
        need(self.smoke(environment)[0]['skia']['loader']['manifest']['package_version'] == '1.0', 'explicit rollback was not selected')
        self.report['checks']['compatible_update_and_explicit_rollback'] = True
        scopes = self.environment('scope lifecycle')
        self.raco(scopes, 'pkg', 'config', '--set', 'catalogs', self.catalog, self.base_catalog)
        self.raco(scopes, 'pkg', 'install', '--installation', '--auto', '--batch', original, timeout=1800)
        install_lib = Path(self.run(scopes, '-e', '(begin (require setup/dirs) (display (find-lib-dir)))'))
        need((install_lib / 'skia-native-1/manifest.json').is_file(), 'installation-scope directory absent')
        sentinel = install_lib / 'unrelated catalog lifecycle sentinel.txt'
        sentinel.write_text('retain me\n')
        failure = self.raco(scopes, 'pkg', 'install', '--user', '--auto', '--batch', original, failure=True)
        need('installed in a wider scope' in failure, 'same-name scope rejection had an unrelated cause')
        self.raco(scopes, 'pkg', 'remove', '--installation', '--batch', native, timeout=1800)
        need(not (install_lib / 'skia-native-1').exists() and sentinel.read_text() == 'retain me\n', 'installation removal ownership failed')
        self.raco(scopes, 'pkg', 'install', '--user', '--auto', '--batch', original, timeout=1800)
        user_lib = Path(self.run(scopes, '-e', '(begin (require setup/dirs) (display (find-user-lib-dir)))'))
        need(user_lib != install_lib and (user_lib / 'skia-native-1/manifest.json').is_file(), 'user scope did not isolate its directory')
        self.raco(scopes, 'pkg', 'remove', '--user', '--batch', native, timeout=1800)
        need(not (user_lib / 'skia-native-1').exists() and sentinel.exists(), 'user removal ownership failed')
        self.remove_environment(scopes)
        self.report['checks']['scopes_removal_and_unrelated_sentinel'] = True
        self.save()

    def execute(self):
        if sys.platform.startswith('linux'):
            self.report['execution_uid'] = os.geteuid()
            need(self.report['execution_uid'] > 0,
                 'Linux qualification must run unprivileged so read-only source permissions are enforced')
        self.report['network_denial'] = network_evidence()
        first = self.environment('source installation')
        identity = json.loads(self.run(first, '-e', "(begin (require json) (write-json (hasheq 'version (version) 'target (path->string (system-library-subpath #f)) 'vm (symbol->string (system-type 'vm)) 'bits (system-type 'word) 'compile_target_machine (let ([m (current-compile-target-machine)]) (and m (symbol->string m))))))"))
        need(identity['version'] in ('8.18', '9.3') and identity['vm'] == 'chez-scheme' and identity['bits'] == 64,
             'qualification requires exact released 64-bit CS Racket 8.18 or 9.3')
        self.report['identity'] = identity
        self.install(first, self.catalog)
        self.report['checks']['ordinary_setup_with_documentation'] = True
        self.raco(first, 'setup', '--check-pkg-deps', '--pkgs', 'skia', timeout=3600)
        self.report['checks']['package_dependencies_and_registered_manuals'] = True
        self.qualify_installed(first)

    def foreign_data(self, native):
        # install-platform must suppress foreign-library copying/execution on
        # another target, while binary-lib rebuilding retains its inert data.
        environment = self.environment('foreign target data')
        self.raco(environment, 'pkg', 'config', '--set', 'catalogs', self.catalog, self.base_catalog)
        library = Path(self.run(environment, '-e', '(begin (require setup/dirs) (display (find-user-lib-dir)))'))
        records = []
        for name in ('skia-native-macos-1', 'skia-native-win32-x86_64-1', 'skia-native-x86_64-linux-1'):
            if name == native: continue
            self.raco(environment, 'pkg', 'install', '--auto', '--batch', name, timeout=1800)
            self.raco(environment, 'setup', '--pkgs', name, timeout=1800)
            need(not (library / 'skia-native-1').exists(), 'foreign-target setup copied an active native generation')
            directory = Path(self.run(environment, '-e', f'(begin (require pkg/lib) (display (pkg-directory "{name}")))'))
            artifacts = self.root / 'foreign rebuilt' / name
            artifacts.mkdir(parents=True)
            self.raco(environment, 'pkg', 'create', '--from-install', '--binary-lib', '--dest', artifacts, name)
            with zipfile.ZipFile(artifacts / (name + '.zip')) as archive:
                members = [p for p in directory.rglob('*') if p.is_file() and not p.is_symlink() and
                           p.name != 'info.rkt' and p.suffix not in ('.zo', '.dep')]
                for member in members:
                    need(archive.read(member.relative_to(directory).as_posix()) == member.read_bytes(),
                         'foreign binary-lib stripped/changed payload or notice')
            records.append(dict(package=name, preserved_files=len(members)))
            self.raco(environment, 'pkg', 'remove', '--batch', name, timeout=1800)
            need(not directory.exists() and not (library / 'skia-native-1').exists(), 'foreign package removal left payload')
        self.report['foreign_target_data'] = records
        self.report['checks']['foreign_target_setup_and_binary_preservation'] = True
        self.remove_environment(environment)
        self.save()

    def qualify_installed(self, first):
        self.report['smoke'] = self.smoke(first)
        collection = Path(self.report['smoke'][0]['collection'])
        native = self.report['smoke'][0]['skia']['loader']['manifest']['package']
        self.negatives(first, self.report['smoke'][0])
        self.run(first, '-l', 'skia/tools/ci-import-smoke', extra_env={
            'RACKET_SKIA_LIBRARY':str(self.away / 'missing skia'),
            'RACKET_HARFBUZZ_LIBRARY':str(self.away / 'missing harfbuzz')})
        self.report['checks']['lazy_imports_invalid_overrides'] = True
        self.run(first, '-e', '(begin (require skia) (skia-check!))', failure=True,
                 extra_env={'RACKET_SKIA_LIBRARY':str(self.away / 'missing skia')})
        self.report['checks']['invalid_override_exclusive'] = True
        self.raco(first, 'test', (collection / 'tests/catalog-package-test.rkt'))
        self.report['checks']['bounded_cpu_catalog_tests'] = True
        self.native_lifecycle(first, native, self.report['smoke'][0])
        self.foreign_data(native)
        if self.drdr:
            start = time.monotonic()
            self.raco(first, 'test', '--drdr', '--package', 'skia', timeout=600)
            self.report['drdr_seconds'] = round(time.monotonic()-start, 3)
            self.report['checks']['actual_drdr_traversal_under_600_seconds'] = True
        else:
            self.report['checks']['actual_drdr_traversal_under_600_seconds'] = 'unrun'
        # First native use in a new process with installed source read-only.
        saved = [(p, p.stat().st_mode & 0o777) for p in (collection, *collection.rglob('*')) if not p.is_symlink()]
        generated_fontconfig = Path(first[1]['PLTADDONDIR']) / 'font-cache/skia-native-1'
        if generated_fontconfig.exists():
            shutil.rmtree(generated_fontconfig)
        try:
            for path, mode in saved:
                path.chmod(mode & ~0o222)
            self.report['readonly_smoke'] = self.smoke(first)
        finally:
            for path, mode in saved:
                path.chmod(mode)
        self.report['checks']['readonly_source_first_use'] = True
        self.raco(first, 'skia-examples', 'shaping', self.away / 'copied shaping')
        self.report['checks']['advertised_example_copier'] = True
        self.report['installed_packages'] = self.raco(first, 'pkg', 'show', '--all', '--long')
        if self.forms:
            import importlib.util
            spec = importlib.util.spec_from_file_location('catalog_from_archives', ROOT / 'tools/catalog-from-archives.py')
            maker = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(maker)
            catalogs = {}
            expected = {}
            tutorial_catalog = json.loads((collection / 'scribblings/tutorials/support/catalog.json').read_text())
            example_paths = {'scribblings/' + (name if name.startswith('quick/') else 'tutorials/' + name)
                             for tutorial in tutorial_catalog['tutorials'] for name in tutorial['files']}
            need(all(not Path(name).is_absolute() and '..' not in Path(name).parts for name in example_paths),
                 'unsafe advertised tutorial source path')
            example_hashes = {name:sha256((collection / name).read_bytes()) for name in example_paths}
            original_directories = {}
            metadata_checks = []
            for name in (native, 'skia-fonts-1'):
                directory = Path(self.run(first, '-e', f'(begin (require pkg/lib) (display (pkg-directory "{name}")))'))
                original_directories[name] = directory
                # Payload may be moved in binary forms; at this point it is a source install.
                expected[name] = preserved_package_files(directory)
            for form in ('source', 'built', 'binary-lib'):
                artifacts = self.root / 'rebuilt' / form
                artifacts.mkdir(parents=True)
                for package in ('skia', native, 'skia-fonts-1'):
                    self.raco(first, 'pkg', 'create', '--from-install', '--' + form, '--dest', artifacts, package)
                for name, members in expected.items():
                    with zipfile.ZipFile(artifacts / (name + '.zip')) as archive:
                        for member, digest in members.items():
                            need(sha256(archive.read(member)) == digest, form + ' dropped/changed notice or payload: ' + member)
                with zipfile.ZipFile(artifacts / 'skia.zip') as archive:
                    for name, digest in example_hashes.items():
                        need(name in archive.namelist() and sha256(archive.read(name)) == digest,
                             form + ' stripped/changed advertised editable example: ' + name)
                # Raco CHECKSUM files deliberately have no newline; enforce that here too.
                catalogs[form] = maker.create(first[0], artifacts, self.root / ('catalog-' + form))
                for name, original in original_directories.items():
                    metadata_checks.append(dict(original=str(original),
                                                rebuilt=str(catalogs[form].parent / 'metadata' / name), form=form))
            request = self.root / 'rebuilt-metadata-checks.json'
            request.write_bytes(json_bytes(metadata_checks))
            self.report['rebuilt_metadata'] = json.loads(self.run(first, ROOT / 'tools/check-rebuilt-native-info.rkt', request))
            self.report['checks']['rebuilt_native_metadata_semantics'] = True
            self.report['checks']['advertised_example_sources_preserved'] = True
            self.report['retained_example_source_files'] = len(example_hashes)
            self.raco(first, 'pkg', 'remove', '--batch', 'skia', native, 'skia-fonts-1', timeout=1800)
            managed = Path(self.report['smoke'][0]['skia']['loader']['managed_directory'])
            need(not managed.exists(), 'native removal left its generation directory')
            standard = self.root / 'standard-only-catalog'
            self.run(first, ROOT / 'tools/standard-only-catalog.rkt', self.base_catalog, standard)
            self.base_catalog = standard
            self.remove_environment(first, required=True)
            if self.owned_stage:
                removed = []
                for directory in (self.owned_stage / 'artifacts', self.owned_stage / 'snapshot/pkgs'):
                    for path in directory.glob('skia*.zip*'):
                        need(path.is_file() and not path.is_symlink(), 'unsafe original candidate archive')
                        removed.append(str(path))
                        path.unlink()
                inputs = self.owned_stage / 'inputs'
                if inputs.exists():
                    shutil.rmtree(inputs)
                self.report['original_candidate_inputs_removed'] = removed
                self.report['checks']['original_environment_and_candidate_archives_removed'] = True
            for form, catalog in catalogs.items():
                current = self.environment('reinstalled ' + form)
                self.install(current, catalog)
                self.report.setdefault('rebuilt_smoke', {})[form] = self.smoke(current)
                self.raco(current, 'skia-examples', 'shaping', self.away / ('copied ' + form))
                self.raco(current, 'pkg', 'remove', '--batch', 'skia', native, 'skia-fonts-1', timeout=1800)
                smoke = self.report['rebuilt_smoke'][form][0]
                need(not Path(smoke['skia']['loader']['managed_directory']).exists()
                     and not Path(smoke['collection']).exists(), 'rebuilt removal left native/source payload')
                self.remove_environment(current)
            self.report['checks']['source_built_binary_lib_roundtrips_and_removal'] = True
        self.report.update(status='passed-local-selected-checks', catalog_candidate_validated=False,
                           external_platform_qualification_complete=False)
        self.save()
        shutil.rmtree(self.away)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime', type=Path, required=True)
    p.add_argument('--catalog', type=Path, required=True)
    p.add_argument('--base-catalog', type=Path)
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--no-forms', action='store_true', help='partial diagnostic run; never full qualification')
    p.add_argument('--no-drdr', action='store_true', help='partial diagnostic run; never full qualification')
    p.add_argument('--wrong-abi', type=Path, help='locally compiled incompatible scalar ABI fixture, never a distribution input')
    p.add_argument('--owned-stage', type=Path, help='disposable stage owned by this run; remove original candidate archives before rebuilt installs')
    args = p.parse_args()
    validator = Validator(args.runtime, args.catalog, args.work, base_catalog=args.base_catalog,
                          forms=not args.no_forms, drdr=not args.no_drdr, wrong_abi=args.wrong_abi, owned_stage=args.owned_stage)
    try:
        validator.execute()
    except Exception as error:
        validator.report.update(status='failed', error=str(error))
        validator.save()
        raise
