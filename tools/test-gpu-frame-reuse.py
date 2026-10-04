#!/usr/bin/env python3
"""Synthetic 0.62 gate/receipt tests and source contracts; not GPU execution."""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent

def load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

v = load("frame_reuse_runner", "validate-gpu-frame-reuse.py")
f = load("frame_reuse_fixtures", "test-render-canvas.py")
FULL = f.FULL
TOKEN = f.TOKEN


def measurements(backend="egl"):
    return [dict(mode=mode, backend=backend, frames=32, creations=1 if reuse else 32,
                 reuses=31 if reuse else 0, retirements=0 if reuse else 32,
                 live_targets=1 if reuse else 0, readbacks=0, context_closed=True,
                 retirements_after_close=1 if reuse else 32, live_targets_after_close=0,
                 busy=False, closed=False, quarantined=False)
            for mode, reuse in (("reuse", True), ("fresh", False))]


def measurement_output(rows=None):
    return "".join("gpu-frame-target-measurement: " + json.dumps(row) + "\n" for row in (rows if rows is not None else measurements()))


def baseline(gui=True):
    if not gui:
        return dict(stage="0.60", status="passed", identity=FULL, native_backend="egl", baseline_passed=True,
                    native_consumers_passed=True, gui_required=False, gui_consumers_passed=False,
                    native_capture_count=144, native_bounded_comparisons=96)
    return dict(stage="0.61", status="passed", identity=FULL, run_token=TOKEN,
                gui_required=True, gpu_required=True, pure_passed=True,
                raster_baseline_passed=True, gpu_baseline_passed=True,
                completed_renderers=[dict(requested_renderer=r, backend="raster" if r == "raster" else "opengl",
                                          cases=20, captures=24, bounded_comparisons=8) for r in ("raster", "gpu", "auto")])


def gui_report(request="gpu"):
    report = f.report(request)
    if request != "raster":
        for row in report["captures"]:
            row["draw_io"].append(dict(kind="dc-frame-target", action="reuse", reason="compatible-extent",
                                       pixel_width=row["extent"]["pixel_width"], pixel_height=row["extent"]["pixel_height"]))
    return report


class Measurements(unittest.TestCase):
    def bad(self, change):
        rows = measurements(); change(rows)
        with self.assertRaises((ValueError, TypeError)): v.validate_measurements(measurement_output(rows), "egl")
    def test_valid(self): self.assertEqual(len(v.validate_measurements(measurement_output(), "egl")), 2)
    def test_backend(self): self.bad(lambda r: r[0].update(backend="metal"))
    def test_missing(self): self.bad(lambda r: r.pop())
    def test_duplicate(self): self.bad(lambda r: r.append(r[0]))
    def test_wrong_modes(self): self.bad(lambda r: r[0].update(mode="fresh"))
    def test_unknown_mode(self): self.bad(lambda r: r[0].update(mode="cached"))
    def test_no_constructor_reduction(self): self.bad(lambda r: r[0].update(creations=32))
    def test_no_cache_hits(self): self.bad(lambda r: r[0].update(reuses=0))
    def test_wrong_fresh_count(self): self.bad(lambda r: r[1].update(creations=1))
    def test_boolean_count(self): self.bad(lambda r: r[0].update(creations=True))
    def test_partial_frame_count(self): self.bad(lambda r: r[0].update(frames=31))
    def test_readback(self): self.bad(lambda r: r[0].update(readbacks=1))
    def test_not_closed(self): self.bad(lambda r: r[0].update(context_closed=False))
    def test_retained_after_close(self): self.bad(lambda r: r[0].update(live_targets_after_close=1))
    def test_missing_retirement(self): self.bad(lambda r: r[0].update(retirements_after_close=0))
    def test_quarantined(self): self.bad(lambda r: r[0].update(quarantined=True))
    def test_busy(self): self.bad(lambda r: r[0].update(busy=True))
    def test_duplicate_json_key(self):
        output = measurement_output().replace('"frames": 32', '"frames": 32, "frames": 32', 1)
        with self.assertRaises(ValueError): v.validate_measurements(output, "egl")


class Baseline(unittest.TestCase):
    def bad(self, change, gui=True):
        value = baseline(gui); change(value)
        with self.assertRaises((ValueError, TypeError)): v.validate_baseline(value, FULL, "egl", gui)
    def test_both_modes(self):
        for gui in (True, False): v.validate_baseline(baseline(gui), FULL, "egl", gui)
    def test_failed(self): self.bad(lambda r: r.update(status="failed"))
    def test_wrong_stage(self): self.bad(lambda r: r.update(stage="0.60"))
    def test_foreign_identity(self): self.bad(lambda r: r.update(identity={}))
    def test_missing_renderer(self): self.bad(lambda r: r["completed_renderers"].pop())
    def test_missing_gpu_baseline(self): self.bad(lambda r: r.update(gpu_baseline_passed=False))
    def test_wrong_backend(self): self.bad(lambda r: r["completed_renderers"][1].update(backend="metal"))
    def test_partial_captures(self): self.bad(lambda r: r["completed_renderers"][1].update(captures=23))
    def test_missing_token(self): self.bad(lambda r: r.pop("run_token"))
    def test_headless_gui_claim(self): self.bad(lambda r: r.update(gui_required=True), False)
    def test_headless_partial_matrix(self): self.bad(lambda r: r.update(native_capture_count=143), False)
    def test_headless_wrong_backend(self): self.bad(lambda r: r.update(native_backend="direct3d"), False)


