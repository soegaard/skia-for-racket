#!/usr/bin/env python3
"""Synthetic acceptance/runner regressions. Never evidence of Racket/GPU execution."""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import itertools
import json
import math
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib

import gpu_dc_consumer_validation as d

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("consumer_runner", HERE / "validate-gpu-dc-consumers.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
IDENTITY = dict(version="9.3", os="unix", architecture="x86_64", vm="chez-scheme")
FULL_IDENTITY = dict(IDENTITY, pointer_bytes=8)
TOKEN = "synthetic-unit-test-only"


def extent(name="1x"):
    pw, ph, lw, lh = d.EXTENTS[name]
    return dict(name=name, pixel_width=pw, pixel_height=ph, logical_width=lw, logical_height=lh)


def layout():
    return dict(lower_left=[40.0, 200.0], upper_right=[290.0, 50.0])


def report(suite="native"):
    captures = []
    targets = ("cpu", "surface", "frame") if suite == "native" else ("cpu", "gui")
    sizes = {k: extent(k) for k in d.EXTENTS} if suite == "native" else {
        "small": dict(name="small", pixel_width=380, pixel_height=300, logical_width=380.0, logical_height=300.0),
        "large": dict(name="large", pixel_width=520, pixel_height=400, logical_width=520.0, logical_height=400.0)}
    for target, scene, mode, size in itertools.product(targets, d.SCENES, d.MODES, sizes):
        key = f"{target}-{scene}-{mode}-{size}"
        events = [{"kind": "gpu-snapshot"}] if target in ("frame", "gui") else []
        if target == "gui": events += [{"kind": "present-request"}]
        captures.append(dict(id=key, scene=scene, mode=mode, target=target, extent=copy.deepcopy(sizes[size]),
                             file=key + ".rgba", layout=layout() if scene == "plot" else {}, draw_io=events))
    gpu = [r for r in captures if r["target"] != "cpu"]
    checks = dict(expired_dcs=96 if suite == "native" else 48,
                  window_created=suite == "gui", final_target_pixels=suite == "native",
                  transfers=[dict(id=r["id"], io=[{"kind": "readback"}]) for r in gpu])
    checks["context_closed" if suite == "native" else "canvas_closed"] = True
    if suite == "gui": checks["normal_frames"] = [dict(id=r["id"], io=r["draw_io"]) for r in gpu]
    return dict(schema=1, stage="0.60", suite=suite, status="passed", run_token=TOKEN,
                backend="egl" if suite == "native" else "opengl", identity=IDENTITY,
                physical_display_verified=False, captures=captures, checks=checks)


class Structure(unittest.TestCase):
    def check(self, value, suite="native"):
        return d.validate_structure(value, suite, TOKEN, "egl" if suite == "native" else "opengl", IDENTITY)

    def bad(self, change, suite="native"):
        value = report(suite); change(value)
        with self.assertRaises((ValueError, TypeError)): self.check(value, suite)

    def test_complete_native(self): self.assertEqual(len(self.check(report())), 144)
    def test_complete_gui(self): self.assertEqual(len(self.check(report("gui"), "gui")), 48)
    def test_unknown_suite(self):
        with self.assertRaises(ValueError): d.expected_ids("other")
    def test_failed_status(self): self.bad(lambda r: r.update(status="failed"))
    def test_old_stage(self): self.bad(lambda r: r.update(stage="0.59"))
    def test_boolean_schema(self): self.bad(lambda r: r.update(schema=True))
    def test_wrong_schema(self): self.bad(lambda r: r.update(schema=2))
    def test_stale_token(self): self.bad(lambda r: r.update(run_token="old"))
    def test_wrong_backend(self): self.bad(lambda r: r.update(backend="metal"))
    def test_wrong_identity(self): self.bad(lambda r: r.update(identity=dict(IDENTITY, version="8.18")))
    def test_screen_claim(self): self.bad(lambda r: r.update(physical_display_verified=True))
    def test_missing_capture(self): self.bad(lambda r: r["captures"].pop())
    def test_duplicate_capture(self): self.bad(lambda r: r["captures"].__setitem__(1, r["captures"][0]))
    def test_foreign_capture(self): self.bad(lambda r: r["captures"][0].update(id="foreign"))
    def test_mismatched_scene(self): self.bad(lambda r: r["captures"][0].update(scene="plot"))
    def test_unsafe_path(self): self.bad(lambda r: r["captures"][0].update(file="../escape.rgba"))
    def test_absolute_path(self): self.bad(lambda r: r["captures"][0].update(file="/escape.rgba"))
    def test_boolean_width(self): self.bad(lambda r: r["captures"][0]["extent"].update(pixel_width=True))
    def test_invalid_width(self): self.bad(lambda r: r["captures"][0]["extent"].update(pixel_width=0))
    def test_nonfinite_logical_size(self): self.bad(lambda r: r["captures"][0]["extent"].update(logical_width=math.inf))
    def test_wrong_native_geometry(self): self.bad(lambda r: r["captures"][0]["extent"].update(pixel_width=321))
    def test_unknown_extent(self): self.bad(lambda r: r["captures"][0]["extent"].update(name="other"))
    def test_wrong_gui_geometry(self): self.bad(lambda r: r["captures"][0]["extent"].update(pixel_width=381), "gui")
    def test_missing_layout(self): self.bad(lambda r: r["captures"][0].pop("layout"))
    def test_plot_layout_missing(self): self.bad(lambda r: next(x for x in r["captures"] if x["scene"] == "plot").update(layout={}))
    def test_plot_layout_reversed(self):
        self.bad(lambda r: next(x for x in r["captures"] if x["scene"] == "plot")["layout"].update(upper_right=[0, 50]))
    def test_implicit_readback(self): self.bad(lambda r: r["captures"][-1]["draw_io"].append({"kind": "readback"}))
    def test_missing_ledger(self): self.bad(lambda r: r["captures"][0].pop("draw_io"))
    def test_invalid_event(self): self.bad(lambda r: r["captures"][-1]["draw_io"].append({}))
    def test_cpu_gpu_event(self): self.bad(lambda r: r["captures"][0]["draw_io"].append({"kind": "gpu-snapshot"}))
    def test_missing_final_snapshot(self): self.bad(lambda r: r["captures"][-1].update(draw_io=[]))
    def test_unclosed_context(self): self.bad(lambda r: r["checks"].update(context_closed=False))
    def test_missing_expiry(self): self.bad(lambda r: r["checks"].update(expired_dcs=95))
    def test_boolean_expiry(self): self.bad(lambda r: r["checks"].update(expired_dcs=True))
    def test_wrong_target_disclosure(self): self.bad(lambda r: r["checks"].update(final_target_pixels=False))
    def test_wrong_window_disclosure(self): self.bad(lambda r: r["checks"].update(window_created=True))
    def test_missing_transfer(self): self.bad(lambda r: r["checks"]["transfers"].pop())
    def test_duplicate_transfer(self): self.bad(lambda r: r["checks"]["transfers"].__setitem__(1, r["checks"]["transfers"][0]))
    def test_no_readback_positive_control(self): self.bad(lambda r: r["checks"]["transfers"][0].update(io=[]))
    def test_duplicate_readback_control(self): self.bad(lambda r: r["checks"]["transfers"][0]["io"].append({"kind": "readback"}))
    def test_missing_normal_gui_frame(self): self.bad(lambda r: r["checks"]["normal_frames"].pop(), "gui")
    def test_missing_gui_present(self): self.bad(lambda r: r["captures"][-1].update(draw_io=[{"kind": "gpu-snapshot"}]), "gui")
    def test_gui_ledger_mismatch(self): self.bad(lambda r: r["checks"]["normal_frames"][0].update(io=[]), "gui")
    def test_gui_expiry(self): self.bad(lambda r: r["checks"].update(expired_dcs=47), "gui")


class JsonAndFiles(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
    def read(self, text):
        p = self.root / "a.json"; p.write_text(text); return d.read_json(p)
    def test_json_positive(self): self.assertEqual(self.read('{"a":1}'), {"a": 1})
    def test_duplicate_json(self):
        with self.assertRaises(ValueError): self.read('{"a":1,"a":2}')
    def test_nonfinite_json(self):
        for token in ("NaN", "Infinity", "-Infinity"):
            with self.assertRaises(ValueError): self.read('{"a":' + token + '}')
    def test_missing_json(self):
        with self.assertRaises(ValueError): d.read_json(self.root / "missing")
    def test_json_symlink(self):
        (self.root / "target").write_text('{}'); (self.root / "a.json").symlink_to(self.root / "target")
        with self.assertRaises(ValueError): d.read_json(self.root / "a.json")
    def test_missing_capture(self):
        with self.assertRaises(ValueError): d.capture_bytes(self.root, report()["captures"][0])
    def test_short_capture(self):
        row = report()["captures"][0]; (self.root / row["file"]).write_bytes(b"short")
        with self.assertRaises(ValueError): d.capture_bytes(self.root, row)
    def test_symlink_capture(self):
        row = report()["captures"][0]; target = self.root / "data"
        target.write_bytes(b"\xff" * (320 * 240 * 4)); (self.root / row["file"]).symlink_to(target)
        with self.assertRaises(ValueError): d.capture_bytes(self.root, row)
    def test_valid_capture(self):
        row = report()["captures"][0]; data = b"\xff" * (320 * 240 * 4)
        (self.root / row["file"]).write_bytes(data)
        self.assertEqual(d.capture_bytes(self.root, row), data)


def pixels_fixture(scene, shape=None):
    """Synthetic ink sufficient for the documented semantic predicates only."""
    e = shape or extent()
    w, h = e["pixel_width"], e["pixel_height"]
    sx, sy = w / e["logical_width"], h / e["logical_height"]
    data = bytearray(b"\xff" * (w * h * 4))
    def fill(x0, y0, x1, y1, rgba):
        for y in range(max(0, math.floor(y0 * sy)), min(h, math.ceil(y1 * sy))):
            for x in range(max(0, math.floor(x0 * sx)), min(w, math.ceil(x1 * sx))):
                data[4 * (x + y * w):4 * (x + y * w) + 4] = bytes(rgba)
    if scene in ("pict", "geometry"):
        fill(12, 12, 36 if scene == "geometry" else 56, 32, (255, 0, 0, 255))
        fill(12, 64, 28, 88, (255, 128, 128, 255)); fill(28, 64, 68, 88, (128, 128, 255, 255))
        if scene == "pict":
            fill(160, 12, 172, 22, (20, 180, 60, 255)); fill(20, 130, 32, 140, (0, 0, 128, 255))
        else:
            fill(108, 12, 124, 28, (255, 0, 0, 255)); fill(124, 12, 140, 28, (0, 0, 255, 255))
            fill(206, 125, 236, 145, (0, 255, 0, 255))
    elif scene == "plot":
        lo, hi = layout()["lower_left"], layout()["upper_right"]
        for x, y, rgb in ((-1.5, -.75, (0, 0, 255, 255)), (-.5, -.25, (0, 0, 255, 255)),
                          (.5, .25, (0, 0, 255, 255)), (1.5, .75, (0, 0, 255, 255)),
                          (-1, 1, (255, 0, 0, 255)), (1, -1, (255, 0, 0, 255))):
            px, py = lo[0] + (x + 2) / 4 * (hi[0] - lo[0]), lo[1] + (y + 1.5) / 3 * (hi[1] - lo[1])
            fill(px - 1, py - 1, px + 1, py + 1, rgb)
        fill(100, 10, 110, 20, (0, 0, 0, 255))
    elif scene == "styles":
        fill(0, 0, 8, 16, (255, 0, 0, 255)); fill(8, 0, 16, 16, (0, 0, 255, 255))
        fill(0, 16, 16, 32, (0, 0, 255, 255)); fill(7, 23, 10, 26, (255, 0, 0, 255))
        colors = ((255, 0, 0, 255), (0, 0, 255, 255), (0, 255, 0, 255), (255, 255, 0, 255))
        for i, color in enumerate(colors):
            fill(17 + 3 * i, 1, 20 + 3 * i, 15, color)
            fill(49 + 3 * i, 33, 52 + 3 * i, 47, color)
        fill(33, 1, 47, 4, (255, 0, 0, 255))
    row = dict(id="synthetic", scene=scene, extent=e, layout=layout() if scene == "plot" else {})
    return bytes(data), row


class Oracles(unittest.TestCase):
    def test_positive_synthetic_ink_all_sizes(self):
        for scene, name in itertools.product(d.SCENES, d.EXTENTS):
            with self.subTest(scene=scene, size=name):
                data, row = pixels_fixture(scene, extent(name)); self.assertTrue(d.inspect_pixels(data, row))
    def test_blank_images_fail_every_scene(self):
        for scene in d.SCENES:
            data, row = pixels_fixture(scene)
            with self.subTest(scene=scene), self.assertRaises(ValueError): d.inspect_pixels(b"\xff" * len(data), row)
    def test_wrong_alpha_fails_solid(self):
        data, row = pixels_fixture("geometry"); data = bytearray(data)
        data[4 * (20 + 20 * 320) + 3] = 0
        with self.assertRaises(ValueError): d.inspect_pixels(data, row)
    def test_clipping_leak_fails(self):
        data, row = pixels_fixture("geometry"); data = bytearray(data)
        data[4 * (45 + 20 * 320):4 * (45 + 20 * 320) + 4] = bytes((255, 0, 0, 255))
        with self.assertRaises(ValueError): d.inspect_pixels(data, row)
    def test_per_draw_not_group_opacity_fails(self):
        data, row = pixels_fixture("pict"); data = bytearray(data)
        data[4 * (36 + 72 * 320):4 * (36 + 72 * 320) + 4] = bytes((128, 64, 192, 255))
        with self.assertRaises(ValueError): d.inspect_pixels(data, row)
    def test_unscaled_hidpi_sample_fails(self):
        data, row = pixels_fixture("pict", extent("2x")); row["extent"] = dict(row["extent"], logical_width=640.0, logical_height=480.0)
        with self.assertRaises(ValueError): d.inspect_pixels(data, row)
    def test_absent_plot_curve_fails(self):
        data, row = pixels_fixture("plot"); data = data.replace(bytes((0, 0, 255, 255)), b"\xff" * 4)
        with self.assertRaises(ValueError): d.inspect_pixels(data, row)
    def test_absent_plot_markers_fails(self):
        data, row = pixels_fixture("plot"); data = data.replace(bytes((255, 0, 0, 255)), b"\xff" * 4)
        with self.assertRaises(ValueError): d.inspect_pixels(data, row)
    def test_missing_navy_text_fails(self):
        data, row = pixels_fixture("pict"); data = data.replace(bytes((0, 0, 128, 255)), b"\xff" * 4)
        with self.assertRaises(ValueError): d.inspect_pixels(data, row)
    def test_same_backend_tolerance(self):
        self.assertEqual(d.bounded_equal(b"\x00\xff", b"\x02\xfd", 2, "pair"), 2)
        with self.assertRaises(ValueError): d.bounded_equal(b"\x00", b"\x03", 2, "pair")
    def test_different_sizes_fail(self):
        with self.assertRaises(ValueError): d.bounded_equal(b"a", b"ab", 2, "pair")
    def test_png_pixels_roundtrip(self):
        data = bytes((255, 0, 0, 255)) * 6; png = d.png_bytes(data, 3, 2)
        self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
        pos = 8; compressed = b""
        while pos < len(png):
            n = struct.unpack(">I", png[pos:pos + 4])[0]; kind = png[pos + 4:pos + 8]; value = png[pos + 8:pos + 8 + n]
            self.assertEqual(struct.unpack(">I", png[pos + 8 + n:pos + 12 + n])[0], zlib.crc32(kind + value) & 0xffffffff)
            if kind == b"IDAT": compressed += value
            pos += n + 12
        self.assertEqual(zlib.decompress(compressed), b"\0" + data[:12] + b"\0" + data[12:])
    def test_png_rejects_size(self):
        with self.assertRaises(ValueError): d.png_bytes(b"", 3, 2)


class Completion(unittest.TestCase):
    def test_markers(self):
        for suite, n in d.COUNTS.items(): v.validate_marker(f"gpu-dc-consumers-{suite}: {n} captures; passed.\n", suite)
    def test_partial_duplicate_failed_markers(self):
        good = "gpu-dc-consumers-native: 144 captures; passed.\n"
        for output in ("", good * 2, good.replace("144", "143"), "FAILURE\n" + good, good.replace("native", "gui")):
            with self.assertRaises(ValueError): v.validate_marker(output, "native")
    def test_incomplete_baseline(self):
        with self.assertRaises(ValueError): v.validate_baseline({"status": "passed"}, FULL_IDENTITY, False)
    def test_selected_interpreter_and_backend(self):
        code, result, commands = simulate(["--require-gui"])
        self.assertEqual(code, 0); self.assertTrue(result["gui_consumers_passed"])
        for c in commands:
            if c[0] != "/selected/racket": continue
            if len(c) > 1 and c[1].endswith("consumer-native.rkt"): self.assertIn("egl", c)
            if len(c) > 1 and c[1].endswith("consumer-gui.rkt"): self.assertIn("opengl", c)
        baseline = next(c for c in commands if any(x.endswith("validate-gpu-dc.py") for x in c))
        self.assertEqual(baseline[baseline.index("--racket") + 1], "/selected/racket")
    def test_headless_does_not_claim_gui(self):
        code, result, commands = simulate()
        self.assertEqual(code, 0); self.assertFalse(result["gui_consumers_passed"])
        self.assertFalse(any(c[1].endswith("consumer-gui.rkt") for c in commands))
    def test_baseline_failure_stops_consumers(self):
        code, result, commands = simulate(fail="validate-gpu-dc.py")
        self.assertEqual(code, 1); self.assertFalse(result["native_consumers_passed"])
        self.assertFalse(any(c[1].endswith("consumer-native.rkt") for c in commands))
    def test_native_failure_stops_gui(self):
        code, result, _ = simulate(["--require-gui"], fail="gpu-dc-consumer-native.rkt")
        self.assertEqual(code, 1); self.assertFalse(result["gui_consumers_passed"])
    def test_gui_failure_stays_failed(self):
        code, result, _ = simulate(["--require-gui"], fail="gpu-dc-consumer-gui.rkt")
        self.assertEqual(code, 1); self.assertTrue(result["native_consumers_passed"])
    def test_inspector_failure(self):
        code, result, _ = simulate(inspect_fail=True)
        self.assertEqual(code, 1); self.assertFalse(result["native_consumers_passed"])
    def test_source_changed(self):
        code, result, _ = simulate(mutate=True)
        self.assertEqual(code, 1); self.assertIn("source changed", result["error"])
    def test_missing_executable(self):
        code, result, _ = simulate(missing=True)
        self.assertEqual(code, 1); self.assertIn("not found", result["error"])
    def test_adapter_requires_direct3d(self):
        code, result, _ = simulate(["--adapter", "warp"])
        self.assertEqual(code, 1); self.assertIn("Direct3D", result["error"])


def simulate(options=(), *, fail=None, inspect_fail=False, mutate=False, missing=False):
    with tempfile.TemporaryDirectory() as t:
        root = Path(t); commands = []
        for name in v.SOURCES:
            p = root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text("synthetic")
        out = root / "evidence"
        def run(argv, root):
            c = list(map(str, argv)); commands.append(c)
            if len(c) > 1 and c[1].endswith(fail or "NO-FAILURE"):
                raise RuntimeError("synthetic selected command failure")
            if c[1].endswith("ci-identity.rkt"): return json.dumps(FULL_IDENTITY)
            if c[1].endswith("validate-gpu-dc.py"):
                directory = Path(c[c.index("--directory") + 1]); directory.mkdir()
                gui = "--require-gui" in c
                names = ("gpu-dc-pure", "gpu-dc-native", "gpu-dc-gui") if gui else ("gpu-dc-pure", "gpu-dc-native")
                data = dict(status="passed", stage="0.59", identity=FULL_IDENTITY, native_gpu_tests_passed=True,
                            gui_required=gui, gui_tests_passed=gui,
                            completed_suites=[dict(name=n, cases=v.base.COUNTS[n]) for n in names])
                (directory / "validation.json").write_text(json.dumps(data))
            for suite, n in d.COUNTS.items():
                if c[1].endswith(f"consumer-{suite}.rkt"):
                    if mutate: (root / "gpu-dc.rkt").write_text("changed")
                    return f"gpu-dc-consumers-{suite}: {n} captures; passed.\n"
            return ""
        def inspect(directory, suite, *args):
            if inspect_fail: raise ValueError("synthetic corrupted pixel")
            return dict(captures=[{}] * d.COUNTS[suite], bounded_comparisons=[])
        with patch.object(v.shutil, "which", return_value=None if missing else "/selected/racket"), \
             patch.object(v.base.Runner, "run", side_effect=run), patch.object(v.inspection, "inspect_directory", side_effect=inspect), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = v.main(["--racket", "/selected/racket", "--directory", str(out), *options], root=root)
        return code, json.loads((out / "validation.json").read_text()), commands


class EndToEnd(unittest.TestCase):
    def test_complete_synthetic_native_and_gui_reports(self):
        # Real file parsing, exact matrix validation, all independent oracles,
        # bounded comparisons and review encoding. Pixels are synthetic.
        for suite in d.COUNTS:
            with self.subTest(suite=suite), tempfile.TemporaryDirectory() as t:
                root = Path(t); value = report(suite)
                for row in value["captures"]:
                    data, _ = pixels_fixture(row["scene"], row["extent"])
                    (root / row["file"]).write_bytes(data)
                (root / (suite + ".json")).write_text(json.dumps(value))
                result = d.inspect_directory(root, suite, TOKEN, value["backend"], IDENTITY)
                self.assertEqual(len(result["captures"]), d.COUNTS[suite])
                self.assertEqual(len(result["bounded_comparisons"]), 96 if suite == "native" else 16)
                self.assertEqual(len(list(root.glob("*.png"))), d.COUNTS[suite])
                self.assertTrue((root / "review.html").is_file())

    def test_premultiplied_png_is_unpremultiplied(self):
        png = d.png_bytes(bytes((128, 0, 0, 128, 0, 0, 0, 0)), 2, 1)
        pos = 8; compressed = b""
        while pos < len(png):
            n = struct.unpack(">I", png[pos:pos + 4])[0]
            if png[pos + 4:pos + 8] == b"IDAT": compressed += png[pos + 8:pos + 8 + n]
            pos += 12 + n
        self.assertEqual(zlib.decompress(compressed), bytes((0, 255, 0, 0, 128, 0, 0, 0, 0)))


class SourceContracts(unittest.TestCase):
    def test_real_public_consumer_fixtures(self):
        source = (HERE.parent / "tests/gpu-dc-consumer-fixtures.rkt").read_text()
        for term in ('"dc-consumer-fixtures.rkt"', 'make-consumer-pict', 'draw-consumer-plot',
                     'style:style-oracle', 'rd:record-dc%', '(write (send recorder get-recorded-datum)',
                     '(define datum (read in))', '(rd:recorded-datum->procedure datum)'):
            self.assertIn(term, source)
    def test_final_native_target_is_read_after_scope_exit(self):
        source = (HERE / "gpu-dc-consumer-native.rkt").read_text()
        self.assertIn('call-with-gpu-surface-dc', source)
        self.assertIn('call-with-gpu-frame-dc', source)
        self.assertIn('(check-consumer-expired! saved)', source)
        self.assertLess(source.index('(check-consumer-expired! saved)'), source.index('gpu:gpu-surface->rgba-bytes target'))
        self.assertNotIn('sk:make-surface', source)
    def test_gui_has_separate_normal_and_inspection_frames(self):
        source = (HERE / "gpu-dc-consumer-gui.rkt").read_text()
        self.assertIn('#:present? #t', source)
        self.assertIn('#:capture? #t', source)
        self.assertIn('[automatic? #f]', source)
        self.assertIn('(check-consumer-expired! normal-dc)', source)
        self.assertIn('(check-consumer-expired! observed-dc)', source)
    def test_workflow_keeps_required_software_paths(self):
        source = (HERE.parent / ".github/workflows/gpu-dc.yml").read_text()
        self.assertIn("racket: ['8.18', '9.3']", source)
        self.assertIn('--backend egl --require-gui', source)
        self.assertIn('--backend direct3d --adapter warp', source)
        self.assertIn('tools/validate-gpu-dc-consumers.py', source)
        self.assertNotIn('continue-on-error:', source)
    def test_example_is_dispatched_to_handler(self):
        source = (HERE.parent / "examples/gpu-dc-consumers.rkt").read_text()
        self.assertIn('(gui:queue-callback make-window)', source)
        self.assertNotIn('get-rgba-bytes', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
