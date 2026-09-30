#!/usr/bin/env python3
"""Required local Metal interop validation; missing Metal is a failure, not a skip."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import ci
from metal_interop_validation import execute


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket', default=os.environ.get('RACKET', 'racket'))
    parser.add_argument('--output', type=Path, help='new evidence directory; never overwrite an earlier run')
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    selected = shutil.which(args.racket)
    if not selected:
        parser.error('selected Racket executable not found')
    parent = root / 'output'; parent.mkdir(exist_ok=True)
    directory = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='gpu-metal-interop-0.52-', dir=parent))
    if args.output:
        directory.mkdir(parents=True, exist_ok=False)
    # Keep orchestration logs beside, not inside, the initially empty evidence
    # directory required by execute(). ci.Runner preserves failures/timeouts.
    logs = directory.parent / (directory.name + '-commands')
    logs.mkdir(exist_ok=False)
    runner = ci.Runner(logs, dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
    try:
        result = execute(root, str(Path(selected).resolve()), directory,
                         lambda command: runner.run(command, cwd=root))
        print('Metal interop passed:', result['handoffs'], 'handoffs;', directory)
        return 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as e:
        ci.write_json(directory / 'validation.failed.json', dict(stage='0.52', status='failed', error=str(e)))
        print('Metal interop FAILED:', e, file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
