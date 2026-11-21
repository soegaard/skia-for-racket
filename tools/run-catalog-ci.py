#!/usr/bin/env python3
"""Acquire candidates, then execute the catalog validator under OS network denial.

Only for fresh disposable CI runners. No publishing, account changes or normal
user catalog configuration. Linux natipkg uses the pinned official pkg-build
runtime in the explicit --natipkg-runtime directory.
"""
from __future__ import annotations
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


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'tools' / (name + '.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def execute(racket, output, runtime=None, docker_image=None):
    need(not output.exists(), 'CI output must be new')
    output.mkdir(parents=True)
    output = output.resolve()
    selected = Path(shutil.which(racket) or racket).resolve()
    runtime = runtime or (selected.parent.parent if selected.parent.name == 'bin' else selected.parent)
    runtime = runtime.resolve()
    stage = output / 'staged'
    staged = load('stage-native-catalog').stage(str(selected), stage, snapshot=True)
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
    if sys.platform == 'darwin':
        guarded = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', *command]
    elif sys.platform.startswith('linux'):
        if docker_image:
            guarded = ['docker', 'run', '--rm', '--network', 'none', '--platform', 'linux/amd64',
                       '--mount', f'type=bind,source={ROOT},target={ROOT},readonly',
                       '--mount', f'type=bind,source={output},target={output}',
                       docker_image, 'python3', *command[1:]]
        else:
            guarded = ['sudo', '-n', 'unshare', '--net', '--', *command]
    elif sys.platform == 'win32':
        # Rules are limited to the validation processes, and removed in finally.
        # No firewall default/account/repository settings are changed.
        label = 'Skia catalog validation ' + uuid.uuid4().hex
        paths = [Path(sys.executable)]
        paths += [output / 'execution' / name / 'Racket runtime' / exe
                  for name in ('source installation', 'scope lifecycle', 'reinstalled source', 'reinstalled built', 'reinstalled binary-lib')
                  for exe in ('Racket.exe', 'racket.exe')]
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
