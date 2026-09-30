#!/usr/bin/env python3
"""Windows x64 native interop validation. No implicit fallback or optional skip."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import ci
from d3d12_interop_validation import execute, select


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adapter', choices=('warp', 'hardware'), default='warp')
    parser.add_argument('--adapter-index', type=int, default=0)
    parser.add_argument('--racket', default=os.environ.get('RACKET', 'racket'))
    args = parser.parse_args()
    select(args.adapter, args.adapter_index)
    root = Path(__file__).resolve().parents[1]
    output = root / 'output'; output.mkdir(exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix='gpu-interop-0.51-', dir=output))
    logs = directory / 'execution'; logs.mkdir()
    runner = ci.Runner(logs, dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONUTF8='1'))
    code = 1
    try:
        ci.manifest.check(root)
        racket = shutil.which(args.racket)
        ci.require(bool(racket), 'selected RACKET not found')
        evidence = directory / 'gpu-interop-probe'; evidence.mkdir()
        result = execute(root, racket, evidence, lambda argv: runner.run(argv, cwd=root),
                         selection=args.adapter, index=args.adapter_index)
        ci.manifest.check(root)
        ci.write_json(directory / 'validation.json', result)
        code = 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as e:
        ci.write_json(directory / 'validation.failed.json', dict(stage='0.51', status='failed', error=str(e)))
        print('Interop validation FAILED:', e, file=sys.stderr)
    print('Interop evidence:', directory)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
