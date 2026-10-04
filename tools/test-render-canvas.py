#!/usr/bin/env python3
"""Synthetic validator tests and source contracts; not Racket/GPU execution."""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import itertools
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import render_canvas_validation as v

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("render_runner", HERE / "validate-render-canvas.py")
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
fixture_spec = importlib.util.spec_from_file_location("consumer_test_fixtures", HERE / "test-gpu-dc-consumers.py")
f = importlib.util.module_from_spec(fixture_spec)
fixture_spec.loader.exec_module(f)
IDENTITY = dict(version="9.3", os="unix", architecture="x86_64", vm="chez-scheme")
FULL = dict(IDENTITY, pointer_bytes=8)
TOKEN = "synthetic-only"


def report(request="raster", backend=None):
    gpu = request != "raster"
    backend = backend or ("opengl" if gpu else "raster")
    selection = dict(requested_renderer=request, requested_backend=backend if request == "gpu" else "auto", renderer="gpu" if gpu else "raster",
                     backend=backend, runtime_fallback=False,
                     adapter="hardware" if backend == "direct3d" else False, adapter_index=0 if backend == "direct3d" else False,
                     sync_interval=1 if backend == "direct3d" else False)
    rows = []
    for scene, mode, size in itertools.product(v.pixels.SCENES, v.pixels.MODES, v.SIZES):
        w, h = (420, 320) if size == "small" else (600, 440)
        key = f"{scene}-{mode}-{size}"
        e = dict(name=size, pixel_width=w, pixel_height=h, logical_width=float(w), logical_height=float(h))
        rows.append(dict(id=key, scene=scene, mode=mode, extent=e, file=key + ".rgba",
                         layout=f.layout() if scene == "plot" else {},
                         draw_io=[dict(kind="gpu-snapshot"), dict(kind="present-request")] if gpu else [],
                         capture_io=[dict(kind="readback")] if gpu else []))
    return dict(schema=1, stage="0.61", status="passed", run_token=TOKEN,
                identity=IDENTITY, requested_renderer=request, selection=selection,
                cases=v.GUI_CASES, failures=0, physical_display_verified=False, captures=rows)


def good_summary(name, count):
    return f"{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run\n{name}: {count} cases, 0 failures; test-only.\n"