class GuiReuse(unittest.TestCase):
    def inspect(self, change=lambda _: None):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            reports = {r: gui_report(r) for r in ("raster", "gpu", "auto")}
            change(reports)
            for request, report in reports.items():
                (root / request).mkdir()
                (root / request / "result.json").write_text(json.dumps(report))
            return v.inspect_gui_reuse(root, baseline(), FULL, None)
    def bad(self, change):
        with self.assertRaises((ValueError, KeyError, TypeError)): self.inspect(change)
    def event(self, r): return r["gpu"]["captures"][0]["draw_io"][-1]
    def test_all_reused(self):
        rows = self.inspect(); self.assertEqual(len(rows), 2)
        self.assertTrue(all(v["reuse"] == 12 for row in rows for v in row["sizes"].values()))
    def test_one_cold_start_per_size(self):
        def change(reports):
            for r in ("gpu", "auto"):
                for size in ("small", "large"):
                    next(row for row in reports[r]["captures"] if row["extent"]["name"] == size)["draw_io"][-1]["action"] = "create"
        self.assertEqual(len(self.inspect(change)), 2)
    def test_repeated_allocations_rejected(self):
        def change(reports):
            for row in reports["gpu"]["captures"]: row["draw_io"][-1]["action"] = "create"
        self.bad(change)
    def test_missing_use(self): self.bad(lambda r: r["gpu"]["captures"][0]["draw_io"].pop())
    def test_duplicate_use(self): self.bad(lambda r: r["gpu"]["captures"][0]["draw_io"].append(copy.deepcopy(self.event(r))))
    def test_wrong_width(self): self.bad(lambda r: self.event(r).update(pixel_width=2))
    def test_boolean_width(self): self.bad(lambda r: self.event(r).update(pixel_width=True))
    def test_unknown_action(self): self.bad(lambda r: self.event(r).update(action="fallback"))
    def test_auto_still_required(self): self.bad(lambda r: r["auto"]["captures"][0]["draw_io"].pop())
    def test_inherited_readback_contract(self): self.bad(lambda r: r["gpu"]["captures"][0]["draw_io"].append(dict(kind="readback")))
    def test_stale_report(self): self.bad(lambda r: r["gpu"].update(run_token="stale"))
    def test_missing_capture(self): self.bad(lambda r: r["gpu"]["captures"].pop())


def simulate(options=(), *, fail=None, corrupt=False, mutate=False, missing=False):
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp); commands = []
        for name in v.SOURCES:
            p = root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text("synthetic fixture")
        directory = root / "evidence"
        def run(argv, working):
            args = list(map(str, argv)); commands.append(args)
            if any(x.endswith(fail or "NO-FAILURE") for x in args): raise RuntimeError("synthetic command failure")
            if args[1].endswith("ci-identity.rkt"): return json.dumps(FULL)
            if args[1].endswith("gpu-frame-target-pure-test.rkt"):
                return f.good_summary("gpu-frame-target-pure", v.PURE_CASES)
            if args[1].endswith(("validate-render-canvas.py", "validate-gpu-dc-consumers.py")):
                out = Path(args[args.index("--directory")+1]); out.mkdir()
                gui = args[1].endswith("validate-render-canvas.py")
                (out / "validation.json").write_text(json.dumps(baseline(gui)))
                if gui:
                    for r in ("raster", "gpu", "auto"):
                        (out / r).mkdir(); (out / r / "result.json").write_text(json.dumps(gui_report(r)))
            if args[1].endswith("gpu-frame-target-native-test.rkt"):
                if mutate: (root / "private/gpu-presenter.rkt").write_text("changed")
                rows = measurements()
                if corrupt: rows[0]["creations"] = 32
                return measurement_output(rows) + f.good_summary("gpu-frame-target-native", v.NATIVE_CASES)
            return ""
        with patch.object(v.shutil, "which", return_value=None if missing else "/selected/racket"), \
             patch.object(v.base.Runner, "run", side_effect=run), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = v.main(["--racket", "/selected/racket", "--directory", str(directory), *options], root=root)
        return code, json.loads((directory / "validation.json").read_text()), commands


