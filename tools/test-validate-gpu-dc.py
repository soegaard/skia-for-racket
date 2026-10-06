#!/usr/bin/env python3
"""Synthetic validator regressions. These tests do NOT execute Racket or a GPU."""
from __future__ import annotations
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("validate_gpu_dc", HERE / "validate-gpu-dc.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
IDENTITY = dict(version="9.3.0.2", architecture="x86_64", os="unix", pointer_bytes=8, vm="chez-scheme")

def suite(name):
    n = v.COUNTS[name]
    return f"{n} success(es) 0 failure(s) 0 error(s) {n} test(s) run\n{name}: {n} cases, 0 failures; synthetic fixture.\n"

class Summaries(unittest.TestCase):
    def test_accept_complete(self):
        for name in v.COUNTS: v.validate_suite(suite(name), name)
    def test_reject_empty(self):
        with self.assertRaises(ValueError): v.validate_suite("", "gpu-dc-native")
    def test_reject_skip(self):
        with self.assertRaises(ValueError): v.validate_suite("SKIPPED: no GPU", "gpu-dc-native")
    def test_reject_duplicate(self):
        with self.assertRaises(ValueError): v.validate_suite(suite("gpu-dc-gui") * 2, "gpu-dc-gui")
    def test_reject_missing_marker(self):
        with self.assertRaises(ValueError): v.validate_suite(suite("gpu-dc-gui").splitlines()[0], "gpu-dc-gui")
    def test_reject_incomplete_count(self):
        with self.assertRaises(ValueError): v.validate_suite(suite("gpu-dc-native").replace("15", "14"), "gpu-dc-native")
    def test_reject_failure(self):
        with self.assertRaises(ValueError): v.validate_suite(suite("gpu-dc-native").replace("0 failure(s)", "1 failure(s)"), "gpu-dc-native")
    def test_reject_printed_gui_check_failure(self):
        with self.assertRaises(ValueError): v.validate_suite("FAILURE\n" + suite("gpu-dc-gui"), "gpu-dc-gui")
    def test_reject_wrong_suite(self):
        with self.assertRaises(ValueError): v.validate_suite(suite("gpu-dc-pure"), "gpu-dc-native")

class Identity(unittest.TestCase):
    def test_accept(self): self.assertEqual(v.validate_identity(IDENTITY), IDENTITY)
    def test_minimum(self): self.assertEqual(v.validate_identity(dict(IDENTITY, version="8.18"))["version"], "8.18")
    def test_bad_versions(self):
        for version in (None, True, "8.17", "nightly", "9.3.1.2.3"):
            with self.subTest(version=version), self.assertRaises(ValueError): v.validate_identity(dict(IDENTITY, version=version))
    def test_bad_identity(self):
        for key, value in (("pointer_bytes", True), ("pointer_bytes", 4), ("vm", "racket"),
                           ("architecture", "arm"), ("os", "unknown")):
            with self.subTest(key=key, value=value), self.assertRaises(ValueError): v.validate_identity(dict(IDENTITY, **{key: value}))
    def test_backend_choices(self):
        self.assertEqual(v.select_backends("auto", IDENTITY), ("egl", "opengl"))
        self.assertEqual(v.select_backends("auto", dict(IDENTITY, os="macosx")), ("metal", "metal"))
        self.assertEqual(v.select_backends("auto", dict(IDENTITY, os="windows")), ("direct3d", "direct3d"))
        self.assertEqual(v.select_backends("egl", dict(IDENTITY, os="macosx")), ("egl", "opengl"))

class Runner(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.r = v.Runner(self.directory, 20)
    def test_logs_success(self):
        with patch.object(v.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"ok\n")):
            self.assertEqual(self.r.run(["/selected/racket", "a.rkt"], self.directory), "ok\n")
        self.assertEqual((self.directory / "logs/001.log").read_bytes(), b"ok\n")
        self.assertEqual(self.r.commands[0]["argv"][0], "/selected/racket")
    def test_nonzero_is_fatal(self):
        with patch.object(v.subprocess, "run", return_value=subprocess.CompletedProcess([], 2, b"failed")):
            with self.assertRaises(RuntimeError): self.r.run(["racket"], self.directory)
        self.assertEqual(self.r.commands[0]["returncode"], 2)
    def test_timeout_is_fatal_and_logs_partial_output(self):
        with patch.object(v.subprocess, "run", side_effect=subprocess.TimeoutExpired([], 20, output=b"partial")):
            with self.assertRaises(RuntimeError): self.r.run(["racket"], self.directory)
        self.assertTrue(self.r.commands[0]["timed_out"])
        self.assertIn(b"partial", (self.directory / "logs/001.log").read_bytes())
    def test_launch_failure_is_recorded(self):
        with patch.object(v.subprocess, "run", side_effect=OSError("missing executable")):
            with self.assertRaises(OSError): self.r.run(["racket"], self.directory)
        self.assertIn("execution_error", self.r.commands[0])

class Workflow(unittest.TestCase):
    def run_gate(self, options=(), fail=None, mutate=False):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t)
            for name in v.SOURCES:
                path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text("fixture")
            out = root / "evidence"
            commands = []
            def run(args, root):
                args = list(map(str, args)); commands.append(args)
                if any("ci-identity.rkt" in x for x in args): return json.dumps(IDENTITY)
                for name in v.COUNTS:
                    if len(args) > 1 and args[1].endswith(f"/{name}-test.rkt"):
                        if name == fail: raise RuntimeError("selected suite failed")
                        if mutate and name == "gpu-dc-native": (root / "gpu-dc.rkt").write_text("changed")
                        return suite(name)
                return ""
            with patch.object(v.shutil, "which", return_value="/selected/racket"), \
                 patch.object(v.Runner, "run", side_effect=run), \
                 contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                code = v.main(["--racket", "/selected/racket", "--directory", str(out), *options], root=root)
            return code, json.loads((out / "validation.json").read_text()), commands
    def test_headless_never_claims_gui(self):
        code, result, commands = self.run_gate()
        self.assertEqual(code, 0); self.assertTrue(result["native_gpu_tests_passed"])
        self.assertFalse(result["gui_tests_passed"]); self.assertFalse(result["visible_screen_pixels_verified"])
        self.assertFalse(any(any("gui-test.rkt" in x for x in command) for command in commands))
    def test_required_gui_runs_and_is_reported(self):
        code, result, commands = self.run_gate(["--require-gui"])
        self.assertEqual(code, 0); self.assertTrue(result["gui_tests_passed"])
        self.assertTrue(any(command[-2:] == ["--backend", "opengl"] for command in commands))
    def test_native_failure_stops_gui(self):
        code, result, _ = self.run_gate(["--require-gui"], fail="gpu-dc-native")
        self.assertEqual(code, 1); self.assertFalse(result["gui_tests_passed"])
        self.assertFalse(result["native_gpu_tests_passed"])
    def test_gui_failure_not_silently_skipped(self):
        code, result, _ = self.run_gate(["--require-gui"], fail="gpu-dc-gui")
        self.assertEqual(code, 1); self.assertEqual(result["status"], "failed")
        self.assertFalse(result["gui_tests_passed"])
    def test_source_mutation_rejects_pass(self):
        code, result, _ = self.run_gate(mutate=True)
        self.assertEqual(code, 1); self.assertIn("source changed", result["error"])
    def test_wrong_backend_adapter_rejected(self):
        code, result, _ = self.run_gate(["--backend", "egl", "--adapter", "warp"])
        self.assertEqual(code, 1); self.assertIn("Direct3D", result["error"])
    def test_selected_interpreter_used_for_every_racket_command(self):
        code, _, commands = self.run_gate(["--require-gui"])
        self.assertEqual(code, 0)
        for command in commands:
            if not any("update-source-sums.py" in item for item in command):
                self.assertEqual(command[0], "/selected/racket")

class SourceContract(unittest.TestCase):
    def test_suite_counts_match_top_level_test_case_sources(self):
        for name, count in v.COUNTS.items():
            text = (HERE.parent / f"tests/{name}-test.rkt").read_text()
            self.assertEqual(text.count('(test-case "'), count, name)
    def test_no_cpu_factory_in_gpu_native_renderer(self):
        source = (HERE.parent / "private/gpu-dc-native.rkt").read_text()
        self.assertNotRegex(source, r"\(sk:make-surface(?:\s|\))")
        self.assertIn("gpu:make-gpu-surface", source)
        self.assertIn("#:internal-snapshot gpu:gpu-surface-snapshot", source)
    def test_public_module_does_not_import_gui(self):
        source = (HERE.parent / "gpu-dc.rkt").read_text()
        self.assertNotIn('"gpu-canvas.rkt"', source)
        self.assertNotIn("racket/gui", source)

if __name__ == "__main__":
    unittest.main()
