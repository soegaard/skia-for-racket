#!/usr/bin/env python3
"""Run shared Ganesh suites on one explicit backend. Native libraries must be installed."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import shutil
import sys
import tempfile
import ci
from gpu_parity import execute, write_json
from gpu_backend_policy import selection


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--backend', required=True, choices=('opengl', 'metal', 'direct3d'))
    p.add_argument('--host', choices=('gui', 'egl', 'owned'))
    p.add_argument('--adapter', choices=('warp', 'hardware'))
    p.add_argument('--adapter-index', type=int)
    p.add_argument('--scope', choices=('offscreen', 'presentation', 'all'), default='offscreen')
    p.add_argument('--racket', default=os.environ.get('RACKET', 'racket'))
    p.add_argument('--output', type=Path)
    p.add_argument('--egl-platform', choices=('surfaceless', 'device'), default='surfaceless')
    p.add_argument('--egl-device-index', type=int, default=0)
    p.add_argument('--egl-surface', choices=('surfaceless', 'pbuffer'), default='surfaceless')
    args = p.parse_args()
    root = Path(__file__).resolve().parents[1]
    host = args.host or ('gui' if args.backend == 'opengl' or args.scope == 'presentation' else 'owned')
    selection(args.backend, host, args.adapter, args.adapter_index)
    resolved = shutil.which(args.racket)
    if not resolved: p.error('selected Racket executable not found')
    racket = str(Path(resolved).resolve())
    if args.output:
        output = args.output.resolve(); output.mkdir(parents=True, exist_ok=False)
    else:
        (root / 'output').mkdir(exist_ok=True)
        output = Path(tempfile.mkdtemp(prefix='gpu-parity-0.50-', dir=root / 'output'))
    evidence = Path(tempfile.mkdtemp(prefix='gpu-parity-' + args.backend + '-', dir=output))
    # Preserve display variables for an explicit GL/GUI or presentation request.
    # Clean source overrides, benchmark controls and inherited optional modes.
    env = ci.clean_environment(os.environ)
    if host == 'gui' or args.scope != 'offscreen':
        for key in ci.DISPLAY_KEYS:
            if key in os.environ: env[key] = os.environ[key]
    env.update(SKIA_GPU_VALIDATION_RUN=evidence.name, RACKET=racket)
    runner = ci.Runner(output, env)
    try:
        with tempfile.TemporaryDirectory(prefix='skia parity outside source ') as away:
            result = execute(root, racket, evidence,
                             lambda argv: runner.run(argv, cwd=Path(away)),
                             backend=args.backend, host=host, adapter=args.adapter,
                             adapter_index=args.adapter_index, scope=args.scope,
                             egl_platform=args.egl_platform, egl_device_index=args.egl_device_index,
                             egl_surface=args.egl_surface)
        print('Shared GPU parity passed:', evidence / 'parity.inspection.json')
        return 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as exc:
        print('GPU parity FAILED:', exc, file=sys.stderr)
        return 1


if __name__ == '__main__': raise SystemExit(main())
