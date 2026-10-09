"""Same-attempt release evidence validation and bounded, read-only retrieval.

No imports run Racket, load Skia, access the network or approve a release.
GitHub execution results are evidence delegated to the existing validators,
not a new independent pixel test or an authorization to publish a 1.0 release.
"""
from __future__ import annotations
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import zipfile

from release_graph import (BASELINE, STAGE, WORKFLOW, POLICY, REPORT, GATE,
                           MAX_BYTES, build_policy, digest, generated_report,
                           json_data, json_text, need, relative)
MAX_ARTIFACT = 128 * 1024 * 1024
MAX_TOTAL_ARTIFACTS = 1024 * 1024 * 1024
MAX_UNCOMPRESSED = 256 * 1024 * 1024
MAX_TOTAL_UNCOMPRESSED = 2 * 1024 * 1024 * 1024
MAX_PAGES = 32
SHA = re.compile(r'[a-f0-9]{40}\Z')
SHA256 = re.compile(r'[a-f0-9]{64}\Z')
REPOSITORY = re.compile(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z')


def positive(value, label):
    need(type(value) is int and value > 0, 'invalid ' + label)
    return value


def timestamp(value):
    need(type(value) is str, 'missing timestamp')
    parsed = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    need(parsed.tzinfo is not None, 'timestamp has no timezone')
    return parsed


def read_json(path):
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= MAX_BYTES,
         'missing/unsafe/oversized JSON: ' + str(path))
    return json_data(path.read_text(encoding='utf-8'))


def write_json(path, value):
    need(not path.exists(), 'refusing to overwrite evidence: ' + str(path))
    path.write_text(json_text(value), encoding='utf-8', newline='\n')


def git(root, *args):
    result = subprocess.run(['git', *args], cwd=root, check=True, capture_output=True, timeout=120)
    return result.stdout


def source_contracts(root):
    import release_scope
    import public_api
    expected = read_json(relative(root, POLICY))
    actual = build_policy(root)
    need(json_text(actual) == json_text(expected), 'release graph/policy drift: explicitly review changed workflows before updating the ledger')
    need(relative(root, REPORT).read_text(encoding='utf-8') == generated_report(expected),
         'release matrix documentation drift')
    scope = release_scope.audit(root)
    need(scope['in_scope_gaps_closed'] is True and scope['release_ready'] is False, 'release-scope closure required')
    public = public_api.source_contracts(root)
    need(public['api_signatures_verified'] is False, 'source checks must not invent signature execution')
    need('(define version "0.78")' in relative(root, 'info.rkt').read_text(encoding='utf-8'), 'package version changed')
    return expected


