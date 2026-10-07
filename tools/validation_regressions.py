"""Explicit full-suite scope shared by standalone feature validators.

This is not a subprocess filter: feature commands and their inspectors always
run. A caller must deliberately opt out of the global run-tests.rkt suite.
A skipped suite is recorded as not-run, never as a successful regression run.
"""
from __future__ import annotations

import argparse
from collections.abc import Callable
from pathlib import Path
import re
from typing import Any, TypeVar

MODES = ('full', 'none')
T = TypeVar('T')
FIELDS = ('regressions_mode', 'regressions_requested', 'regressions_attempted',
          'regressions_completed', 'regressions_passed', 'regressions_status')


def checked_mode(mode: str) -> str:
    if not isinstance(mode, str) or mode not in MODES:
        raise ValueError('regressions must be full or none')
    return mode


def add_regression_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument('--regressions', choices=MODES, default='full',
                        help='full (default): run the global regression suite; '
                             'none: feature acceptance only, global regressions NOT RUN')


def global_compile_targets(root: Path) -> list[Path]:
    """Compile the full runner and its dynamically loaded native suites."""
    text = (root / 'run-tests.rkt').read_text(encoding='utf-8')
    names = sorted(set(re.findall(
        r'\(define-runtime-path\s+\S+\s+"(tests/[^"\n]+\.rkt)"\)', text)))
    if not names:
        raise ValueError('empty dynamic regression compile graph')
    for name in names:
        if any(p in ('', '.', '..') for p in name.split('/')) or '\\' in name or ':' in name:
            raise ValueError('unsafe regression compile target')
    return [root / 'run-tests.rkt', *(root / name for name in names)]


class RegressionGate:
    """Track only the global suite, not feature-specific baseline tests."""

    def __init__(self, mode: str, report: dict[str, Any]):
        self.mode = checked_mode(mode)
        self.report = report
        report.update(regressions_mode=mode, regressions_requested=(mode == 'full'),
                      regressions_attempted=False, regressions_completed=False,
                      regressions_passed=False,
                      regressions_status='pending' if mode == 'full' else 'not-run')

    def run(self, action: Callable[[], T]) -> T | None:
        if self.mode == 'none':
            print('Global regressions: NOT RUN (--regressions=none).', flush=True)
            return None
        if self.report['regressions_status'] != 'pending':
            raise ValueError('global regressions already attempted')
        self.report.update(regressions_attempted=True, regressions_status='running')
        try:
            value = action()
        except BaseException:
            self.report['regressions_status'] = 'failed'
            raise
        self.report.update(regressions_completed=True, regressions_passed=True,
                           regressions_status='passed')
        return value

    def inherit(self, child: dict[str, Any]) -> None:
        """Accept a nested validator's result only for the requested scope.

        The outer caller separately validates that child's feature acceptance,
        interpreter identity, captures and document matrix.
        """
        expected = dict(regressions_mode=self.mode, regressions_requested=self.mode == 'full',
                        regressions_attempted=self.mode == 'full',
                        regressions_completed=self.mode == 'full', regressions_passed=self.mode == 'full',
                        regressions_status='passed' if self.mode == 'full' else 'not-run')
        if not isinstance(child, dict) or child.get('status') != 'passed':
            raise ValueError('nested regression report did not pass selected gates')
        for field, value in expected.items():
            actual = child.get(field)
            if type(actual) is not type(value) or actual != value:
                raise ValueError('nested regression scope/report mismatch: ' + field)
        self.report.update(expected)


def automatic_regression_mode(event: str, ref: str, requested: str = '') -> str:
    """Match ci.yml's automatic triggers exactly, including case and tag slashes.

    GitHub expression string comparisons ignore case, whereas branch/tag
    filters are case-sensitive. Keep this decision in Python rather than
    duplicating a subtly broader expression in each calling job.
    """
    if requested:
        return checked_mode(requested)
    tag_prefix = 'refs/tags/'
    tag = ref[len(tag_prefix):] if ref.startswith(tag_prefix) else ''
    covered = event == 'pull_request' or (
        event == 'push' and (ref == 'refs/heads/main' or
                             (tag.startswith('v') and '/' not in tag)))
    return 'none' if covered else 'full'


def main(argv=None) -> int:
    import os
    parser = argparse.ArgumentParser(description='Select the Acceptance global-regression scope.')
    parser.add_argument('--github-output', action='store_true', required=True)
    parser.parse_args(argv)
    output = os.environ.get('GITHUB_OUTPUT')
    if not output:
        parser.error('GITHUB_OUTPUT is required')
    try:
        mode = automatic_regression_mode(os.environ.get('GITHUB_EVENT_NAME', ''),
                                         os.environ.get('GITHUB_REF', ''),
                                         os.environ.get('SKIA_REQUESTED_REGRESSIONS', ''))
    except ValueError as error:
        parser.error(str(error))
    with open(output, 'a', encoding='utf-8') as stream:
        stream.write('regressions=' + mode + '\n')
    print('Acceptance global regressions: ' + mode)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
