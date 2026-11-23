#!/usr/bin/env python3
"""Stage A directory lifecycle probe in copies of a relocatable Racket runtime.

Does not alter the selected runtime, the ordinary user package installation,
or catalog configuration. It is a native-directory feasibility probe, not full
rendering, documentation, Linux ABI, or catalog qualification.
"""
from __future__ import annotations
from repository_layout import source_path, library_root, documentation_root

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import zipfile

from native_packages import json_bytes, need, sha256, zip_index, write_zip

class Probe:
    def __init__(self, runtime, archive, directory, *, preload_fontconfig=False, source_root=None):
        need((runtime / 'bin/racket').is_file(), 'expected relocatable runtime root with bin/racket')
        need(not directory.exists(), 'evidence directory must not exist')
        directory.mkdir(parents=True)
        self.directory = directory.resolve()
        self.runtime_source = runtime.resolve()
        self.archive = archive.resolve()
        self.preload_fontconfig = preload_fontconfig
        self.source_root = source_root.resolve() if source_root else None
        self.report = dict(schema=1, status='running', catalog_candidate_validated=False,
                           runtime_source=str(self.runtime_source), commands=[], checks=[])
        with zipfile.ZipFile(self.archive) as z:
            index = zip_index(z)
            self.expected = {n: sha256(z.read(n)) for n in index
                             if n.startswith(('skia-native-1/', 'licenses/'))}
            self.manifest = json.loads(z.read('skia-native-1/manifest.json'))
        self.package = self.manifest['package']

    def environment(self, name, *, runtime=None):
        root = self.directory / name
        root.mkdir()
        runtime = runtime or root / 'runtime'
        if not runtime.exists():
            shutil.copytree(self.runtime_source, runtime, symlinks=True)
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(('PLT', 'RACKET_', 'DYLD_', 'LD_'))
               and k not in ('DISPLAY', 'WAYLAND_DISPLAY')}
        home = root / 'home with spaces æ'
        home.mkdir()
        env.update(HOME=str(home), PLTADDONDIR=str(home / 'addon'),
                   PYTHONDONTWRITEBYTECODE='1')
        return runtime / 'bin/racket', env, root

    def run(self, environment, *args, expected=0):
        racket, env, _ = environment
        command = [str(racket), *map(str, args)]
        start = time.monotonic()
        result = subprocess.run(command, env=env, cwd=self.directory,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
        number = len(self.report['commands']) + 1
        log = f'{number:03}.log'
        (self.directory / log).write_bytes(result.stdout)
        self.report['commands'].append(dict(command=command, log=log, exit_code=result.returncode,
                                            seconds=round(time.monotonic() - start, 3)))
        self.save()
        need((result.returncode == 0) if expected == 0 else (result.returncode != 0),
             f'unexpected exit {result.returncode}; see {self.directory / log}')
        return result.stdout.decode('utf-8', 'replace').strip()

    def raco(self, environment, *args, **kw):
        return self.run(environment, '-l', 'raco', *args, **kw)

    def save(self):
        (self.directory / 'result.json').write_bytes(json_bytes(self.report))

    def lib(self, environment, scope='user'):
        expr = ('(begin (require setup/dirs) (display (find-user-lib-dir)))' if scope == 'user'
                else '(begin (require setup/dirs) (display (find-lib-dir)))')
        return Path(self.run(environment, '-e', expr))

    def payload(self, environment, scope='user'):
        path = self.lib(environment, scope) / 'skia-native-1'
        for name, digest in self.expected.items():
            if name.startswith('skia-native-1/'):
                item = path / name.split('/', 1)[1]
                need(item.is_file() and sha256(item.read_bytes()) == digest,
                     'installed payload changed or disappeared: ' + str(item))
        # This forces both libraries through absolute managed paths, independent
        # of the developer checkout. It does not claim a render or a shape.
        if self.manifest['target'] in ('macos', 'linux'):
            paths = [path / self.manifest['files'][k]['filename'] for k in ('skia', 'harfbuzz')]
            preload = '''(define get-lib-search-dirs (dynamic-require 'setup/dirs 'get-lib-search-dirs))
              (define fc-path (for/first ([d (in-list (get-lib-search-dirs))]
                                         #:when (file-exists? (build-path d "libfontconfig.so.1")))
                                (build-path d "libfontconfig.so.1")))
              (unless fc-path (error 'prototype "no declared fontconfig payload"))
              (define fc (ffi-lib fc-path))''' if self.preload_fontconfig else ''
            expr = f'''(begin (require ffi/unsafe json)
              {preload}
              (define sk (ffi-lib {json.dumps(str(paths[0]))}))
              (define hb (ffi-lib {json.dumps(str(paths[1]))} #:global? #f))
              (define milestone ((get-ffi-obj "sk_version_get_milestone" sk (_fun -> _int))))
              (define hb-v ((get-ffi-obj "hb_version_string" hb (_fun -> _string/utf-8))))
              (unless (and (= milestone 119) (equal? hb-v "8.3.1")) (error 'prototype "wrong ABI"))
              (write-json (hasheq 'milestone milestone 'harfbuzz hb-v)))'''
            self.run(environment, '-e', expr)
            if self.source_root:
                worker = self.source_root / 'tools/probe-managed-pair.rkt'
                # Bypass every checkout .zo. This is expressly the old override
                # route, not a claim that a managed loader has been integrated.
                expr = f'''(begin (require ffi/unsafe)
                            (parameterize ([use-compiled-file-paths '()]
                                         [current-command-line-arguments
                                           (vector {json.dumps(str(paths[0]))} {json.dumps(str(paths[1]))})])
                            {preload}
                            (dynamic-require '(submod (file {json.dumps(str(worker))}) main) #f)))'''
                self.run(environment, '-e', expr)
        self.report['checks'].append(dict(check='payload-and-native-bootstrap', scope=scope, path=str(path)))
        self.save()
        return path

    def execute(self):
        first = self.environment('first')
        self.report['racket_version'] = self.run(first, '-e', '(display (version))')
        self.report['target'] = self.run(first, '-e', '(display (system-library-subpath #f))')
        self.report['fontconfig_explicitly_preloaded'] = self.preload_fontconfig
        self.raco(first, 'pkg', 'install', '--auto', '--batch', self.archive)
        path = self.payload(first)
        self.raco(first, 'setup', '--pkgs', self.package)
        self.payload(first)
        # Exercise an explicit compatible packaging revision, then an explicit
        # rollback. The pair's native bytes remain unchanged in this experiment.
        revision_dir = self.directory / 'revision'
        revision_dir.mkdir()
        with zipfile.ZipFile(self.archive) as z:
            revision = {n: z.read(n) for n in z.namelist()}
        revision['info.rkt'] = revision['info.rkt'].replace(b'(define version "1.0")', b'(define version "1.1")')
        new_manifest = dict(self.manifest, package_version='1.1')
        revision['skia-native-1/manifest.json'] = json_bytes(new_manifest)
        update = revision_dir / (self.package + '.zip')
        write_zip(update, revision)
        self.raco(first, 'pkg', 'update', '--batch', '--name', self.package, update)
        need(json.loads((path / 'manifest.json').read_text())['package_version'] == '1.1',
             'compatible update did not replace managed manifest')
        self.raco(first, 'pkg', 'update', '--batch', '--name', self.package, self.archive)
        self.payload(first)
        self.report['checks'].append(dict(check='compatible-update-and-explicit-rollback', passed=True))
        sentinel = path.parent / 'unrelated-library.txt'
        sentinel.write_text('retain me\n')
        forms = self.directory / 'forms'
        forms.mkdir()
        for form in ('source', 'built', 'binary-lib'):
            destination = forms / form
            destination.mkdir()
            self.raco(first, 'pkg', 'create', '--from-install', '--' + form,
                      '--dest', destination, self.package)
            with zipfile.ZipFile(destination / (self.package + '.zip')) as z:
                for name, digest in self.expected.items():
                    need(sha256(z.read(name)) == digest, f'{form} lost/changed {name}')
            self.report['checks'].append(dict(check='form-preserves-payload-notices', form=form))
        self.raco(first, 'pkg', 'remove', '--batch', self.package)
        need(not path.exists() and sentinel.read_text() == 'retain me\n', 'removal cleanup/ownership failed')
        # Discard access to the original environment before testing the forms.
        shutil.rmtree(first[2])
        for form in ('source', 'built', 'binary-lib'):
            second = self.environment('reinstall-' + form)
            archive = forms / form / (self.package + '.zip')
            self.raco(second, 'pkg', 'install', '--auto', '--batch', archive)
            path = self.payload(second)
            if form == 'binary-lib':
                # move-foreign-libs has removed the package-local payload. The
                # repackager must recover it from Racket's managed directory.
                pkg = Path(self.run(second, '-e', f'(begin (require pkg/lib) (display (pkg-directory "{self.package}")))'))
                need(not (pkg / 'skia-native-1').exists(), 'binary-lib did not exercise moved payload')
                recovered = forms / 'recovered-binary-lib'
                recovered.mkdir()
                self.raco(second, 'pkg', 'create', '--from-install', '--binary-lib', '--dest', recovered, self.package)
                with zipfile.ZipFile(recovered / (self.package + '.zip')) as z:
                    for name, digest in self.expected.items():
                        need(sha256(z.read(name)) == digest, 'unmove lost/changed ' + name)
                self.report['checks'].append(dict(check='repackage-after-move', passed=True))
            self.raco(second, 'pkg', 'remove', '--batch', self.package)
            need(not path.exists(), 'rebuilt package removal left managed payload')
            shutil.rmtree(second[2])
        scopes = self.environment('scopes')
        self.raco(scopes, 'pkg', 'install', '--installation', '--auto', '--batch', self.archive)
        installed = self.payload(scopes, 'installation')
        # Racket rejects the same package name in a narrower scope. Preserve
        # that behavior; --force is not a legitimate shadowing test.
        failure = self.raco(scopes, 'pkg', 'install', '--user', '--auto', '--batch', self.archive, expected=1)
        need('installed in a wider scope' in failure, 'scope rejection was for an unexpected reason')
        self.payload(scopes, 'installation')
        self.report['checks'].append(dict(check='ordinary-same-package-user-shadow-rejected', passed=True))
        self.raco(scopes, 'pkg', 'remove', '--installation', '--batch', self.package)
        need(not installed.exists(), 'installation removal left managed payload')
        self.raco(scopes, 'pkg', 'install', '--user', '--auto', '--batch', self.archive)
        user = self.payload(scopes)
        need(user != installed and not installed.exists(), 'scope collision')
        self.raco(scopes, 'pkg', 'remove', '--user', '--batch', self.package)
        need(not user.exists(), 'user removal left managed payload')
        self.report.update(status='passed', rendering_shaping_qualified=False,
                           explicit_path_rendering_shaping_executed=bool(self.source_root),
                           full_documentation_qualified=False,
                           catalog_candidate_validated=False)
        self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--preload-fontconfig', action='store_true',
                        help='test a proposed natipkg loader repair; does not declare it qualified')
    parser.add_argument('--source-root', type=Path,
                        help='also render/shape with the existing explicit-override route; never claims automatic discovery')
    args = parser.parse_args()
    probe = Probe(args.runtime, args.archive, args.directory, preload_fontconfig=args.preload_fontconfig,
                  source_root=args.source_root)
    try:
        probe.execute()
    except Exception as exc:
        probe.report.update(status='failed', error=str(exc))
        probe.save()
        raise


if __name__ == '__main__':
    main()