def manifest_module(root):
    spec = importlib.util.spec_from_file_location('release_manifest', relative(root, 'tools/update-source-sums.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def clean_source(root):
    need(Path(git(root, 'rev-parse', '--show-toplevel').decode().strip()).resolve() == root.resolve(), 'not repository root')
    sha = git(root, 'rev-parse', 'HEAD').decode().strip()
    need(SHA.fullmatch(sha) is not None, 'invalid source commit')
    need(not git(root, 'diff', '--name-only') and not git(root, 'diff', '--cached', '--name-only'),
         'candidate must be committed with a clean index and working tree')
    # Includes independently discovered, unignored source paths. Untracked source
    # cannot silently enter or be left out of the release ZIP.
    manifest = manifest_module(root)
    count = manifest.check(root)
    return dict(commit=sha, manifest_sha256=digest(relative(root, manifest.NAME)), files=count)


def verify_needs(value, policy):
    need(type(value) is dict and set(value) == set(policy['needs']), 'missing/extra caller needs results')
    for name, result in value.items():
        need(type(result) is dict and result.get('result') == 'success', 'required dependency did not pass: ' + name)


def verify_run(run, *, repository, sha, run_id, attempt, live=True):
    need(type(repository) is str and REPOSITORY.fullmatch(repository) is not None, 'invalid repository')
    need(type(sha) is str and SHA.fullmatch(sha) is not None, 'invalid candidate SHA')
    positive(run_id, 'run ID'); positive(attempt, 'run attempt')
    need(run.get('id') == run_id and type(run.get('id')) is int, 'foreign run ID')
    need(type(run.get('run_attempt')) is int and run['run_attempt'] == attempt, 'foreign run attempt')
    need(run.get('head_sha') == sha, 'foreign run commit')
    need(run.get('repository', {}).get('full_name') == repository
         and run.get('head_repository', {}).get('full_name') == repository, 'foreign or forked run repository')
    need(run.get('path') == WORKFLOW and run.get('name') == 'Release candidate', 'not the candidate workflow')
    need(run.get('event') == 'workflow_dispatch', 'release evidence must be an explicit dispatch')
    need(run.get('status') == 'in_progress' and run.get('conclusion') is None,
         'gate must inspect its own in-progress run, not a historical aggregate')
    timestamp(run.get('run_started_at'))


def verify_jobs(jobs, policy, *, run, sha, run_id, attempt):
    need(type(jobs) is list and jobs, 'empty workflow jobs')
    ids, names = set(), {}
    start = timestamp(run['run_started_at'])
    for job in jobs:
        ident = positive(job.get('id'), 'job ID')
        name = job.get('name')
        need(type(name) is str and name not in names and ident not in ids, 'duplicate/invalid job')
        ids.add(ident); names[name] = job
        need(type(job.get('run_id')) is int and job.get('run_id') == run_id and job.get('head_sha') == sha, 'mixed job run/commit: ' + name)
        # Some REST versions do not include run_attempt on individual jobs. The
        # transport MUST use /attempts/{attempt}/jobs and time bounds still apply.
        if 'run_attempt' in job:
            need(type(job['run_attempt']) is int and job['run_attempt'] == attempt, 'mixed job attempts')
        need(timestamp(job.get('started_at')) >= start, 'reused job from an earlier attempt: ' + name)
    expected = {job['name']: job for job in policy['jobs']}
    need(set(names) == set(expected) | {GATE},
         'job coverage mismatch (rerun ALL jobs): ' + repr(sorted(set(names) ^ (set(expected) | {GATE}))))
    own = names[GATE]
    need(own.get('status') == 'in_progress' and own.get('conclusion') is None, 'unexpected verifier job state')
    for name, contract in expected.items():
        actual = names[name]
        need(actual.get('status') == 'completed' and actual.get('conclusion') == 'success',
             'required job failed/skipped/cancelled/incomplete: ' + name)
        need(timestamp(actual.get('completed_at')) >= timestamp(actual['started_at']), 'invalid job completion time')
        steps = actual.get('steps')
        need(type(steps) is list and bool(steps), 'missing step evidence: ' + name)
        indexed = {}
        for step in steps:
            number = positive(step.get('number'), 'step number')
            need(number not in indexed, 'duplicate step number')
            indexed[number] = step
            need(step.get('status') == 'completed' and step.get('conclusion') in ('success', 'skipped'),
                 'failed/incomplete step despite green job: ' + name)
        for item in contract['steps']:
            found = indexed.get(item['number'])
            need(found is not None, 'missing workflow-authored step: ' + name)
            if item['name'] is not None:
                need(found.get('name') == item['name'], 'step name/position mismatch: ' + name)
            need(found.get('conclusion') == item['expected'], 'required step skipped or unexpected execution: ' + name)
    return len(expected)


def select_artifacts(artifacts, policy, *, run, sha, run_id, attempt):
    need(type(artifacts) is list, 'invalid artifact list')
    expected = {name.replace('{attempt}', str(attempt)) for name in policy['artifact_names']}
    selected = {}
    ids = set()
    for artifact in artifacts:
        ident = positive(artifact.get('id'), 'artifact ID')
        need(ident not in ids, 'duplicate artifact ID')
        ids.add(ident)
        name = artifact.get('name')
        if name not in expected:
            continue  # Other attempts are retained, but never used as evidence.
        need(name not in selected, 'duplicate required evidence artifact: ' + name)
        provenance = artifact.get('workflow_run', {})
        need(type(provenance.get('id')) is int and provenance.get('id') == run_id and provenance.get('head_sha') == sha, 'foreign artifact provenance')
        need(artifact.get('expired') is False, 'required evidence has expired')
        size = positive(artifact.get('size_in_bytes'), 'artifact size')
        need(size <= MAX_ARTIFACT, 'artifact exceeds download limit')
        hash_value = artifact.get('digest', '')
        need(type(hash_value) is str and hash_value.startswith('sha256:') and SHA256.fullmatch(hash_value[7:]),
             'missing/invalid GitHub artifact digest')
        need(timestamp(artifact.get('created_at')) >= timestamp(run['run_started_at']), 'artifact is from an earlier attempt')
        selected[name] = artifact
    need(set(selected) == expected, 'missing required evidence artifacts: ' + repr(sorted(expected - set(selected))))
    need(sum(x['size_in_bytes'] for x in selected.values()) <= MAX_TOTAL_ARTIFACTS, 'artifact total exceeds limit')
    return dict(sorted(selected.items()))


def inspect_zip(path, expected_digest):
    need(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= MAX_ARTIFACT, 'unsafe evidence ZIP')
    need(digest(path) == expected_digest, 'downloaded artifact digest mismatch')
    # Verify CRC and bounded members, but do not extract or execute artifacts.
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        need(0 < len(infos) <= 20000, 'empty/oversized evidence member list')
        names = set(); total = 0
        for info in infos:
            name = info.filename.rstrip('/')
            parts = name.split('/')
            need(name and not name.startswith('/') and '\\' not in name and ':' not in name
                 and all(p not in ('', '.', '..') for p in parts) and not any(ord(c) < 32 for c in name),
                 'unsafe ZIP member name')
            need(name not in names, 'duplicate ZIP member')
            names.add(name)
            need(not stat.S_ISLNK(info.external_attr >> 16), 'symlink ZIP member')
            need(info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), 'unsupported ZIP compression')
            total += info.file_size
            need(total <= MAX_UNCOMPRESSED, 'evidence decompression limit exceeded')
            need(not (info.flag_bits & 1), 'encrypted evidence ZIP')
        need(archive.testzip() is None, 'corrupt evidence ZIP')
    return {'sha256': expected_digest, 'bytes': path.stat().st_size, 'members': len(names), 'uncompressed_bytes': total}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class GitHubReader:
    """Token goes only to api.github.com. Artifact redirects never receive it."""
    def __init__(self, repository, token):
        need(type(repository) is str and REPOSITORY.fullmatch(repository) is not None, 'invalid repository')
        need(type(token) is str and bool(token) and '\n' not in token and '\r' not in token, 'missing/invalid read token')
        self.base = 'https://api.github.com/repos/' + repository
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, url, *, authorized):
        parsed = urllib.parse.urlsplit(url)
        need(parsed.scheme == 'https' and parsed.port in (None, 443) and not parsed.username and not parsed.password,
             'unsafe retrieval URL')
        headers = {'User-Agent': 'skia-for-racket-release-validator/0.78d'}
        if authorized:
            need(url.startswith(self.base + '/') and parsed.hostname == 'api.github.com', 'refusing token to foreign host')
            headers.update({'Authorization': 'Bearer ' + self.token, 'Accept': 'application/vnd.github+json',
                            'X-GitHub-Api-Version': '2022-11-28'})
        else:
            host = parsed.hostname or ''
            need(host.endswith(('.blob.core.windows.net', '.actions.githubusercontent.com', '.githubusercontent.com')),
                 'unapproved artifact redirect host')
        try:
            return self.opener.open(urllib.request.Request(url, headers=headers), timeout=90)
        except urllib.error.HTTPError as error:
            if error.code in (301, 302, 303, 307, 308):
                return error
            # Never leak the token or a signed redirect URL into an error report.
            raise RuntimeError('GitHub evidence request failed with HTTP ' + str(error.code)) from None
        except urllib.error.URLError:
            raise RuntimeError('GitHub evidence request failed') from None

    def get(self, suffix):
        need(suffix.startswith('/actions/') and '..' not in suffix, 'invalid REST evidence route')
        with self.request(self.base + suffix, authorized=True) as response:
            need(response.code == 200, 'unexpected REST metadata redirect/status')
            payload = response.read(MAX_BYTES + 1)
        need(len(payload) <= MAX_BYTES, 'REST JSON exceeds limit')
        return json_data(payload.decode('utf-8'))

    def paged(self, suffix, key):
        rows = []; expected = None
        for page in range(1, MAX_PAGES + 1):
            payload = self.get(suffix + '?per_page=100&page=' + str(page))
            total = payload.get('total_count')
            need(type(total) is int and 0 <= total <= MAX_PAGES * 100, 'invalid REST total')
            if expected is None:
                expected = total
            need(total == expected, 'REST inventory changed during pagination; retry the complete run')
            batch = payload.get(key)
            need(type(batch) is list and len(batch) <= 100, 'invalid REST page')
            rows.extend(batch)
            if len(rows) == expected:
                return rows
            need(len(batch) == 100 and len(rows) < expected, 'truncated/overfull REST pagination')
        raise ValueError('REST pagination limit exceeded')

    def download(self, artifact_id, target):
        positive(artifact_id, 'artifact ID')
        need(not target.exists(), 'refusing to overwrite artifact')
        url = self.base + '/actions/artifacts/' + str(artifact_id) + '/zip'
        authorized = True
        for _ in range(5):
            with self.request(url, authorized=authorized) as response:
                if response.code in (301, 302, 303, 307, 308):
                    url = response.headers.get('Location', '')
                    authorized = False
                    continue
                need(response.code == 200, 'unexpected artifact response')
                size = 0
                try:
                    with target.open('xb') as output:
                        while True:
                            block = response.read(1024 * 1024)
                            if not block:
                                break
                            size += len(block)
                            need(size <= MAX_ARTIFACT, 'artifact download exceeds limit')
                            output.write(block)
                except BaseException:
                    target.unlink(missing_ok=True)
                    raise
                need(size > 0, 'empty artifact download')
                return
        raise ValueError('too many artifact redirects')


