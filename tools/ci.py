#!/usr/bin/env python3
"""CI driver: source checks, isolated CPU tests, required EGL and raster GUI.

All Racket commands use one resolved interpreter. No checkout/user native
libraries are copied into the installed package. No package/compiled/native
cache is restored. Successful workflow execution is evidence, not configuration.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import zipfile

from ci_matrix import load_matrix
from native_abi import catalog as native_abi_catalog, default_version

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('ci_source_manifest', ROOT / 'tools/update-source-sums.py')
manifest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manifest)
DISPLAY_KEYS = ('DISPLAY', 'WAYLAND_DISPLAY', 'MIR_SOCKET')
OVERRIDE_KEYS = ('PLTCOLLECTS', 'PLTADDONDIR', 'PLTCONFIGDIR', 'PLTLINKS', 'PLTCOMPILEDROOTS',
                 'PLT_PKG_NOSETUP', 'PLT_SETUP_OPTIONS', 'PLT_COMPILED_FILE_CHECK',
                 'RACKET_SKIA_LIBRARY', 'RACKET_HARFBUZZ_LIBRARY',
                 'LD_PRELOAD', 'DYLD_INSERT_LIBRARIES', 'LD_LIBRARY_PATH',
                 'DYLD_LIBRARY_PATH', 'DYLD_FALLBACK_LIBRARY_PATH')
ABI_NAMES = ('codec', 'pdf', 'path-matrix', 'filter', 'color-output', 'runtime',
             'geometry', 'projective', 'color-filter', 'gpu', 'presentation', 'cache')
PYTHON_CHECKS = (
    'test-validate-skia-canvas.py',
    'test-dc.py',
    'test-metal-interop.py',
    'test-gpu-interop.py',
    'test-gpu-parity.py',
    'test-dxgi.py',
    'test-d3d12.py',
    'test-native-abi.py',
    'test-install-native-windows.py', 'test-validate-gpu-images.py',
    'test-validate-gpu-headless.py', 'test-validate-gpu-output.py',
    'test-validate-gpu-performance.py', 'test-patch-delivery.py', 'test-ci.py',
    'inspect-gpu-probe.py', 'inspect-gpu-offscreen.py', 'inspect-gpu-images.py',
    'inspect-gpu-parity.py', 'inspect-gpu-presentation.py', 'inspect-gpu-headless.py',
    'inspect-gpu-output.py', 'inspect-gpu-performance.py')


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=True) + '\n', encoding='utf-8')
    os.replace(temporary, path)


def sha256(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def clean_environment(environ: dict[str, str], home: Path | None = None) -> dict[str, str]:
    env = dict(environ)
    for key in (*OVERRIDE_KEYS, *DISPLAY_KEYS):
        env.pop(key, None)
    # Ignore ambient validator switches. A CI lane cannot become a silent skip.
    for key in tuple(env):
        if key.startswith(('GPU_BENCH_', 'GPU_STRESS_', 'SKIA_EGL_')) or key in (
                'SKIP_C_ABI', 'SKIA_GPU_VALIDATION_RUN', 'SKIA_SOURCE_SUMS_MANIFEST_ONLY'):
            env.pop(key, None)
    env.update(PYTHONDONTWRITEBYTECODE='1', PYTHONUTF8='1',
               GPU_MODE='required', REQUIRE_HARDWARE='0', SKIA_SOURCE_SUMS_MODE='check')
    if home is not None:
        env['PLTUSERHOME'] = str(home)
        env['PLTADDONDIR'] = str(home / 'addon')
    return env


def validate_identity(data: dict, row: dict) -> None:
    require(data.get('os') == row['os'], 'selected Racket OS does not match the CI lane')
    require(data.get('architecture') == row['racket_arch'], 'selected Racket architecture does not match the CI lane')
    require(data.get('version') == row['racket'], 'selected Racket version does not match the pinned CI release')
    require(data.get('vm') == 'chez-scheme', 'the 0.46 matrix tests Racket CS only')
    require(type(data.get('pointer_bytes')) is int and data['pointer_bytes'] == 8, 'CI lane requires 64-bit Racket')


def make_source_archive(root: Path, destination: Path) -> dict:
    rows = manifest.read_manifest(root)
    require(not destination.exists(), 'source archive destination already exists')
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_STORED) as archive:
        for name in sorted([*rows, manifest.NAME]):
            parts = Path(name).parts
            require(not any(p in ('.git', 'compiled', '__pycache__', 'output', 'downloads') for p in parts),
                    'generated/developer files must not enter the source package')
            require(not name.endswith(('.nupkg', '.so', '.dylib', '.dll', '.exe', '.pyc')),
                    'native/compiled binary must not enter the clean source package')
            data = manifest.safe_path(root, name).read_bytes()
            if name in rows:
                require(hashlib.sha256(data).hexdigest() == rows[name], 'source changed while packaging: ' + name)
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    return {'files': len(rows) + 1, 'sha256': sha256(destination), 'contains_native_binaries': False}


def verify_install(root: Path, installed: Path, home: Path, archive: Path) -> None:
    installed = installed.resolve()
    require(installed.is_relative_to(home.resolve()), 'package did not resolve inside the isolated user home')
    require(not installed.is_relative_to(root.resolve()), 'package resolved into the checkout instead of an installed copy')
    require(installed != archive.parent.resolve(), 'package is linked to staging')
    require((installed / manifest.NAME).read_bytes() == (root / manifest.NAME).read_bytes(),
            'installed source manifest differs from the checkout')
    for name, digest in manifest.read_manifest(root).items():
        path = manifest.safe_path(installed, name)
        require(path.is_file() and sha256(path) == digest, 'installed source differs: ' + name)


def install_commands(installed: Path, racket: str, os_name: str) -> list[list[str]]:
    if os_name == 'windows':
        return [[sys.executable, str(installed / 'tools/install-native-windows.py'),
                 '--root', str(installed), '--racket', racket]]
    return [['bash', str(installed / ('tools/' + name))]
            for name in ('install-native.sh', 'install-harfbuzz.sh')]


def verify_native_smoke(smoke: dict, installed: Path) -> list[dict]:
    # Canonicalize once. macOS may spell the same temporary directory through
    # /var in one path and /private/var after Path.resolve(). relative_to()
    # requires both operands to use the same spelling.
    installed = installed.resolve()
    require(smoke.get('status') == 'passed', 'installed collection smoke did not pass')
    require(smoke.get('native_package_versions') == {'skia': default_version(), 'harfbuzz': '8.3.1.2'},
            'installed native package declarations changed')
    require(smoke.get('native_versions') == {'skia': native_abi_catalog()['profiles'][0]['expected_default_native_version'],
                                             'harfbuzz': '8.3.1'}, 'wrong native ABI versions')
    require(Path(smoke['collection']).resolve() == installed.resolve(), 'smoke used a different collection')
    result = []
    for name in ('skia', 'harfbuzz'):
        path = Path(smoke['libraries'][name]).resolve()
        require(path.is_relative_to((installed / 'native').resolve()) and path.is_file(),
                f'{name} was loaded from outside the installed package')
        result.append({'library': name, 'file': str(path.relative_to(installed)),
                       'bytes': path.stat().st_size, 'sha256': sha256(path)})
    require(smoke.get('pixels_verified') is True and smoke.get('encoded_roundtrip_verified') is True,
            'CPU pixel/codec smoke evidence is incomplete')
    return result


def validate_headless(directory: Path, surface: str) -> dict:
    """Check the current run, including renderer identity; never treat absence as success."""
    result = json.loads((directory / 'validation.json').read_text(encoding='utf-8'))
    require(result.get('status') == 'passed-selected-checks' and result.get('stage') == '0.46', 'headless run did not pass')
    require(result.get('validation_run') == directory.name and result.get('gpu_mode') == 'required', 'mixed/optional headless run')
    require(result.get('skips') == [], 'a required headless lane skipped checks')
    require(result.get('egl_platform') == 'surfaceless' and result.get('egl_surface') == surface,
            'wrong EGL platform or binding surface')
    for field in ('headless_rendering_verified', 'gl_interop_verified', 'gpu_document_output_verified',
                  'performance_measurements_verified'):
        require(result.get(field) is True, f'missing headless gate: {field}')
    require(result.get('window_created') is False and result.get('presentation_verified') is False,
            'headless lane must not create/claim a window')
    require(set(result.get('display_variables_removed', [])) == set(DISPLAY_KEYS), 'display environment was not removed')
    lifecycle = json.loads((directory / 'egl-lifecycle.diagnostic.json').read_text(encoding='utf-8'))
    require(lifecycle.get('status') == 'passed' and lifecycle.get('validation_run') == directory.name, 'wrong lifecycle run')
    require(lifecycle.get('required') is True and lifecycle.get('display_environment_unset') is True,
            'lifecycle is not required/headless')
    cycles = lifecycle.get('cycles')
    require(isinstance(cycles, list) and len(cycles) == 3, 'EGL lifecycle is incomplete')
    renderers = []
    for cycle in cycles:
        context = cycle['initial_context']
        require(context.get('renderer_class') == 'software' and
                'llvmpipe' in context.get('renderer', '').lower(), 'CI renderer must be explicitly Mesa llvmpipe')
        require(context.get('interface_factory') == 'assembled-desktop-gl' and
                context.get('display_server_free') is True and context.get('requires_glx') is False,
                'not a genuine window-system-free EGL/Ganesh context')
        renderers.append(context['renderer'])
    for prefix in ('headless', 'output-egl', 'performance-opengl'):
        inspection = json.loads((directory / (prefix + '.inspection.json')).read_text(encoding='utf-8'))
        require(inspection.get('status') == 'passed' and inspection.get('validation_run') == directory.name,
                f'{prefix} inspection is missing/foreign/failed')
    return {'status': 'passed', 'renderer_class': 'software', 'renderers': sorted(set(renderers)),
            'binding_surface': surface, 'window_system': 'none', 'hardware_acceleration_claimed': False,
            'hardware_performance_claimed': False, 'presentation_tested': False,
            'gate': 'EGL + surfaces + images + interop + documents + cache/release stress'}


def validate_canvas(directory: Path) -> dict:
    """A headless canvas pass cannot satisfy the separately required GUI lane."""
    result = json.loads((directory / 'validation.json').read_text(encoding='utf-8'))
    require(result.get('status') == 'passed' and result.get('stage') == '0.58',
            'raster canvas stage validation did not pass')
    checks = result.get('checks', {})
    for name in ('pure_lifecycle', 'native_pixels_and_bitmap_bridge', 'required_gui', 'text_load_orders'):
        require(checks.get(name) is True, 'missing required raster canvas check: ' + name)
    gui = result.get('gui', {})
    require(gui.get('required') is True and gui.get('executed') is True and
            gui.get('status') == 'passed', 'raster canvas GUI checks were absent, skipped or failed')
    require(type(gui.get('cases')) is int and gui['cases'] > 0,
            'raster canvas GUI report has no executed cases')
    orders = gui.get('text_load_orders')
    require(isinstance(orders, list) and len(orders) == 2 and
            all(isinstance(order, dict) for order in orders),
            'raster canvas GUI report is missing fresh-process text load orders')
    require({r.get('load_order') for r in orders} == {'gtk-first', 'skia-first'},
            'raster canvas GUI text load orders are missing or duplicated')
    for outcome in orders:
        require(outcome.get('status') == 'passed' and outcome.get('gui_initialized') is True and
                type(outcome.get('skia_text_checks')) is int and outcome['skia_text_checks'] == 2 and
                type(outcome.get('racket_text_checks')) is int and outcome['racket_text_checks'] == 2,
                'raster canvas GUI text coexistence checks did not pass')
    return {'status': 'passed', 'stage': '0.58', 'gui': gui,
            'renderer': 'cpu-skia-raster', 'display_server': 'Xvfb',
            'physical_display_pixels_verified': False,
            'hardware_backing_scale_verified': False}


class Runner:
    """Persist each subprocess log, including on timeout, and retain the actual exit status."""
    def __init__(self, output: Path, env: dict[str, str], timeout: int = 1200):
        self.output, self.env, self.timeout = output, env, timeout
        self.commands: list[dict] = []
        (output / 'logs').mkdir()
        write_json(output / 'commands.json', {'commands': []})

    def run(self, argv, *, cwd: Path, env: dict | None = None) -> str:
        argv = [str(a) for a in argv]
        label = f'{len(self.commands) + 1:03d}.log'
        path = self.output / 'logs' / label
        entry = {'argv': argv, 'cwd': str(cwd), 'log': 'logs/' + label, 'returncode': None}
        self.commands.append(entry)
        print('+', subprocess.list2cmdline(argv), flush=True)
        started = time.monotonic()
        process = None
        try:
            with path.open('wb') as out:
                process = subprocess.Popen(argv, cwd=cwd, env=self.env if env is None else env,
                                           stdout=out, stderr=subprocess.STDOUT,
                                           start_new_session=os.name != 'nt')
                try:
                    entry['returncode'] = process.wait(timeout=self.timeout)
                except subprocess.TimeoutExpired:
                    entry['timed_out'] = True
                    if os.name == 'nt':
                        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                                       stdout=out, stderr=subprocess.STDOUT, timeout=30, check=False)
                    else:
                        os.killpg(process.pid, signal.SIGKILL)
                    process.kill()
                    entry['returncode'] = process.wait()
                    raise RuntimeError(f'command timed out after {self.timeout}s; see {path}')
        except OSError as exc:
            entry['launch_error'] = str(exc)
            raise
        finally:
            entry['elapsed_seconds'] = round(time.monotonic() - started, 3)
            write_json(self.output / 'commands.json', {'commands': self.commands})
        text = path.read_bytes().decode('utf-8', errors='replace')
        print(text[-16000:], end='' if text.endswith('\n') else '\n', flush=True)
        if entry['returncode'] != 0:
            raise RuntimeError(f'command exited {entry["returncode"]}; see {path}')
        return text


def copy_artifacts(installed: Path, output: Path) -> None:
    # Include reports and actual visual outputs on failure as well as success.
    # Do not upload DLLs, NuGet archives, the user home, or compiled Racket code.
    generated = installed / 'output'
    if generated.is_dir():
        for directory in sorted(generated.glob('gpu-*')):
            if directory.is_dir() and not directory.is_symlink():
                dest = output / 'gpu-artifacts' / directory.name
                dest.mkdir(parents=True, exist_ok=True)
                for source in sorted(directory.iterdir()):
                    if source.is_file() and not source.is_symlink() and source.suffix in (
                            '.json', '.html', '.csv', '.png', '.svg', '.pdf', '.txt'):
                        shutil.copy2(source, dest / source.name)
    native = installed / 'native'
    if native.is_dir():
        for source in sorted(native.rglob('*')):
            if source.is_file() and not source.is_symlink() and source.suffix in ('.json', '.txt', '.nuspec'):
                dest = output / 'native-provenance' / source.relative_to(native)
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, dest)


def package_checks(runner: Runner, root: Path, row: dict, profile: str, report: dict, *, extra_checks=None) -> None:
    selected = os.environ.get('RACKET', 'racket')
    executable = shutil.which(selected)
    if not executable and Path(selected).is_file():
        executable = str(Path(selected).resolve())
    require(bool(executable), 'selected RACKET is not executable/found')
    racket = str(Path(executable).resolve())
    report['racket_executable'] = racket
    with tempfile.TemporaryDirectory(prefix='skia CI isolated ') as temporary:
        temporary = Path(temporary)
        home = temporary / 'user home'
        away = temporary / 'outside checkout'
        home.mkdir(); away.mkdir()
        env = clean_environment(runner.env, home)
        runner.env = env
        env['RACKET'] = racket
        identity = json.loads(runner.run([racket, root / 'tools/ci-identity.rkt'], cwd=away))
        validate_identity(identity, row)
        report['identity'] = identity
        archive = temporary / 'skia source.zip'
        report['source_archive'] = make_source_archive(root, archive)
        raco = [racket, '-l', 'raco', '--']
        runner.run([*raco, 'pkg', 'install', '--scope', 'user', '--auto', '--batch', '--no-cache', '--no-setup',
                    '--name', 'skia-for-racket', archive], cwd=away)
        found = runner.run([racket, '-e', '(require json) (write-json (path->string (collection-path "skia")))'], cwd=away)
        installed = Path(json.loads(found)).resolve()
        report['installed_collection'] = str(installed)
        try:
            verify_install(root, installed, home, archive)
            report['checks']['isolated_source_package'] = True
            # Remove the source ZIP to catch accidental dependencies on staging.
            archive.unlink()
            import_env = dict(env, RACKET_SKIA_LIBRARY=str(temporary / 'absent-skia'),
                              RACKET_HARFBUZZ_LIBRARY=str(temporary / 'absent-harfbuzz'))
            imports = json.loads(runner.run([racket, '-l', 'skia/tools/ci-import-smoke'], cwd=away, env=import_env))
            require(imports.get('status') == 'passed' and imports.get('gui_instantiated') is False,
                    'import-only smoke did not establish GUI-free imports')
            runner.run([racket, installed / 'run-tests.rkt', '--pure'], cwd=away, env=import_env)
            report['checks']['imports_and_pure_without_natives'] = True
            for command in install_commands(installed, racket, identity['os']):
                runner.run(command, cwd=away)
            report['checks']['fresh_native_install'] = True
            runner.run([*raco, 'setup', '--jobs', '2', '--no-docs', '--check-pkg-deps',
                        '--pkgs', 'skia-for-racket'], cwd=away)
            report['checks']['package_setup_and_dependencies'] = True
            abi = temporary / 'C ABI build'
            runner.run(['cmake', '-S', installed / 'tools/ci-abi', '-B', abi,
                        *(['-G', 'Visual Studio 17 2022', '-A', 'x64'] if identity['os'] == 'windows' else [])], cwd=away)
            runner.run(['cmake', '--build', abi, '--config', 'Release', '--parallel', '2'], cwd=away)
            runner.run(['ctest', '--test-dir', abi, '-C', 'Release', '--output-on-failure'], cwd=away)
            report['checks']['c_abi_mirrors'] = list(ABI_NAMES)
            smoke = json.loads(runner.run([racket, '-l', 'skia/tools/ci-package-smoke'], cwd=away))
            report['native_libraries'] = verify_native_smoke(smoke, installed)
            report['checks']['installed_native_pixels_and_symbols'] = True
            native_abi = json.loads(runner.run([racket, installed / 'tools/native-abi-doctor.rkt'], cwd=away))
            require(native_abi.get('required_cpu_symbols_resolved') is True and
                    native_abi.get('racket_layouts_checked') is True,
                    'native ABI preflight evidence is incomplete')
            report['native_abi'] = native_abi
            report['checks']['native_abi_preflight'] = True
            if profile == 'cpu':
                if identity['os'] != 'windows':
                    for name in ('audit-symbols.sh', 'audit-harfbuzz-symbols.sh'):
                        runner.run(['bash', installed / 'tools' / name], cwd=away)
                for name in ('doctor', 'portable-drawing-doctor', 'color-filter-doctor', 'raster-buffer-doctor'):
                    runner.run([racket, installed / 'tools' / (name + '.rkt')], cwd=away)
                runner.run([racket, installed / 'run-tests.rkt'], cwd=away)
                report['checks']['cpu_regressions'] = True
                # Raster DC evidence is produced by the INSTALLED package and
                # retained directly inside this job's artifact, even on failure.
                runner.run([sys.executable, installed / 'tools/validate-dc.py',
                            '--racket', racket, '--manifest-only',
                            '--output', runner.output / 'dc-foundation'], cwd=away)
                report['checks']['dc_foundation'] = True
                # Required negative compatibility gate, on one clean Linux lane.
                # A rejected m153 candidate is NOT a rendering/compatibility pass.
                if row['id'] == 'linux-x64':
                    candidate_output = runner.output / 'native-abi-candidate'
                    runner.run([sys.executable, installed / 'tools/native-abi-lab.py',
                                '--candidate', '--racket', racket,
                                '--output', candidate_output], cwd=away)
                    candidate = json.loads((candidate_output / 'report.json').read_text(encoding='utf-8'))
                    require(candidate.get('status') == 'passed-investigation-candidate-rejected',
                            'candidate investigation did not establish the required safe rejection')
                    report['native_abi_candidate'] = candidate
                    report['checks']['candidate_abi_rejection'] = True
                report['gpu'] = {'status': 'not-run', 'reason': 'CPU/native/package lane; no hosted GPU availability assumed'}
            elif profile == 'canvas':
                require(sys.platform.startswith('linux'), 'the raster GUI CI lane requires Linux')
                # Start Xvfb only around the actual GUI gate. Earlier import,
                # pure and native-package setup remain display-server-free;
                # existing CPU and EGL profiles never run this command.
                canvas_output = runner.output / 'skia-canvas'
                runner.run(['xvfb-run', '--auto-servernum',
                            '--server-args=-screen 0 1280x960x24',
                            sys.executable, installed / 'tools/validate-skia-canvas.py',
                            '--racket', racket, '--manifest-only', '--require-gui',
                            '--output', canvas_output], cwd=away)
                report['canvas'] = validate_canvas(canvas_output)
                report['checks']['raster_canvas_required_gui'] = True
                report['gpu'] = {'status': 'not-run', 'reason': 'CPU raster GUI canvas; no GPU execution'}
            else:
                require(profile == 'egl', 'unknown installed-package CI profile')
                require(sys.platform.startswith('linux'), 'EGL CI lane requires Linux')
                env.update(LIBGL_ALWAYS_SOFTWARE='1', GALLIUM_DRIVER='llvmpipe',
                           SKIA_EGL_PLATFORM='surfaceless', SKIA_EGL_DEVICE_INDEX='0',
                           SKIA_EGL_SURFACE=row['surface'],
                           SKIA_SOURCE_SUMS_MANIFEST_ONLY='1')
                # Leave the full 0.45 default stress size intact (3 x 180).
                runner.run([sys.executable, installed / 'tools/validate-gpu-headless.py'], cwd=away)
                runs = list((installed / 'output').glob('gpu-0.46-headless-*'))
                require(len(runs) == 1, 'expected exactly one fresh headless run')
                report['gpu'] = validate_headless(runs[0], row['surface'])
                report['checks']['cpu_regressions'] = True  # included in that required runner
            # Additional required backends use the same isolated installation.
            # Exceptions propagate; finally still retains partial evidence.
            if extra_checks is not None:
                extra_checks(runner, installed, away, env, report)
            # Check against the checkout's manifest again, not just a possibly
            # changed manifest in the installed copy.
            verify_install(root, installed, home, archive)
            runner.run([sys.executable, installed / 'tools/update-source-sums.py', '--check', '--manifest-only'], cwd=away)
            report['checks']['installed_source_unchanged'] = True
        finally:
            copy_artifacts(installed, runner.output)


def source_checks(runner: Runner, root: Path, report: dict) -> None:
    require(sys.platform.startswith('linux'), 'the shared Unix source checks run in the Linux source lane')
    runner.run([sys.executable, root / 'tools/static-check.py'], cwd=root)
    runner.run([sys.executable, root / 'tools/check-gpu-source.py', '--require-integration'], cwd=root)
    for name in PYTHON_CHECKS:
        runner.run([sys.executable, root / 'tools' / name,
                    *(['--self-test'] if name.startswith('inspect-') else [])], cwd=root)
    report['checks']['source_and_synthetic_suites'] = True
    report['gpu'] = {'status': 'not-run', 'reason': 'source/synthetic checks do not execute a GPU'}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=('source', 'cpu', 'egl', 'canvas'), required=True)
    parser.add_argument('--id', required=True,
                        help='exact matrix id, source, or canvas-linux-x64 for the raster GUI lane')
    parser.add_argument('--timeout', type=int, default=1200, help='per-command seconds; failure is never skipped')
    args = parser.parse_args(argv)
    require(re.fullmatch(r'[a-z][a-z0-9-]{0,47}', args.id) is not None, 'unsafe CI lane id')
    require(1 <= args.timeout <= 3600, 'timeout must be between 1 and 3600 seconds')
    output = ROOT / 'output' / ('ci-' + args.id)
    output.mkdir(parents=True, exist_ok=False)  # reruns must not reuse stale success
    runner = Runner(output, clean_environment(os.environ), args.timeout)
    report = {'schema_version': 1, 'stage': '0.58' if args.profile == 'canvas' else '0.46',
              'profile': args.profile, 'id': args.id,
              'status': 'running', 'checks': {}, 'commands': runner.commands,
              'host': {'system': platform.system(), 'machine': platform.machine(), 'python': sys.version,
                       'platform': platform.platform(), 'libc': platform.libc_ver(),
                       'runner_image': {k: os.environ.get(k) for k in
                                        ('ImageOS', 'ImageVersion', 'RUNNER_OS', 'RUNNER_ARCH')}},
              'github': {k: os.environ.get(k) for k in ('GITHUB_SHA', 'GITHUB_EVENT_NAME', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT')},
              'hardware_performance_claimed': False, 'visible_pixels_verified': False}
    code = 1
    try:
        data = load_matrix()
        if args.profile == 'source':
            require(args.id == 'source', 'source lane id must be source')
            row = None
        elif args.profile == 'canvas':
            require(args.id == 'canvas-linux-x64', 'raster canvas lane id must be canvas-linux-x64')
            rows = [r for r in data['cpu'] if r['id'] == 'linux-x64']
            require(len(rows) == 1, 'raster canvas lane requires the pinned linux-x64 matrix identity')
            row = rows[0]
            report['matrix'] = row
        else:
            rows = [r for r in data[args.profile] if r['id'] == args.id]
            require(len(rows) == 1, 'unknown id for this CI profile')
            row = rows[0]
            report['matrix'] = row
        report['source_commit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        report['source_manifest_sha256'] = sha256(ROOT / manifest.NAME)
        report['source_files_verified'] = manifest.check(ROOT)
        if args.profile == 'source':
            source_checks(runner, ROOT, report)
        else:
            package_checks(runner, ROOT, row, args.profile, report)
        manifest.check(ROOT)  # never rewrite the checkout to manufacture success
        report['checks']['checkout_source_unchanged'] = True
        report['status'] = 'passed'
        code = 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as exc:
        report['status'] = 'failed'
        report['error'] = str(exc)
        print(f'CI FAILED: {exc}', file=sys.stderr)
    finally:
        write_json(output / 'ci-report.json', report)
        gpu = report.get('gpu', {'status': 'not-established'})
        summary = (f'## skia-for-racket / {args.id}\n\n'
                   f'Status: **{report["status"]}**. Profile: `{args.profile}`.\n\n'
                   f'GPU evidence: `{gpu["status"]}`. Hardware performance and display pixels are not certified.\n\n'
                   'See `ci-report.json`, `commands.json`, native provenance, and complete command logs in the job artifact.\n')
        (output / 'ci-summary.md').write_text(summary, encoding='utf-8')
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as out:
                out.write(summary)
    print(f'CI evidence: {output}')
    return code


if __name__ == '__main__':
    raise SystemExit(main())