class Report(unittest.TestCase):
    def bad(self, change, request="raster"):
        value = report(request); change(value)
        with self.assertRaises((ValueError, TypeError, KeyError)):
            v.validate_report(value, request, "raster" if request == "raster" else "opengl", TOKEN, IDENTITY)
    def test_all_selected_modes(self):
        for request in ("raster", "gpu", "auto"):
            self.assertEqual(len(v.validate_report(report(request), request, "raster" if request == "raster" else "opengl", TOKEN, IDENTITY)), 24)
    def test_unknown_schema(self): self.bad(lambda x: x.update(schema=2))
    def test_boolean_schema(self): self.bad(lambda x: x.update(schema=True))
    def test_wrong_stage(self): self.bad(lambda x: x.update(stage="0.60"))
    def test_failed_worker(self): self.bad(lambda x: x.update(status="failed"))
    def test_old_run(self): self.bad(lambda x: x.update(run_token="old"))
    def test_wrong_identity(self): self.bad(lambda x: x.update(identity=dict(IDENTITY, version="8.18")))
    def test_wrong_request(self): self.bad(lambda x: x.update(requested_renderer="gpu"))
    def test_screen_claim(self): self.bad(lambda x: x.update(physical_display_verified=True))
    def test_partial_case_count(self): self.bad(lambda x: x.update(cases=v.GUI_CASES-1))
    def test_boolean_case_count(self): self.bad(lambda x: x.update(cases=True))
    def test_failures(self): self.bad(lambda x: x.update(failures=1))
    def test_boolean_failures(self): self.bad(lambda x: x.update(failures=False))
    def test_missing_selection(self): self.bad(lambda x: x.pop("selection"))
    def test_wrong_selection_request(self): self.bad(lambda x: x["selection"].update(requested_renderer="auto"))
    def test_wrong_backend(self): self.bad(lambda x: x["selection"].update(backend="metal"), "gpu")
    def test_auto_backend_not_overridden(self): self.bad(lambda x: x["selection"].update(requested_backend="opengl"), "auto")
    def test_gpu_backend_is_explicit(self): self.bad(lambda x: x["selection"].update(requested_backend="auto"), "gpu")
    def test_no_hidden_raster_adapter_index(self): self.bad(lambda x: x["selection"].update(adapter_index=0))
    def test_silent_raster_fallback(self): self.bad(lambda x: x["selection"].update(renderer="raster"), "auto")
    def test_fallback_flag(self): self.bad(lambda x: x["selection"].update(runtime_fallback=True), "gpu")
    def test_missing_capture(self): self.bad(lambda x: x["captures"].pop())
    def test_duplicate_capture(self): self.bad(lambda x: x["captures"].__setitem__(1, x["captures"][0]))
    def test_unknown_capture(self): self.bad(lambda x: x["captures"][0].update(id="other"))
    def test_wrong_scene(self): self.bad(lambda x: x["captures"][0].update(scene="plot"))
    def test_wrong_mode(self): self.bad(lambda x: x["captures"][0].update(mode="other"))
    def test_parent_path(self): self.bad(lambda x: x["captures"][0].update(file="../outside.rgba"))
    def test_absolute_path(self): self.bad(lambda x: x["captures"][0].update(file="/outside.rgba"))
    def test_boolean_pixel_width(self): self.bad(lambda x: x["captures"][0]["extent"].update(pixel_width=True))
    def test_nonfinite_width(self): self.bad(lambda x: x["captures"][0]["extent"].update(logical_width=float("nan")))
    def test_oversized_capture(self): self.bad(lambda x: x["captures"][0]["extent"].update(pixel_width=100000))
    def test_small_canvas(self): self.bad(lambda x: x["captures"][0]["extent"].update(logical_width=200))
    def test_missing_layout(self): self.bad(lambda x: x["captures"][0].pop("layout"))
    def test_bad_plot_layout(self): self.bad(lambda x: next(c for c in x["captures"] if c["scene"] == "plot").update(layout={}))
    def test_implicit_readback(self): self.bad(lambda x: x["captures"][0]["draw_io"].append(dict(kind="readback")), "gpu")
    def test_absent_gpu_present(self): self.bad(lambda x: x["captures"][0].update(draw_io=[]), "gpu")
    def test_no_positive_control(self): self.bad(lambda x: x["captures"][0].update(capture_io=[]), "gpu")
    def test_double_positive_control(self): self.bad(lambda x: x["captures"][0]["capture_io"].append(dict(kind="readback")), "gpu")
    def test_raster_gpu_activity(self): self.bad(lambda x: x["captures"][0]["draw_io"].append(dict(kind="gpu-snapshot")))
    def test_malformed_ledger(self): self.bad(lambda x: x["captures"][0]["draw_io"].append({}))
    def test_missing_ledger(self): self.bad(lambda x: x["captures"][0].pop("draw_io"))
    def test_resize_not_observed(self):
        def change(x):
            for c in x["captures"]:
                c["extent"].update(pixel_width=420, pixel_height=320, logical_width=420.0, logical_height=320.0)
        self.bad(change)
    def test_wrong_direct3d_adapter(self):
        value = report("gpu", "direct3d")
        with self.assertRaises(ValueError): v.validate_report(value, "gpu", "direct3d", TOKEN, IDENTITY, "warp")
        value["selection"]["adapter"] = "warp"
        self.assertEqual(len(v.validate_report(value, "gpu", "direct3d", TOKEN, IDENTITY, "warp")), 24)


