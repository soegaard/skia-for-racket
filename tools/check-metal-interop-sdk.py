#!/usr/bin/env python3
"""Compile the Apple SDK fixture without creating a GPU device (required macOS CI)."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import ci
from metal_interop_validation import build_sdk


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    directory = args.output.resolve()
    directory.mkdir(parents=True, exist_ok=False)
    runner = ci.Runner(directory, dict(os.environ))
    try:
        if sys.platform != 'darwin':
            raise ValueError('Apple SDK checks require macOS')
        machine = platform.machine()
        architecture = 'aarch64' if machine == 'arm64' else machine
        with tempfile.TemporaryDirectory(prefix="skia metal SDK ") as temporary:
            build_sdk(root, directory, lambda command: runner.run(command, cwd=root), architecture,
                      build_directory=Path(temporary) / "abi")
        return 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as e:
        ci.write_json(directory / 'sdk.failed.json', dict(status='failed', error=str(e)))
        print('Metal SDK validation FAILED:', e, file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
