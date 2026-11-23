#!/usr/bin/env python3
"""Prepare/check six ordinary public Git sources in disposable Racket scopes.

Default: describe the proposed sources, with no network or installation.
--execute is for the later authorized repository-publication phase: it verifies
remote HEADs and actually fetches the Git sources. It never publishes anything.
This focused source-fetch proof does not replace the full Release candidate gate.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
from native_packages import ROOT, need, json_bytes, sha256, read_json
from catalog_execution import racket_command, runtime_child_environment
from repository_layout import SOURCE_PACKAGES, NATIVE_PACKAGES

SOURCE_REPOSITORY = 'https://github.com/soegaard/skia-for-racket.git'
NATIVE_REPOSITORY = 'https://github.com/soegaard/skia-libs.git'
SOURCES = {name: (SOURCE_REPOSITORY if name in SOURCE_PACKAGES else NATIVE_REPOSITORY) + '?path=' + name
           for name in SOURCE_PACKAGES + NATIVE_PACKAGES}


def commit(value):
    need(type(value) is str and re.fullmatch('[0-9a-f]{40}', value), 'expected a resolved 40-digit Git commit')
    return value


def rows(source_commit, native_commit, native_tree):
    source_commit, native_commit = commit(source_commit), commit(native_commit)
    return [dict(name=name, source=url, sha1=source_commit if name in SOURCE_PACKAGES else native_commit,
                 metadata_directory=str((ROOT if name in SOURCE_PACKAGES else native_tree) / name))
            for name, url in SOURCES.items()]


def remote_head(url):
    result = subprocess.run(['git', '-c', 'credential.helper=', 'ls-remote', '--exit-code', url, 'HEAD'],
                            capture_output=True, text=True, timeout=120, check=True,
                            env={**os.environ, 'GIT_TERMINAL_PROMPT': '0', 'GIT_CONFIG_NOSYSTEM': '1',
                                 'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_ASKPASS': ''})
    values = result.stdout.splitlines()
    need(len(values) == 1 and values[0].endswith('\tHEAD'), 'ambiguous remote HEAD')
    return commit(values[0].split()[0])


def execute(args):
    need(not args.work.exists(), 'Git-source evidence directory must be new')
    need(not subprocess.check_output(['git','status','--porcelain'], cwd=ROOT), 'Git-fetch proof requires a clean committed source checkout')
    need(subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip() == args.source_commit,
         'source checkout differs from proposed Git commit')
    need(remote_head(SOURCE_REPOSITORY) == args.source_commit and remote_head(NATIVE_REPOSITORY) == args.native_commit,
         'ordinary default-branch HEAD differs from the reviewed candidate')
    args.work.mkdir(parents=True)
    request = args.work / 'catalog-request.json'
    request.write_bytes(json_bytes(rows(args.source_commit, args.native_commit, args.native_tree.resolve())))
    runtime = args.runtime.resolve()
    executable = runtime / ('Racket.exe' if os.name == 'nt' else 'bin/racket')
    subprocess.run([*racket_command(executable), str(ROOT / 'tools/write-staging-catalog.rkt'),
                    str(request), str(args.work / 'catalog')], check=True,
                   env={**os.environ, **runtime_child_environment(executable)})
    spec = importlib.util.spec_from_file_location('catalog_validator', ROOT / 'tools/validate-catalog-package.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    validator = module.Validator(runtime, args.work / 'catalog', args.work / 'execution',
                                 base_catalog=args.base_catalog.resolve())
    validator.report['git_sources'] = read_json(request)
    validator.report['remote_heads'] = dict(source=args.source_commit, native=args.native_commit)
    try:
        validator.library_only(validator.catalog)
        full = validator.environment('source installation')
        identity = json.loads(validator.run(full, '-e', "(begin (require json) (write-json (hasheq 'version (version) 'vm (symbol->string (system-type 'vm)) 'bits (system-type 'word))))"))
        need(identity['version'] in ('8.18','9.3') and identity['vm'] == 'chez-scheme' and identity['bits'] == 64,
             'Git proof requires a released supported Racket CS runtime')
        validator.report['identity'] = identity
        validator.install(full, validator.catalog)
        validator.raco(full, 'setup', '--check-pkg-deps', '--pkgs', *SOURCE_PACKAGES, timeout=3600)
        validator.raco(full, 'test', '--drdr', '--package', 'skia-lib', 'skia-doc', timeout=600)
        smokes = validator.smoke(full)
        need(all(s.get('source_identity') is False for s in smokes), 'Git install required generated identity')
        expected_lock = sha256((ROOT / 'packaging/native-assets.json').read_bytes())
        for smoke in smokes:
            for native in (smoke['skia']['loader'], smoke['harfbuzz']):
                need(native['manifest']['lock_sha256'] == expected_lock, 'Git native payload has a different reviewed lock')
        validator.report['smoke'] = smokes
        validator.report['documentation_smoke'] = validator.documentation_smoke(full)
        installed = validator.raco(full, 'pkg', 'show', '--all', '--long')
        need(args.source_commit in installed, 'installed Git source commit absent')
        need(args.native_commit in installed, 'installed native Git commit absent')
        validator.report['installed_packages'] = installed
        validator.raco(full, 'skia-examples', 'shaping', validator.away / 'git shaping')
        validator.raco(full, 'pkg', 'remove', '--auto', '--batch', *SOURCE_PACKAGES, timeout=1800)
        need(not Path(smokes[0]['collection']).exists(), 'Git source removal left collection')
        validator.remove_environment(full, required=True)
        validator.report.update(status='passed-actual-git-fetch-checks', catalog_candidate_validated=False,
                                publication_performed=False, full_release_gate_replaced=False)
    except Exception as error:
        validator.report.update(status='failed', error=str(error))
        raise
    finally:
        validator.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true', help='actually fetch public Git; only after repository publication is authorized/completed')
    parser.add_argument('--source-commit', type=commit)
    parser.add_argument('--native-commit', type=commit)
    parser.add_argument('--native-tree', type=Path, default=ROOT / 'output/catalog/windows-native-package/skia-libs')
    parser.add_argument('--runtime', type=Path)
    parser.add_argument('--base-catalog', type=Path, help='staged standard dependency catalog for this released Racket/platform')
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    if not args.execute:
        print(json_bytes(dict(sources=SOURCES, publication_performed=False, public_git_fetch_executed=False)).decode(), end='')
        return
    if not all((args.source_commit,args.native_commit,args.runtime,args.base_catalog,args.work)):
        parser.error('--execute requires both resolved commits, --runtime, --base-catalog and a new --work directory')
    execute(args)


if __name__ == '__main__': main()
