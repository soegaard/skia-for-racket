"""Strict, deliberately bounded expansion of this repository's release workflow.

This is not a GitHub expression interpreter. Unknown syntax requires review;
never silently omit a job, matrix row, step, or evidence artifact.
"""
from __future__ import annotations
import copy
import hashlib
import itertools
import json
from pathlib import Path
import re

STAGE = '0.78d'
BASELINE = '705a090d287a8a2887eb2cb4f33b43961626c6e4'
WORKFLOW = '.github/workflows/release-candidate.yml'
POLICY = 'api/release-candidate-policy.json'
REPORT = 'docs/RELEASE-CANDIDATE-MATRIX.md'
GATE = 'Release candidate required'
ROOT_JOBS = {'ci': './.github/workflows/ci.yml',
             'acceptance': './.github/workflows/acceptance.yml',
             'inventory': './.github/workflows/api-inventory.yml'}
MAX_BYTES = 16 * 1024 * 1024
MAX_JOBS = 512
MAX_STEPS = 128


def need(ok, message):
    if not ok:
        raise ValueError(message)


def relative(root: Path, name: str) -> Path:
    need(type(name) is str and bool(name) and '\\' not in name and ':' not in name
         and not name.startswith('/') and all(p not in ('', '.', '..') for p in name.split('/'))
         and not any(ord(c) < 32 for c in name), 'unsafe source path: ' + repr(name))
    root = root.resolve()
    result = root.joinpath(*name.split('/'))
    for part in (result, *result.parents):
        if part == root:
            break
        need(not part.is_symlink(), 'symlink in source path: ' + name)
    need(result.resolve().is_relative_to(root), 'source path escapes root')
    need(result.is_file() and result.stat().st_size <= MAX_BYTES, 'missing/oversized source: ' + name)
    return result


def unique(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'duplicate key: ' + str(key))
        result[key] = value
    return result


def json_data(text):
    def invalid(value):
        raise ValueError('nonfinite JSON: ' + value)
    return json.loads(text, object_pairs_hook=unique, parse_constant=invalid)


def json_text(value):
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + '\n'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def workflow_data(text):
    # YAML 1.1's conversion of an unquoted `on` to True is wrong for Actions.
    # Use BaseLoader: all scalars stay strings; booleans are checked explicitly.
    # Disallow aliases, tags and duplicate keys instead of accepting ambiguity.
    import yaml
    class StrictLoader(yaml.BaseLoader):
        pass
    def mapping(loader, node):
        return unique((loader.construct_object(k), loader.construct_object(v)) for k, v in node.value)
    StrictLoader.add_constructor('tag:yaml.org,2002:map', mapping)
    need(len(text.encode('utf-8')) <= MAX_BYTES, 'oversized workflow')
    for token in yaml.scan(text):
        need(not isinstance(token, (yaml.tokens.AliasToken, yaml.tokens.AnchorToken, yaml.tokens.TagToken)),
             'workflow aliases/anchors/tags require explicit parser review')
    result = yaml.load(text, Loader=StrictLoader)
    need(type(result) is dict and type(result.get('jobs')) is dict, 'workflow has no jobs')
    return result


def scalar(value):
    if type(value) is bool:
        return 'true' if value else 'false'
    need(type(value) in (str, int), 'non-scalar matrix/expression value')
    return str(value)


def context_value(key, context):
    need(key in context, 'unreviewed expression: ' + key)
    return context[key]


def render(text, context):
    need(type(text) is str, 'workflow text must be a string')
    result = re.sub(r'\$\{\{\s*([A-Za-z_][\w.-]*)\s*\}\}',
                    lambda m: scalar(context_value(m[1], context)), text)
    need('${{' not in result, 'unsupported workflow expression: ' + result)
    return result


