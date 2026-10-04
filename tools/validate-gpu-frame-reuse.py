#!/usr/bin/env python3
"""0.62 required staging-reuse gate. No driver-allocation or speedup claim.

Headless: require the complete 0.60 native consumer gate and new cache tests.
--require-gui (or --require-gpu): require the complete 0.61 common-API gate,
including 0.60 consumers, and inspect its ordinary GPU/auto frame reuse ledgers.
All commands use the selected interpreter; no failed backend becomes a skip.
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

import render_canvas_validation as gui_checks

ROOT = Path(__file__).resolve().parents[1]

def load(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

base = load("reuse_dc_baseline", "validate-gpu-dc.py")
render = load("reuse_render_baseline", "validate-render-canvas.py")
consumer = load("reuse_consumer_baseline", "validate-gpu-dc-consumers.py")
require = gui_checks.pixels.require
PURE_CASES = 32
NATIVE_CASES = 14
SOURCES = tuple(dict.fromkeys((*render.SOURCES, *consumer.SOURCES,
    "SOURCE-SHA256SUMS.txt",
    "private/gpu-presenter.rkt", "private/gpu-io-trace.rkt", "private/gpu-frame-target-cache.rkt",
    "tests/gpu-frame-target-pure-test.rkt", "tests/gpu-frame-target-native-test.rkt",
    "tools/validate-gpu-frame-reuse.py", "tools/test-gpu-frame-reuse.py")))


def fingerprint(root):
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in SOURCES}


def validate_measurements(output, backend):
    lines = re.findall(r"^gpu-frame-target-measurement: (.+)$", output, re.M)
    require(len(lines) == 2, "missing/duplicate constructor measurements")
    rows = [json.loads(line, object_pairs_hook=gui_checks.pixels.unique_object) for line in lines]
    require(all(type(row) is dict for row in rows), "measurement must be an object")
    require({row.get("mode") for row in rows} == {"reuse", "fresh"}, "wrong measurement modes")
    for row in rows:
        reuse = row["mode"] == "reuse"
        expected = dict(frames=32, creations=1 if reuse else 32, reuses=31 if reuse else 0,
                        retirements=0 if reuse else 32, live_targets=1 if reuse else 0, readbacks=0,
                        retirements_after_close=1 if reuse else 32, live_targets_after_close=0)
        for key, value in expected.items():
            require(type(row.get(key)) is int and row[key] == value, "wrong constructor measurement: " + key)
        require(row.get("backend") == backend, "foreign measurement backend")
        require(row.get("context_closed") is True, "context did not close after staging retirement")
        for key in ("busy", "closed", "quarantined"):
            require(row.get(key) is False, "invalid pre-close cache state: " + key)
    return rows


def validate_baseline(value, identity, backend, gui):
    require(type(value) is dict and value.get("status") == "passed", "baseline failed")
    require(value.get("identity") == identity, "foreign baseline identity")
    require(value.get("stage") == ("0.61" if gui else "0.60"), "wrong baseline stage")
    if gui:
        for field in ("gui_required", "gpu_required", "pure_passed", "raster_baseline_passed", "gpu_baseline_passed"):
            require(value.get(field) is True, "incomplete baseline: " + field)
        rows = value.get("completed_renderers")
        require(type(rows) is list and len(rows) == 3, "incomplete renderer matrix")
        _, explicit_gui = base.select_backends(backend, identity)
        _, auto_gui = base.select_backends("auto", identity)
        wanted = [dict(requested_renderer=r, backend=b, cases=20, captures=24, bounded_comparisons=8)
                  for r, b in (("raster", "raster"), ("gpu", explicit_gui), ("auto", auto_gui))]
        # Exact integer fields, not Python's True == 1 coercion.
        require(rows == wanted and all(type(row.get(k)) is int for row in rows
                                       for k in ("cases", "captures", "bounded_comparisons")),
                "incomplete/wrong renderer acceptance matrix")
        require(type(value.get("run_token")) is str and bool(value["run_token"]), "missing baseline run token")
    else:
        require(value.get("native_backend") == backend, "foreign native baseline")
        for field in ("baseline_passed", "native_consumers_passed"):
            require(value.get(field) is True, "incomplete baseline: " + field)
        require(value.get("gui_required") is False and value.get("gui_consumers_passed") is False,
                "headless baseline must not claim GUI")
        for key, count in (("native_capture_count", 144), ("native_bounded_comparisons", 96)):
            require(type(value.get(key)) is int and value[key] == count, "incomplete baseline: " + key)


def inspect_gui_reuse(directory, baseline, identity, adapter):
    """Read the real 0.61 reports; retain their geometry/expiry/pixel contracts."""
    worker_identity = {k: identity[k] for k in ("version", "os", "architecture", "vm")}
    results = []
    for selected in baseline["completed_renderers"]:
        request, backend = selected["requested_renderer"], selected["backend"]
        report = gui_checks.pixels.read_json(directory / request / "result.json")
        rows = gui_checks.validate_report(report, request, backend, baseline["run_token"], worker_identity,
                                         adapter if request != "raster" else None)
        if request == "raster":
            continue
        sizes = {}
        for row in rows:
            # Old checks already require one presentation and no implicit readback.
            events = [e for e in row["draw_io"] if e["kind"] == "dc-frame-target"]
            require(all(e.get("action") in ("create", "reuse", "retire") for e in events), "unknown target action")
            borrows = [e for e in events if e["action"] in ("create", "reuse")]
            require(len(borrows) == 1, "ordinary frame did not acquire exactly one staging target")
            event, extent = borrows[0], row["extent"]
            for name in ("pixel_width", "pixel_height"):
                require(type(event.get(name)) is int and event[name] == extent[name], "staging target size mismatch")
            counts = sizes.setdefault(extent["name"], dict(create=0, reuse=0))
            counts[event["action"]] += 1
        require(set(sizes) == {"small", "large"}, "missing reused GUI size")
        for size, counts in sizes.items():
            # Exposures may warm the cache before a recorded normal frame.
            # At most the first of twelve equal-sized normal frames may create.
            require(counts["create"] + counts["reuse"] == 12 and counts["create"] <= 1 and counts["reuse"] >= 11,
                    f"staging is not reused across {request}/{size} consumer frames")
        results.append(dict(renderer=request, backend=backend, normal_frames=24, sizes=sizes))
    require(len(results) == 2, "GPU and automatic GUI reuse are both required")
    return results


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--racket", default=os.environ.get("RACKET", "racket"))
    p.add_argument("--backend", choices=("auto", "egl", "metal", "direct3d"), default="auto")
    p.add_argument("--adapter", choices=("hardware", "warp"))
    p.add_argument("--require-gui", "--require-gpu", dest="require_gui", action="store_true")
    p.add_argument("--directory", type=Path)
    p.add_argument("--timeout", type=float, default=600)
    return p


def main(argv=None, *, root=ROOT):
    args = parser().parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser().error("--timeout must be finite and positive")
    root = root.resolve()
    if args.directory:
        directory = args.directory.resolve()
        directory.mkdir(parents=True, exist_ok=False)
    else:
        (root / "output").mkdir(exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix="gpu-frame-reuse-0.62-", dir=root / "output"))
    runner = base.Runner(directory, args.timeout)
    result = dict(schema=1, stage="0.62", status="failed", gui_required=args.require_gui,
                  pure_passed=False, baseline_passed=False, native_reuse_passed=False,
                  gui_reuse_passed=False, physical_display_verified=False, performance_measured=False,
                  driver_allocations_measured=False, commands=runner.commands)
    try:
        executable = shutil.which(args.racket)
        require(executable is not None, "selected Racket executable not found")
        racket = str(Path(executable).resolve())
        result["racket_executable"] = racket
        before = fingerprint(root)
        runner.run([sys.executable, root / "tools/update-source-sums.py", "--check"], root)
        identity = base.validate_identity(json.loads(runner.run([racket, root / "tools/ci-identity.rkt"], root),
                                                     object_pairs_hook=gui_checks.pixels.unique_object))
        native, _ = base.select_backends(args.backend, identity)
        require(args.adapter is None or native == "direct3d", "--adapter requires Direct3D")
        result.update(identity=identity, native_backend=native)
        modules = ("private/gpu-frame-target-cache.rkt", "private/gpu-presenter.rkt", "private/gpu-dc-native.rkt",
                   "tests/gpu-frame-target-pure-test.rkt", "tests/gpu-frame-target-native-test.rkt")
        runner.run([racket, "-l", "raco", "--", "make", *(root / p for p in modules)], root)
        gui_checks.validate_suite(runner.run([racket, root / "tests/gpu-frame-target-pure-test.rkt"], root),
                                  "gpu-frame-target-pure", PURE_CASES)
        result["pure_passed"] = True
        options = ["--backend", native] + (["--adapter", args.adapter] if args.adapter else [])
        baseline_name = "validate-render-canvas.py" if args.require_gui else "validate-gpu-dc-consumers.py"
        baseline_cmd = [sys.executable, root / "tools" / baseline_name, "--racket", racket,
                        *options, "--directory", directory / "baseline", "--timeout", str(args.timeout)]
        if args.require_gui:
            baseline_cmd.append("--require-gpu")
        runner.timeout = args.timeout * 24
        try:
            runner.run(baseline_cmd, root)
        finally:
            runner.timeout = args.timeout
        baseline = gui_checks.pixels.read_json(directory / "baseline/validation.json")
        validate_baseline(baseline, identity, native, args.require_gui)
        result["baseline_passed"] = True
        output = runner.run([racket, root / "tests/gpu-frame-target-native-test.rkt", *options], root)
        gui_checks.validate_suite(output, "gpu-frame-target-native", NATIVE_CASES)
        result["constructor_measurements"] = validate_measurements(output, native)
        result["native_reuse_passed"] = True
        if args.require_gui:
            result["gui_reuse"] = inspect_gui_reuse(directory / "baseline", baseline, identity, args.adapter)
            result["gui_reuse_passed"] = True
        require(fingerprint(root) == before, "source changed during validation")
        runner.run([sys.executable, root / "tools/update-source-sums.py", "--check"], root)
        result.update(status="passed", source_sha256=before)
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
        print("GPU frame reuse FAILED:", result["error"], file=sys.stderr)
    finally:
        (directory / "validation.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print("Evidence:", directory, flush=True)
    if result["status"] == "passed":
        print("GPU frame reuse passed; " + ("real GUI reuse verified." if args.require_gui else "GUI NOT RUN."))
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
