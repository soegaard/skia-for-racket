"""0.78b: frozen release-scope decisions, independently checked against inventory.

No network, native library, or Racket execution on import. --write regenerates
only the Markdown report; it never silently approves changed review inputs.
The existing API inventory remains the authority for declarations/anchors.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any

SCHEMA = 1
STAGE = '0.78b'
BASELINE = '4a6082274e06456aa385fa9337c31528f2f44a4a'
REVIEW = 'api/release-scope.json'
POLICY = 'api/release-scope-policy.json'
REPORT = 'docs/RELEASE-SCOPE.md'
BASIS = 'catalogue-and-source-review; not overload reflection or execution'
EVIDENCE = 'not-asserted; test-source references and baseline CI evidence are separate'
SHA256 = re.compile(r'[0-9a-f]{64}\Z')
EXTENDED = frozenset(('G1', 'G2', 'U1', 'U2', 'U3', 'H1', 'X1'))
COMPARISON = dict(package='3.119.1', skia_revision='40f75dc0051d141913c07c20d4c19590c7da0cb7',
                  skiasharp_revision='cc78b5933d23e6383db5d246e70db915770d55d6',
                  minimum_racket='8.18', minimum_draw_lib='1.22')
ROOT = Path(__file__).resolve().parents[1]
MAX_JSON = 8 * 1024 * 1024
PURE_CASES = 16


def need(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def path_at(root: Path, name: str, *, exists: bool = True) -> Path:
    need(type(name) is str and bool(name), 'empty/non-string source path')
    need(not name.startswith('/') and '\\' not in name and ':' not in name
         and all(p not in ('', '.', '..') for p in name.split('/'))
         and not any(ord(c) < 32 for c in name), 'unsafe source path: ' + repr(name))
    root = Path(root).resolve()
    p = root.joinpath(*PurePosixPath(name).parts)
    for part in (p, *p.parents):
        if part == root:
            break
        need(not part.is_symlink(), 'symlink in source path: ' + name)
    need(p.resolve().is_relative_to(root), 'path escapes source root: ' + name)
    if exists:
        need(p.is_file(), 'missing source file: ' + name)
    return p


def unique_object(pairs):
    result = {}
    for k, v in pairs:
        need(k not in result, 'duplicate JSON key: ' + k)
        result[k] = v
    return result


def read_json(path: Path) -> dict:
    need(path.is_file() and not path.is_symlink(), 'missing/symlink JSON: ' + str(path))
    need(path.stat().st_size <= MAX_JSON, 'oversized JSON: ' + str(path))
    def bad(value):
        raise ValueError('nonfinite JSON value: ' + value)
    data = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_object,
                      parse_constant=bad)
    need(type(data) is dict, 'JSON object required: ' + str(path))
    return data


def json_text(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + '\n'


def value_hash(value: Any) -> str:
    return hashlib.sha256(json_text(value).encode('utf-8')).hexdigest()


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_catalog_shape(catalog: dict) -> dict[str, dict]:
    # validate_catalog/validate_sources also run for real repositories. These
    # independent invariants keep the review from trusting a status count alone.
    u, b, d = (catalog[k] for k in ('upstream', 'bindings', 'features'))
    need(u['package_version'] == COMPARISON['package']
         and u['skia_revision'] == COMPARISON['skia_revision']
         and u['skiasharp_revision'] == COMPARISON['skiasharp_revision'], 'comparison pin changed')
    need(type(d['comparison'].get('milestone')) is int and type(d['comparison'].get('increment')) is int,
         'non-integer comparison identity')
    need(d['comparison'] == dict(package='3.119.1', milestone=119, increment=0,
                                 minimum_racket='8.18', minimum_draw_lib='1.22'),
         'comparison/minimum changed')
    rows = d['capabilities']
    need(type(rows) is list and rows, 'empty capability catalogue')
    by_id = {}
    assigned = []
    for cap in rows:
        ident = cap['id']
        need(type(ident) is str and ident not in by_id, 'duplicate/invalid capability ID')
        need(cap['execution_evidence'] == EVIDENCE, 'source review cannot invent runtime evidence')
        need(type(cap['limitations']) is str and bool(cap['limitations'].strip()), 'missing limits: ' + ident)
        by_id[ident] = cap
        assigned.extend(cap['native_symbols'])
    declared = [s for names in u['headers'].values() for s in names]
    bound = b['symbols']
    need(len(declared) == len(set(declared)), 'duplicate upstream declaration')
    need(len(assigned) == len(set(assigned)) and set(assigned) == set(declared),
         'unclassified or multiply assigned C declaration')
    need(len(bound) == len(set(bound)) and set(bound) <= set(declared), 'invalid bound-symbol set')
    need(set(b['cpu_symbols']) <= set(bound), 'invalid CPU-symbol set')
    for cap in rows:
        symbols = set(cap['native_symbols'])
        need(cap['bindings_expected'] == sorted(symbols & set(bound)), 'binding classification drift: ' + cap['id'])
        need(cap['unbound_declarations'] == sorted(symbols - set(bound)), 'unbound classification drift: ' + cap['id'])
    return by_id


def validate_policy(policy: dict, caps: dict[str, dict]) -> None:
    need(set(policy) == {'schema', 'stage', 'reviewed_commit', 'comparison', 'decisions'}, 'policy fields differ')
    need(type(policy['schema']) is int and policy['schema'] == SCHEMA, 'wrong policy schema')
    need(policy['stage'] == STAGE and policy['reviewed_commit'] == BASELINE, 'wrong policy stage/baseline')
    need(policy['comparison'] == COMPARISON, 'policy comparison changed')
    decisions = policy['decisions']
    need(type(decisions) is dict and set(decisions) <= set(caps), 'unknown policy capability')
    for ident, decision in decisions.items():
        need(set(decision) == {'resolution', 'target', 'reason', 'acceptance'}, 'decision fields differ: ' + ident)
        for field in ('reason', 'acceptance'):
            need(type(decision[field]) is str and bool(decision[field].strip()), 'missing decision ' + field)
        validate_resolution(caps[ident], decision)
    # A new missing/excluded/future family cannot be approved by a catch-all.
    for ident, cap in caps.items():
        if cap['status'] not in ('supported', 'supported-with-limits', 'racket-equivalent'):
            need(ident in decisions, 'explicit residual decision required: ' + ident)


def validate_resolution(cap: dict, row: dict) -> None:
    ident, status = cap['id'], cap['status']
    resolution, target = row['resolution'], row['target']
    if status in ('supported', 'supported-with-limits', 'racket-equivalent'):
        expected = {'supported': 'supported', 'supported-with-limits': 'limited',
                    'racket-equivalent': 'equivalent'}[status]
        need(resolution == expected and target is None, 'supported family disposition drift: ' + ident)
        need(bool(cap['public_equivalents']) and bool(cap['implementation_files']) and bool(cap['test_sources']),
             'existing feature needs source and test anchors: ' + ident)
    elif status == 'intentionally-excluded':
        need(resolution == 'excluded' and target is None, 'excluded family disposition drift: ' + ident)
    elif status in ('missing-available-abi', 'unavailable-pinned-abi', 'bound-not-public'):
        need(resolution in ('pending', 'deferred'), 'missing feature cannot be marked complete: ' + ident)
        need(target == cap['planned_stage'], 'target disagrees with inventory: ' + ident)
        if resolution == 'pending':
            need(status != 'unavailable-pinned-abi' and target == '0.78b',
                 'in-scope gap requires a current closure stage: ' + ident)
        else:
            need(target in EXTENDED, 'deferred gap needs a named extended workstream: ' + ident)
    else:
        raise ValueError('unknown catalogue disposition: ' + status)


def decision_for(cap: dict, policy: dict) -> dict:
    if cap['id'] in policy['decisions']:
        return dict(policy['decisions'][cap['id']])
    status = cap['status']
    need(status in ('supported', 'supported-with-limits', 'racket-equivalent'),
         'no reviewed residual decision: ' + cap['id'])
    return dict(resolution={'supported': 'supported', 'supported-with-limits': 'limited',
                            'racket-equivalent': 'equivalent'}[status], target=None,
                reason='Retain the existing catalogue declaration within its documented restrictions. '
                       + cap['limitations'],
                acceptance='Existing public/source/test anchors must continue to validate. '
                           'This review does not certify every managed overload, backend, format, or runtime result.')


def review_inputs(root: Path, catalog: dict, inventory_hashes: dict[str, str]) -> dict[str, str]:
    # Freeze the exact implementation and test sources examined by the existing
    # inventory, plus the review/checker semantics. Deliberate changes require
    # a new review, not just regenerating Markdown or the source manifest.
    hashes = dict(inventory_hashes)
    names = {'tools/api_inventory.py', 'tools/release_scope.py', 'tools/validate-release-scope.py',
             'tools/test-release-scope.py', 'tools/ci.py', 'run-tests.rkt',
             '.github/workflows/api-inventory.yml', POLICY,
             'docs/RELEASE-SCOPE-REVIEW.md', 'tests/release-scope-pure-test.rkt',
             'docs/SMALL-GAPS.md', 'tools/small_gap_validation.py',
             'tools/test-small-gaps.py', 'tools/validate-small-gaps.py',
             'examples/small-gaps.rkt',
             'api/public-api-policy.json',
             'api/public-api-headless.json',
             'api/public-api-gui.json',
             'api/public-api-capture.json',
             'docs/API-CONTRACTS.md',
             'docs/PUBLIC-API.md',
             'tools/public_api.py',
             'tools/public-api-reflect.rkt',
             'tools/public-api-probe.rkt',
             'tools/validate-public-api.py',
             'tools/test-public-api.py',
             'tests/public-api-pure-test.rkt',
             'tests/public-api-fixture.rkt',
             'examples/public/value-basics.rkt',
             'examples/public/raster-lifetime.rkt',
             }
    for cap in catalog['features']['capabilities']:
        names.update(cap['test_sources'])
    for name in sorted(names):
        hashes[name] = file_hash(path_at(root, name))
    need(REVIEW not in hashes and REPORT not in hashes and 'SOURCE-SHA256SUMS.txt' not in hashes,
         'self-referential review input')
    return dict(sorted(hashes.items()))


def make_initial_review(catalog: dict, hashes: dict, policy: dict) -> dict:
    """Installer-only initial capture, after the exact baseline guard has passed.

    No CLI exposes automatic re-approval. --write checks this reviewed ledger.
    """
    caps = checked_catalog_shape(catalog)
    validate_policy(policy, caps)
    rows = []
    for ident, cap in sorted(caps.items()):
        rows.append(dict(id=ident, status=cap['status'], capability_sha256=value_hash(cap),
                         **decision_for(cap, policy)))
    return dict(schema=SCHEMA, stage=STAGE, reviewed_commit=BASELINE,
                comparison=COMPARISON, basis=BASIS,
                source_hashes=dict(sorted(hashes.items())), policy_sha256=value_hash(policy),
                capabilities=rows)


def validate_review(catalog: dict, hashes: dict, review: dict, policy: dict) -> dict:
    caps = checked_catalog_shape(catalog)
    validate_policy(policy, caps)
    need(set(review) == {'schema', 'stage', 'reviewed_commit', 'comparison', 'basis',
                         'source_hashes', 'policy_sha256', 'capabilities'}, 'review fields differ')
    need(type(review['schema']) is int and review['schema'] == SCHEMA, 'wrong review schema')
    need(review['stage'] == STAGE and review['reviewed_commit'] == BASELINE, 'wrong review stage/baseline')
    need(review['comparison'] == COMPARISON and review['basis'] == BASIS, 'review basis/comparison changed')
    need(review['policy_sha256'] == value_hash(policy), 'reviewed policy changed')
    actual_hashes = review['source_hashes']
    need(type(actual_hashes) is dict and bool(actual_hashes), 'missing review inputs')
    for name, digest in actual_hashes.items():
        # Validate even removed input paths before comparing with discovered ones.
        need(type(name) is str and not name.startswith('/') and '\\' not in name and ':' not in name
             and all(x not in ('', '.', '..') for x in name.split('/'))
             and not any(ord(x) < 32 for x in name), 'unsafe review input')
        need(type(digest) is str and SHA256.fullmatch(digest) is not None, 'bad review digest')
    changed = sorted(p for p in set(hashes) | set(actual_hashes) if hashes.get(p) != actual_hashes.get(p))
    need(not changed, 'review input drift; explicitly review changes: ' + ', '.join(changed[:12]))
    rows = review['capabilities']
    need(type(rows) is list and rows, 'empty review capability list')
    seen = set()
    for row in rows:
        need(type(row) is dict and set(row) == {'id', 'status', 'capability_sha256', 'resolution',
                                               'target', 'reason', 'acceptance'}, 'review row fields differ')
        ident = row['id']
        need(type(ident) is str and ident in caps and ident not in seen, 'unknown/duplicate reviewed family')
        seen.add(ident)
        cap = caps[ident]
        need(row['status'] == cap['status'] and row['capability_sha256'] == value_hash(cap),
             'capability review drift: ' + ident)
        validate_resolution(cap, row)
        need({k: row[k] for k in ('resolution', 'target', 'reason', 'acceptance')}
             == decision_for(cap, policy), 'reviewed decision changed: ' + ident)
    need(seen == set(caps), 'unreviewed capability families: ' + ', '.join(sorted(set(caps) - seen)))
    need([r['id'] for r in rows] == sorted(seen), 'review rows must be sorted')
    u, b = catalog['upstream'], catalog['bindings']
    declared = {s for names in u['headers'].values() for s in names}
    pending = [dict(id=r['id'], stage=r['target'], reason=r['reason'], acceptance=r['acceptance'])
               for r in rows if r['resolution'] == 'pending']
    return dict(capability_families=len(rows), core_c_declarations=len(declared),
                managed_source_files=len(u['managed_files']), public_modules=len(catalog['features']['public_modules']),
                core_bound_symbols=len(b['symbols']), core_cpu_bound_symbols=len(b['cpu_symbols']),
                core_unbound_declarations=len(declared - set(b['symbols'])),
                dispositions=dict(sorted(Counter(c['status'] for c in caps.values()).items())),
                release_dispositions=dict(sorted(Counter(r['resolution'] for r in rows).items())),
                reviewed_source_files=len(hashes), open_in_scope=pending,
                in_scope_gaps_closed=not pending, release_ready=False,
                remaining_release_gates=['0.78c current API check (tools/validate-public-api.py)', '0.78d end-to-end release gate'],
                native_symbols_probed=False, rendering_executed=False,
                per_capability_runtime_verified=False)


def markdown(value: str) -> str:
    return str(value).replace('|', '\\|').replace('\n', ' ')


def generated_report(catalog: dict, review: dict, summary: dict) -> str:
    lines = ['# Release-scope reconciliation — ' + STAGE, '',
             '<!-- Generated by tools/validate-release-scope.py --write; decisions live in api/release-scope*.json. -->', '',
             f"Reviewed GitHub baseline: `{BASELINE}`. Library package version is **0.78**.", '',
             '**This is a source/capability audit, not a 1.0 release approval.**', '',
             f"{summary['capability_families']} capability families; {summary['core_c_declarations']} pinned core C declarations; "
             f"{summary['managed_source_files']} managed source files; {summary['public_modules']} public Racket modules.", '',
             f"{summary['core_bound_symbols']} distinct core bindings ({summary['core_cpu_bound_symbols']} CPU); "
             f"{summary['core_unbound_declarations']} unbound declarations. An unbound convenience function is not automatically a missing user capability.", '',
             'Managed stream and trace-adapter declarations remain separately inventoried; they are not silently added to the core-C denominator. No overload-reflection or feature-parity percentage is asserted.', '',
             '## Release decisions', '', '| Decision | Families |', '|---|---:|']
    lines += [f'| {k} | {v} |' for k, v in summary['release_dispositions'].items()]
    lines += ['', '## Open in-scope work', '',
              'A green audit means these items are classified and tracked, **not implemented**.', '']
    for item in summary['open_in_scope']:
        lines += [f"### {item['id']} — {item['stage']}", '', item['reason'], '', '**Closure gate:** ' + item['acceptance'], '']
    if not summary['open_in_scope']:
        lines += ['No open capability-family gap is recorded. API and release-execution gates still apply.', '']
    lines += ['## Capability decision map', '', '| Family | Catalogue status | Release decision | Next stage |', '|---|---|---|---|']
    for row in review['capabilities']:
        lines.append(f"| `{row['id']}` | {row['status']} | {row['resolution']} | {row['target'] or '—'} |")
    lines += ['', '## Restrictions retained from the existing catalogue', '',
              'Supported-with-limits entries retain their actual limitations, source anchors, and test references. '
              'They are not promoted to complete overload/backend support. Every family is fingerprinted in the review ledger, '
              'and the complete discovered source/anchor graph is checked before this report is accepted.', '',
              'Native file/buffered typeface and codec constructors are not retained live-port consumers. '
              'The scaled/subset family describes queries, not unrestricted subset/scaled decoding. '
              'No-draw canvases do not by themselves establish null-surface ownership or snapshot behavior.', '',
              'The accepted 0.77c GPU diagnostics and retained-interface helpers keep their native-build and matching-host restrictions. '
              'A memory dump is not total VRAM, and an exported GLES/WebGL factory is not proof of browser rendering.', '',
              '## Evidence boundary', '',
              'The audit runs declaration, public-anchor, fingerprint, and generated-report checks. '
              'It does not reinterpret all-green CI, an exported symbol, a source test, or a synthetic fixture as per-feature native execution. '
              'Existing pinned-upstream/native observation and backend Acceptance workflows remain separate required evidence.', '',
              'Use `--require-no-open-gaps` to reject this baseline while any in-scope capability is pending. '
              'Even that switch does not certify API stability or the 0.78d release gate.', '',
              'See [review rationale and maintenance](RELEASE-SCOPE-REVIEW.md) and [full capability catalogue](SKIASHARP-GAPS.md).', '']
    return '\n'.join(lines)


def check_report(root: Path, expected: str, *, write: bool) -> None:
    path = path_at(root, REPORT, exists=not write)
    if write:
        path.parent.mkdir(parents=True, exist_ok=True)
        atomic_text(path, expected)
    else:
        need(path.read_text(encoding='utf-8') == expected, 'release-scope report drift; review inputs before --write')


def atomic_text(path: Path, text: str) -> None:
    need(not path.is_symlink(), 'refusing symlink output: ' + str(path))
    fd, tmp = tempfile.mkstemp(prefix='.release-scope-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def audit(root: Path, *, write: bool = False) -> dict:
    inv = importlib.import_module('api_inventory')
    catalog = inv.load_catalog(root)
    inv.validate_catalog(catalog)
    sources = inv.validate_sources(root, catalog)
    inv.check_report(root, catalog)
    policy = read_json(path_at(root, POLICY))
    review = read_json(path_at(root, REVIEW))
    hashes = review_inputs(root, catalog, sources['source_hashes'])
    summary = validate_review(catalog, hashes, review, policy)
    check_report(root, generated_report(catalog, review, summary), write=write)
    return summary


def check_pure_output(text: str) -> None:
    need(re.findall(r'^release-scope-pure: (\d+) cases, (\d+) failures\s*$', text, re.M)
         == [(str(PURE_CASES), '0')], 'missing/duplicate/failed pure-suite completion')
    need(re.findall(r'(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run', text)
         == [(str(PURE_CASES), '0', '0', str(PURE_CASES))], 'wrong/incomplete pure RackUnit result')
    need(not re.search(r'\b(?:ERROR|FAILURE)\b', text), 'pure suite reported a failure')


def main(argv=None, *, root=ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--check', action='store_true', help='check decisions, current source graph and reports (default)')
    modes.add_argument('--write', action='store_true', help='write Markdown only after the frozen review passes')
    parser.add_argument('--require-no-open-gaps', action='store_true', help='fail when an in-scope feature still needs implementation')
    parser.add_argument('--racket', help='also execute the focused pure-Racket equivalence checks')
    parser.add_argument('--directory', type=Path, help='new evidence directory')
    parser.add_argument('--timeout', type=float, default=300)
    args = parser.parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error('--timeout must be finite and positive')
    root = Path(root).resolve()
    if args.directory:
        out = args.directory.resolve()
        out.mkdir(parents=True, exist_ok=False)
    else:
        (root / 'output').mkdir(exist_ok=True)
        out = Path(tempfile.mkdtemp(prefix='release-scope-0.78a-', dir=root / 'output'))
    report = dict(schema=SCHEMA, stage=STAGE, status='failed', reviewed_commit=BASELINE,
                  source_audit_passed=False, pure_requested=bool(args.racket), pure_executed=False,
                  pure_passed=False, native_symbols_probed=False, rendering_executed=False,
                  release_ready=False, commands=[])
    try:
        # Unlike --write on the Markdown generator, this never regenerates a
        # source manifest or review ledger as a way to make checks turn green.
        summary = audit(root, write=args.write)
        report.update(source_audit_passed=True, summary=summary)
        if args.racket:
            racket = shutil.which(args.racket)
            if not racket and Path(args.racket).is_file():
                racket = str(Path(args.racket).resolve())
            need(bool(racket), 'Racket executable not found')
            roots = [root / 'tests/release-scope-pure-test.rkt']
            for name, command in [('compile', [racket, '-l', 'raco', '--', 'make', *roots]),
                                  ('pure', [racket, *roots])]:
                command = list(map(str, command))
                entry = dict(command=command, log=name + '.log', status='running')
                report['commands'].append(entry)
                with (out / entry['log']).open('w', encoding='utf-8') as log:
                    log.write('$ ' + repr(command) + '\n'); log.flush()
                    try:
                        if name == 'pure':
                            report['pure_executed'] = True
                        subprocess.run(command, cwd=root, check=True, timeout=args.timeout,
                                       stdout=log, stderr=subprocess.STDOUT)
                        entry['status'] = 'passed'
                    except BaseException:
                        entry['status'] = 'failed'
                        raise
                if name == 'pure':
                    check_pure_output((out / entry['log']).read_text(encoding='utf-8', errors='replace'))
                    report['pure_passed'] = True
            # Don't silently accept a Racket command that altered audited input.
            audit(root)
        need(not args.require_no_open_gaps or summary['in_scope_gaps_closed'],
             'open in-scope gaps remain: ' + ', '.join(x['id'] for x in summary['open_in_scope']))
        report['status'] = 'passed'
        code = 0
    except Exception as exc:
        report['error'] = type(exc).__name__ + ': ' + str(exc)
        code = 1
        print('Release scope FAILED: ' + report['error'], file=sys.stderr)
    atomic_text(out / 'validation.json', json_text(report))
    print(json_text(report), end='')
    print('Evidence: ' + str(out))
    return code
