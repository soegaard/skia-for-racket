#!/usr/bin/env python3
"""0.64 DC compatibility gate: real contract/font tests and 0.63 documents.

--require-renderers additionally requires independent PDF/SVG pixel checks.
--require-gui additionally requires the complete 0.62 GPU/raster/auto GUI gate.
All Racket commands use one resolved interpreter. Selected gates cannot skip.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("closure_runner_base", Path(__file__).with_name("validate-gpu-dc.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
COUNTS = {"dc-closure-pure": 35, "dc-closure-native": 22}
MODULES = ("dc.rkt", "private/dc-font-name-native.rkt", "examples/dc-closure.rkt",
           "tests/dc-closure-pure-test.rkt", "tests/dc-closure-native-test.rkt")
SOURCES = (*MODULES, "private/dc-font-name.rkt", "private/dc-text-spec.rkt", "private/dc-text.rkt",
           "private/dc-compatibility.rkt", "tests/dc-consumer-fixtures.rkt", "run-tests.rkt", "info.rkt",
           "SOURCE-SHA256SUMS.txt", "tools/validate-dc-closure.py", "tools/test-dc-closure.py",
           "tools/validate-dc-output.py", "tools/validate-gpu-frame-reuse.py")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key: " + key)
        result[key] = value
    return result


def read_report(path: Path) -> dict:
    require(path.is_file() and not path.is_symlink(), "missing or linked baseline report")
    def nonfinite(value):
        raise ValueError("nonfinite JSON value: " + value)
    result = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique, parse_constant=nonfinite)
    require(type(result) is dict, "invalid baseline report")
    return result


def fingerprint(root: Path) -> dict:
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in SOURCES}


def validate_suite(text: str, name: str) -> None:
    text = text.replace("\r\n", "\n")
    n = str(COUNTS[name])
    summaries = re.findall(r"^(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run$", text, re.M)
    markers = re.findall(rf"^{re.escape(name)}: (\d+) cases, (\d+) failures$", text, re.M)
    require(summaries == [(n, "0", "0", n)] and markers == [(n, "0")],
            name + ": incomplete, duplicate, or failed result")
    require(not re.search(r"^(?:FAILURE|ERROR)\s*$", text, re.M), name + ": printed failure")


def validate_document_baseline(report: dict, identity: dict, racket: str, rendered: bool) -> None:
    require(type(report.get("schema")) is int and report["schema"] == 1, "bad document baseline schema")
    require(report.get("physical_display_verified") is False, "invalid document display claim")
    require(report.get("stage") == "0.63" and report.get("status") == "passed", "document baseline failed")
    require(report.get("identity") == identity and report.get("racket_executable") == racket, "foreign document baseline")
    for flag in ("compiled", "baseline_passed", "native_tests_passed", "structure_passed"):
        require(report.get(flag) is True, "incomplete document baseline: " + flag)
    require(type(report.get("document_count")) is int and report["document_count"] == 24, "incomplete document matrix")
    require(report.get("suites") == {"dc-output-pure": 34, "dc-output-native": 22}, "incomplete document suites")
    require(report.get("renderers_required") is rendered and report.get("independent_pixels_verified") is rendered,
            "incorrect document pixel claim")


def validate_gui_baseline(report: dict, identity: dict, racket: str, backend: str) -> None:
    require(type(report.get("schema")) is int and report["schema"] == 1, "bad GUI baseline schema")
    require(report.get("physical_display_verified") is False, "invalid GUI display claim")
    require(report.get("stage") == "0.62" and report.get("status") == "passed", "GUI baseline failed")
    require(report.get("identity") == identity and report.get("racket_executable") == racket, "foreign GUI baseline")
    require(report.get("native_backend") == backend, "wrong GUI backend")
    for flag in ("gui_required", "pure_passed", "baseline_passed", "native_reuse_passed", "gui_reuse_passed"):
        require(report.get(flag) is True, "incomplete GUI baseline: " + flag)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--racket", default=os.environ.get("RACKET", "racket"))
    p.add_argument("--require-renderers", action="store_true")
    p.add_argument("--require-gui", action="store_true")
    p.add_argument("--backend", choices=("auto", "egl", "metal", "direct3d"), default="auto")
    p.add_argument("--adapter", choices=("hardware", "warp"))
    p.add_argument("--directory", type=Path)
    p.add_argument("--timeout", type=float, default=600)
    return p


def main(argv=None, *, root: Path = ROOT) -> int:
    args = parser().parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser().error("--timeout must be positive and finite")
    if not args.require_gui and (args.backend != "auto" or args.adapter):
        parser().error("--backend and --adapter require --require-gui")
    root = root.resolve()
    if args.directory:
        directory = args.directory.resolve()
        directory.mkdir(parents=True, exist_ok=False)
    else:
        (root / "output").mkdir(exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix="dc-closure-0.64-", dir=root / "output"))
    runner = base.Runner(directory, args.timeout)
    result = dict(schema=1, stage="0.64", status="failed", compiled=False, completed_suites=[],
                  document_baseline_passed=False, gui_baseline_passed=False,
                  gui_required=args.require_gui, renderers_required=args.require_renderers,
                  independent_pixels_verified=False, physical_display_verified=False,
                  full_drop_in_compatibility=False, commands=runner.commands)
    try:
        executable = shutil.which(args.racket)
        require(executable is not None, "selected Racket executable not found")
        racket = str(Path(executable).resolve())
        result["racket_executable"] = racket
        before = fingerprint(root)
        manifest = [sys.executable, root / "tools/update-source-sums.py", "--check"]
        runner.run(manifest, root)
        identity = base.validate_identity(json.loads(runner.run([racket, root / "tools/ci-identity.rkt"], root), object_pairs_hook=unique))
        result["identity"] = identity
        native, _ = base.select_backends(args.backend, identity)
        result["native_backend"] = native if args.require_gui else None
        require(args.adapter is None or native == "direct3d", "--adapter requires Direct3D")
        runner.run([racket, "-l", "raco", "--", "make", *(root / name for name in MODULES)], root)
        result["compiled"] = True
        for name, n in COUNTS.items():
            validate_suite(runner.run([racket, root / f"tests/{name}-test.rkt"], root), name)
            result["completed_suites"].append(dict(name=name, cases=n))
        # Earlier validators remain responsible for their complete matrices,
        # resource checks, and independent oracles; they are not reimplemented.
        runner.timeout = args.timeout * 32
        command = [sys.executable, root / "tools/validate-dc-output.py", "--racket", racket,
                   "--directory", directory / "documents", "--timeout", args.timeout]
        if args.require_renderers:
            command.append("--require-renderers")
        runner.run(command, root)
        validate_document_baseline(read_report(directory / "documents/validation.json"), identity, racket, args.require_renderers)
        result["document_baseline_passed"] = True
        result["independent_pixels_verified"] = args.require_renderers
        if args.require_gui:
            command = [sys.executable, root / "tools/validate-gpu-frame-reuse.py", "--racket", racket,
                       "--backend", native, "--require-gui", "--directory", directory / "gui", "--timeout", args.timeout]
            if args.adapter:
                command += ["--adapter", args.adapter]
            runner.run(command, root)
            validate_gui_baseline(read_report(directory / "gui/validation.json"), identity, racket, native)
            result["gui_baseline_passed"] = True
        runner.timeout = args.timeout
        require(fingerprint(root) == before, "source changed during validation")
        runner.run(manifest, root)
        result.update(status="passed", source_sha256=before)
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
        print("DC compatibility FAILED:", result["error"], file=sys.stderr)
    finally:
        (directory / "validation.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print("Evidence:", directory, flush=True)
    if result["status"] == "passed":
        print("DC compatibility selected gates passed; GUI " + ("passed." if args.require_gui else "NOT RUN."))
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