class Completion(unittest.TestCase):
    def test_complete_summaries(self):
        for name, n in (("render-canvas-pure", v.PURE_CASES), ("render-canvas-gui", v.GUI_CASES)):
            v.validate_suite(good_summary(name, n), name, n)
    def test_partial_or_wrong_completions(self):
        good = good_summary("render-canvas-gui", v.GUI_CASES)
        for text in ("", good*2, good.replace("0 failures", "1 failures"), good.replace("20", "19"), good+"FAILURE\n", good.splitlines()[0]):
            with self.subTest(text=text), self.assertRaises(ValueError): v.validate_suite(text, "render-canvas-gui", v.GUI_CASES)
    def test_headless_only(self):
        code, result, commands = simulate()
        self.assertEqual(code, 0); self.assertTrue(result["pure_passed"])
        self.assertFalse(result["gui_required"]); self.assertEqual(result["completed_renderers"], [])
        self.assertFalse(any("--require-gui" in c for c in commands))
    def test_raster_only(self):
        code, result, commands = simulate(["--require-gui"])
        self.assertEqual(code, 0); self.assertTrue(result["raster_baseline_passed"])
        self.assertFalse(result["gpu_baseline_passed"])
        self.assertEqual([x["requested_renderer"] for x in result["completed_renderers"]], ["raster"])
        self.assertFalse(any(any(x.endswith("validate-gpu-dc-consumers.py") for x in c) for c in commands))
    def test_full_selects_all_three_and_compiles_example(self):
        code, result, commands = simulate(["--require-gpu"])
        self.assertEqual(code, 0)
        self.assertEqual([x["requested_renderer"] for x in result["completed_renderers"]], ["raster", "gpu", "auto"])
        self.assertTrue(any("make" in c and any(x.endswith("examples/render-canvas.rkt") for x in c) for c in commands))
        self.assertTrue(all(c[0] == "/selected/racket" for c in commands if len(c)>1 and c[1].endswith(".rkt")))
    def test_explicit_backend_does_not_override_auto_worker(self):
        code, result, commands = simulate(["--require-gpu", "--backend", "egl"])
        self.assertEqual(code, 0)
        auto = next(c for c in commands if "--renderer" in c and c[c.index("--renderer")+1] == "auto")
        self.assertEqual(auto[auto.index("--backend")+1], "auto")
    def test_missing_interpreter(self):
        code, result, _ = simulate(missing=True)
        self.assertEqual(code, 1); self.assertIn("not found", result["error"])
    def test_pure_failure_stops_gui(self):
        code, result, commands = simulate(["--require-gpu"], fail="render-canvas-pure-test.rkt")
        self.assertEqual(code, 1); self.assertFalse(result["raster_baseline_passed"])
    def test_raster_baseline_failure_stops_renderers(self):
        code, result, _ = simulate(["--require-gpu"], fail="validate-skia-canvas.py")
        self.assertEqual(code, 1); self.assertEqual(result["completed_renderers"], [])
    def test_gpu_baseline_failure_stops_renderers(self):
        code, result, _ = simulate(["--require-gpu"], fail="validate-gpu-dc-consumers.py")
        self.assertEqual(code, 1); self.assertTrue(result["raster_baseline_passed"])
        self.assertEqual(result["completed_renderers"], [])
    def test_stale_baseline_rejected(self):
        code, result, _ = simulate(["--require-gui"], stale=True)
        self.assertEqual(code, 1); self.assertIn("baseline", result["error"])
    def test_gui_failure_is_not_a_pass(self):
        code, result, _ = simulate(["--require-gpu"], fail="render-canvas-gui-test.rkt")
        self.assertEqual(code, 1); self.assertEqual(result["completed_renderers"], [])
    def test_oracle_failure(self):
        code, result, _ = simulate(["--require-gui"], inspect_fail=True)
        self.assertEqual(code, 1); self.assertEqual(result["completed_renderers"], [])
    def test_source_mutation(self):
        code, result, _ = simulate(mutate=True)
        self.assertEqual(code, 1); self.assertIn("source changed", result["error"])
    def test_wrong_adapter_rejected(self):
        code, result, _ = simulate(["--require-gpu", "--adapter", "warp"])
        self.assertEqual(code, 1); self.assertIn("Direct3D", result["error"])
    def test_incomplete_gpu_baseline(self):
        with self.assertRaises(ValueError): r.validate_gpu_baseline({"stage":"0.60", "status":"passed"}, FULL, "egl")
    def test_incomplete_raster_baseline(self):
        with self.assertRaises(ValueError): r.validate_raster_baseline({"stage":"0.58", "status":"passed"}, FULL)


