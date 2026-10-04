#!/usr/bin/env python3
"""0.60 GPU DC consumer gate, including the complete selected 0.59 gate.

All output goes to a new directory. Missing Racket, a backend, a selected GUI,
an incomplete report, failed independent pixel probes or a readback in a normal
frame is fatal. A CPU reference is not a fallback for a failed GPU capture.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import shutil
import sys
import tempfile
import uuid

import gpu_dc_consumer_validation as inspection

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("gpu_dc_baseline", Path(__file__).with_name("validate-gpu-dc.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

SOURCES = tuple(dict.fromkeys((*base.SOURCES,
    "tests/dc-consumer-fixtures.rkt", "tests/dc-style-fixtures.rkt",
    "tests/gpu-dc-consumer-fixtures.rkt", "tools/gpu-dc-consumer-common.rkt",
    "tools/gpu-dc-consumer-native.rkt", "tools/gpu-dc-consumer-gui.rkt",
    "tools/gpu_dc_consumer_validation.py", "tools/validate-gpu-dc-consumers.py",
    "tools/test-gpu-dc-consumers.py", ".github/workflows/gpu-dc.yml")))


def fingerprint(root: Path) -> dict:
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in SOURCES}


def validate_marker(output: str, suite: str) -> None:
    found = re.findall(r"^gpu-dc-consumers-(native|gui): (\d+) captures; passed\.$", output, re.M)
    inspection.require(found == [(suite, str(inspection.COUNTS[suite]))], "incomplete/duplicate worker completion")
    inspection.require(not re.search(r"^(?:ERROR|FAILURE|FAIL:.*)$", output, re.M), "worker printed a failure")


def validate_baseline(report: dict, identity: dict, gui: bool) -> None:
    inspection.require(report.get("status") == "passed" and report.get("stage") == "0.59", "baseline did not pass")
    inspection.require(report.get("identity") == identity, "foreign baseline identity")
    inspection.require(report.get("native_gpu_tests_passed") is True, "native baseline missing")
    inspection.require(report.get("gui_required") is gui and report.get("gui_tests_passed") is gui, "GUI baseline missing/misreported")
    names = ("gpu-dc-pure", "gpu-dc-native", "gpu-dc-gui") if gui else ("gpu-dc-pure", "gpu-dc-native")
    inspection.require(report.get("completed_suites") == [{"name": n, "cases": base.COUNTS[n]} for n in names],
                       "incomplete baseline suites")


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--racket", default="racket")
    p.add_argument("--backend", choices=("auto", "egl", "metal", "direct3d"), default="auto")
    p.add_argument("--adapter", choices=("hardware", "warp"))
    p.add_argument("--require-gui", action="store_true")
    p.add_argument("--directory", type=Path)
    p.add_argument("--timeout", type=float, default=600)
    return p


def main(argv=None, *, root: Path = ROOT) -> int:
    args = parser().parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser().error("--timeout must be a positive finite number")
    root = root.resolve()
    if args.directory:
        directory = args.directory.absolute()
        # Do not follow a preexisting symlink or reuse old evidence.
        directory.mkdir(parents=True, exist_ok=False)
    else:
        (root / "output").mkdir(exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix="gpu-dc-consumers-0.60-", dir=root / "output"))
    runner = base.Runner(directory, args.timeout)
    token = uuid.uuid4().hex
    result = {"schema": 1, "stage": "0.60", "status": "failed", "run_token": token,
              "baseline_passed": False, "native_consumers_passed": False, "gui_consumers_passed": False,
              "gui_required": args.require_gui, "physical_display_verified": False,
              "cpu_gpu_byte_identity_required": False, "performance_measured": False,
              "commands": runner.commands}
    try:
        racket = shutil.which(args.racket)
        if not racket:
            raise RuntimeError(f"selected Racket executable not found: {args.racket}")
        result["racket_executable"] = str(Path(racket).resolve())
        before = fingerprint(root)
        result["source_sha256"] = before
        runner.run([sys.executable, root / "tools/update-source-sums.py", "--check"], root)
        identity = base.validate_identity(json.loads(runner.run([racket, root / "tools/ci-identity.rkt"], root)))
        result["identity"] = identity
        worker_identity = {k: identity[k] for k in ("version", "os", "architecture", "vm")}
        native, gui = base.select_backends(args.backend, identity)
        if args.adapter and native != "direct3d":
            raise ValueError("--adapter requires Direct3D")
        result.update(native_backend=native, gui_backend=gui if args.require_gui else None)
        options = ["--backend", native]
        if args.adapter:
            options += ["--adapter", args.adapter]
        baseline_args = [sys.executable, root / "tools/validate-gpu-dc.py", "--racket", racket,
                         *options, "--directory", directory / "baseline", "--timeout", args.timeout]
        if args.require_gui:
            baseline_args += ["--require-gui"]
        # The old validator launches multiple commands; allow its overall
        # invocation a bounded multiple of the per-command timeout.
        runner.timeout = args.timeout * 12
        try:
            runner.run(baseline_args, root)
        finally:
            runner.timeout = args.timeout
        validate_baseline(inspection.read_json(directory / "baseline/validation.json"), identity, args.require_gui)
        result["baseline_passed"] = True
        suites = [("native", native)] + ([("gui", gui)] if args.require_gui else [])
        for suite, backend in suites:
            module = root / f"tools/gpu-dc-consumer-{suite}.rkt"
            runner.run([racket, "-l", "raco", "--", "make", module], root)
            command = [racket, module, "--backend", backend, "--directory", directory / suite, "--run-token", token]
            if args.adapter:
                command += ["--adapter", args.adapter]
            validate_marker(runner.run(command, root), suite)
            inspected = inspection.inspect_directory(directory / suite, suite, token, backend, worker_identity)
            result[suite + "_consumers_passed"] = True
            result[suite + "_capture_count"] = len(inspected["captures"])
            result[suite + "_bounded_comparisons"] = len(inspected["bounded_comparisons"])
        if fingerprint(root) != before:
            raise RuntimeError("source changed during validation")
        runner.run([sys.executable, root / "tools/update-source-sums.py", "--check"], root)
        result["status"] = "passed"
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
        print("GPU DC consumers FAILED:", result["error"], file=sys.stderr)
    finally:
        (directory / "validation.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print("Evidence:", directory, flush=True)
    if result["status"] == "passed":
        print("GPU DC consumers passed; GUI " + ("passed." if args.require_gui else "NOT RUN."))
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
