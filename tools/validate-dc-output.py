#!/usr/bin/env python3
"""Compile and validate 0.63 PDF/SVG DC output; selected tests never silently skip.

Default: native Racket tests plus parsed PDF/SVG structure, text and annotations.
--require-renderers also requires independent Poppler/librsvg pixel acceptance.
"""
from __future__ import annotations
from validation_regressions import RegressionGate, add_regression_argument, checked_mode, global_compile_targets
import argparse
import hashlib
import importlib.util
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
import uuid

import dc_output_validation as checks

ROOT = Path(__file__).resolve().parents[1]
COUNTS = {"dc-output-pure": 34, "dc-output-native": 22}
SOURCES = (
    "dc-output.rkt", "private/dc-output-capture.rkt", "private/dc-output-native.rkt",
    "private/dc-render.rkt", "private/dc-text.rkt", "private/dc-style-render.rkt",
    "private/dc-class.rkt", "private/dc-support.rkt", "private/dc-alpha.rkt",
    "private/dc-styles.rkt", "private/dc-bitmap.rkt", "private/dc-region-adapter.rkt",
    "private/core.rkt", "private/output-util.rkt", "private/output-group-util.rkt", "output-groups.rkt",
    "output-policy.rkt", "output-audit.rkt", "output.rkt", "annotations.rkt",
    "tests/dc-output-pure-test.rkt", "tests/dc-output-native-test.rkt",
    "tests/dc-output-fixtures.rkt", "tests/dc-consumer-fixtures.rkt", "tests/dc-style-fixtures.rkt",
    "tools/dc-output-doctor.rkt", "examples/dc-output.rkt", "tools/dc_output_validation.py",
    "tools/validate-dc-output.py", "tools/test-dc-output.py", "tools/dc-output-requirements.txt",
    "tools/update-source-sums.py", "tools/ci-identity.rkt", "tools/validate-dc.py",
    "info.rkt", "run-tests.rkt", "SOURCE-SHA256SUMS.txt")


def fingerprint(root: Path):
    return {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in SOURCES}


def suite_output(text: str, name: str):
    n = COUNTS[name]
    summary = re.findall(r"^(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run$", text, re.M)
    marker = re.findall(rf"^{re.escape(name)}: (\d+) cases, (\d+) failures$", text, re.M)
    checks.require(summary == [(str(n), "0", "0", str(n))] and marker == [(str(n), "0")],
                   name+": missing, duplicate or failed completion")
    checks.require(re.search(r"^(?:FAILURE|ERROR|FAILED)(?:\b|:)", text, re.M) is None,
                   name+": printed failure")


def worker_output(text):
    found = re.findall(r"^dc-output-documents: (\d+) documents; passed\.$", text, re.M)
    checks.require(found == [str(len(checks.SPECS))], "incomplete document worker output")
    checks.require(re.search(r"^(?:FAILURE|ERROR|FAILED)(?:\b|:)", text, re.M) is None,
                   "document worker printed failure")


def identity(value):
    checks.require(type(value) is dict and value.get("vm") == "chez-scheme"
                   and type(value.get("pointer_bytes")) is int and value["pointer_bytes"] == 8
                   and value.get("os") in ("macosx", "windows", "unix")
                   and value.get("architecture") in ("aarch64", "x86_64"), "require supported 64-bit Racket CS")
    version = value.get("version", "")
    checks.require(type(version) is str and re.fullmatch(r"\d+(?:\.\d+){1,3}", version) is not None,
                   "invalid Racket version")
    parts = tuple(map(int, version.split(".")))
    checks.require(parts+(0,)*(4-len(parts)) >= (8, 18, 0, 0), "require Racket 8.18 or later")
    return value


class Runner:
    def __init__(self, directory: Path, timeout: float):
        self.directory, self.timeout, self.commands = directory, timeout, []
        (directory/"logs").mkdir()

    def run(self, argv, root: Path):
        command = list(map(str, argv))
        file = self.directory/"logs"/f"{len(self.commands)+1:03}.log"
        entry = dict(argv=command, cwd=str(root), log=str(file.relative_to(self.directory)))
        self.commands.append(entry)
        print("+", subprocess.list2cmdline(command), flush=True)
        start = time.monotonic()
        try:
            process = subprocess.run(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1", SKIA_SOURCE_SUMS_MODE="check"),
                timeout=self.timeout, check=False)
            file.write_bytes(process.stdout)
            text = process.stdout.decode("utf-8", errors="replace")
            print(text, end="" if text.endswith("\n") else "\n", flush=True)
            entry["returncode"] = process.returncode
            if process.returncode:
                raise RuntimeError(f"command exited {process.returncode}; see {file}")
            return text
        except subprocess.TimeoutExpired as exc:
            file.write_bytes(exc.stdout or b"")
            entry["timed_out"] = True
            raise RuntimeError(f"command timed out; see {file}") from exc
        except OSError as exc:
            file.write_text(str(exc), encoding="utf-8")
            entry["launch_error"] = str(exc)
            raise
        finally:
            entry["elapsed_seconds"] = time.monotonic()-start
            (self.directory/"commands.json").write_text(json.dumps(self.commands, indent=2)+"\n", encoding="utf-8")