def simulate(options=(), *, missing=False, fail=None, stale=False, mutate=False, inspect_fail=False):
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp); commands=[]
        for name in r.SOURCES:
            path=root/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text("synthetic")
        def run(argv, root):
            c=list(map(str,argv)); commands.append(c)
            if len(c)>1 and c[1].endswith(fail or "NO-FAIL"):
                raise RuntimeError("selected command failed")
            if c[1].endswith("ci-identity.rkt"): return json.dumps(FULL)
            if c[1].endswith("render-canvas-pure-test.rkt"):
                if mutate: (root/"render-canvas.rkt").write_text("mutated")
                return good_summary("render-canvas-pure", v.PURE_CASES)
            if c[1].endswith("render-canvas-gui-test.rkt"): return good_summary("render-canvas-gui", v.GUI_CASES)
            if c[1].endswith("validate-skia-canvas.py"):
                folder=Path(c[c.index("--output")+1]);folder.mkdir()
                value=dict(stage="0.58", status="failed" if stale else "passed", identity=FULL,
                           checks={k:True for k in ("pure_lifecycle","native_pixels_and_bitmap_bridge","required_gui","text_load_orders","source_unchanged")},
                           gui=dict(status="passed"))
                (folder/"validation.json").write_text(json.dumps(value))
            if c[1].endswith("validate-gpu-dc-consumers.py"):
                folder=Path(c[c.index("--directory")+1]);folder.mkdir()
                value=dict(stage="0.60", status="passed", identity=FULL, native_backend="egl", gui_required=True,
                           baseline_passed=True, native_consumers_passed=True, gui_consumers_passed=True,
                           native_capture_count=144, gui_capture_count=48, native_bounded_comparisons=96, gui_bounded_comparisons=16)
                (folder/"validation.json").write_text(json.dumps(value))
            return ""
        def inspect(*args):
            if inspect_fail: raise ValueError("pixel oracle failed")
            return dict(captures=[{}]*24, bounded_comparisons=[{}]*8)
        with patch.object(r.shutil,"which",return_value=None if missing else "/selected/racket"), \
             patch.object(r.base.Runner,"run",side_effect=run), patch.object(r.checks,"inspect_directory",side_effect=inspect), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code=r.main(["--racket","/selected/racket","--directory",str(root/"out"),*options],root=root)
        return code,json.loads((root/"out/validation.json").read_text()),commands


class PixelsAndFiles(unittest.TestCase):
    def test_complete_synthetic_evidence_all_renderers(self):
        for request in ("raster", "gpu", "auto"):
            with self.subTest(request=request), tempfile.TemporaryDirectory() as temp:
                folder=Path(temp);value=report(request)
                for row in value["captures"]:
                    data,_=f.pixels_fixture(row["scene"],row["extent"])
                    (folder/row["file"]).write_bytes(data)
                (folder/"result.json").write_text(json.dumps(value))
                result=v.inspect_directory(folder,request,value["selection"]["backend"],TOKEN,IDENTITY)
                self.assertEqual(len(result["captures"]),24)
                self.assertEqual(len(result["bounded_comparisons"]),8)
                self.assertEqual(len(list(folder.glob("*.png"))),24)
                self.assertTrue((folder/"review.html").is_file())
    def test_missing_and_short_pixels_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp);value=report()
            (folder/"result.json").write_text(json.dumps(value))
            with self.assertRaises(ValueError):v.inspect_directory(folder,"raster","raster",TOKEN,IDENTITY)
            (folder/value["captures"][0]["file"]).write_bytes(b"bad")
            with self.assertRaises(ValueError):v.inspect_directory(folder,"raster","raster",TOKEN,IDENTITY)
    def test_blank_images_fail(self):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp);value=report()
            for row in value["captures"]:
                e=row["extent"];(folder/row["file"]).write_bytes(b"\xff"*(4*e["pixel_width"]*e["pixel_height"]))
            (folder/"result.json").write_text(json.dumps(value))
            with self.assertRaises(ValueError):v.inspect_directory(folder,"raster","raster",TOKEN,IDENTITY)
    def test_symlink_capture_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp);row=report()["captures"][0]
            target=folder/"data";target.write_bytes(b"\xff"*(4*420*320))
            (folder/row["file"]).symlink_to(target)
            with self.assertRaises(ValueError):v.pixels.capture_bytes(folder,row)