def condition(value, context):
    if value is None:
        return True
    need(type(value) is str, 'invalid workflow condition')
    text = value.strip()
    if text.startswith('${{') and text.endswith('}}'):
        text = text[3:-2].strip()
    # All required dependencies must succeed, so success()/always() are true.
    if text in ('always()', 'success()', 'true'):
        return True
    if text in ('failure()', 'cancelled()', 'false'):
        return False
    # Restrict syntax: the accepted workflow uses scalar equality comparisons.
    match = re.fullmatch(r"([\w.-]+)\s*(!=|==)\s*'([^']*)'", text)
    need(match is not None, 'unreviewed workflow condition: ' + text)
    left = scalar(context_value(match[1], context))
    return (left == match[3]) if match[2] == '==' else (left != match[3])


def matrix_rows(spec, matrices):
    if spec is None:
        return [{}]
    if type(spec) is str:
        match = re.fullmatch(r'\$\{\{\s*fromJSON\(needs\.source\.outputs\.(cpu|egl)\)\s*\}\}', spec)
        need(match is not None, 'unreviewed dynamic matrix: ' + spec)
        rows = matrices[match[1]]
        need(type(rows) is list and rows, 'empty CI matrix')
        return copy.deepcopy(rows)
    need(type(spec) is dict and bool(spec), 'invalid static matrix')
    axes = {key: value for key, value in spec.items() if key not in ('include', 'exclude')}
    for values in axes.values():
        need(type(values) is list and bool(values), 'empty matrix axis')
        for value in values:
            scalar(value)
    size = 1
    for values in axes.values():
        size *= len(values)
    need(size <= MAX_JOBS, 'matrix too large')
    base = [dict(zip(axes, values)) for values in itertools.product(*axes.values())] if axes else []
    excludes = spec.get('exclude', [])
    need(type(excludes) is list and all(type(v) is dict and v for v in excludes), 'invalid matrix exclusions')
    for exclusion in excludes:
        need(set(exclusion) <= set(axes), 'unknown matrix exclusion axis')
        base = [row for row in base if not all(scalar(row[k]) == scalar(v) for k, v in exclusion.items())]
    rows = copy.deepcopy(base)
    includes = spec.get('include', [])
    need(type(includes) is list and all(type(v) is dict and v for v in includes), 'invalid matrix includes')
    for addition in includes:
        for value in addition.values():
            scalar(value)
        matched = False
        for original, current in zip(base, rows):
            if all(key not in original or scalar(original[key]) == scalar(value) for key, value in addition.items()):
                current.update(addition)
                matched = True
        if not matched:
            rows.append(dict(addition))
    need(rows and len(rows) <= MAX_JOBS, 'empty/oversized expanded matrix')
    need(len({json_text(row) for row in rows}) == len(rows), 'duplicate matrix row')
    return rows


def runner_os(runner):
    for prefix, os_name in (('ubuntu-', 'Linux'), ('windows-', 'Windows'), ('macos-', 'macOS')):
        if runner.startswith(prefix):
            need(not runner.endswith('-latest'), 'release runners must be versioned')
            return os_name
    raise ValueError('only reviewed hosted runners are allowed: ' + runner)


def permission_check(value):
    if value is None:
        return
    need(type(value) is dict and all(v in ('read', 'none') for v in value.values()),
         'release workflows may not grant write permissions or inherit secrets')


