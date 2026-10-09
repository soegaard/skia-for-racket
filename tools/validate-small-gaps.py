#!/usr/bin/env python3
"""Require 0.78b numerical/native no-draw acceptance, or explicitly audit source only."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

from small_gap_validation import STAGE, BASELINE, PURE_CASES, NATIVE_CASES, source_contracts, suite_output

ROOT = Path(__file__).resolve().parents[1]


def main(argv=None, *, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--racket", help="Racket executable; both pure and native execution are mandatory")
    mode.add_argument("--source-only", action="store_true", help="explicitly omit all Racket/native execution")
    parser.add_argument("--directory", type=Path, help="new evidence directory; existing directories are refused")
    args = parser.parse_args(argv)
    token = uuid.uuid4().hex
    directory = (args.directory or root / "output" / ("small-gaps-" + token)).resolve()
    # Do not replace an earlier evidence receipt or leave an old successful one.
    try:
        directory.mkdir(parents=True, exist_ok=False)
    except OSError as exc:
        print("Cannot create a new evidence directory: " + str(exc), file=sys.stderr)
        return 1
    logs = directory / "logs"
    logs.mkdir()
    report = dict(schema=1, stage=STAGE, baseline_commit=BASELINE, run_token=token,
                  status="failed", source_only=args.source_only, source_audit_passed=False,
                  pure_executed=False, native_attempted=False, native_executed=False,
                  gpu_executed=False, document_rendering_executed=False, release_ready=False,
                  null_surface_implemented=False, commands=[])

    def run(command):
        path = logs / f"{len(report['commands']) + 1:03}.log"
        record = dict(argv=[str(x) for x in command], log=str(path.relative_to(directory)), status="failed")
        report["commands"].append(record)
        print("+ " + " ".join(record["argv"]), flush=True)
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PYTHONUTF8="1")
        with path.open("w", encoding="utf-8", newline="\n") as output:
            try:
                result = subprocess.run(record["argv"], cwd=root, env=env, stdout=output,
                                        stderr=subprocess.STDOUT, timeout=300, check=False)
            except subprocess.TimeoutExpired:
                record["status"] = "timed-out"
                raise
        text = path.read_text(encoding="utf-8", errors="replace")
        record["exit_code"] = result.returncode
        if result.returncode:
            print(text[-12000:], file=sys.stderr)
            raise RuntimeError(f"command exited {result.returncode}; see {path}")
        record["status"] = "passed"
        return text

    try:
        report["summary"] = source_contracts(root)
        report["source_audit_passed"] = True
        run([sys.executable, root / "tools/update-source-sums.py", "--check"])
        run([sys.executable, root / "tools/test-small-gaps.py"])
        if args.racket:
            racket = shutil.which(args.racket)
            if not racket:
                raise ValueError("Racket executable not found: " + args.racket)
            run([racket, root / "tools/check-package-version.rkt"])
            run([racket, "-l", "raco", "--", "make", root / "main.rkt",
                 root / "tests/small-gap-pure-test.rkt", root / "tests/small-gap-native-test.rkt",
                 root / "examples/small-gaps.rkt"])
            text = run([racket, root / "tests/small-gap-pure-test.rkt"])
            suite_output(text, "small-gap-pure", PURE_CASES)
            report["pure_executed"] = True
            report["native_attempted"] = True
            text = run([racket, root / "tests/small-gap-native-test.rkt"])
            suite_output(text, "small-gap-native", NATIVE_CASES)
            report["native_executed"] = True
            run([racket, root / "examples/small-gaps.rkt"])
        source_contracts(root)
        run([sys.executable, root / "tools/update-source-sums.py", "--check"])
        report["status"] = "passed"
    except Exception as exc:
        report["error"] = f"{type(exc).__name__}: {exc}"
        print("0.78b acceptance FAILED: " + report["error"], file=sys.stderr)
    finally:
        (directory / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print("Evidence: " + str(directory))
    if args.source_only:
        print("Native, GPU, and document execution NOT RUN (--source-only).")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