def dependencies():
    import pypdf
    import PIL
    return dict(pypdf=pypdf.__version__, pillow=PIL.__version__)


def main(argv=None, *, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    add_regression_argument(parser)
    parser.add_argument("--racket", default=os.environ.get("RACKET", "racket"))
    parser.add_argument("--directory", type=Path)
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("--require-renderers", action="store_true")
    args = parser.parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be positive and finite")
    root = Path(root).resolve()
    if args.directory:
        directory = args.directory.resolve()
        directory.mkdir(parents=True, exist_ok=False)
    else:
        (root/"output").mkdir(exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix="dc-output-0.63-", dir=root/"output"))
    runner = Runner(directory, args.timeout)
    token = uuid.uuid4().hex
    result = dict(schema=1, stage="0.63", status="failed", run_token=token,
                  renderers_required=args.require_renderers, independent_pixels_verified=False,
                  baseline_passed=False, native_tests_passed=False, structure_passed=False,
                  physical_display_verified=False, pdfa_certified=False, color_fidelity_certified=False,
                  commands=runner.commands)
    regressions = RegressionGate(args.regressions, result)
    try:
        result["inspector_versions"] = dependencies()
        executable = shutil.which(args.racket)
        checks.require(executable is not None, "selected Racket executable not found")
        racket = str(Path(executable).resolve())
        result["racket_executable"] = racket
        renderers = {}
        if args.require_renderers:
            for name in ("pdftoppm", "rsvg-convert"):
                resolved = shutil.which(name)
                checks.require(resolved is not None, "required independent renderer missing: "+name)
                renderers[name] = str(Path(resolved).resolve())
            result["renderers"] = renderers
        before = fingerprint(root)
        manifest = [sys.executable, root/"tools/update-source-sums.py", "--check"]
        runner.run(manifest, root)
        ident = identity(json.loads(runner.run([racket, root/"tools/ci-identity.rkt"], root), object_pairs_hook=checks.unique))
        result["identity"] = ident
        modules = ["dc-output.rkt", "tests/dc-output-pure-test.rkt", "tests/dc-output-native-test.rkt",
                   "tools/dc-output-doctor.rkt", "examples/dc-output.rkt"]
        runner.run([racket, "-l", "raco", "--", "make", *[root/p for p in modules]], root)
        result["compiled"] = True
        # Only the global suite is optional. The DC-specific baseline and all
        # document suites/inspectors below remain mandatory in both modes.
        regressions.run(lambda: runner.run([racket, root/"run-tests.rkt"], root))
        runner.run([sys.executable, root/"tools/validate-dc.py", "--racket", racket], root)
        result["baseline_passed"] = True
        for name in COUNTS:
            suite_output(runner.run([racket, root/f"tests/{name}-test.rkt"], root), name)
        result["native_tests_passed"] = True
        result["suites"] = dict(COUNTS)
        documents = directory/"documents"
        worker_output(runner.run([racket, root/"tools/dc-output-doctor.rkt", "--directory", documents,
                                  "--run-token", token], root))
        rows = checks.validate_receipt(checks.read_json(documents/"documents.json"), token,
                                      {k: ident[k] for k in ("version", "os", "architecture", "vm")})
        inspected = []
        for row in rows:
            source = checks.safe_file(documents, row["file"])
            data = checks.inspect_document(source, row)
            if args.require_renderers:
                prefix = documents/(row["id"]+"-render")
                png = prefix.with_name(prefix.name+".png")
                if row["format"] == "pdf":
                    runner.run([renderers["pdftoppm"], "-f", "1", "-l", "1", "-singlefile", "-r", "144",
                                "-png", source, prefix], root)
                else:
                    runner.run([renderers["rsvg-convert"], "--format=png", "--width", math.ceil(row["width_points"]*2),
                                "--height", math.ceil(row["height_points"]*2), "--output", png, source], root)
                data["render"] = checks.inspect_pixels(png, row)
            inspected.append(data)
        (documents/"inspection.json").write_text(json.dumps(inspected, indent=2)+"\n", encoding="utf-8")
        checks.write_review(documents, rows, inspected)
        result["document_count"] = len(inspected)
        result["structure_passed"] = True
        result["independent_pixels_verified"] = bool(args.require_renderers)
        checks.require(fingerprint(root) == before, "source changed during document validation")
        runner.run(manifest, root)
        result.update(status="passed", source_sha256=before)
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
        print("DC output FAILED:", result["error"], file=sys.stderr)
    finally:
        (directory/"validation.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
        print("Evidence:", directory, flush=True)
    if result["status"] == "passed":
        print("DC output passed: 24 native documents; "+
              ("independent PDF/SVG pixels passed." if args.require_renderers else "independent rasterizers NOT RUN."))
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