def build_policy(root: Path) -> dict:
    """Deterministic review candidate. No CLI writes or approves this policy."""
    matrices = json_data(relative(root, 'tools/ci-matrix.json').read_text(encoding='utf-8'))
    hashes = {'tools/ci-matrix.json': digest(relative(root, 'tools/ci-matrix.json'))}
    jobs = []
    concurrency_groups = {}
    workflows = {}
    seen_paths = set()

    def read(path):
        if path not in workflows:
            file = relative(root, path)
            hashes[path] = digest(file)
            workflows[path] = workflow_data(file.read_text(encoding='utf-8'))
        return workflows[path]

    root_data = read(WORKFLOW)
    need(root_data.get('name') == 'Release candidate', 'wrong release workflow name')
    need(set(root_data.get('on', {})) == {'workflow_dispatch'}, 'release workflow must be manual-only')
    need(set(root_data['jobs']) == set(ROOT_JOBS) | {'required'}, 'release root must include exactly all three gates')
    for key, target in ROOT_JOBS.items():
        need(root_data['jobs'][key].get('uses') == target, 'incorrect release dependency: ' + key)
    need(root_data['jobs']['acceptance'].get('with') == {'regressions': 'full'}, 'release needs full acceptance')
    gate = root_data['jobs']['required']
    need(gate.get('name') == GATE and gate.get('if') == 'always()', 'required release gate must always execute')
    need(set(gate.get('needs', [])) == set(ROOT_JOBS), 'release gate omits a dependency')
    need(gate.get('permissions') == {'contents': 'read', 'actions': 'read'}, 'incorrect gate permissions')
    permission_check(root_data.get('permissions'))
    root_context = {'github.workflow': 'Release candidate', 'github.ref': '{ref}',
                    'github.run_attempt': '{attempt}', 'github.sha': '{sha}',
                    'github.event_name': 'workflow_dispatch', 'inputs.regressions': 'full',
                    'needs.regression-scope.outputs.regressions': 'full'}

    def walk(path, prefix='', stack=()):
        need(path not in stack and len(stack) <= 4, 'cyclic/deep reusable workflow graph')
        data = read(path)
        permission_check(data.get('permissions'))
        if path != WORKFLOW:
            need('workflow_call' in data.get('on', {}), 'not callable: ' + path)
        concurrent = data.get('concurrency')
        if concurrent:
            need(type(concurrent) is dict, 'unreviewed concurrency')
            key = render(concurrent['group'], root_context)
            need(key not in concurrency_groups or concurrency_groups[key] == path,
                 'caller/callee concurrency collision: ' + key)
            concurrency_groups[key] = path
            # Isolate called workflows from regular push CI/Acceptance.
            if path != WORKFLOW:
                need('github.workflow' in concurrent['group'], 'standalone/release concurrency collision: ' + path)
        for ident, job in data['jobs'].items():
            need(type(job) is dict, 'invalid workflow job')
            permission_check(job.get('permissions'))
            need('secrets' not in job and job.get('continue-on-error', 'false') == 'false',
                 'no secrets inheritance or allowed failures in release jobs')
            if path == WORKFLOW and ident == 'required':
                continue  # The one explicitly identified in-progress verifier.
            need(job.get('if', 'always()') in ('always()', '${{ always() }}'),
                 'conditional release jobs require review, never silent omission')
            need(not job.get('container') and not job.get('services'), 'unreviewed job container/service')
            rows = matrix_rows(job.get('strategy', {}).get('matrix'), matrices)
            for row in rows:
                context = dict(root_context, **{'matrix.' + k: v for k, v in row.items()})
                need('name' in job, 'release jobs require explicit names: ' + ident)
                name = prefix + render(job['name'], context)
                if 'uses' in job:
                    match = re.fullmatch(r'\./(\.github/workflows/[\w-]+\.yml)', job['uses'])
                    need(match is not None, 'only same-commit local reusable workflows are allowed')
                    for key, value in job.get('with', {}).items():
                        need(key == 'regressions' and render(value, context) == 'full', 'non-full reusable regression scope')
                    walk(match[1], name + ' / ', (*stack, path))
                    continue
                runner = render(job['runs-on'], context)
                context['runner.os'] = runner_os(runner)
                steps = job.get('steps')
                need(type(steps) is list and 0 < len(steps) <= MAX_STEPS, 'missing/oversized steps: ' + name)
                required_steps, artifacts = [], []
                run_steps = 0
                for index, step in enumerate(steps, 2):
                    need(type(step) is dict and step.get('continue-on-error', 'false') == 'false', 'allowed step failure')
                    enabled = condition(step.get('if'), context)
                    need(('run' in step) != ('uses' in step), 'ambiguous workflow step')
                    entry = {'number': index, 'name': render(step['name'], context) if 'name' in step else None,
                             'expected': 'success' if enabled else 'skipped'}
                    required_steps.append(entry)
                    if 'run' in step:
                        run_steps += enabled
                    else:
                        need(re.fullmatch(r'[\w.-]+/[\w./-]+@[a-f0-9]{40}', step['uses']) is not None,
                             'action must be SHA pinned: ' + step['uses'])
                        options = step.get('with', {})
                        if step['uses'].startswith('actions/checkout@'):
                            need(options.get('persist-credentials') == 'false', 'checkout credentials must not persist')
                            if 'repository' not in options:
                                need('ref' not in options, 'candidate checkout must use the caller commit')
                            else:
                                need(re.fullmatch('[a-f0-9]{40}', options.get('ref', '')) is not None
                                     and options.get('path', '').startswith('output/'), 'unreviewed upstream checkout')
                        if enabled and step['uses'].startswith('actions/upload-artifact@'):
                            artifact = render(options['name'], context)
                            need('{attempt}' in artifact and '{sha}' not in artifact, 'evidence artifact must identify the attempt')
                            need(options.get('overwrite', 'false') == 'false', 'do not overwrite evidence artifacts')
                            artifacts.append(artifact)
                need(run_steps > 0, 'release job has no executing checks: ' + name)
                jobs.append({'name': name, 'workflow': path, 'job_id': ident, 'matrix': row, 'runner': runner,
                             'steps': required_steps, 'artifacts': sorted(artifacts)})
                need(len(jobs) <= MAX_JOBS, 'oversized workflow graph')
        seen_paths.add(path)

    walk(WORKFLOW)
    names = [job['name'] for job in jobs]
    need(len(set(names)) == len(names) and GATE not in names, 'duplicate/ambiguous release job names')
    artifacts = [name for job in jobs for name in job['artifacts']]
    need(len(set(artifacts)) == len(artifacts), 'artifact name collision across required lanes')
    need(set(ROOT_JOBS.values()) <= {'./' + p for p in seen_paths}, 'incomplete release graph')
    # Inventory every existing workflow, not just a hand-selected family list.
    actual = {p.relative_to(root).as_posix() for suffix in ('*.yml', '*.yaml')
              for p in (root / '.github/workflows').glob(suffix)}
    need(actual == seen_paths, 'workflow omitted from release graph: ' + repr(sorted(actual ^ seen_paths)))
    # Validate selector semantics by freezing the existing, independently tested selector.
    for file in ('tools/validation_regressions.py', 'tools/ci_matrix.py'):
        hashes[file] = digest(relative(root, file))
    return {'schema': 1, 'stage': STAGE, 'baseline_commit': BASELINE, 'package_version': '0.78',
            'workflow': WORKFLOW, 'self_job': GATE, 'needs': sorted(ROOT_JOBS),
            'workflow_sources': dict(sorted(hashes.items())), 'jobs': sorted(jobs, key=lambda j: j['name']),
            'artifact_names': sorted(artifacts), 'evidence_basis': 'same-run-attempt-job-step-and-artifact-evidence',
            'release_ready': False}


def generated_report(policy):
    lines = ['# Release candidate matrix — 0.78d', '',
             'Generated from the reviewed local reusable-workflow graph. Not a run receipt.', '',
             f"Integration baseline: `{policy['baseline_commit']}`. Package version: **0.78**.", '',
             f"**{len(policy['jobs'])} required jobs; {len(policy['artifact_names'])} required evidence artifacts.**", '',
             'All jobs must finish successfully in one attempt of the Release candidate workflow.',
             'The in-progress `Release candidate required` verifier is the sole exception to the job list below.', '',
             '| Required job | Hosted runner | Workflow | Evidence artifacts |', '|---|---|---|---:|']
    for job in policy['jobs']:
        lines.append(f"| {job['name']} | {job['runner']} | `{job['workflow']}` | {len(job['artifacts'])} |")
    lines += ['', '## Evidence boundary', '',
              'The gate checks workflow identity, every reviewed matrix job and authored step, and every evidence ZIP. '
              'It delegates native pixel/document/consumer assertions to the existing executing validators. '
              'It does not reinterpret successful source checks as new native rendering, hardware performance, '
              'physical-display validation, universal backend support, or permission to publish version 1.0.', '']
    return '\n'.join(lines)
