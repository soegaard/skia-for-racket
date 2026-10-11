#!/usr/bin/env python3
"""Test the narrow approval guard; these tests do not claim Racket reflection."""
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).with_name('accept-gpu-render-api.py')
spec = importlib.util.spec_from_file_location('gpu_render_approval', path)
approval = importlib.util.module_from_spec(spec)
spec.loader.exec_module(approval)


class ApprovalGuardTests(unittest.TestCase):
    def test_exact_addition(self):
        self.assertTrue(approval.validate_changes([copy.deepcopy(approval.ADDITION)],
                                                   copy.deepcopy(approval.ENTRY)))

    def test_syntax_backed_callable_keeps_its_observed_category(self):
        entry = dict(approval.ENTRY, export_kind='syntax')
        change = dict(approval.ADDITION, export_kind='syntax', after=entry)
        self.assertTrue(approval.validate_changes([change], entry))

    def test_already_accepted(self):
        self.assertFalse(approval.validate_changes([], copy.deepcopy(approval.ENTRY)))

    def test_missing_function(self):
        with self.assertRaises(ValueError):
            approval.validate_changes([], None)

    def test_extra_optional_keyword(self):
        entry = copy.deepcopy(approval.ENTRY)
        entry['allowed_keywords'].append('fallback')
        with self.assertRaises(ValueError):
            approval.validate_changes([approval.ADDITION], entry)

    def test_backend_became_optional(self):
        entry = copy.deepcopy(approval.ENTRY)
        entry['required_keywords'] = []
        with self.assertRaises(ValueError):
            approval.validate_changes([approval.ADDITION], entry)

    def test_unrelated_addition(self):
        extra = dict(approval.ADDITION, name='other-function')
        with self.assertRaises(ValueError):
            approval.validate_changes([approval.ADDITION, extra], approval.ENTRY)

    def test_replacement_not_addition(self):
        changed = dict(approval.ADDITION, change='changed', before=approval.ENTRY)
        with self.assertRaises(ValueError):
            approval.validate_changes([changed], approval.ENTRY)

    def test_wrong_module(self):
        changed = dict(approval.ADDITION, module='main.rkt')
        with self.assertRaises(ValueError):
            approval.validate_changes([changed], approval.ENTRY)


if __name__ == '__main__':
    unittest.main()
