#!/usr/bin/env python3
"""Synthetic 0.64 runner/source contracts. Not evidence of Racket execution."""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
spec = importlib.util.spec_from_file_location("closure_driver", HERE / "validate-dc-closure.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
IDENTITY = dict(version="9.3", os="unix", architecture="x86_64", vm="chez-scheme", pointer_bytes=8)


def summary(name):
    n = v.COUNTS[name]
    return f"{n} success(es) 0 failure(s) 0 error(s) {n} test(s) run\n{name}: {n} cases, 0 failures\n"


def document_report(racket="selected", rendered=False, identity=None, regressions="full"):
    full = regressions == "full"
    return dict(schema=1, stage="0.63", status="passed", identity=identity or IDENTITY,
                racket_executable=racket, compiled=True, baseline_passed=True,
                native_tests_passed=True, structure_passed=True, document_count=24,
                suites={"dc-output-pure": 34, "dc-output-native": 22},
                renderers_required=rendered, independent_pixels_verified=rendered,
                regressions_mode=regressions, regressions_requested=full,
                regressions_attempted=full, regressions_completed=full, regressions_passed=full,
                regressions_status="passed" if full else "not-run",
                physical_display_verified=False)


def gui_report(racket="selected", backend="egl", identity=None):
    return dict(schema=1, stage="0.62", status="passed", identity=identity or IDENTITY,
                racket_executable=racket, native_backend=backend, gui_required=True,
                pure_passed=True, baseline_passed=True, native_reuse_passed=True,
                gui_reuse_passed=True, physical_display_verified=False)


def simulate(options=(), *, fail=None, missing=False, identity=None, bad_suite=None,
             bad_document=None, bad_gui=None, mutate=False, report_text=None):
    ident = identity or IDENTITY
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        for name in v.SOURCES:
            file = root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("synthetic", encoding="utf-8")
        selected = str((root / "selected interpreter" / "racket").resolve())
        commands = []
        def run(argv, cwd):
            c = list(map(str, argv))
            commands.append(c)
            script = Path(c[1]).name if len(c) > 1 else ""
            if script == fail:
                raise RuntimeError("synthetic selected command failure: " + script)
            if script == "ci-identity.rkt":
                return json.dumps(ident)
            for name in v.COUNTS:
                if script == name + "-test.rkt":
                    if mutate:
                        (root / "private/dc-font-name.rkt").write_text("changed", encoding="utf-8")
                    return bad_suite if bad_suite is not None else summary(name)
            if script in ("validate-dc-output.py", "validate-gpu-frame-reuse.py"):
                directory = Path(c[c.index("--directory") + 1]); directory.mkdir()
                if script == "validate-dc-output.py":
                    result = document_report(selected, "--require-renderers" in c, ident,
                                             regressions=c[c.index("--regressions") + 1])
                    if bad_document:
                        bad_document(result)
                else:
                    backend = c[c.index("--backend") + 1]
                    result = gui_report(selected, backend, ident)
                    if bad_gui:
                        bad_gui(result)
                (directory / "validation.json").write_text(
                    report_text if report_text is not None else json.dumps(result), encoding="utf-8")
            return ""
        with patch.object(v.shutil, "which", return_value=None if missing else selected), \
             patch.object(v.base.Runner, "run", side_effect=run), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = v.main(["--racket", selected, "--directory", str(root / "out"), *options], root=root)
        return code, json.loads((root / "out/validation.json").read_text()), commands, selected


class SuiteCompletion(unittest.TestCase):
    def test_exact_completions(self):
        for name in v.COUNTS:
            v.validate_suite(summary(name), name)
    def test_crlf(self):
        v.validate_suite(summary("dc-closure-pure").replace("\n", "\r\n"), "dc-closure-pure")
    def test_missing(self):
        with self.assertRaises(ValueError): v.validate_suite("", "dc-closure-pure")
    def test_duplicate(self):
        with self.assertRaises(ValueError): v.validate_suite(summary("dc-closure-pure") * 2, "dc-closure-pure")
    def test_wrong_count(self):
        with self.assertRaises(ValueError): v.validate_suite(summary("dc-closure-pure").replace("35", "34"), "dc-closure-pure")
    def test_wrong_suite(self):
        with self.assertRaises(ValueError): v.validate_suite(summary("dc-closure-native"), "dc-closure-pure")
    def test_marker_alone(self):
        with self.assertRaises(ValueError): v.validate_suite(summary("dc-closure-pure").splitlines()[1], "dc-closure-pure")
    def test_summary_alone(self):
        with self.assertRaises(ValueError): v.validate_suite(summary("dc-closure-pure").splitlines()[0], "dc-closure-pure")
    def test_printed_failure(self):
        for word in ("ERROR", "FAILURE"):
            with self.assertRaises(ValueError): v.validate_suite(word + "\n" + summary("dc-closure-pure"), "dc-closure-pure")
    def test_errors_and_failures(self):
        for text in (summary("dc-closure-pure").replace("0 error(s)", "1 error(s)"),
                     summary("dc-closure-pure").replace("0 failures", "1 failures")):
            with self.assertRaises(ValueError): v.validate_suite(text, "dc-closure-pure")


class Reports(unittest.TestCase):
    def bad_document(self, change):
        value = document_report(); change(value)
        with self.assertRaises(ValueError): v.validate_document_baseline(value, IDENTITY, "selected", False)
    def bad_gui(self, change):
        value = gui_report(); change(value)
        with self.assertRaises(ValueError): v.validate_gui_baseline(value, IDENTITY, "selected", "egl")
    def test_valid_documents(self):
        for rendered in (False, True): v.validate_document_baseline(document_report(rendered=rendered), IDENTITY, "selected", rendered)
    def test_valid_gui(self):
        v.validate_gui_baseline(gui_report(), IDENTITY, "selected", "egl")
    def test_document_failed(self): self.bad_document(lambda r: r.update(status="failed"))
    def test_document_old_stage(self): self.bad_document(lambda r: r.update(stage="0.62"))
    def test_document_identity(self): self.bad_document(lambda r: r.update(identity=dict(IDENTITY, version="8.18")))
    def test_document_interpreter(self): self.bad_document(lambda r: r.update(racket_executable="another"))
    def test_document_flags(self):
        for flag in ("compiled", "baseline_passed", "native_tests_passed", "structure_passed"):
            self.bad_document(lambda r: r.update({flag: False}))
    def test_document_matrix(self):
        for n in (23, 25, None, True): self.bad_document(lambda r: r.update(document_count=n))
    def test_document_suites(self): self.bad_document(lambda r: r.update(suites={"dc-output-pure": 34}))
    def test_document_pixel_claim(self): self.bad_document(lambda r: r.update(independent_pixels_verified=True))
    def test_document_required_renderers(self): self.bad_document(lambda r: r.update(renderers_required=True))
    def test_document_schema(self):
        for n in (None, True, 0, 2): self.bad_document(lambda r: r.update(schema=n))
    def test_document_display_claim(self): self.bad_document(lambda r: r.update(physical_display_verified=True))
    def test_gui_failed(self): self.bad_gui(lambda r: r.update(status="failed"))
    def test_gui_old_stage(self): self.bad_gui(lambda r: r.update(stage="0.61"))
    def test_gui_flags(self):
        for flag in ("gui_required", "pure_passed", "baseline_passed", "native_reuse_passed", "gui_reuse_passed"):
            self.bad_gui(lambda r: r.update({flag: False}))
    def test_gui_identity(self): self.bad_gui(lambda r: r.update(identity={}))
    def test_gui_interpreter(self): self.bad_gui(lambda r: r.update(racket_executable="another"))
    def test_gui_backend(self): self.bad_gui(lambda r: r.update(native_backend="metal"))
    def test_gui_schema(self): self.bad_gui(lambda r: r.update(schema=True))
    def test_gui_display_claim(self): self.bad_gui(lambda r: r.update(physical_display_verified=True))


class Json(unittest.TestCase):
    def read(self, content):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "report.json"; path.write_text(content, encoding="utf-8")
            return v.read_report(path)
    def test_valid(self): self.assertEqual(self.read('{"ok":true}'), {"ok": True})
    def test_duplicates(self):
        with self.assertRaises(ValueError): self.read('{"ok":true,"ok":false}')
    def test_nonfinite(self):
        for token in ("NaN", "Infinity", "-Infinity"):
            with self.assertRaises(ValueError): self.read('{"value":' + token + '}')
    def test_not_object(self):
        for text in ('[]', 'false', 'null'):
            with self.assertRaises(ValueError): self.read(text)
    def test_missing(self):
        with tempfile.TemporaryDirectory() as temp, self.assertRaises(ValueError): v.read_report(Path(temp) / "missing")
    def test_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "target"; target.write_text('{}', encoding="utf-8")
            path = Path(temp) / "report"; path.symlink_to(target)
            with self.assertRaises(ValueError): v.read_report(path)


class Runner(unittest.TestCase):
    def test_default_runs_native_and_document_baseline(self):
        code, result, commands, _ = simulate()
        self.assertEqual(code, 0); self.assertTrue(result["document_baseline_passed"])
        self.assertTrue(result["compiled"])
        self.assertEqual(result["completed_suites"], [dict(name=k, cases=n) for k, n in v.COUNTS.items()])
        self.assertFalse(result["gui_baseline_passed"]); self.assertFalse(result["independent_pixels_verified"])
        self.assertFalse(any("--require-gui" in c for c in commands))
    def test_selected_interpreter_everywhere(self):
        code, result, commands, selected = simulate(["--require-gui", "--require-renderers"])
        self.assertEqual(code, 0)
        self.assertEqual(result["racket_executable"], selected)
        racket_commands = [c for c in commands if len(c) > 1 and (c[1].endswith('.rkt') or c[1] == '-l')]
        self.assertTrue(racket_commands)
        self.assertTrue(all(c[0] == selected for c in racket_commands))
        for c in commands:
            if "--racket" in c: self.assertEqual(c[c.index("--racket")+1], selected)
    def test_full_chain(self):
        code, result, commands, _ = simulate(["--require-gui", "--require-renderers"])
        self.assertEqual(code, 0); self.assertTrue(result["gui_baseline_passed"])
        self.assertTrue(result["independent_pixels_verified"]); self.assertFalse(result["physical_display_verified"])
        doc = next(c for c in commands if c[1].endswith("validate-dc-output.py"))
        gpu = next(c for c in commands if c[1].endswith("validate-gpu-frame-reuse.py"))
        self.assertIn("--require-renderers", doc); self.assertIn("--require-gui", gpu)
        self.assertEqual(gpu[gpu.index("--backend")+1], "egl")
        self.assertLess(commands.index(doc), commands.index(gpu))
    def test_mac_selects_metal(self):
        code, _, commands, _ = simulate(["--require-gui"], identity=dict(IDENTITY, os="macosx", architecture="aarch64"))
        self.assertEqual(code, 0)
        gpu = next(c for c in commands if c[1].endswith("validate-gpu-frame-reuse.py"))
        self.assertEqual(gpu[gpu.index("--backend")+1], "metal")
    def test_windows_explicit_warp(self):
        code, _, commands, _ = simulate(["--require-gui", "--adapter", "warp"], identity=dict(IDENTITY, os="windows"))
        self.assertEqual(code, 0)
        gpu = next(c for c in commands if c[1].endswith("validate-gpu-frame-reuse.py"))
        self.assertEqual(gpu[gpu.index("--backend")+1], "direct3d")
        self.assertEqual(gpu[gpu.index("--adapter")+1], "warp")
    def test_wrong_adapter(self):
        code, result, _, _ = simulate(["--require-gui", "--adapter", "warp"])
        self.assertEqual(code, 1); self.assertIn("Direct3D", result["error"])
    def test_compiles_actual_example(self):
        code, _, commands, _ = simulate()
        self.assertEqual(code, 0)
        compile = next(c for c in commands if "make" in c)
        self.assertTrue(any(x.replace('\\', '/').endswith('examples/dc-closure.rkt') for x in compile))
        self.assertTrue(any(x.replace('\\', '/').endswith('private/dc-font-name-native.rkt') for x in compile))
    def test_missing_interpreter(self):
        code, result, _, _ = simulate(missing=True)
        self.assertEqual(code, 1); self.assertIn("not found", result["error"])
    def test_bad_identity(self):
        code, result, _, _ = simulate(identity=dict(IDENTITY, pointer_bytes=4))
        self.assertEqual(code, 1); self.assertFalse(result["document_baseline_passed"])
    def test_pure_failure_stops_native_and_documents(self):
        code, _, commands, _ = simulate(fail="dc-closure-pure-test.rkt")
        self.assertEqual(code, 1)
        self.assertFalse(any(c[1].endswith("dc-closure-native-test.rkt") for c in commands))
        self.assertFalse(any(c[1].endswith("validate-dc-output.py") for c in commands))
    def test_native_failure_stops_documents(self):
        code, _, commands, _ = simulate(fail="dc-closure-native-test.rkt")
        self.assertEqual(code, 1); self.assertFalse(any(c[1].endswith("validate-dc-output.py") for c in commands))
    def test_partial_suite_stops_documents(self):
        code, result, _, _ = simulate(bad_suite="pretend pass\n")
        self.assertEqual(code, 1); self.assertEqual(result["completed_suites"], [])
    def test_document_failure_stops_gui(self):
        code, result, commands, _ = simulate(["--require-gui"], fail="validate-dc-output.py")
        self.assertEqual(code, 1); self.assertFalse(result["document_baseline_passed"])
        self.assertFalse(any(c[1].endswith("validate-gpu-frame-reuse.py") for c in commands))
    def test_failed_document_report_stops_gui(self):
        code, result, _, _ = simulate(["--require-gui"], bad_document=lambda r: r.update(structure_passed=False))
        self.assertEqual(code, 1); self.assertFalse(result["gui_baseline_passed"])
    def test_gui_failure_stays_failed(self):
        code, result, _, _ = simulate(["--require-gui"], fail="validate-gpu-frame-reuse.py")
        self.assertEqual(code, 1); self.assertTrue(result["document_baseline_passed"])
        self.assertFalse(result["gui_baseline_passed"])
    def test_partial_gui_report_stays_failed(self):
        code, result, _, _ = simulate(["--require-gui"], bad_gui=lambda r: r.update(gui_reuse_passed=False))
        self.assertEqual(code, 1); self.assertFalse(result["gui_baseline_passed"])
    def test_source_mutation(self):
        code, result, _, _ = simulate(mutate=True)
        self.assertEqual(code, 1); self.assertIn("source changed", result["error"])
    def test_duplicate_json_baseline(self):
        code, _, _, _ = simulate(report_text='{"status":"passed","status":"failed"}')
        self.assertEqual(code, 1)
    def test_manifest_checked_at_both_ends(self):
        code, _, commands, _ = simulate()
        self.assertEqual(code, 0)
        manifests = [c for c in commands if c[1].endswith("update-source-sums.py")]
        self.assertEqual(len(manifests), 2)
        self.assertTrue(all("--check" in c for c in manifests))
    def test_invalid_cli_combinations(self):
        for opts in (("--backend", "metal"), ("--adapter", "warp"), ("--timeout", "nan"), ("--timeout", "0")):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit): v.main(opts)
    def test_existing_evidence_directory_refused(self):
        with tempfile.TemporaryDirectory() as temp, self.assertRaises(FileExistsError):
            v.main(["--directory", temp])