def source_archive(root, destination):
    manifest = manifest_module(root)
    rows = manifest.read_manifest(root)
    need(not destination.exists(), 'source archive already exists')
    names = sorted([*rows, manifest.NAME])
    with zipfile.ZipFile(destination, 'x', compression=zipfile.ZIP_STORED) as archive:
        for name in names:
            parts = PurePosixPath(name).parts
            need(not any(p in ('.git', 'compiled', '__pycache__', 'output', 'downloads') for p in parts), 'generated source archive member')
            need(not name.endswith(('.dll', '.so', '.dylib', '.exe', '.pyc', '.nupkg')), 'native/binary source archive member')
            file = relative(root, name)
            data = file.read_bytes()
            if name in rows:
                need(hashlib.sha256(data).hexdigest() == rows[name], 'source mutated during packaging: ' + name)
            entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    with zipfile.ZipFile(destination) as archive:
        need(archive.namelist() == names and archive.testzip() is None, 'source archive roundtrip failed')
    return {'file': destination.name, 'sha256': digest(destination), 'bytes': destination.stat().st_size, 'files': len(names)}


def github_identity(env, source):
    need(env.get('GITHUB_ACTIONS') == 'true' and env.get('GITHUB_EVENT_NAME') == 'workflow_dispatch',
         '--github is restricted to the dispatched release workflow')
    need(env.get('GITHUB_WORKFLOW') == 'Release candidate', 'wrong caller workflow context')
    need(env.get('GITHUB_API_URL', 'https://api.github.com') == 'https://api.github.com', 'only public GitHub API supported')
    repository = env.get('GITHUB_REPOSITORY', '')
    need(REPOSITORY.fullmatch(repository) is not None, 'invalid GitHub repository')
    sha = env.get('GITHUB_SHA', '')
    need(sha == source['commit'], 'checkout does not match workflow SHA')
    ref = env.get('GITHUB_WORKFLOW_REF', '')
    need(ref.startswith(repository + '/' + WORKFLOW + '@refs/'), 'incorrect workflow reference')
    for key in ('GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT'):
        need(re.fullmatch('[1-9][0-9]*', env.get(key, '')) is not None, 'invalid ' + key)
    return {'repository': repository, 'sha': sha, 'run_id': int(env['GITHUB_RUN_ID']),
            'attempt': int(env['GITHUB_RUN_ATTEMPT'])}


