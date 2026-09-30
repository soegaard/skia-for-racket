#!/usr/bin/env python3
"""Windows x64 local D3D12 validation. WARP is explicit; failures never skip."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import ci
from d3d12_validation import execute


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adapter', choices=('warp', 'hardware'), default='warp')
    parser.add_argument('--adapter-index', type=int, default=0)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = root / 'output'; output.mkdir(exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix='gpu-d3d12-0.48-', dir=output))
    logs = directory / 'execution'; logs.mkdir()
    # Preserve explicit native library overrides in a local run, but force the
    # selected adapter on the command line. The CI entry point isolates its env.
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    runner = ci.Runner(logs, env)
    result = {'stage': '0.48', 'status': 'failed'}
    code = 1
    try:
        racket = shutil.which(env.get('RACKET', 'racket'))
        ci.require(bool(racket), 'selected RACKET not found')
        native_output = directory / (directory.name + '-probe'); native_output.mkdir()
        result = execute(root, racket, native_output,
                         lambda argv: runner.run(argv, cwd=root),
                         selection=args.adapter, index=args.adapter_index)
        # Only verify; never rewrite source checksums to manufacture a pass.
        runner.run([sys.executable, root / 'tools/update-source-sums.py', '--check'], cwd=root)
        code = 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as exc:
        result = {'stage': '0.48', 'status': 'failed', 'error': str(exc)}
        print(f'D3D12 validation FAILED: {exc}', file=sys.stderr)
    ci.write_json(directory / ('validation.json' if code == 0 else 'validation.failed.json'), result)
    print(f'D3D12 evidence: {directory}')
    return code


if __name__ == '__main__':
    raise SystemExit(main())
