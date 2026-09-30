"""Required shared Ganesh validation, reusing production doctors and inspectors.

No synthetic fixture is an execution path. The supplied runner must raise on
any nonzero exit, launch failure or timeout. CI uses ci.Runner, with persistent
logs and a private installed source package; the standalone CLI uses it too.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
from gpu_backend_policy import (BACKEND_IDS, declared_capabilities, selection, require,
                                integer, read_json, check_backend_context, check_backend_host,
                                context_signature)

STAGE = '0.50'
SUITES = {
    'offscreen': ('gpu-offscreen-doctor.rkt', 'inspect-gpu-offscreen.py', '0.41', 'offscreen', 33),
    'images': ('gpu-image-doctor.rkt', 'inspect-gpu-images.py', '0.41', 'images', 42),
    'output': ('gpu-output-doctor.rkt', 'inspect-gpu-output.py', '0.44', 'gpu-output', 42),
    'performance': ('gpu-performance-doctor.rkt', 'inspect-gpu-performance.py', '0.45', 'performance', 20),
    'redraw': ('gpu-redraw-doctor.rkt', 'inspect-gpu-performance.py', '0.45', 'redraw', 0),
}
CONFIG = dict(samples=12, warmup=3, frames=180, cycles=3, width=640, height=400, sample_count=0)
TIMING_ARGS = ['--samples', '12', '--warmup', '3', '--frames', '180', '--cycles', '3',
               '--width', '640', '--height', '400', '--sample-count', '0']
SOURCE_PATHS = ('examples/gpu-scenes.rkt', 'examples/gpu-presentation-scene.rkt',
               'private/gpu-performance-util.rkt', 'private/gpu-cache.rkt',
               'tools/gpu-performance-options.rkt', 'tools/gpu-performance-work.rkt',
               'tools/gpu-performance-doctor.rkt', 'tools/gpu-redraw-doctor.rkt')
RESULT = 'parity.inspection.json'
FAILURE = 'parity.failed.json'


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix='.parity-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write(json.dumps(value, indent=2, allow_nan=False) + '\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def suite_names(scope):
    require(scope in ('offscreen', 'presentation', 'all'), 'unknown parity scope')
    return tuple(SUITES) if scope == 'all' else (('redraw',) if scope == 'presentation' else
                                                ('offscreen', 'images', 'output', 'performance'))


def observed_contexts(value):
    if isinstance(value, dict):
        if all(k in value for k in ('backend', 'native_backend', 'generation', 'live_children', 'state')):
            yield value
        for child in value.values(): yield from observed_contexts(child)
    elif isinstance(value, list):
        for child in value: yield from observed_contexts(child)


def no_bool_count(value, expected, message):
    require(type(value) is int and value == expected, message)


def check_identity(identity, backend):
    require(isinstance(identity, dict) and type(identity.get('pointer_bytes')) is int and
            identity['pointer_bytes'] == 8 and identity.get('vm') == 'chez-scheme',
            'parity requires selected 64-bit Racket CS')
    require(isinstance(identity.get('version'), str) and identity['version'], 'missing interpreter version')
    require(isinstance(identity.get('os'), str) and isinstance(identity.get('architecture'), str),
            'missing interpreter platform')
    if backend == 'direct3d':
        require((identity['os'], identity['architecture']) == ('windows', 'x86_64'),
                'Direct3D parity requires Windows x64')
    if backend == 'metal': require(identity['os'] == 'macosx', 'Metal parity requires macOS')


def check_receipt(name, raw, inspected, *, root, run_id, identity, backend, adapter, adapter_index):
    """Bind successfully inspected native reports to this invocation, not a stale/foreign run."""
    _, _, stage, kind, count = SUITES[name]
    for row in (raw, inspected):
        require(isinstance(row, dict) and row.get('status') == 'passed' and
                row.get('backend') == backend and row.get('kind') == kind and row.get('stage') == stage,
                name + ': wrong or failed inspector/native report')
        no_bool_count(row.get('schema_version'), 1, name + ': schema')
    require(raw.get('validation_run') == run_id and raw.get('required') is True,
            name + ': optional or foreign native invocation')
    require(raw.get('os') == identity['os'] and raw.get('architecture') == identity['architecture'] and
            raw.get('racket_version') == identity['version'], name + ': interpreter identity changed')
    check_backend_host(raw, backend, presentation=name == 'redraw')
    contexts = list(observed_contexts(raw))
    require(contexts, name + ': no actual native context evidence')
    signatures = set()
    for c in contexts:
        check_backend_context(c, backend, adapter=adapter, adapter_index=adapter_index)
        signatures.add(context_signature(c, backend))
        require(c.get('binding_package') == '3.119.1' and c.get('native_version') == '119.0',
                name + ': native baseline changed')
    require(len(signatures) == 1, name + ': device identity changed within one report')
    if count:
        no_bool_count(raw.get('native_test_cases'), count, name + ': native suite truncated')
        no_bool_count(raw.get('native_test_failures'), 0, name + ': native cases failed')
    if name == 'offscreen':
        no_bool_count(inspected.get('scenes_checked'), 8, 'offscreen scene coverage')
        require(inspected.get('rendering_verified') is True and
                inspected.get('detached_image_survived_teardown') is True, 'offscreen not rendered/detached')
    elif name == 'images':
        # Individual image inspector already enforces both ordered workflows,
        # real texture residency and the independent exact sample oracle.
        require(len(raw.get('scenes', [])) == 2 and raw.get('detached_survived_teardown') is True,
                'image workflows/detachment incomplete')
    elif name == 'output':
        no_bool_count(inspected.get('documents_checked'), 16, 'document coverage')
        no_bool_count(inspected.get('gpu_group_readbacks'), 8, 'document transfer coverage')
        for field in ('documents_serialized_after_gpu_teardown', 'embedded_svg_pixels_verified',
                      'pdf_structure_verified', 'vector_surroundings_and_links_verified'):
            require(inspected.get(field) is True, 'document evidence missing: ' + field)
        require(inspected.get('pdf_rendered_pixels_verified') is False, 'unverified PDF screen-pixel claim')
    if name in ('performance', 'redraw'):
        conf = raw.get('config', {})
        for key, value in CONFIG.items(): no_bool_count(conf.get(key), value, 'full workload required: ' + key)
        require(inspected.get('config') == conf and inspected.get('resource_envelopes_verified') is True,
                name + ': resource/config inspection missing')
        require(raw.get('performance_measured') is True and raw.get('speedup_claimed') is False and
                raw.get('display_latency_measured') is False, 'timing scope is not host latency')
        sources = raw.get('workload_sources', [])
        require([s.get('path') for s in sources] == list(SOURCE_PATHS), 'missing source fingerprints')
        for item in sources:
            source = root / item['path']
            require(source.is_file() and not source.is_symlink() and
                    hashlib.sha1(source.read_bytes()).hexdigest() == item['sha1'],
                    'timing workload source changed: ' + item['path'])
        if name == 'performance':
            require(len(raw.get('scenes', [])) == 3 and len(raw.get('cycles', [])) == 3,
                    'performance scene/recreate coverage')
            for c in raw['cycles']: no_bool_count(c.get('frames'), 180, 'offscreen stress shortened')
        else:
            require(len(raw.get('windows', [])) == 6, 'redraw context/window coverage')
            for w in raw['windows']: require(len(w.get('frames', [])) == 180, 'redraw stress shortened')
    return dict(name=name, status='passed', backend=backend, native_test_cases=count,
                native_diagnostic=name + '.diagnostic.json', inspection=name + '.inspection.json',
                context_snapshots_checked=len(contexts), device_signature=list(next(iter(signatures))))


def execute(root, racket, directory, run, *, backend, host, adapter=None, adapter_index=None,
            scope='offscreen', egl_platform='surfaceless', egl_device_index=0, egl_surface='surfaceless'):
    root, directory = Path(root).resolve(), Path(directory)
    names = suite_names(scope)
    adapter, adapter_index = selection(backend, host, adapter, adapter_index)
    require(scope == 'offscreen' or host != 'egl', 'presentation cannot use an EGL headless host')
    require(egl_platform in ('surfaceless', 'device') and egl_surface in ('surfaceless', 'pbuffer') and
            integer(egl_device_index, 0, 0xfffffffe), 'invalid EGL selection')
    require(directory.is_dir() and not directory.is_symlink() and not any(directory.iterdir()),
            'parity needs a new, empty evidence directory')
    directory = directory.resolve()
    require(directory != root, 'source root is not an evidence directory')
    require(isinstance(racket, str) and bool(racket), 'selected interpreter required')
    manifest = root / 'SOURCE-SHA256SUMS.txt'
    require(manifest.is_file() and not manifest.is_symlink(), 'source manifest required')
    before = sha256(manifest)
    progress = dict(schema=1, stage=STAGE, status='running', validation_run=directory.name,
                    backend=backend, host=host, adapter=adapter, adapter_index=adapter_index,
                    scope=scope, source_manifest_sha256=before, suites=[],
                    hardware_acceleration_verified=False, visible_pixels_verified=False,
                    speedup_claimed=False)
    try:
        # The caller supplies SKIA_GPU_VALIDATION_RUN; each raw report must echo it.
        identity = json.loads(run([racket, root / 'tools/ci-identity.rkt']))
        check_identity(identity, backend)
        progress['identity'] = identity
        run([sys.executable, root / 'tools/update-source-sums.py', '--check', '--manifest-only'])
        declaration = json.loads(run([racket, root / 'tools/gpu-backend-doctor.rkt']))
        expected = dict(schema=1, native_probe_performed=False,
                        backends=[declared_capabilities(b) for b in BACKEND_IDS])
        require(declaration == expected, 'Racket and Python backend declarations disagree')
        progress['wrapper_declarations_checked'] = True
        doctors = [root / ('tools/' + SUITES[n][0]) for n in names]
        run([racket, '-l', 'raco', '--', 'make', *doctors])
        for name in names:
            doctor, inspector, _, _, _ = SUITES[name]
            prefix = directory / name
            selected_host = 'gui' if name == 'redraw' else host
            args = [racket, root / ('tools/' + doctor), '--prefix', prefix,
                    '--backend', backend, '--host', selected_host]
            if backend == 'direct3d': args += ['--adapter', adapter, '--adapter-index', str(adapter_index)]
            if selected_host == 'egl':
                args += ['--egl-platform', egl_platform, '--egl-device-index', str(egl_device_index),
                         '--egl-surface', egl_surface]
            if name in ('performance', 'redraw'): args += TIMING_ARGS
            run(args)
            run([sys.executable, root / ('tools/' + inspector), '--probe-prefix', prefix])
            raw = read_json(str(prefix) + '.diagnostic.json')
            inspected = read_json(str(prefix) + '.inspection.json')
            progress['suites'].append(check_receipt(name, raw, inspected, root=root, run_id=directory.name,
                                                   identity=identity, backend=backend, adapter=adapter,
                                                   adapter_index=adapter_index))
        run([sys.executable, root / 'tools/update-source-sums.py', '--check', '--manifest-only'])
        require(sha256(manifest) == before, 'source manifest changed during parity validation')
        # Bind the complete retained evidence to the aggregate. Do not publish
        # any success marker until every doctor/inspector and source check passes.
        artifacts = []
        for p in sorted(directory.iterdir()):
            require(p.is_file() and not p.is_symlink(), 'unexpected evidence directory/symlink')
            require(p.suffix in ('.json', '.html', '.csv', '.png', '.pdf', '.svg', '.txt'),
                    'unexpected binary in parity evidence')
            require(p.stat().st_size <= 64 * 1024 * 1024, 'oversized parity evidence')
            artifacts.append(dict(path=p.name, sha256=sha256(p), bytes=p.stat().st_size))
        progress.update(status='passed', native_test_cases=sum(SUITES[n][4] for n in names),
                        rich_offscreen_scenes=8 if 'offscreen' in names else 0,
                        retained_image_workflows=2 if 'images' in names else 0,
                        documents_checked=16 if 'output' in names else 0,
                        offscreen_stress_frames=540 if 'performance' in names else 0,
                        presentation_stress_frames=1080 if 'redraw' in names else 0,
                        measured_host_latency='performance' in names or 'redraw' in names,
                        backend_suite_copies=0, source_unchanged=True, artifacts=artifacts)
        write_json(directory / RESULT, progress)
        return progress
    except BaseException as exc:
        (directory / RESULT).unlink(missing_ok=True)
        progress.update(status='failed', error=str(exc))
        write_json(directory / FAILURE, progress)
        raise


def parity_ci_checks(runner, installed, away, env, report, *, scope):
    """Hook runs inside the installed-package lifetime; never imports the checkout's sources."""
    installed, away = Path(installed), Path(away)
    output = installed / 'output'; output.mkdir(exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix='gpu-parity-0.50-' + scope + '-', dir=output))
    child_env = dict(env)
    child_env.update(SKIA_GPU_VALIDATION_RUN=directory.name, GPU_MODE='required', REQUIRE_HARDWARE='0')
    result = execute(installed, report['racket_executable'], directory,
                     lambda argv: runner.run(argv, cwd=away, env=child_env), backend='direct3d',
                     host='owned' if scope == 'offscreen' else 'gui', adapter='warp', adapter_index=0,
                     scope=scope)
    report['backend_parity_' + scope] = result
    report['checks']['required_backend_parity_' + scope] = True