def collect(root, directory, policy, source, *, env=None, reader_factory=GitHubReader):
    env = os.environ if env is None else env
    identity = github_identity(env, source)
    needs = json_data(env.get('RELEASE_NEEDS_JSON', '{}'))
    write_json(directory / 'identity.json', identity)
    write_json(directory / 'needs.json', needs)
    verify_needs(needs, policy)
    reader = reader_factory(identity['repository'], env.get('GH_TOKEN', ''))
    run_id, attempt = identity['run_id'], identity['attempt']
    run = reader.get(f'/actions/runs/{run_id}')
    write_json(directory / 'run.json', run)
    verify_run(run, **identity)
    jobs = reader.paged(f'/actions/runs/{run_id}/attempts/{attempt}/jobs', 'jobs')
    write_json(directory / 'jobs.json', jobs)
    count = verify_jobs(jobs, policy, run=run, **{k: identity[k] for k in ('sha', 'run_id', 'attempt')})
    artifacts = reader.paged(f'/actions/runs/{run_id}/artifacts', 'artifacts')
    write_json(directory / 'artifact-metadata.json', artifacts)
    selected = select_artifacts(artifacts, policy, run=run, **{k: identity[k] for k in ('sha', 'run_id', 'attempt')})
    folder = directory / 'artifacts'; folder.mkdir()
    downloaded = {}; used = 0; expanded = 0
    for name, artifact in selected.items():
        target = folder / (str(artifact['id']) + '.zip')
        reader.download(artifact['id'], target)
        used += target.stat().st_size
        need(used <= MAX_TOTAL_ARTIFACTS, 'total downloaded evidence exceeds limit')
        inspection = inspect_zip(target, artifact['digest'][7:])
        expanded += inspection['uncompressed_bytes']
        need(expanded <= MAX_TOTAL_UNCOMPRESSED, 'total decompressed evidence exceeds limit')
        downloaded[name] = dict(inspection, file=target.relative_to(directory).as_posix(), artifact_id=artifact['id'])
        # Keep partial evidence index even if a subsequent download fails.
        (directory / 'artifact-index.json').write_text(json_text(downloaded), encoding='utf-8', newline='\n')
    # A new attempt or cancellation during the gate must not produce a pass.
    verify_run(reader.get(f'/actions/runs/{run_id}'), **identity)
    return {'identity': identity, 'jobs_verified': count, 'artifacts_verified': len(downloaded),
            'artifact_bytes': used, 'github_evidence_observed': True}
