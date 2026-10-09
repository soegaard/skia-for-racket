#!/usr/bin/env python3
"""Verify the 0.78c API baseline; source-only/headless-only are explicit partial checks."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import sys
import uuid

import public_api as api
ROOT = Path(__file__).resolve().parents[1]


def main(argv=None, *, root=ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--racket', help='Racket CS executable (full distribution)')
    mode.add_argument('--source-only', action='store_true', help='do not claim any Racket/API execution')
    parser.add_argument('--headless-only', action='store_true', help='partial import check; not a complete 0.78c pass')
    parser.add_argument('--directory', type=Path, help='new evidence directory')
    args = parser.parse_args(argv)
    if args.source_only and args.headless_only:
        parser.error('--headless-only requires --racket')
    root = Path(root).resolve()
    token = uuid.uuid4().hex
    directory = (args.directory or root / 'output' / ('public-api-' + token)).resolve()
    try:
        directory.mkdir(parents=True, exist_ok=False)
    except OSError as error:
        print(f'Public API evidence directory refused: {error}', file=sys.stderr)
        return 1
    result = dict(schema=1, stage=api.STAGE, run_token=token, status='failed',
                  source_verified=False, racket_executed=False, reflection_tests_passed=False,
                  aggregate_pure_passed=False, groups_verified=[], api_signatures_verified=False,
                  rendering_executed=False, release_ready=False, commands=[])
    try:
        result['source'] = api.source_contracts(root)
        # Preserve the independent reviewed source graph; don't replace its
        # checks with the new callable signature comparison.
        import release_scope
        scope = release_scope.audit(root)
        api.need(scope['in_scope_gaps_closed'] and not scope['release_ready'], 'release scope is not closed')
        result['source_verified'] = True
        policy = api.read_json(root / api.POLICY)
        frozen_paths = [api.POLICY, api.REPORT, api.CONTRACT, *api.SNAPSHOTS.values()]
        frozen = {p: api.file_hash(root / p) for p in frozen_paths}
        if args.source_only:
            result['status'] = 'source-only'
        else:
            racket = shutil.which(args.racket)
            api.need(racket is not None, 'Racket executable not found: ' + args.racket)
            env = api.isolated_environment(directory, 'headless')
            def execute(label, command):
                result['commands'].append(dict(label=label, command=[str(x) for x in command], status='running'))
                text = api.run_logged(command, root=root, env=env, log=directory / (label + '.log'), timeout=900)
                result['commands'][-1]['status'] = 'passed'
                result['racket_executed'] = True
                return text
            execute('compile-runner-and-probe', [racket, '-l', 'raco', '--', 'make',
                    str(root / 'run-tests.rkt'), str(root / 'tools/public-api-probe.rkt'),
                    str(root / 'tests/public-api-pure-test.rkt'),
                    str(root / 'examples/public/value-basics.rkt'),
                    str(root / 'examples/public/raster-lifetime.rkt')])
            text = execute('reflection-fixtures', [racket, str(root / 'tests/public-api-pure-test.rkt')])
            api.checked_pure_output(text)
            result['reflection_tests_passed'] = True
            text = execute('aggregate-pure', [racket, str(root / 'run-tests.rkt'), '--pure'])
            api.need('Native rendering tests NOT RUN (--pure).' in text, 'aggregate pure runner did not complete')
            # RackUnit can report failures without a nonzero result in a broken
            # runner. Inspect every suite summary as well as the process exit.
            import re
            summaries = re.findall(r'(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run', text)
            api.need(bool(summaries) and all(int(s) == int(n) and f == '0' and e == '0' for s, f, e, n in summaries),
                     'aggregate pure result reported an incomplete/failed suite')
            api.need(not re.search(r'\b(?:ERROR|FAILURE)\b', text), 'aggregate pure failure output')
            result['aggregate_pure_passed'] = True
            text = execute('public-value-example', [racket, str(root / 'examples/public/value-basics.rkt')])
            api.need(text.strip() == 'public-value-example: passed', 'public example did not complete')
            groups = ('headless',) if args.headless_only else api.GROUPS
            for group in groups:
                observation = api.reflect_group(root, root / api.POLICY, group, racket, directory, token)
                expected = api.checked_snapshot(api.read_json(root / api.SNAPSHOTS[group]), policy, group)
                actual = api.snapshot_from_observation(observation, policy, group, token)
                changes = api.differences(expected, actual)
                (directory / f'{group}-diff.json').write_text(api.json_text(changes), encoding='utf-8')
                api.need(not changes, f'{group} public API drift ({len(changes)} entries); see {group}-diff.json')
                result['groups_verified'].append(group)
            result['api_signatures_verified'] = result['groups_verified'] == list(api.GROUPS)
            result['status'] = 'passed' if result['api_signatures_verified'] else 'headless-only'
        api.need(frozen == {p: api.file_hash(root / p) for p in frozen_paths}, 'API baseline changed while validating')
        # Reflection must not bless changes to the source graph it just ran.
        api.source_contracts(root)
        release_scope.audit(root)
    except Exception as error:
        result['status'] = 'failed'
        result['api_signatures_verified'] = False
        result['error'] = f'{type(error).__name__}: {error}'
        for command in result['commands']:
            if command['status'] == 'running': command['status'] = 'failed'
        print(result['error'], file=sys.stderr)
    (directory / 'result.json').write_text(api.json_text(result), encoding='utf-8')
    print(f'Public API: {result["status"]}. Evidence: {directory}')
    return 1 if result['status'] == 'failed' else 0


if __name__ == '__main__':
    raise SystemExit(main())
