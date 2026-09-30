#!/usr/bin/env python3
"""Required 0.51 installed-package interop checks, additional to the 0.48/0.50 gates."""
from __future__ import annotations
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import ci
from ci_matrix import load_matrix
from d3d12_interop_validation import execute


def interop_checks(runner, installed, away, env, report):
    output = installed / 'output'
    output.mkdir(exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix='gpu-d3d12-interop-0.51-', dir=output))
    result = execute(installed, report['racket_executable'], directory,
                     lambda argv: runner.run(argv, cwd=away, env=env), selection='warp')
    ci.require(result.get('status') == 'passed', 'interop inspection did not pass')
    report['interop'] = result
    report['checks']['required_d3d12_interop'] = True


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / 'output/ci-d3d12-interop'
    output.mkdir(parents=True, exist_ok=False)
    runner = ci.Runner(output, ci.clean_environment(os.environ))
    report = dict(schema_version=1, stage='0.51', status='running', profile='d3d12-interop',
                  checks={}, commands=runner.commands,
                  github={k: os.environ.get(k) for k in ('GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT')})
    code = 1
    try:
        report['source_files_verified'] = ci.manifest.check(root)
        report['source_manifest_sha256'] = ci.sha256(root / ci.manifest.NAME)
        row = next(r for r in load_matrix()['cpu'] if r['id'] == 'windows-x64')
        ci.package_checks(runner, root, row, 'cpu', report, extra_checks=interop_checks)
        ci.require(report['checks'].get('required_d3d12_interop') is True, 'interop gate did not execute')
        ci.manifest.check(root)
        report['status'] = 'passed'; code = 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as e:
        report.update(status='failed', error=str(e))
        print('D3D12 interop CI FAILED:', e, file=sys.stderr)
    finally:
        ci.write_json(output / 'ci-report.json', report)
        text = f'## Direct3D interop\n\nStatus: **{report["status"]}**. WARP, not hardware or screen certification.\n'
        (output / 'ci-summary.md').write_text(text, encoding='utf-8')
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as out:
                out.write(text)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