class SourceContracts(unittest.TestCase):
    def source(self, name): return (HERE.parent/name).read_text()
    def test_only_selected_renderer_is_loaded(self):
        source=self.source("render-canvas.rkt")
        self.assertIn("dynamic-require raster-module",source)
        self.assertIn("dynamic-require gpu-module",source)
        self.assertIn("(delay/sync",source)
        self.assertNotIn('(require "canvas.rkt"',source)
    def test_real_superclasses_and_shared_interface(self):
        source=self.source("render-canvas.rkt")
        self.assertIn("(class* base% (skia-render-canvas<%>)",source)
        self.assertIn("(inherit/super closed? get-skia-info)",source)
        self.assertIn("'skia-canvas%",source);self.assertIn("'skia-gpu-canvas%",source)
        self.assertNotIn("vertical-panel%",source)
    def test_no_raw_gpu_transfers_in_facade(self):
        source=self.source("render-canvas.rkt")
        for needle in ("gpu-surface->", "get-rgba-bytes", "get-png-bytes", "make-surface"):
            self.assertNotIn(needle,source)
    def test_raster_toolkit_handoff_is_single_use(self):
        source=self.source("render-canvas.rkt")
        self.assertIn("(begin (set! toolkit-dc-permitted? #f) (super get-dc))",source)
        self.assertIn("(with-toolkit-access (lambda () (super present)))",source)
        self.assertIn("(lambda () (set! toolkit-dc-permitted? #f))",source)
    def test_scope_unwinds_and_forbids_reentry(self):
        source=self.source("private/render-canvas-state.rkt")
        self.assertIn("call-with-continuation-barrier",source)
        self.assertIn("dynamic-wind",source)
        self.assertIn("(lambda () (set-render-session-active! session #f))",source)
        self.assertIn("(current-future)",source)
    def test_cli_options_are_submodule_local_and_lexically_captured(self):
        source=self.source("examples/render-canvas.rkt")
        self.assertLess(source.index("(module+ main"),source.index("(define renderer 'auto)"))
        self.assertIn("(gui:queue-callback (lambda () (open-review renderer backend adapter)))",source)
    def test_real_consumer_oracles_reused(self):
        source=self.source("tests/render-canvas-gui-test.rkt")
        for needle in ('"gpu-dc-consumer-fixtures.rkt"',"exercise-consumer!","current-gpu-io-ledger","capture-io","#:premultiplied? #t"):
            self.assertIn(needle,source)
        self.assertIn("pixels.inspect_pixels(content, row)",self.source("tools/render_canvas_validation.py"))
    def test_gui_callbacks_capture_options_and_check_handler(self):
        source=self.source("tests/render-canvas-gui-test.rkt")
        self.assertIn("[request opts] [output-directory directory]",source)
        self.assertIn("[current-check-around (lambda (check) (check))]",source)
    def test_case_count_declarations(self):
        for suite,n in (("pure",v.PURE_CASES),("gui",v.GUI_CASES)):
            source=self.source(f"tests/render-canvas-{suite}-test.rkt")
            self.assertEqual(source.count("(test-case "),n)
            self.assertIn(f"(define render-canvas-{suite}-test-count {n})",source)
    def test_workflow_is_required_when_selected(self):
        source=self.source(".github/workflows/render-canvas.yml")
        self.assertIn("racket: ['8.18', '9.3']",source)
        self.assertIn("--require-gpu",source)
        self.assertIn("--backend direct3d --adapter warp",source)
        self.assertNotIn("continue-on-error:",source)
        self.assertIn("examples/render-canvas.rkt",source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
