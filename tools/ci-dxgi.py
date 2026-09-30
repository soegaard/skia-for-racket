#!/usr/bin/env python3
"""Required installed-package Windows DXGI/WARP lane; offscreen CI stays independent."""
from __future__ import annotations
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import ci
from ci_matrix import load_matrix
from gpu_parity import parity_ci_checks
from dxgi_validation import execute


def dxgi_checks(runner, installed, away, env, report):
    output = installed / 'output'
    output.mkdir(exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix='gpu-dxgi-0.49-', dir=output))
    result = execute(installed, report['racket_executable'], directory,
                     lambda argv: runner.run(argv, cwd=away, env=env), selection='warp')
    report['dxgi'] = result
    report['presentation_tested'] = True
    report['checks']['required_dxgi_warp'] = True
    report['gpu'] = {'status': 'passed', 'backend': 'direct3d', 'renderer_class': 'software',
                     'hardware_acceleration_claimed': False, 'presentation_tested': True, 'visible_pixels_verified': False}


def dxgi_and_parity_checks(runner, installed, away, env, report):
    dxgi_checks(runner, installed, away, env, report)
    parity_ci_checks(runner, installed, away, env, report, scope='presentation')


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    output = root / 'output/ci-dxgi-warp'
    output.mkdir(parents=True, exist_ok=False)
    runner = ci.Runner(output, ci.clean_environment(os.environ))
    report = {'schema_version': 1, 'stage': '0.50', 'profile': 'dxgi-warp',
              'status': 'running', 'checks': {}, 'commands': runner.commands,
              'hardware_acceleration_claimed': False, 'presentation_tested': False, 'visible_pixels_verified': False,
              'github': {k: os.environ.get(k) for k in ('GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT')}}
    code = 1
    try:
        report['source_files_verified'] = ci.manifest.check(root)
        report['source_manifest_sha256'] = ci.sha256(root / ci.manifest.NAME)
        row = next(row for row in load_matrix()['cpu'] if row['id'] == 'windows-x64')
        # Reuse the FULL isolated-install/CPU/ABI path. The hook executes before
        # source re-verification, artifact copying and temporary-home destruction.
        ci.package_checks(runner, root, row, 'cpu', report, extra_checks=dxgi_and_parity_checks)
        ci.require(report['checks'].get('required_dxgi_warp') is True, 'DXGI WARP gate did not execute')
        ci.require(report['checks'].get('required_backend_parity_presentation') is True,
                   'shared presentation parity gate did not execute')
        ci.manifest.check(root)
        report['status'] = 'passed'
        code = 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as exc:
        report['status'] = 'failed'; report['error'] = str(exc)
        print(f'DXGI CI FAILED: {exc}', file=sys.stderr)
    finally:
        ci.write_json(output / 'ci-report.json', report)
        summary = (f'## DXGI / D3D12 WARP / Windows x64\n\nStatus: **{report["status"]}**. '
                   'Required: software WARP swap-chain presentation/readback; no hardware or screen certification.\n')
        (output / 'ci-summary.md').write_text(summary, encoding='utf-8')
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as out:
                out.write(summary)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