class Sources(unittest.TestCase):
    def source(self, name): return (ROOT / name).read_text(encoding="utf-8")
    def test_case_counts(self):
        for name, n in v.COUNTS.items():
            text = self.source(f"tests/{name}-test.rkt")
            self.assertEqual(text.count("(test-case "), n)
            self.assertIn(f"(define {name}-test-count {n})", text)
    def test_all_focused_sources_fingerprinted(self):
        for name in ("private/dc-font-name-native.rkt", "private/dc-font-name.rkt", "private/dc-text-spec.rkt",
                     "private/dc-text.rkt", "private/dc-compatibility.rkt", "tests/dc-consumer-fixtures.rkt"):
            self.assertIn(name, v.SOURCES)
    def test_plain_name_parser_is_lazy(self):
        text = self.source("private/dc-font-name.rkt")
        self.assertIn("delay/sync", text); self.assertIn("dynamic-require parser-module", text)
        self.assertIn('(string-contains? checked ",")', text)
    def test_native_parser_only_uses_description_operations(self):
        text = self.source("private/dc-font-name-native.rkt")
        functions = set(re.findall(r'get-ffi-obj "([^"]+)"', text))
        expected = {"pango_font_description_" + n for n in
                    ("from_string", "free", "get_family", "get_weight", "get_style", "get_stretch", "get_variant", "get_set_fields")}
        self.assertEqual(functions, expected)
        self.assertIn("(dynamic-require 'racket/draw/unsafe/pango-lib 'pango-lib)", text)
        self.assertNotIn("(only-in racket/draw/unsafe/pango-lib", text)
        self.assertIn("exn:fail:filesystem:missing-module?", text)
        for name in ("libpango-1.0", "libpango-1.0.0.dylib", "libpango-1.0-0.dll",
                     "libfribidi.0.dylib", "libfribidi-0.dll"):
            self.assertIn(name, text)
        self.assertIn("legacy-pango-dependencies", text)
        self.assertIn('(or cairo-lock-name "pango-lock")', text)
        self.assertIn('(lambda () (free-description description))', text)
        self.assertIn('parameterize-break #f', text)
        self.assertIn('vector-immutable', text)
        for forbidden in ("pango_layout_", "pango_font_map_", "pango_cairo_", "cairo_create", "skia-check!"):
            self.assertNotIn(forbidden, text)
    def test_fields_fail_closed(self):
        text = self.source("private/dc-font-name.rkt")
        for token in ("pango-family-list", "pango-font-variant", "pango-font-extra-fields", "(bitwise-not #x3f)",
                      '(string-contains? family ",")', '(add1 (string-utf-8-length value))'):
            self.assertIn(token, text)
    def test_actual_directory_mapping_not_get_face_shortcut(self):
        text = self.source("private/dc-text-spec.rkt")
        code = '\n'.join(l for l in text.splitlines() if not l.lstrip().startswith(';'))
        self.assertIn("get-screen-name", code); self.assertNotIn("(send f get-face)", code)
        self.assertIn("(send f get-size #t)", code)
    def test_width_reaches_primary_and_fallback(self):
        text = self.source("private/dc-text.rkt")
        self.assertEqual(text.count("#:width (dc-font-request-width "), 2)
        self.assertIn("sk:typeface-from-family", text); self.assertIn("sk:font-manager-match-character", text)
    def test_native_rendering_still_uses_skia_harfbuzz(self):
        text = self.source("private/dc-text.rkt")
        for term in ("sk:layout-mixed-text", "sk:draw-mixed-text-layout", "sk:font-get-metrics"):
            self.assertIn(term, text)
        self.assertNotIn("pango_cairo", text)
    def test_new_query_is_additive(self):
        text = self.source("dc.rkt")
        for name in ("skia-dc%", "skia-dc?", "skia-dc-capabilities", "exn:fail:skia-dc:unsupported", "skia-dc-compatibility"):
            self.assertIn(name, text)
        report = self.source("private/dc-compatibility.rkt")
        self.assertIn("'native_probe_performed #f", report)
        self.assertIn("'full_drop_in_compatibility #f", report)
    def test_real_interface_and_arity_oracles(self):
        text = self.source("tests/dc-closure-pure-test.rkt")
        self.assertIn("interface->method-names rd:dc<%>", text)
        self.assertIn("object-method-arity-includes?", text)
        self.assertIn("make-skia-dc-class", text)
    def test_full_regression_and_source_ci_integrated(self):
        text = self.source("run-tests.rkt")
        self.assertIn("(run-tests dc-closure-pure-tests)", text)
        self.assertIn("dynamic-require dc-closure-native-tests-file 'dc-closure-native-tests", text)
        self.assertIn("'test-dc-closure.py'", self.source("tools/ci.py"))
    def test_existing_pict_oracles_exercise_descriptions(self):
        text = self.source("tests/dc-consumer-fixtures.rkt")
        self.assertIn('(string-append mapped-name ",")', text)
        self.assertIn('(p:text "Skia / pict" described-font)', text)
    def test_existing_document_workflow_requires_new_gate(self):
        text = self.source(".github/workflows/dc-output.yml")
        self.assertIn("tools/validate-dc-closure.py", text)
        self.assertIn("--require-renderers", text)
        self.assertIn("racket: ['8.18', '9.3']", text)
        self.assertIn("python tools/test-dc-closure.py", text)
        self.assertNotIn("continue-on-error:", text)
    def test_actual_example_compiled_and_cli_state_local(self):
        text = self.source("examples/dc-closure.rkt")
        self.assertLess(text.index("(module+ main"), text.index("(define directory"))
        self.assertIn("save-output/audit", text)
        self.assertIn("output-page->image", text)
    def test_version_and_minimum(self):
        text = self.source("info.rkt")
        self.assertIn('(define version "0.78")', text)
        self.assertIn('("base" #:version "8.18")', text)
        self.assertIn('("draw-lib" #:version "1.22")', text)
    def test_explicit_documented_exclusions(self):
        text = self.source("docs/DC-COMPATIBILITY.md")
        for term in ("Pango family cascades", "Native Cairo-handle brushes", "variable axes", "VT", "FF",
                     "does **not** certify", "not a full", "0.65"):
            self.assertIn(term, text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
