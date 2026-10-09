"""0.78c: strict public-call-boundary snapshots, not behavioral/rendering proof.

No native library or Racket execution on import. Expected snapshots are never
rewritten by source checks, runtime validation, or the observation probe.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
from typing import Any

STAGE = '0.78c'
BASELINE = 'cc6e63c3e14a9059b326f515ee01fd2b582c123f'
POLICY = 'api/public-api-policy.json'
REPORT = 'docs/PUBLIC-API.md'
CONTRACT = 'docs/API-CONTRACTS.md'
PURE_CASES = 22
GROUPS = ('headless', 'gui')
SNAPSHOTS = {g: f'api/public-api-{g}.json' for g in GROUPS}
MAX_JSON = 16 * 1024 * 1024


def need(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def path_at(root: Path, name: str, *, exists: bool = True) -> Path:
    need(type(name) is str and bool(name), 'empty/non-string source path')
    need(not name.startswith('/') and '\\' not in name and ':' not in name
         and all(x not in ('', '.', '..') for x in name.split('/'))
         and not any(ord(x) < 32 for x in name), 'unsafe source path: ' + repr(name))
    root = Path(root).resolve()
    path = root.joinpath(*PurePosixPath(name).parts)
    for part in (path, *path.parents):
        if part == root:
            break
        need(not part.is_symlink(), 'symlink in source path: ' + name)
    need(path.resolve().is_relative_to(root), 'path escapes root: ' + name)
    if exists:
        need(path.is_file(), 'missing source: ' + name)
    return path


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def read_json(path: Path) -> dict:
    need(path.is_file() and not path.is_symlink(), 'missing/symlink JSON: ' + str(path))
    need(path.stat().st_size <= MAX_JSON, 'oversized JSON: ' + str(path))
    def nonfinite(value):
        raise ValueError('nonfinite JSON: ' + value)
    result = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_object,
                        parse_constant=nonfinite)
    need(type(result) is dict, 'JSON object required')
    return result


def json_text(value: Any) -> str:
    return json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False, allow_nan=False) + '\n'


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_list(value, message: str) -> list[str]:
    need(type(value) is list and all(type(x) is str and x and not any(ord(c) < 32 for c in x)
                                   for x in value), 'invalid ' + message)
    need(value == sorted(set(value)), 'unsorted/duplicate ' + message)
    return value


def checked_policy(policy: dict) -> dict[str, dict]:
    need(set(policy) == {'schema', 'stage', 'baseline_commit', 'package_version', 'minimum_racket',
                         'comparison', 'contract_document', 'modules'}, 'policy fields differ')
    need(type(policy['schema']) is int and policy['schema'] == 1, 'wrong policy schema')
    need(policy['stage'] == STAGE and policy['baseline_commit'] == BASELINE, 'wrong API baseline/stage')
    need(policy['package_version'] == '0.78' and policy['minimum_racket'] == '8.18', 'API version/minimum changed')
    need(policy['comparison'] == 'exact-export-and-call-boundary', 'unsupported comparison policy')
    need(policy['contract_document'] == CONTRACT, 'contract document changed')
    modules = policy['modules']
    need(type(modules) is list and bool(modules), 'empty module policy')
    by_path = {}
    for row in modules:
        need(type(row) is dict and set(row) == {'path', 'stability', 'load_group', 'reason'}, 'module policy fields differ')
        name = row['path']
        need(type(name) is str and re.fullmatch(r'(?:unsafe/)?[a-z0-9-]+\.rkt', name) is not None,
             'private/unsafe module-policy path: ' + repr(name))
        need(name not in by_path, 'duplicate module policy: ' + name)
        need(row['stability'] in ('stable', 'experimental') and row['load_group'] in GROUPS,
             'unknown module classification: ' + name)
        need(type(row['reason']) is str and bool(row['reason'].strip()), 'missing classification rationale')
        if name.startswith('unsafe/'):
            need(row['stability'] == 'experimental', 'unsafe module cannot be stable')
        by_path[name] = row
    need(list(by_path) == sorted(by_path), 'unsorted module policy')
    need('main.rkt' in by_path and by_path['main.rkt']['load_group'] == 'headless'
         and by_path['main.rkt']['stability'] == 'stable', 'core public entry is not stable/headless')
    need(all(any(r['load_group'] == group for r in modules) for group in GROUPS), 'missing import group')
    return by_path


def selected_paths(policy: dict, group: str) -> list[str]:
    need(group in GROUPS, 'unknown group')
    return [name for name, row in checked_policy(policy).items() if row['load_group'] == group]


def export_key(row: dict) -> tuple:
    return row['phase'], row['name'], row['export_kind']


def checked_modules(modules, expected_paths: list[str]) -> list[dict]:
    need(type(modules) is list, 'missing module observations')
    paths = []
    for module in modules:
        need(type(module) is dict and set(module) == {'path', 'exports'}, 'module observation fields differ')
        paths.append(module['path'])
        rows = module['exports']
        need(type(rows) is list, 'missing exports')
        keys = []
        for row in rows:
            need(type(row) is dict and set(row) >= {'name', 'phase', 'export_kind', 'kind'}, 'incomplete export')
            need(type(row['name']) is str and bool(row['name']) and not any(ord(x) < 32 for x in row['name']),
                 'invalid export name')
            need(type(row['phase']) is str and bool(row['phase']) and len(row['phase']) < 512,
                 'invalid phase/space')
            need(row['export_kind'] in ('value', 'syntax'), 'unknown export binding category')
            keys.append(export_key(row))
            if row['kind'] in ('procedure', 'parameter'):
                need(set(row) == {'name', 'phase', 'export_kind', 'kind', 'arity_mask',
                                   'required_keywords', 'allowed_keywords'}, 'callable fields differ')
                mask = row['arity_mask']
                need(type(mask) is str and re.fullmatch(r'0|-?[1-9][0-9]*', mask) is not None
                     and len(mask) <= 4096, 'invalid arity mask')
                required = text_list(row['required_keywords'], 'required keywords')
                allowed = row['allowed_keywords']
                if allowed is not None:
                    text_list(allowed, 'allowed keywords')
                    need(set(required) <= set(allowed), 'required keyword not accepted')
                need(row['phase'] == '0', 'runtime signature at an unprobed phase')
            else:
                need(set(row) == {'name', 'phase', 'export_kind', 'kind'}, 'non-callable fields differ')
                need(row['kind'] in ('value', 'syntax', 'class', 'interface', 'phase-only'), 'unknown value kind')
                if row['phase'] != '0':
                    need(row['kind'] == 'phase-only', 'higher-phase value was not inspected')
                else:
                    need(row['kind'] != 'phase-only', 'phase zero observation is incomplete')
                if row['kind'] == 'syntax':
                    need(row['export_kind'] == 'syntax', 'variable classified as macro')
        need(keys == sorted(set(keys)), 'unsorted/duplicate exports: ' + str(module['path']))
        if module['path'] == 'main.rkt':
            need(bool(rows), 'empty main API snapshot')
    need(paths == expected_paths, 'incomplete/extra/unsorted module coverage')
    return modules


def checked_snapshot(snapshot: dict, policy: dict, group: str) -> dict:
    need(set(snapshot) == {'schema', 'stage', 'baseline_commit', 'group', 'modules'}, 'snapshot fields differ')
    need(type(snapshot['schema']) is int and snapshot['schema'] == 1, 'wrong snapshot schema')
    need(snapshot['stage'] == STAGE and snapshot['baseline_commit'] == BASELINE and snapshot['group'] == group,
         'wrong snapshot identity')
    checked_modules(snapshot['modules'], selected_paths(policy, group))
    return snapshot


def checked_observation(data: dict, policy: dict, group: str, token: str) -> dict:
    need(set(data) == {'schema', 'stage', 'status', 'run_token', 'group', 'modules', 'runtime',
                       'gui_instantiated', 'native_overrides', 'exported_procedures_called',
                       'rendering_executed', 'release_ready'}, 'observation fields differ')
    need(type(data['schema']) is int and data['schema'] == 1 and data['stage'] == STAGE,
         'wrong observation schema/stage')
    need(data['run_token'] == token and data['group'] == group and data['status'] == 'passed',
         'stale/failed/wrong-group observation')
    need(type(data['gui_instantiated']) is bool, 'invalid GUI observation')
    need(group != 'headless' or data['gui_instantiated'] is False, 'headless import instantiated GUI')
    need(data['native_overrides'] == 'nonexistent', 'native override protection missing')
    for field in ('exported_procedures_called', 'rendering_executed', 'release_ready'):
        need(data[field] is False, 'unsupported evidence claim: ' + field)
    runtime = data['runtime']
    need(type(runtime) is dict and set(runtime) == {'racket', 'os', 'vm'}
         and all(type(v) is str and v for v in runtime.values()), 'missing runtime identity')
    need(runtime['vm'] == 'chez-scheme', 'Racket CS is required for the accepted package scope')
    parts = runtime['racket'].split('.')
    need(all(p.isdigit() for p in parts) and len(parts) >= 2
         and tuple(map(int, parts)) >= (8, 18), 'runtime below declared minimum')
    checked_modules(data['modules'], selected_paths(policy, group))
    return data


def snapshot_from_observation(data: dict, policy: dict, group: str, token: str) -> dict:
    """Pure format conversion. Only the exact-baseline installer writes this."""
    checked_observation(data, policy, group, token)
    return dict(schema=1, stage=STAGE, baseline_commit=BASELINE, group=group, modules=data['modules'])


def differences(expected: dict, actual: dict) -> list[dict]:
    def flatten(snapshot):
        return {(m['path'], *export_key(e)): e for m in snapshot['modules'] for e in m['exports']}
    before, after = flatten(expected), flatten(actual)
    result = []
    for key in sorted(before.keys() | after.keys()):
        if before.get(key) == after.get(key):
            continue
        result.append(dict(module=key[0], phase=key[1], name=key[2], export_kind=key[3],
                           change='added' if key not in before else 'removed' if key not in after else 'changed',
                           before=before.get(key), after=after.get(key)))
    # Empty modules have no exports; coverage is also compared independently.
    bp = [m['path'] for m in expected['modules']]
    ap = [m['path'] for m in actual['modules']]
    if bp != ap:
        result.insert(0, dict(change='module-coverage', before=bp, after=ap))
    return result


def checked_pure_output(text: str) -> None:
    need(re.findall(r'^public-api-pure: (\d+) cases, (\d+) failures\s*$', text, re.M)
         == [(str(PURE_CASES), '0')], 'missing/duplicate/failed reflection-suite completion')
    need(re.findall(r'(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run', text)
         == [(str(PURE_CASES), '0', '0', str(PURE_CASES))], 'wrong/incomplete RackUnit result')
    need(not re.search(r'\b(?:ERROR|FAILURE)\b', text), 'reflection suite reported failure')


def isolated_environment(directory: Path, group: str) -> dict[str, str]:
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONUTF8='1')
    for key in ('PLTCOLLECTS', 'PLTADDONDIR', 'PLT_COMPILED_FILE_CHECK'):
        env.pop(key, None)
    for key, name in (('RACKET_SKIA_LIBRARY', 'skia-must-not-load'),
                      ('RACKET_HARFBUZZ_LIBRARY', 'harfbuzz-must-not-load')):
        target = directory / name
        need(not target.exists(), 'native override path already exists')
        env[key] = str(target.resolve())
    if group == 'headless':
        for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'MIR_SOCKET'):
            env.pop(key, None)
    return env


def run_logged(command: list[str], *, root: Path, env: dict, log: Path, timeout: int = 300) -> str:
    with log.open('w', encoding='utf-8', newline='\n') as out:
        result = subprocess.run([str(x) for x in command], cwd=root, env=env, stdout=out,
                                stderr=subprocess.STDOUT, timeout=timeout, check=False)
    text = log.read_text(encoding='utf-8', errors='replace')
    if result.returncode:
        raise RuntimeError(f'command exited {result.returncode}; see {log}\n{text[-8000:]}')
    return text


def reflect_group(root: Path, policy_file: Path, group: str, racket: str,
                  directory: Path, token: str, *, probe_root: Path | None = None) -> dict:
    need(directory.is_dir(), 'observation directory does not exist')
    observation = directory / f'{group}.json'
    need(not observation.exists(), 'refusing stale observation')
    run_logged([racket, str((probe_root or root) / 'tools/public-api-probe.rkt'),
                '--root', str(root), '--policy', str(policy_file), '--group', group,
                '--output', str(observation), '--token', token],
               root=root, env=isolated_environment(directory, group), log=directory / f'{group}.log')
    policy = read_json(policy_file)
    return checked_observation(read_json(observation), policy, group, token)


def markdown(text: str) -> str:
    return str(text).replace('|', '\\|').replace('`', '\\`').replace('\n', ' ')


def arity_description(mask_text: str) -> str:
    mask = int(mask_text)
    fixed = []
    i = 0
    # A normalized negative mask ends with all ones, i.e. an unbounded tail.
    while mask not in (0, -1):
        if mask & 1:
            fixed.append(str(i))
        mask >>= 1
        i += 1
    if mask == -1:
        fixed.append(f'{i}+')
    return ', '.join(fixed) or 'none'


def generated_report(policy: dict, snapshots: dict[str, dict]) -> str:
    rows = checked_policy(policy)
    experimental_names = {(e['phase'], e['name']) for snap in snapshots.values()
                          for m in snap['modules'] if rows[m['path']]['stability'] == 'experimental'
                          for e in m['exports']}
    lines = ['# Public API baseline — 0.78c', '',
             '<!-- Generated from checked-in public-api snapshots, not from source regexes. -->', '',
             f'Baseline: `{BASELINE}`. Package version: **0.78**.', '',
             'This is an exact export/call-boundary baseline, **not a 1.0 release approval**, '
             'an overload-parity claim, or native/backend execution evidence.', '',
             'See [ownership, errors and output contracts](API-CONTRACTS.md). '
             'Stable means a compatibility commitment for the reviewed API surface; '
             'experimental exports remain explicitly tracked, not silently omitted.', '',
             'Nonzero phases and binding spaces are inventoried by name. Macro grammars, '
             'class constructor arguments/method arities, constant contents, defaults, '
             'return-value contracts and numerical/rendering semantics are not inferred '
             'by reflection. Existing class/consumer and native acceptance tests remain necessary.', '',
             'Experimental names retain that label through convenience re-exports.', '',
             '## Module policy', '', '| Module | Default stability | Import group |', '|---|---|---|']
    lines += [f"| `{n}` | {r['stability']} | {r['load_group']} |" for n, r in rows.items()]
    for group in GROUPS:
        snapshot = checked_snapshot(snapshots[group], policy, group)
        lines += ['', f'## {group.title()} exports', '']
        for module in snapshot['modules']:
            name = module['path']
            lines += [f'### {name}', '', rows[name]['reason'], '',
                      '| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |',
                      '|---|---|---|---|---|---|---|']
            for entry in module['exports']:
                callable_ = entry['kind'] in ('procedure', 'parameter')
                arity = arity_description(entry['arity_mask']) if callable_ else '—'
                required = ', '.join('#:' + k for k in entry['required_keywords']) or 'none' if callable_ else '—'
                allowed = ('any' if entry['allowed_keywords'] is None else
                           ', '.join('#:' + k for k in entry['allowed_keywords']) or 'none') if callable_ else '—'
                lines.append('| ' + ' | '.join(markdown(v) for v in
                    (entry['name'], 'experimental' if (entry['phase'], entry['name']) in experimental_names else rows[name]['stability'],
                     entry['phase'], entry['kind'], arity, required, allowed)) + ' |')
            if not module['exports']:
                lines += ['| (no exports) | — | — | — | — | — | — |']
    lines += ['', '## Updating the baseline', '',
              'The validator and probe never rewrite expected snapshots. An intentional API change '
              'requires a separately reviewed baseline update, a generated-document diff, a release-review '
              'update, source checksums, and fresh runtime checks. Exact comparison flags additions as '
              'well as removals and changed arities/keywords.', '',
              '### Reference', '',
              'Racket reflection: `module->exports`, `dynamic-require`, `procedure-arity-mask`, '
              'and `procedure-keywords`. This baseline uses the actual expanded and instantiated '
              'modules, including aliases and syntax-backed constructors, rather than parsing '
              'a procedure definition to guess its signature.', '']
    return '\n'.join(lines)


def example_import_audit(root: Path) -> dict:
    """Check literal import boundaries; not a sandbox or computed-code proof.

    Existing examples may use shared test scene/data fixtures. Those helpers are
    recorded as development dependencies, never advertised as public Skia APIs.
    New examples/public tutorials must import the collection's public APIs only.
    """
    import api_inventory as inv
    public = set(inv.load_catalog(root)['features']['public_modules'])
    result = {}
    for file in sorted((root / 'examples').rglob('*.rkt')):
        relative = file.relative_to(root).as_posix()
        path_at(root, relative)
        nodes = inv.forms(file.read_text(encoding='utf-8'))
        refs = []
        computed = []
        def atom(value):
            if isinstance(value, inv.String):
                return value.value
            return value if type(value) is str else None
        def require_spec(value):
            literal = atom(value)
            if literal is not None:
                refs.append(literal)
            elif isinstance(value, list) and value:
                op = value[0]
                if op in ('only-in', 'except-in', 'rename-in', 'file'):
                    require_spec(value[1])
                elif op in ('prefix-in', 'for-meta', 'for-space'):
                    for child in value[2:]: require_spec(child)
                elif op in ('combine-in', 'for-syntax', 'for-template', 'for-label'):
                    for child in value[1:]: require_spec(child)
                elif op == 'submod':
                    need(not any(atom(x) in ('test', 'testing', 'internals') or
                                 (isinstance(atom(x), str) and atom(x).endswith('-internals')) for x in value[2:]),
                         'example imports a private submodule: ' + relative)
                    require_spec(value[1])
                elif op == 'lib':
                    pieces = [atom(x) for x in value[1:]]
                    if not pieces or any(x is None for x in pieces):
                        computed.append('lib')
                    else:
                        # (lib "private/core.rkt" "skia") and the old
                        # collection-component spelling must not hide private
                        # imports from the same literal boundary check.
                        name = '/'.join([*pieces[1:], pieces[0]])
                        refs.append(name[:-4] if name.endswith('.rkt') else name)
                else:
                    computed.append(str(op))
        def walk(node):
            if not isinstance(node, list) or not node:
                return
            if node[0] == 'quote':
                return
            if node[0] == 'require':
                for spec in node[1:]: require_spec(spec)
            if node[0] == 'dynamic-require':
                arg = node[1] if len(node) > 1 else None
                if isinstance(arg, inv.String): refs.append(arg.value)
                elif isinstance(arg, list) and arg and arg[0] == 'quote': require_spec(arg[1])
                else: computed.append('dynamic-require')
            for child in node[1:]: walk(child)
        for node in nodes: walk(node)
        development = []
        for ref in refs:
            if ref.startswith('skia/'):
                need(not ref.startswith(('skia/private/', 'skia/tools/', 'skia/tests/')),
                     'example imports implementation module: ' + relative + ': ' + ref)
            if ref.startswith('.') or ref.endswith('.rkt'):
                resolved = (file.parent / ref).resolve()
                need(resolved.is_relative_to(root.resolve()), 'example import escapes repository: ' + relative)
                name = resolved.relative_to(root.resolve()).as_posix()
                need(not name.startswith('private/'), 'example imports private module: ' + relative + ': ' + name)
                if relative.startswith('examples/public/'):
                    need(name in public, 'public tutorial imports a non-public file: ' + relative + ': ' + name)
                elif name not in public and not name.startswith('examples/'):
                    development.append(name)
            if relative.startswith('examples/public/'):
                need(ref == 'skia' or not ref.startswith('skia/') or (ref[5:] + '.rkt') in public,
                     'tutorial imports unlisted Skia module: ' + ref)
        if relative.startswith('examples/public/'):
            need(not development and not computed, 'public tutorial has development/computed imports: ' + relative)
        result[relative] = dict(development_helpers=sorted(set(development)),
                                computed_imports=sorted(set(computed)))
    need(bool(result) and any(n.startswith('examples/public/') for n in result), 'no public examples')
    return result


def source_contracts(root: Path, *, check_report: bool = True) -> dict:
    import api_inventory as inv
    root = root.resolve()
    catalog = inv.load_catalog(root)
    inv.validate_sources(root, catalog)
    policy = read_json(path_at(root, POLICY))
    by_path = checked_policy(policy)
    need(list(by_path) == sorted(catalog['features']['public_modules']), 'module policy differs from complete public inventory')
    for name in by_path: path_at(root, name)
    snapshots = {g: checked_snapshot(read_json(path_at(root, p)), policy, g) for g, p in SNAPSHOTS.items()}
    docs = path_at(root, CONTRACT).read_text(encoding='utf-8')
    for heading in ('## Stability', '## Ownership', '## Errors', '## Output', '## Evidence', '## Examples'):
        need(heading in docs, 'missing contract section: ' + heading)
    for target in re.findall(r'\]\(([^\s)#]+)(?:#[^)]*)?\)', docs):
        if '://' not in target:
            resolved = (root / 'docs' / target).resolve()
            need(resolved.is_relative_to(root) and resolved.is_file(), 'broken contract link: ' + target)
    if check_report:
        need(path_at(root, REPORT).read_text(encoding='utf-8') == generated_report(policy, snapshots),
             'public API documentation drift; no automatic snapshot approval')
    suite = path_at(root, 'tests/public-api-pure-test.rkt').read_text(encoding='utf-8')
    need(suite.count('(test-case ') == PURE_CASES, 'reflection source test count drift')
    runner = path_at(root, 'run-tests.rkt').read_text(encoding='utf-8')
    need('"tests/public-api-pure-test.rkt"' in runner and '(run-tests public-api-pure-tests)' in runner,
         'reflection tests missing from aggregate runner')
    ci = path_at(root, 'tools/ci.py').read_text(encoding='utf-8')
    need("'test-public-api.py'" in ci, 'public API source tests missing from CI')
    workflow = path_at(root, '.github/workflows/api-inventory.yml').read_text(encoding='utf-8')
    need('xvfb-run -a python tools/validate-public-api.py --racket' in workflow,
         'required full GUI/headless signature gate missing')
    need('--headless-only' not in workflow and 'continue-on-error' not in workflow,
         'required API gate may not skip GUI or swallow failure')
    examples = example_import_audit(root)
    return dict(schema=1, stage=STAGE, status='source-verified', public_modules=len(by_path),
                exports=sum(len(m['exports']) for s in snapshots.values() for m in s['modules']),
                examples=examples, api_signatures_verified=False, rendering_executed=False,
                release_ready=False)
