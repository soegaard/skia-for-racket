#!/usr/bin/env python3
"""Delivery checks: strict unified-hunk counts and ordinary Git application.

Run with no arguments for synthetic regression tests, or --patch PATH to check
an exported delivery. This does not replace git apply --check on its real base.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

HEADER = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?:.*)$')


def check_patch(text):
    lines = text.splitlines()
    path = None
    hunks = 0
    for i, line in enumerate(lines):
        if line.startswith('diff --git '): path = line[11:]
        if not line.startswith('@@'): continue
        m = HEADER.fullmatch(line)
        if not m: raise ValueError(f'{path}: malformed unified hunk header')
        old_n, new_n = int(m[2] or 1), int(m[4] or 1)
        old = new = context = meaningful = 0
        for body in lines[i+1:]:
            if body.startswith(('diff --git ', '@@')): break
            if body == r'\ No newline at end of file': continue
            if not body or body[0] not in ' +-':
                raise ValueError(f'{path}: missing unified-diff line prefix')
            if body[0] in ' -': old += 1
            if body[0] in ' +': new += 1
            if body[0] == ' ':
                context += 1
                meaningful += bool(body[1:].strip())
        if (old, new) != (old_n, new_n):
            raise ValueError(f'{path}: declared {old_n}/{new_n} lines but body contains {old}/{new}')
        # Whole-file additions/deletions legitimately have no shared context.
        if old_n and new_n and (context < 3 or not meaningful):
            raise ValueError(f'{path}: insufficient meaningful unchanged context')
        hunks += 1
    if not hunks: raise ValueError('no textual hunks to validate')
    return hunks


class Checks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='skia-patch-check-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        if not shutil.which('git'): self.fail('Git is required for delivery regression tests')
        self.git('init', '-q')
        self.git('config', 'user.name', 'Synthetic validation')
        self.git('config', 'user.email', 'validation@example.invalid')
        self.before = '# Testing\n\n## Current revision: offscreen OpenGL (0.39)\n\n' + ''.join(f'Unchanged validation instruction {i}.\n' for i in range(32))
        (self.root/'TESTING.md').write_text(self.before)
        self.git('add', 'TESTING.md'); self.git('commit', '-qm', 'Synthetic baseline')
        self.after = self.before.replace('## Current revision: offscreen OpenGL (0.39)',
            '## Current revision: GPU images (0.40)\n\nKeep prior validation evidence.\n\n## Previous revision: offscreen OpenGL (0.39)')
        (self.root/'TESTING.md').write_text(self.after)
        self.patch = self.git('diff', '--no-ext-diff', '--full-index', '--unified=8').stdout
    def git(self, *args, check=True):
        return subprocess.run(['git', *args], cwd=self.root, capture_output=True, text=True, check=check)
    def write_patch(self, value):
        p = self.root/'delivery.patch'; p.write_text(value); return str(p)
    def test_git_generated_counts(self): self.assertEqual(check_patch(self.patch), 1)
    def test_forward_application_without_relaxation(self):
        p = self.write_patch(self.patch); self.git('restore', 'TESTING.md')
        self.git('apply', '--check', p); self.git('apply', p)
        self.assertEqual((self.root/'TESTING.md').read_text(), self.after)
    def test_reverse_application_is_byte_exact(self):
        p = self.write_patch(self.patch)
        self.git('apply', '--reverse', '--check', p); self.git('apply', '--reverse', p)
        self.assertEqual((self.root/'TESTING.md').read_text(), self.before)
    def test_extra_postimage_line_count_is_rejected(self):
        bad = re.sub(r'(@@ -\d+,\d+ \+\d+,)(\d+)', lambda m:m[1]+str(int(m[2])+1), self.patch, count=1)
        with self.assertRaisesRegex(ValueError, 'declared'): check_patch(bad)
    def test_missing_body_line_is_rejected(self):
        bad = self.patch.replace('+Keep prior validation evidence.\n', '', 1)
        with self.assertRaisesRegex(ValueError, 'declared'): check_patch(bad)
    def test_zero_context_is_not_a_delivery_workaround(self):
        bad = self.git('diff', '--unified=0').stdout
        with self.assertRaisesRegex(ValueError, 'context'): check_patch(bad)
    def test_blank_context_is_not_meaningful(self):
        bad = 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,4 +1,4 @@\n \n \n-a\n+b\n \n'
        with self.assertRaisesRegex(ValueError, 'context'): check_patch(bad)
    def test_new_file_is_supported(self):
        (self.root/'new.rkt').write_text('#lang racket/base\n')
        self.git('add', '-N', 'new.rkt')
        self.assertEqual(check_patch(self.git('diff', '--unified=8').stdout), 2)
    def test_surrounding_real_content_is_preserved(self):
        p = self.write_patch(self.patch); self.git('restore', 'TESTING.md')
        tail = '\nUnrelated later documentation must remain unchanged.\n'
        (self.root/'TESTING.md').write_text(self.before+tail)
        self.git('apply', '--check', p); self.git('apply', p)
        self.assertEqual((self.root/'TESTING.md').read_text(), self.after+tail)
    def test_whitespace_check_passes(self): self.git('diff', '--check')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--patch', type=Path)
    args = parser.parse_args()
    if args.patch:
        try: print(f'Unified hunk counts/context passed: {check_patch(args.patch.read_text())} hunks')
        except (ValueError, OSError) as error: parser.exit(1, str(error)+'\n')
    else:
        raise SystemExit(0 if unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks)).wasSuccessful() else 1)
