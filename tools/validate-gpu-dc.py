#!/usr/bin/env python3
"""Explicit GPU DC gate. Missing native backends/displays fail selected gates.

A successful process exit alone is insufficient: every selected RackUnit suite
must emit its exact complete summary and completion marker. Reports distinguish
GPU-offscreen validation from real-window validation and never certify a screen
capture or performance. The selected Racket is used for ALL Racket commands.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
COUNTS = {"gpu-dc-pure": 33, "gpu-dc-native": 15, "gpu-dc-gui": 10}
HEADLESS = ("gpu-dc.rkt", "private/gpu-dc-scope.rkt", "private/gpu-dc-native.rkt",
            "tests/gpu-dc-pure-test.rkt", "tests/gpu-dc-native-test.rkt")
GUI = ("gpu-canvas.rkt", "tests/gpu-dc-gui-test.rkt", "examples/skia-gpu-canvas.rkt")
SOURCES = (*HEADLESS, *GUI, "private/dc-render.rkt", "private/dc-class.rkt", "private/dc-alpha.rkt", "gpu-gui.rkt",
           "gpu.rkt", "info.rkt", "run-tests.rkt", "SOURCE-SHA256SUMS.txt",
           "tools/validate-gpu-dc.py", "tools/test-validate-gpu-dc.py")


def fingerprint(root: Path) -> dict[str, str]:
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in SOURCES}


def validate_suite(output: str, name: str) -> None:
    n = COUNTS[name]
    summaries = re.findall(r"^(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run$",
                           output, re.MULTILINE)
    markers = re.findall(rf"^{re.escape(name)}: (\d+) cases, (\d+) failures; .+$", output, re.MULTILINE)
    if summaries != [(str(n), "0", "0", str(n))] or markers != [(str(n), "0")]:
        raise ValueError(f"{name}: missing, partial, duplicated or failed completion result")
    if re.search(r"^(?:FAILURE|ERROR)$", output, re.MULTILINE):
        raise ValueError(f"{name}: printed failure cannot count as a pass")


def validate_identity(value: object) -> dict:
    if not isinstance(value, dict):
        raise ValueError("invalid Racket identity")
    version = value.get("version", "")
    if not isinstance(version, str) or re.fullmatch(r"\d+(?:\.\d+){1,3}", version) is None:
        raise ValueError("invalid Racket version")
    parts = tuple(map(int, version.split(".")))
    if parts + (0,) * (4 - len(parts)) < (8, 18, 0, 0):
        raise ValueError("Racket 8.18 or later is required")
    if (type(value.get("pointer_bytes")) is not int or value["pointer_bytes"] != 8
            or value.get("vm") != "chez-scheme"
            or value.get("architecture") not in ("x86_64", "aarch64")
            or value.get("os") not in ("unix", "macosx", "windows")):
        raise ValueError("this GPU gate requires a supported 64-bit Racket CS identity")
    return value


def select_backends(request: str, identity: dict) -> tuple[str, str]:
    native = request
    if native == "auto":
        native = {"macosx": "metal", "windows": "direct3d", "unix": "egl"}[identity["os"]]
    return native, "opengl" if native == "egl" else native


class Runner:
    def __init__(self, directory: Path, timeout: float):
        self.directory, self.timeout = directory, timeout
        self.commands: list[dict] = []
        (directory / "logs").mkdir()

    def run(self, argv, root: Path) -> str:
        args = [str(v) for v in argv]
        logfile = self.directory / "logs" / f"{len(self.commands) + 1:03}.log"
        entry = {"argv": args, "log": str(logfile.relative_to(self.directory))}
        self.commands.append(entry)
        print("+", subprocess.list2cmdline(args), flush=True)
        started = time.monotonic()
        try:
            result = subprocess.run(args, cwd=root,
                env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1", SKIA_SOURCE_SUMS_MODE="check"),
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=self.timeout, check=False)
            logfile.write_bytes(result.stdout)
            entry["returncode"] = result.returncode
            output = result.stdout.decode("utf-8", errors="replace")
            print(output, end="" if output.endswith("\n") else "\n", flush=True)
            if result.returncode != 0:
                raise RuntimeError(f"command exited {result.returncode}; see {logfile}")
            return output
        except subprocess.TimeoutExpired as exc:
            data = exc.output or b""
            if isinstance(data, str):
                data = data.encode("utf-8")
            logfile.write_bytes(data + b"\nTIMEOUT\n")
            entry["timed_out"] = True
            raise RuntimeError(f"command timed out; see {logfile}") from exc
        except OSError as exc:
            logfile.write_text(f"Could not execute command: {exc}\n", encoding="utf-8")
            entry["execution_error"] = str(exc)
            raise
        finally:
            entry["elapsed_seconds"] = time.monotonic() - started


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--racket", default="racket")
    p.add_argument("--backend", choices=("auto", "egl", "metal", "direct3d"), default="auto")
    p.add_argument("--adapter", choices=("hardware", "warp"), default=None)
    p.add_argument("--require-gui", action="store_true")
    p.add_argument("--directory", type=Path, help="new evidence directory; existing directories are rejected")
    p.add_argument("--timeout", type=float, default=300)
    return p


def main(argv=None, *, root: Path = ROOT) -> int:
    args = parser().parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser().error("--timeout must be a positive finite number")
    root = root.resolve()
    if args.directory:
        directory = args.directory.resolve()
        directory.mkdir(parents=True, exist_ok=False)
    else:
        (root / "output").mkdir(exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix="gpu-dc-0.59-", dir=root / "output"))
    runner = Runner(directory, args.timeout)
    result = {"schema": 1, "stage": "0.59", "status": "failed", "gui_required": args.require_gui,
              "native_gpu_tests_passed": False, "gui_tests_passed": False,
              "visible_screen_pixels_verified": False, "performance_measured": False,
              "completed_suites": [], "commands": runner.commands}
    try:
        racket = shutil.which(args.racket)
        if not racket:
            raise RuntimeError(f"selected Racket executable not found: {args.racket}")
        result["racket_executable"] = str(Path(racket).resolve())
        before = fingerprint(root)
        result["source_sha256"] = before
        runner.run([sys.executable, root / "tools/update-source-sums.py", "--check"], root)
        identity = validate_identity(json.loads(runner.run([racket, root / "tools/ci-identity.rkt"], root)))
        result["identity"] = identity
        native, gui = select_backends(args.backend, identity)
        if args.adapter is not None and native != "direct3d":
            raise ValueError("--adapter requires the Direct3D backend")
        result["native_backend"] = native
        result["gui_backend"] = gui if args.require_gui else None
        backend_args = ["--backend", native]
        gui_args = ["--backend", gui]
        if args.adapter is not None:
            backend_args += ["--adapter", args.adapter]
            gui_args += ["--adapter", args.adapter]
        runner.run([racket, "-l", "raco", "--", "make", *(root / p for p in HEADLESS)], root)
        for name, options in (("gpu-dc-pure", []), ("gpu-dc-native", backend_args)):
            validate_suite(runner.run([racket, root / f"tests/{name}-test.rkt", *options], root), name)
            result["completed_suites"].append({"name": name, "cases": COUNTS[name]})
        result["native_gpu_tests_passed"] = True
        if args.require_gui:
            runner.run([racket, "-l", "raco", "--", "make", *(root / p for p in GUI)], root)
            validate_suite(runner.run([racket, root / "tests/gpu-dc-gui-test.rkt", *gui_args], root), "gpu-dc-gui")
            result["completed_suites"].append({"name": "gpu-dc-gui", "cases": COUNTS["gpu-dc-gui"]})
            result["gui_tests_passed"] = True
        if fingerprint(root) != before:
            raise RuntimeError("source changed during validation")
        runner.run([sys.executable, root / "tools/update-source-sums.py", "--check"], root)
        result["status"] = "passed"
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
        print("GPU DC FAILED:", result["error"], file=sys.stderr)
    finally:
        (directory / "validation.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print("Evidence:", directory, flush=True)
    if result["status"] == "passed":
        print("GPU DC passed selected gates; GUI " + ("passed." if args.require_gui else "NOT RUN."))
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