class Runner(unittest.TestCase):
    def test_headless_has_no_gui_claim(self):
        code, result, commands = simulate()
        self.assertEqual(code, 0); self.assertTrue(result["native_reuse_passed"])
        self.assertFalse(result["gui_reuse_passed"])
        self.assertFalse(any(any(a.endswith("validate-render-canvas.py") for a in c) for c in commands))
    def test_full_requires_old_gui_gate(self):
        code, result, commands = simulate(["--require-gui"])
        self.assertEqual(code, 0); self.assertTrue(result["gui_reuse_passed"])
        command = next(c for c in commands if c[1].endswith("validate-render-canvas.py"))
        self.assertIn("--require-gpu", command); self.assertIn("egl", command)
        self.assertEqual(command[command.index("--racket")+1], str(Path("/selected/racket").resolve()))
    def test_alias(self): self.assertEqual(simulate(["--require-gpu"])[0], 0)
    def test_missing_racket(self): self.assertEqual(simulate(missing=True)[0], 1)
    def test_pure_failure_stops_baseline(self):
        code, result, commands = simulate(fail="gpu-frame-target-pure-test.rkt")
        self.assertEqual(code, 1); self.assertFalse(result["baseline_passed"])
    def test_baseline_failure_stops_native(self):
        code, result, commands = simulate(fail="validate-gpu-dc-consumers.py")
        self.assertEqual(code, 1); self.assertFalse(result["native_reuse_passed"])
        self.assertFalse(any(c[1].endswith("gpu-frame-target-native-test.rkt") for c in commands))
    def test_native_failure(self): self.assertEqual(simulate(fail="gpu-frame-target-native-test.rkt")[0], 1)
    def test_corrupt_measurements(self): self.assertEqual(simulate(corrupt=True)[0], 1)
    def test_source_mutation(self):
        code, result, _ = simulate(mutate=True)
        self.assertEqual(code, 1); self.assertIn("source changed", result["error"])
    def test_wrong_adapter(self): self.assertEqual(simulate(["--adapter", "warp"])[0], 1)
    def test_no_performance_or_physical_display_claim(self):
        _, result, _ = simulate()
        for flag in ("performance_measured", "driver_allocations_measured", "physical_display_verified"):
            self.assertIs(result[flag], False)


class SourceContracts(unittest.TestCase):
    def source(self, name): return (HERE.parent / name).read_text()
    def test_private_pool_keeps_no_canvas_or_dc(self):
        source = self.source("private/gpu-frame-target-cache.rkt")
        self.assertIn("(struct target-entry (width height value dispose))", source)
        self.assertNotIn("make-hash", source)
        self.assertIn("(check-dimensions who width height)", source)
    def test_expired_frame_drops_cache(self):
        source = self.source("private/gpu-presenter.rkt")
        self.assertIn("(set-gpu-frame-targets! f #f)", source)
        self.assertIn("(gpu-frame-canvas f)\n  (unless", source)
    def test_cache_closes_before_adapter(self):
        source = self.source("private/gpu-presenter.rkt")
        self.assertLess(source.index("(close-frame-target-cache! (gpu-presenter-targets p))"),
                        source.index("((presentation-adapter-close (gpu-presenter-adapter p)))"))
    def test_native_staging_is_borrowed_and_still_committed(self):
        source = self.source("private/gpu-dc-native.rkt")
        self.assertIn("(gpu-renderer context staging)", source)
        self.assertIn("(gpu:gpu-surface-snapshot root)", source)
        self.assertIn("#:clear? #t", source)
        self.assertIn("cached staging surface has an unbalanced canvas stack", source)
    def test_primary_failure_and_quarantine(self):
        source = self.source("private/gpu-frame-target-cache.rkt")
        for needle in ("call-with-continuation-barrier", "dynamic-wind", "parameterize-break #f",
                       '(retire! cache "failed-dc-scope")', '(set-frame-target-cache-quarantined?! cache #t)'):
            self.assertIn(needle, source)
    def test_case_counts_match_complete_suites(self):
        for kind, n in (("pure", v.PURE_CASES), ("native", v.NATIVE_CASES)):
            source = self.source(f"tests/gpu-frame-target-{kind}-test.rkt")
            self.assertEqual(source.count("(test-case "), n)
            self.assertIn(f"(define gpu-frame-target-{kind}-test-count {n})", source)
    def test_no_forced_native_wait(self):
        source = self.source("private/gpu-dc-native.rkt") + self.source("private/gpu-frame-target-cache.rkt")
        for needle in ("gpu-wait!", "gpu-flush-and-submit!", "gr_direct_context_submit"):
            self.assertNotIn(needle, source)
    def test_windows_path_assertion_accepts_native_separators(self):
        source = self.source("tools/test-render-canvas.py")
        self.assertIn('x.replace("\\\\", "/").endswith("examples/render-canvas.rkt")', source)
    def test_workflow_requires_new_gate_on_both_platforms(self):
        source = self.source(".github/workflows/render-canvas.yml")
        self.assertEqual(source.count("python tools/validate-gpu-frame-reuse.py"), 2)
        self.assertIn("--backend direct3d --adapter warp", source)
        self.assertNotIn("continue-on-error:", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
