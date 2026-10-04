#!/usr/bin/env python3
"""0.61 unified canvas gate. Default: headless pure policy/callback tests.

--require-gui requires the old raster canvas gate and new real raster GUI tests.
--require-gpu additionally requires the complete 0.60 native/GUI consumer gate
and tests the common API with both explicit GPU and automatic renderer choice.
All selected gates are mandatory. Every execution uses the chosen interpreter.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import sys
import tempfile
import uuid

import render_canvas_validation as checks

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("render_gpu_base", Path(__file__).with_name("validate-gpu-dc.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
SOURCES = tuple(dict.fromkeys((*base.SOURCES,
    "render-canvas.rkt", "private/render-canvas-policy.rkt", "private/render-canvas-state.rkt",
    "tests/render-canvas-pure-test.rkt", "tests/render-canvas-gui-test.rkt", "examples/render-canvas.rkt",
    "canvas.rkt", "private/canvas-backing.rkt", "tests/gpu-dc-consumer-fixtures.rkt",
    "tests/dc-consumer-fixtures.rkt", "tests/dc-style-fixtures.rkt",
    "tools/validate-skia-canvas.py", "tools/validate-gpu-dc-consumers.py",
    "tools/gpu_dc_consumer_validation.py", "tools/render_canvas_validation.py",
    "tools/validate-render-canvas.py", "tools/test-render-canvas.py", ".github/workflows/render-canvas.yml")))


def fingerprint(root: Path) -> dict[str, str]:
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in SOURCES}


def validate_raster_baseline(value: dict, identity: dict) -> None:
    require = checks.pixels.require
    require(value.get("stage") == "0.58" and value.get("status") == "passed", "raster baseline failed")
    require(value.get("identity") == identity, "foreign raster baseline identity")
    require(type(value.get("checks")) is dict, "missing raster baseline checks")
    for name in ("pure_lifecycle", "native_pixels_and_bitmap_bridge", "required_gui", "text_load_orders", "source_unchanged"):
        require(value["checks"].get(name) is True, "incomplete raster baseline: " + name)
    require(value.get("gui", {}).get("status") == "passed", "raster GUI baseline missing")


def validate_gpu_baseline(value: dict, identity: dict, backend: str) -> None:
    require = checks.pixels.require
    require(value.get("stage") == "0.60" and value.get("status") == "passed", "GPU consumer baseline failed")
    require(value.get("identity") == identity and value.get("native_backend") == backend, "foreign GPU baseline")
    for flag in ("baseline_passed", "native_consumers_passed", "gui_consumers_passed", "gui_required"):
        require(value.get(flag) is True, "incomplete GPU baseline: " + flag)
    for key, n in (("native_capture_count", 144), ("gui_capture_count", 48),
                   ("native_bounded_comparisons", 96), ("gui_bounded_comparisons", 16)):
        require(type(value.get(key)) is int and value[key] == n, "incomplete GPU baseline: " + key)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--racket", default=os.environ.get("RACKET", "racket"))
    p.add_argument("--backend", choices=("auto", "egl", "metal", "direct3d"), default="auto")
    p.add_argument("--adapter", choices=("hardware", "warp"))
    p.add_argument("--require-gui", action="store_true")
    p.add_argument("--require-gpu", action="store_true")
    p.add_argument("--directory", type=Path)
    p.add_argument("--timeout", type=float, default=600)
    return p


def main(argv=None, *, root: Path = ROOT) -> int:
    args = parser().parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser().error("--timeout must be a positive finite number")
    if not args.require_gpu and (args.backend != "auto" or args.adapter):
        parser().error("--backend and --adapter require --require-gpu")
    root = root.resolve()
    if args.directory:
        directory = args.directory.absolute()
        directory.mkdir(parents=True, exist_ok=False)
    else:
        (root / "output").mkdir(exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix="render-canvas-0.61-", dir=root / "output"))
    runner = base.Runner(directory, args.timeout)
    token = uuid.uuid4().hex
    gui = args.require_gui or args.require_gpu
    result = dict(schema=1, stage="0.61", status="failed", run_token=token,
                  gui_required=gui, gpu_required=args.require_gpu, pure_passed=False,
                  raster_baseline_passed=False, gpu_baseline_passed=False,
                  completed_renderers=[], physical_display_verified=False,
                  performance_measured=False, commands=runner.commands)
    try:
        racket = shutil.which(args.racket)
        if not racket:
            raise RuntimeError(f"selected Racket executable not found: {args.racket}")
        racket = str(Path(racket).resolve())
        result["racket_executable"] = racket
        before = fingerprint(root)
        runner.run([sys.executable, root / "tools/update-source-sums.py", "--check"], root)
        identity = base.validate_identity(json.loads(runner.run([racket, root / "tools/ci-identity.rkt"], root), object_pairs_hook=checks.pixels.unique_object))
        result["identity"] = identity
        native, gpu_backend = base.select_backends(args.backend, identity)
        if args.adapter and native != "direct3d":
            raise ValueError("--adapter requires Direct3D")
        runner.run([racket, "-l", "raco", "--", "make", root / "tests/render-canvas-pure-test.rkt"], root)
        checks.validate_suite(runner.run([racket, root / "tests/render-canvas-pure-test.rkt"], root), "render-canvas-pure", checks.PURE_CASES)
        result["pure_passed"] = True
        if gui:
            # Explicitly compile both the new module and interactive example.
            # An uncompiled example caused the 0.60 package-install failure.
            runner.run([racket, "-l", "raco", "--", "make", root / "render-canvas.rkt",
                        root / "tests/render-canvas-gui-test.rkt", root / "examples/render-canvas.rkt",
                        root / "examples/gpu-dc-consumers.rkt"], root)
            runner.timeout = args.timeout * 24
            try:
                runner.run([sys.executable, root / "tools/validate-skia-canvas.py", "--racket", racket,
                            "--require-gui", "--output", directory / "raster-baseline"], root)
                validate_raster_baseline(checks.pixels.read_json(directory / "raster-baseline/validation.json"), identity)
                result["raster_baseline_passed"] = True
                if args.require_gpu:
                    opts = ["--backend", native]
                    if args.adapter: opts += ["--adapter", args.adapter]
                    runner.run([sys.executable, root / "tools/validate-gpu-dc-consumers.py", "--racket", racket,
                                *opts, "--require-gui", "--directory", directory / "gpu-baseline", "--timeout", args.timeout], root)
                    validate_gpu_baseline(checks.pixels.read_json(directory / "gpu-baseline/validation.json"), identity, native)
                    result["gpu_baseline_passed"] = True
            finally:
                runner.timeout = args.timeout
            worker_identity = {k: identity[k] for k in ("version", "os", "architecture", "vm")}
            for renderer in (["raster", "gpu", "auto"] if args.require_gpu else ["raster"]):
                backend = ("raster" if renderer == "raster" else
                           base.select_backends("auto", identity)[1] if renderer == "auto" else gpu_backend)
                requested_backend = "auto" if renderer in ("raster", "auto") else gpu_backend
                command = [racket, root / "tests/render-canvas-gui-test.rkt", "--renderer", renderer,
                           "--backend", requested_backend, "--directory", directory / renderer, "--run-token", token]
                if renderer != "raster" and args.adapter: command += ["--adapter", args.adapter]
                checks.validate_suite(runner.run(command, root), "render-canvas-gui", checks.GUI_CASES)
                inspected = checks.inspect_directory(directory / renderer, renderer, backend, token, worker_identity,
                                                     args.adapter if renderer != "raster" else None)
                result["completed_renderers"].append(dict(requested_renderer=renderer, backend=backend,
                    cases=checks.GUI_CASES, captures=len(inspected["captures"]),
                    bounded_comparisons=len(inspected["bounded_comparisons"])))
        if fingerprint(root) != before:
            raise RuntimeError("source changed during validation")
        runner.run([sys.executable, root / "tools/update-source-sums.py", "--check"], root)
        result.update(status="passed", source_sha256=before)
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
        print("Unified canvas FAILED:", result["error"], file=sys.stderr)
    finally:
        (directory / "validation.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print("Evidence:", directory, flush=True)
    if result["status"] == "passed":
        print("Unified canvas selected gates passed; " + ("GUI tested." if gui else "GUI and GPU NOT RUN."))
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
