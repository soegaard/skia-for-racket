#!/usr/bin/env python3
"""Check source policy only, or validate one complete dispatched release attempt.

No option refreshes a frozen policy, dispatches jobs, retries failed jobs,
creates a tag, changes branch protection or publishes a package.
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import sys
import traceback
import uuid

import release_candidate as rc
from release_graph import STAGE, BASELINE, POLICY, json_text, need, relative
ROOT = Path(__file__).resolve().parents[1]


def main(argv=None, *, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--source-only', action='store_true', help='no network or runtime pass')
    mode.add_argument('--github', action='store_true', help='only inside the release workflow with a read token')
    parser.add_argument('--directory', type=Path, help='new evidence directory; existing output is refused')
    args = parser.parse_args(argv)
    directory = (args.directory or root / 'output' / ('release-candidate-' + uuid.uuid4().hex)).resolve()
    try:
        directory.mkdir(parents=True, exist_ok=False)
    except OSError:
        print('Evidence directory must be new and writable.', file=sys.stderr)
        return 1
    result = {'schema': 1, 'stage': STAGE, 'integration_baseline': BASELINE, 'status': 'failed',
              'source_verified': False, 'release_candidate_validated': False,
              'github_evidence_observed': False, 'rendering_executed_by_this_validator': False,
              'physical_display_or_hardware_performance_verified': False, 'release_ready': False,
              'publication_performed': False}
    code = 1
    try:
        policy = rc.source_contracts(root)
        before = rc.digest(relative(root, POLICY))
        # Source-only may validate a prepared working tree; it does not package it.
        result.update(source_verified=True, required_jobs=len(policy['jobs']),
                      required_artifacts=len(policy['artifact_names']), policy_sha256=before)
        if args.source_only:
            result['status'] = 'source-only'
        else:
            source = rc.clean_source(root)
            rc.write_json(directory / 'source.json', source)
            rc.write_json(directory / 'policy.json', policy)
            result.update(rc.collect(root, directory, policy, source))
            need(rc.clean_source(root) == source, 'source changed during evidence collection')
            need(rc.digest(relative(root, POLICY)) == before, 'policy changed during validation')
            package = rc.source_archive(root, directory / 'skia-for-racket-source.zip')
            need(rc.clean_source(root) == source, 'source changed during archive creation')
            result.update(source=source, source_archive=package, status='validated-release-candidate',
                          release_candidate_validated=True)
            result['evidence_boundary'] = ('Same-run-attempt execution of every reviewed job/step plus verified artifact ZIPs. '
                'Native, document, and consumer assertions are delegated to their executing validators. '
                'The enclosing GitHub job must also complete successfully; this is not 1.0 publication approval.')
        code = 0
    except Exception as error:
        result['error'] = str(error)
        # Traceback contains local source locations, never environment/token dumps.
        (directory / 'failure.txt').write_text(traceback.format_exc(), encoding='utf-8')
        print('Release candidate validation failed: ' + str(error), file=sys.stderr)
    finally:
        (directory / 'result.json').write_text(json_text(result), encoding='utf-8', newline='\n')
        summary = ('## Release candidate — 0.78d\n\nStatus: **' + result['status'] + '**.\n\n'
                   'Source policy checks alone do not establish runtime acceptance. '
                   'No tag or release was published. See result.json, source.json, the frozen policy, '
                   'and the job/step/artifact evidence.\n')
        (directory / 'summary.md').write_text(summary, encoding='utf-8', newline='\n')
        step_summary = os.environ.get('GITHUB_STEP_SUMMARY')
        if step_summary:
            with open(step_summary, 'a', encoding='utf-8') as output:
                output.write(summary)
    print('Release evidence: ' + str(directory))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
