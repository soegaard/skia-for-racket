"""Native ABI policy, source inventory and isolated binary investigation (0.47).

No library is loaded in the parent process. The worker calls only the two
scalar version functions and, for the reviewed candidate milestone only, the
Graphite compiled-backend query. No context or versioned structure is created.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BINDINGS = (
    ('private/native.rkt', 'define-native', 1, 'cpu'),
    ('private/gpu-native.rkt', 'define-gpu-native', 2, 'gpu-context'),
    ('private/gpu-surface-native.rkt', 'define-surface-native', 3, 'gpu-surface'),
    ('private/gpu-image-native.rkt', 'define-image-native', 2, 'gpu-image'),
    ('private/gpu-cache-native.rkt', 'define-cache-native', 2, 'gpu-cache'),
    ('private/gpu-gl-interop-native.rkt', 'define-interop-native', 2, 'gpu-interop'),
    ('private/gpu-presentation-native.rkt', 'define-call', 2, 'gpu-presentation'),
)
SYMBOL = re.compile(r'(?:sk|gr)_[A-Za-z0-9_]+\Z')
MAX_ARCHIVE = 512 * 1024 * 1024
MAX_NATIVE = 256 * 1024 * 1024


def catalog(root: Path = ROOT) -> dict:
    data = json.loads((root / 'private/native-abi.json').read_text(encoding='utf-8'))
    if data.get('schema') != 1 or not data.get('profiles'):
        raise ValueError('invalid native ABI catalog')
    return data


def default_version(root: Path = ROOT) -> str:
    value = (root / 'private/native-default-version.txt').read_text(encoding='utf-8').strip()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', value):
        raise ValueError('invalid default native package version')
    return value


def profile_for(data: dict, milestone: int, increment: int, pointer_bytes: int) -> dict | None:
    if any(type(x) is not int for x in (milestone, increment, pointer_bytes)):
        raise ValueError('native ABI identity fields must be integers')
    if milestone < 0 or increment < 0 or pointer_bytes <= 0:
        raise ValueError('invalid native ABI identity')
    matches = [p for p in data['profiles'] if p['milestone'] == milestone
               and p['minimum_increment'] <= increment and p['pointer_bytes'] == pointer_bytes]
    if len(matches) > 1:
        raise ValueError('ambiguous native ABI profile')
    return matches[0] if matches else None


def _tokens(text: str) -> list:
    """Small fail-closed reader for declaration inventories, not a Racket parser.

    Handles strings, characters, nested block comments, datum comments, quotes
    and all bracket forms so examples/macros are not counted as declarations.
    """
    text = re.sub(r'\A#lang[^\n]*', '', text)
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
        elif c == ';':
            end = text.find('\n', i)
            i = n if end < 0 else end
        elif text.startswith('#|', i):
            depth, i = 1, i + 2
            while depth and i < n:
                if text.startswith('#|', i): depth += 1; i += 2
                elif text.startswith('|#', i): depth -= 1; i += 2
                else: i += 1
            if depth: raise ValueError('unterminated block comment')
        elif text.startswith('#;', i):
            out.append('#;'); i += 2
        elif text.startswith('#\\', i):
            i += 2
            if i == n: raise ValueError('incomplete character literal')
            i += 1
            while i < n and not text[i].isspace() and text[i] not in '()[]{}': i += 1
            out.append(('literal', 'character'))
        elif c == '"':
            i += 1
            while i < n and text[i] != '"':
                if text[i] == '\\': i += 1
                i += 1
            if i >= n: raise ValueError('unterminated string')
            i += 1; out.append(('literal', 'string'))
        elif c in '()[]{}':
            out.append(c); i += 1
        elif c in "'`,":
            out.append(c); i += 1
            if c == ',' and i < n and text[i] == '@': i += 1
        else:
            j = i
            while i < n and not text[i].isspace() and text[i] not in '()[]{};"': i += 1
            out.append(text[j:i])
    return out


def forms(text: str) -> list:
    tokens, pos = _tokens(text), 0
    skip = object()
    close = {'(': ')', '[': ']', '{': '}'}
    def read():
        nonlocal pos
        if pos == len(tokens): raise ValueError('incomplete datum')
        token = tokens[pos]; pos += 1
        if isinstance(token, str) and token in close:
            result = []
            while pos < len(tokens) and tokens[pos] != close[token]:
                item = read()
                if item is not skip: result.append(item)
            if pos == len(tokens): raise ValueError('unclosed declaration')
            pos += 1
            return result
        if isinstance(token, str) and token in (')', ']', '}'):
            raise ValueError('mismatched closing bracket')
        if token == '#;':
            item = read()
            while item is skip: item = read()
            return skip
        if token in ("'", '`', ','):
            return ['quote', read()]
        return token
    result = []
    while pos < len(tokens):
        item = read()
        if item is not skip: result.append(item)
    return result


def source_inventory(root: Path = ROOT) -> dict[str, list[str]]:
    groups = {}
    for relative, macro, index, group in BINDINGS:
        names = []
        for form in forms((root / relative).read_text(encoding='utf-8')):
            if isinstance(form, list) and form and form[0] == macro:
                if len(form) <= index or not isinstance(form[index], str) or not SYMBOL.fullmatch(form[index]):
                    raise ValueError(f'unrecognized {macro} declaration in {relative}')
                names.append(form[index])
        if not names or len(set(names)) != len(names):
            raise ValueError(f'empty or duplicate symbol registry: {relative}')
        groups[group] = sorted(names)
    return groups


def _worker(spec: dict) -> dict:
    # Native loading is deliberately confined to a disposable child process.
    import ctypes
    path = Path(spec['library'])
    if not path.is_absolute() or not path.is_file():
        raise ValueError('worker library must be an existing absolute filename')
    names = spec['symbols']
    if not isinstance(names, list) or not all(isinstance(n, str) and SYMBOL.fullmatch(n) for n in names):
        raise ValueError('invalid symbol inventory')
    lib = ctypes.CDLL(str(path))
    def integer(name):
        function = getattr(lib, name)
        function.argtypes, function.restype = [], ctypes.c_int
        return function()
    milestone = integer('sk_version_get_milestone')
    increment = integer('sk_version_get_increment')
    if milestone < 0 or increment < 0: raise ValueError('negative native version')
    resolved = {}
    for name in names:
        try: getattr(lib, name); resolved[name] = True
        except AttributeError: resolved[name] = False
    calls = ['sk_version_get_milestone', 'sk_version_get_increment']
    graphite = None
    if milestone == spec.get('graphite_milestone') and resolved.get('sk_graphite_backend_is_available'):
        query = getattr(lib, 'sk_graphite_backend_is_available')
        query.argtypes, query.restype = [ctypes.c_int], ctypes.c_bool
        graphite = {name: bool(query(index)) for name, index in (('dawn', 0), ('metal', 1), ('vulkan', 2))}
        calls.append('sk_graphite_backend_is_available')
    return {'schema': 1, 'status': 'observed', 'milestone': milestone, 'increment': increment,
            'pointer_bytes': ctypes.sizeof(ctypes.c_void_p), 'symbols': resolved,
            'native_calls': calls, 'graphite_compiled_backends': graphite,
            'versioned_structs_passed': False, 'rendering_executed': False,
            'backend_creation_verified': False, 'hardware_acceleration_verified': False}


def clean_probe_environment() -> dict[str, str]:
    env = dict(os.environ)
    for key in ('RACKET_SKIA_LIBRARY', 'LD_PRELOAD', 'DYLD_INSERT_LIBRARIES',
                'LD_LIBRARY_PATH', 'DYLD_LIBRARY_PATH', 'DYLD_FALLBACK_LIBRARY_PATH',
                'PLTCOLLECTS', 'PLTLINKS', 'PLTCOMPILEDROOTS', 'PLTCONFIGDIR',
                'PLT_COMPILED_FILE_CHECK'):
        env.pop(key, None)
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    return env


def run_probe(library: Path, groups: dict, output: Path, timeout: int = 30, *, graphite_milestone: int | None = None) -> dict:
    symbols = sorted({name for names in groups.values() for name in names})
    command = [sys.executable, str(Path(__file__).resolve()), '--worker']
    spec = {'library': str(library.resolve()), 'symbols': symbols, 'graphite_milestone': graphite_milestone}
    (output / 'probe-input.json').write_text(json.dumps(spec, indent=2) + '\n', encoding='utf-8')
    try:
        result = subprocess.run(command, input=json.dumps(spec), capture_output=True, text=True,
                                encoding='utf-8', env=clean_probe_environment(), timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        for suffix, value in (('stdout', exc.stdout), ('stderr', exc.stderr)):
            raw = value.encode('utf-8') if isinstance(value, str) else (value or b'')
            (output / ('probe-' + suffix + '.txt')).write_bytes(raw)
        raise ValueError(f'native worker timed out after {timeout} seconds') from exc
    (output / 'probe-stdout.txt').write_text(result.stdout, encoding='utf-8')
    (output / 'probe-stderr.txt').write_text(result.stderr, encoding='utf-8')
    if result.returncode != 0:
        raise ValueError(f'native worker failed/crashed (exit {result.returncode}); see probe-stderr.txt')
    observed = json.loads(result.stdout)
    if (observed.get('schema') != 1 or observed.get('status') != 'observed'
            or set(observed.get('symbols', {})) != set(symbols)
            or any(type(v) is not bool for v in observed['symbols'].values())
            or observed.get('versioned_structs_passed') is not False
            or observed.get('rendering_executed') is not False):
        raise ValueError('invalid or incomplete native worker report')
    return observed


def assessment(data: dict, observed: dict, groups: dict) -> dict:
    profile = profile_for(data, observed['milestone'], observed['increment'], observed['pointer_bytes'])
    missing = {group: [n for n in names if not observed['symbols'][n]] for group, names in groups.items()}
    return {'supported_profile': profile['id'] if profile else None,
            'wrapper_load_policy': 'eligible-for-runtime-checks' if profile and not missing['cpu'] else 'reject',
            'missing_symbols': missing,
            'symbol_counts': {group: len(names) for group, names in groups.items()},
            'symbol_resolution_is_abi_proof': False,
            'runtime_suite_executed': False,
            'default_dependency_changed': False}


class HTTPSRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.lower().startswith('https://'):
            raise ValueError('non-HTTPS package redirect refused')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(url: str, target: Path) -> None:
    if not url.startswith('https://'): raise ValueError('HTTPS required')
    opener = urllib.request.build_opener(HTTPSRedirects())
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'skia-for-racket-native-abi/0.47'})
            with opener.open(request, timeout=60) as response, target.open('wb') as out:
                count = 0
                while block := response.read(1024 * 1024):
                    count += len(block)
                    if count > MAX_ARCHIVE: raise ValueError('native package is too large')
                    out.write(block)
            return
        except (OSError, TimeoutError):
            target.unlink(missing_ok=True)
            if attempt == 2: raise
            time.sleep(attempt + 1)


def target_package(system: str | None = None, machine: str | None = None) -> tuple[str, str, str]:
    system, machine = system or platform.system(), (machine or platform.machine()).lower()
    if machine not in ('x86_64', 'amd64', 'arm64', 'aarch64'):
        raise ValueError('investigation supports 64-bit x86 and ARM hosts only')
    if system == 'Darwin': return ('skiasharp.nativeassets.macos', 'osx', 'libSkiaSharp.dylib')
    arch = 'x64' if machine in ('x86_64', 'amd64') else 'arm64'
    if system == 'Linux': return ('skiasharp.nativeassets.linux', f'linux-{arch}', 'libSkiaSharp.so')
    if system == 'Windows' and arch == 'x64': return ('skiasharp.nativeassets.win32', 'win-x64', 'libSkiaSharp.dll')
    raise ValueError('unsupported native investigation host')


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        h = hashlib.sha256()
        while block := stream.read(1024 * 1024): h.update(block)
    return h.hexdigest()


def extract_package(archive: Path, package: str, version: str, member: str, destination: Path) -> dict:
    if archive.stat().st_size > MAX_ARCHIVE: raise ValueError('native package is too large')
    with zipfile.ZipFile(archive) as z:
        specs = [i for i in z.infolist() if i.filename.lower().endswith('.nuspec')]
        members = [i for i in z.infolist() if i.filename == member]
        if len(specs) != 1 or len(members) != 1: raise ValueError('missing/duplicate nuspec or native member')
        if specs[0].file_size > 1024 * 1024: raise ValueError('oversized nuspec')
        info = members[0]
        if not 0 < info.file_size <= MAX_NATIVE: raise ValueError('empty/oversized native member')
        if stat.S_ISLNK(info.external_attr >> 16): raise ValueError('symlink native member refused')
        xml = z.read(specs[0])
        if b'<!DOCTYPE' in xml.upper() or b'<!ENTITY' in xml.upper(): raise ValueError('DTD/entity nuspec refused')
        root = ET.fromstring(xml)
        metadata = [n for n in root if n.tag.rsplit('}', 1)[-1] == 'metadata']
        if len(metadata) != 1: raise ValueError('invalid package metadata')
        def field(name):
            found = [n for n in metadata[0] if n.tag.rsplit('}', 1)[-1] == name]
            if len(found) != 1 or list(found[0]): raise ValueError('ambiguous package metadata field')
            return (found[0].text or '').strip()
        if field('id').lower() != package.lower() or field('version') != version:
            raise ValueError('native package identity/version mismatch')
        # Fixed member only; archive paths are never extracted to the filesystem.
        with z.open(info) as source, destination.open('xb') as out:
            shutil.copyfileobj(source, out)
        destination.chmod(0o755)
    return {'package': package, 'version': version, 'member': member,
            'archive_sha256': digest(archive), 'native_sha256': digest(destination),
            'native_bytes': destination.stat().st_size,
            'hashes_are_observations_not_independent_authentication': True}


def reject_with_racket(racket: str, library: Path, milestone: int, output: Path, timeout: int) -> dict:
    resolved = shutil.which(racket)
    if not resolved: raise ValueError('selected Racket executable not found')
    env = clean_probe_environment()
    env['RACKET_SKIA_LIBRARY'] = str(library.resolve())
    command = [resolved, str(ROOT / 'tools/native-abi-reject.rkt'), str(milestone)]
    try:
        result = subprocess.run(command, env=env, capture_output=True, text=True, encoding='utf-8', timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        for suffix, value in (('stdout', exc.stdout), ('stderr', exc.stderr)):
            raw = value.encode('utf-8') if isinstance(value, str) else (value or b'')
            (output / ('rejection-' + suffix + '.txt')).write_bytes(raw)
        raise ValueError(f'Racket rejection check timed out after {timeout} seconds') from exc
    (output / 'rejection-stdout.txt').write_text(result.stdout, encoding='utf-8')
    (output / 'rejection-stderr.txt').write_text(result.stderr, encoding='utf-8')
    if result.returncode: raise ValueError('Racket ABI rejection check failed; see rejection-stderr.txt')
    data = json.loads(result.stdout)
    if data.get('status') != 'rejected-unsupported-abi' or data.get('milestone') != milestone:
        raise ValueError('wrong Racket rejection evidence')
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', action='store_true', help='investigate the exact catalogued 4.x package')
    parser.add_argument('--archive', type=Path, help='offline copy of that NuGet package')
    parser.add_argument('--sha256', help='optional independently obtained package SHA-256')
    parser.add_argument('--library', type=Path, help='inspect a trusted local binary instead of downloading')
    parser.add_argument('--racket', help='selected Racket; required for the candidate rejection gate')
    parser.add_argument('--output', type=Path, required=True, help='new evidence directory; never reuse stale success')
    parser.add_argument('--timeout', type=int, default=60)
    args = parser.parse_args(argv)
    if args.candidate == bool(args.library): parser.error('choose exactly one of --candidate or --library')
    if args.candidate and not args.racket: parser.error('--candidate requires --racket for the real rejection gate')
    if (args.archive or args.sha256) and not args.candidate: parser.error('package options require --candidate')
    if args.sha256 and not re.fullmatch(r'[0-9a-fA-F]{64}', args.sha256): parser.error('invalid SHA-256')
    if not 1 <= args.timeout <= 600: parser.error('timeout must be 1..600 seconds')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {'schema': 1, 'stage': '0.47', 'status': 'failed',
              'host': {'system': platform.system(), 'machine': platform.machine(), 'python': sys.version},
              'default_dependency_changed': False}
    try:
        data = catalog()
        report['default_package_version'] = default_version()
        groups = source_inventory()
        groups['graphite-candidate'] = data['candidate']['graphite_probe_symbols']
        report['binding_sources_sha256'] = {p: digest(ROOT / p) for p, _, _, _ in BINDINGS}
        with tempfile.TemporaryDirectory(prefix='skia native ABI ') as temporary:
            work = Path(temporary)
            if args.candidate:
                candidate = data['candidate']
                package, rid, filename = target_package()
                version = candidate['package_version']
                url = f'https://api.nuget.org/v3-flatcontainer/{package}/{version}/{package}.{version}.nupkg'
                archive = args.archive.resolve() if args.archive else work / 'candidate.nupkg'
                if not args.archive: download(url, archive)
                if args.sha256 and digest(archive) != args.sha256.lower(): raise ValueError('package SHA-256 mismatch')
                library = work / filename
                report['package'] = extract_package(archive, package, version, f'runtimes/{rid}/native/{filename}', library)
                report['package'].update(url=url, independent_hash_checked=bool(args.sha256))
                report['candidate'] = candidate
            else:
                library = args.library.resolve(strict=True)
                report['local_library'] = {'path': str(library), 'sha256': digest(library)}
            observed = run_probe(library, groups, output, args.timeout, graphite_milestone=(data['candidate']['milestone'] if args.candidate else None))
            report['observation'] = observed
            report['assessment'] = assessment(data, observed, groups)
            if args.candidate:
                if observed['milestone'] != candidate['milestone']: raise ValueError('candidate native milestone mismatch')
                if report['assessment']['wrapper_load_policy'] != 'reject': raise ValueError('candidate unexpectedly admitted')
                report['racket_rejection'] = reject_with_racket(args.racket, library, candidate['milestone'], output, args.timeout)
                report['status'] = 'passed-investigation-candidate-rejected'
            else:
                report['status'] = 'observed-not-a-runtime-validation'
        code = 0
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError,
            zipfile.BadZipFile, ET.ParseError) as exc:
        report['error'] = str(exc)
        print(f'Native ABI investigation FAILED: {exc}', file=sys.stderr)
        code = 1
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print(f'Native ABI evidence: {output / "report.json"}')
    return code


if __name__ == '__main__':
    if sys.argv[1:] == ['--worker']:
        try:
            print(json.dumps(_worker(json.load(sys.stdin)), sort_keys=True))
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
            print(f'native worker failed: {exc}', file=sys.stderr)
            raise SystemExit(1)
    else:
        raise SystemExit(main())
