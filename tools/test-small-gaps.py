#!/usr/bin/env python3
"""0.78b receipt/orchestration regressions and mandatory real source integration.

Mocked command tests establish fail-closed orchestration, not Racket/native execution.
The default invocation includes RepositoryIntegration; it must not be skipped in CI.
"""
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

import small_gap_validation as v
ROOT = Path(__file__).resolve().parents[1]


def complete(label, count):
    return (f"{count} success(es) 0 failure(s) 0 error(s) {count} test(s) run\n"
            f"{label}: {count} cases, 0 failures\n")


class Completion(unittest.TestCase):
    def valid(self):
        return complete("small-gap-native", v.NATIVE_CASES)
    def check(self, text):
        v.suite_output(text, "small-gap-native", v.NATIVE_CASES)
    def test_valid(self): self.check(self.valid())
    def test_crlf(self): self.check(self.valid().replace("\n", "\r\n"))
    def test_empty(self):
        with self.assertRaises(ValueError): self.check("")
    def test_missing_completion(self):
        with self.assertRaises(ValueError): self.check(self.valid().splitlines()[0])
    def test_duplicate(self):
        with self.assertRaises(ValueError): self.check(self.valid() * 2)
    def test_wrong_count(self):
        with self.assertRaises(ValueError): self.check(complete("small-gap-native", v.NATIVE_CASES - 1))
    def test_failure(self):
        with self.assertRaises(ValueError): self.check(self.valid().replace("0 failures", "1 failures"))
    def test_error(self):
        with self.assertRaises(ValueError): self.check(self.valid().replace("0 error(s)", "1 error(s)"))
    def test_extra_error(self):
        with self.assertRaises(ValueError): self.check(self.valid() + "ERROR\n")
    def test_wrong_label(self):
        with self.assertRaises(ValueError): self.check(complete("small-gap-pure", v.NATIVE_CASES))


class Orchestration(unittest.TestCase):
    def invoke(self, *, source_only=False, failed=None, malformed=False, drift=False, existing=False):
        spec = importlib.util.spec_from_file_location("small_gap_driver_test", ROOT / "tools/validate-small-gaps.py")
        driver = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(driver)
        calls = []
        audits = []
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            directory = root / "evidence"
            if existing:
                directory.mkdir()
                (directory / "keep").write_text("unchanged")
            def audit(_):
                audits.append(1)
                if failed == "audit" or drift and len(audits) > 1:
                    raise ValueError("synthetic source drift")
                return dict(in_scope_gaps_closed=True, release_ready=False)
            def run(command, **kwargs):
                calls.append(command)
                name = Path(command[1]).name
                if failed == "timeout" and name == "small-gap-native-test.rkt":
                    raise subprocess.TimeoutExpired(command, 300)
                output = ""
                if name == "small-gap-pure-test.rkt": output = complete("small-gap-pure", v.PURE_CASES)
                if name == "small-gap-native-test.rkt": output = complete("small-gap-native", v.NATIVE_CASES)
                if malformed and name == "small-gap-native-test.rkt": output = ""
                kwargs["stdout"].write(output)
                return subprocess.CompletedProcess(command, 1 if failed == name else 0)
            args = ["--directory", str(directory)] + (["--source-only"] if source_only else ["--racket", "racket"])
            with patch.object(driver, "source_contracts", side_effect=audit), \
                 patch.object(driver.shutil, "which", return_value="/synthetic/racket"), \
                 patch.object(driver.subprocess, "run", side_effect=run), \
                 contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                code = driver.main(args, root=root)
            report = json.loads((directory / "report.json").read_text()) if (directory / "report.json").exists() else None
            if existing:
                self.assertEqual((directory / "keep").read_text(), "unchanged")
            return code, report, calls
    def test_source_only_not_native(self):
        code, report, calls = self.invoke(source_only=True)
        self.assertEqual(code, 0); self.assertFalse(report["native_attempted"])
        self.assertFalse(report["native_executed"]); self.assertFalse(report["pure_executed"])
    def test_complete(self):
        code, report, calls = self.invoke()
        self.assertEqual(code, 0); self.assertTrue(report["pure_executed"]); self.assertTrue(report["native_executed"])
        self.assertFalse(report["gpu_executed"]); self.assertFalse(report["document_rendering_executed"])
        self.assertFalse(report["release_ready"]); self.assertFalse(report["null_surface_implemented"])
    def test_audit_failure(self):
        code, report, calls = self.invoke(failed="audit")
        self.assertEqual(code, 1); self.assertEqual(calls, [])
    def test_compile_failure(self):
        code, report, calls = self.invoke(failed="-l")
        self.assertEqual(code, 1); self.assertFalse(report["pure_executed"])
    def test_pure_failure(self):
        code, report, calls = self.invoke(failed="small-gap-pure-test.rkt")
        self.assertEqual(code, 1); self.assertFalse(report["native_attempted"])
    def test_native_failure(self):
        code, report, calls = self.invoke(failed="small-gap-native-test.rkt")
        self.assertEqual(code, 1); self.assertTrue(report["native_attempted"]); self.assertFalse(report["native_executed"])
    def test_empty_native_output(self):
        code, report, calls = self.invoke(malformed=True)
        self.assertEqual(code, 1); self.assertFalse(report["native_executed"])
    def test_example_failure(self):
        self.assertEqual(self.invoke(failed="small-gaps.rkt")[0], 1)
    def test_timeout(self):
        code, report, calls = self.invoke(failed="timeout")
        self.assertEqual(code, 1); self.assertFalse(report["native_executed"])
    def test_post_execution_source_drift(self):
        self.assertEqual(self.invoke(drift=True)[0], 1)
    def test_existing_evidence_is_not_overwritten(self):
        code, report, calls = self.invoke(existing=True)
        self.assertEqual(code, 1); self.assertIsNone(report); self.assertEqual(calls, [])


class RepositoryIntegration(unittest.TestCase):
    def test_complete_source_review(self):
        result = v.source_contracts(ROOT)
        self.assertTrue(result["in_scope_gaps_closed"])
        self.assertFalse(result["release_ready"])
    def test_no_new_native_layout_or_raw_null_binding(self):
        native = (ROOT / "private/native.rkt").read_text()
        for name in v.NATIVE_SYMBOLS:
            self.assertEqual(native.count("(define-native " + name + " "), 1)
        self.assertNotIn("(define-native sk_surface_new_null ", native)
    def test_exclusion_documents_snapshot_boundary(self):
        doc = (ROOT / "docs/SMALL-GAPS.md").read_text()
        for word in ("intentionally excluded", "call-with-nodraw-canvas", "snapshot", "0.78c", "0.78d"):
            self.assertIn(word, doc)


if __name__ == "__main__":
    unittest.main(verbosity=2)
