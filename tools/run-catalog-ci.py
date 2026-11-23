#!/usr/bin/env python3
"""Acquire candidates, then execute the catalog validator under OS network denial.

Only for fresh disposable CI runners. No publishing, account changes or normal
user catalog configuration. Linux natipkg uses the pinned official pkg-build
runtime in the explicit --natipkg-runtime directory.
"""
from __future__ import annotations
from repository_layout import source_path, library_root, documentation_root
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid
from native_packages import ROOT, need, json_bytes
from catalog_execution import relocatable_runtime, windows_network_programs


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'tools' / (name + '.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def execute(racket, output, runtime=None, docker_image=None):
    need(not output.exists(), 'CI output must be new')
    if sys.platform.startswith('linux'):
        need(os.getuid() > 0, 'Linux catalog CI must start from an unprivileged runner account')
    selected = Path(shutil.which(racket) or racket).resolve()
    runtime = runtime or (selected.parent.parent if selected.parent.name == 'bin' else selected.parent)
    runtime = relocatable_runtime(runtime)
    output.mkdir(parents=True)
    output = output.resolve()
    stage = output / 'staged'
    try:
        staged = load('stage-native-catalog').stage(str(selected), stage, snapshot=True)
    except Exception as error:
        # A preparation failure must remain a failed job and retain its cause,
        # even though no installed-package execution receipt exists yet.
        evidence = output / 'evidence'
        evidence.mkdir()
        (evidence / 'preparation-failure.json').write_bytes(json_bytes(dict(
            schema=1, status='failed-preparation', error=str(error),
            runtime=str(runtime), catalog_candidate_validated=False)))
        for path in (stage / 'catalog-metadata.log', stage / 'dependency-staging.log',
                     runtime.with_suffix('.acquisition.json')):
            if path.is_file() and not path.is_symlink():
                limit = 4 * 1024 * 1024
                size = path.stat().st_size
                with path.open('rb') as stream:
                    stream.seek(max(0, size - limit))
                    (evidence / path.name).write_bytes(stream.read(limit))
                if size > limit:
                    (evidence / (path.name + '.truncated.json')).write_bytes(json_bytes(dict(
                        original_bytes=size, retained_tail_bytes=limit)))
        raise
    fixture_build = output / 'fixture-build'
    architecture = (['-DCMAKE_OSX_ARCHITECTURES=' + ('arm64' if staged['identity']['target'].startswith('aarch64-') else 'x86_64')]
                    if sys.platform == 'darwin' else [])
    subprocess.run(['cmake', '-S', str(ROOT / 'tools/catalog-fixtures'), '-B', str(fixture_build), *architecture,
                    *(['-G', 'Visual Studio 17 2022', '-A', 'x64'] if os.name == 'nt' else [])], check=True)
    subprocess.run(['cmake', '--build', str(fixture_build), '--config', 'Release'], check=True)
    fixtures = [p for p in fixture_build.rglob('skia-wrong-abi.*') if p.suffix in ('.so', '.dylib', '.dll')]
    need(len(fixtures) == 1, 'expected one incompatible scalar ABI test fixture')
    command = [sys.executable, str(ROOT / 'tools/validate-catalog-package.py'), '--runtime', str(runtime),
               '--catalog', str(stage / 'snapshot/catalog'), '--work', str(output / 'execution'),
               '--wrong-abi', str(fixtures[0]), '--owned-stage', str(stage)]
    if sys.platform == 'win32':
        from windows_native import acquire
        inputs = output / 'windows-upstream-inputs'
        # Exercise the real direct NuGet acquisition before firewall isolation.
        # Its raw archives stay outside candidate/built packages and CI evidence.
        try:
            acquire(ROOT / 'packaging/native-assets.json', inputs)
        except Exception as error:
            evidence = output / 'evidence'
            evidence.mkdir()
            (evidence / 'windows-acquisition-failure.json').write_bytes(json_bytes(dict(
                schema=1, status='failed-windows-upstream-acquisition', error=str(error)[:8192],
                catalog_candidate_validated=False, publication_performed=False)))
            raise
        command += ['--windows-inputs', str(inputs)]
    if sys.platform == 'darwin':
        guarded = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', *command]
    elif sys.platform.startswith('linux'):
        if docker_image:
            guarded = ['docker', 'run', '--rm', '--network', 'none', '--platform', 'linux/amd64',
                       '--user', f'{os.getuid()}:{os.getgid()}',
                       '--mount', f'type=bind,source={ROOT},target={ROOT},readonly',
                       '--mount', f'type=bind,source={output},target={output}',
                       docker_image, 'python3', *command[1:]]
        else:
            # The namespace needs privilege; package execution must return to
            # the runner account so source chmod restrictions actually apply.
            guarded = ['sudo', '-n', 'unshare', '--net', '--setgid', str(os.getgid()),
                       '--setuid', str(os.getuid()), '--', *command]
    elif sys.platform == 'win32':
        # Rules are limited to the validation processes, and removed in finally.
        # No firewall default/account/repository settings are changed.
        label = 'Skia catalog validation ' + uuid.uuid4().hex
        paths = windows_network_programs(output, Path(sys.executable))
        quote = lambda s: "'" + str(s).replace("'", "''") + "'"
        rules = '\n'.join('New-NetFirewallRule -DisplayName ' + quote(label) +
                          ' -Direction Outbound -Action Block -Program ' + quote(path) + ' | Out-Null' for path in paths)
        script = output / 'deny-network.ps1'
        script.write_text("$ErrorActionPreference = 'Stop'\ntry {\n" + rules + '\n& ' +
                          ' '.join(quote(s) for s in command) +
                          '\n$code = $LASTEXITCODE\n} finally { Get-NetFirewallRule -DisplayName ' + quote(label) +
                          ' -ErrorAction SilentlyContinue | Remove-NetFirewallRule }\nexit $code\n')
        guarded = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script)]
    else:
        raise ValueError('unqualified catalog CI OS')
    result = subprocess.run(guarded, cwd=output)
    # Upload logs/receipts, never several copies of large native/runtime/doc trees.
    evidence = output / 'evidence'
    evidence.mkdir()
    for name in ('staging-receipt.json', 'catalog-request.json', 'dependency-staging.log'):
        shutil.copy2(stage / name, evidence / name)
    acquisition = runtime.with_suffix('.acquisition.json')
    if acquisition.is_file():
        shutil.copy2(acquisition, evidence / 'runtime-acquisition.json')
    for path in (stage / 'artifacts').glob('*.json'):
        shutil.copy2(path, evidence / path.name)
    execution = output / 'execution'
    if execution.exists():
        for path in execution.iterdir():
            if path.is_file() and path.suffix in ('.json', '.log'):
                shutil.copy2(path, evidence / path.name)
    need(result.returncode == 0, 'catalog validation failed; retain execution/result.json and logs')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--racket', default=os.environ.get('RACKET', 'racket'))
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--natipkg-runtime', type=Path)
    p.add_argument('--docker-image', help='natipkg lane: clean image without OS fontconfig, network none')
    args = p.parse_args()
    execute(args.racket, args.output, args.natipkg_runtime, args.docker_image)
