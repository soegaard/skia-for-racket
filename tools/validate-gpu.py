#!/usr/bin/env python3
"""One selected Racket for CPU regression tests and explicit GPU validation.

GPU_MODE=required (default), optional, or off. REQUIRE_HARDWARE=1 rejects
software/unclassified backend names. An explicit render/cleanup failure
always fails, even in optional mode. SKIP_C_ABI=1 explicitly omits C mirrors.
"""
from __future__ import annotations
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

def main() -> int:
    os.chdir(ROOT)
    os.environ['PYTHONDONTWRITEBYTECODE'] = '1'
    racket = os.environ.get('RACKET', 'racket')
    mode = os.environ.get('GPU_MODE', 'required')
    if mode not in ('required', 'optional', 'off'):
        raise ValueError('GPU_MODE must be required, optional, or off')
    hardware = os.environ.get('REQUIRE_HARDWARE', '0') == '1'
    (ROOT/'output').mkdir(exist_ok=True)
    # Fresh directories prevent a failure or optional skip from leaving an old
    # successful image/inspection report looking like the current result.
    directory = Path(tempfile.mkdtemp(prefix='gpu-0.45-', dir=ROOT/'output'))
    os.environ['SKIA_GPU_VALIDATION_RUN'] = directory.name
    metal_rendering = False
    backend_parity = False
    presentation_passed = {}
    presentation_summary = False
    gl_interop = False
    gpu_output_passed = {}
    performance_passed = {}
    redraw_passed = {}
    commands = []
    skips = []
    def run(arguments, *, capture=False):
        print('+', subprocess.list2cmdline([str(x) for x in arguments]), flush=True)
        started = time.monotonic()
        result = subprocess.run([str(x) for x in arguments], text=True,
                                stdout=subprocess.PIPE if capture else None)
        commands.append({'argv':[str(x) for x in arguments], 'returncode':result.returncode,
                         'elapsed_seconds':round(time.monotonic()-started,3)})
        if result.returncode:
            raise subprocess.CalledProcessError(result.returncode, arguments)
        return result.stdout
    try:
        identity = run([racket, '-e', '(printf "~a/~a; Racket ~a; VM ~a\\n" (system-type (quote os)) (system-type (quote arch)) (version) (system-type (quote vm)))'], capture=True)
        print(identity, end='')
        # Check the complete repository as well as this milestone's new source.
        if identity.startswith('windows/'):
            skips.append('Legacy Unix-only static/installer smoke script not run on Windows; Windows installer self-tests and Racket compilation run instead')
            print(skips[-1])
        else:
            run([sys.executable, 'tools/static-check.py'])
        run([sys.executable, 'tools/check-gpu-source.py','--require-integration'])
        run([sys.executable, 'tools/test-install-native-windows.py'])
        run([sys.executable, 'tools/test-validate-gpu-images.py'])
        run([sys.executable, 'tools/inspect-gpu-probe.py', '--self-test'])
        run([sys.executable, 'tools/inspect-gpu-offscreen.py', '--self-test'])
        run([sys.executable, 'tools/inspect-gpu-images.py', '--self-test'])
        run([sys.executable, 'tools/inspect-gpu-parity.py', '--self-test'])
        run([sys.executable, 'tools/inspect-gpu-presentation.py', '--self-test'])
        run([sys.executable, 'tools/test-patch-delivery.py'])
        run([sys.executable, 'tools/inspect-gpu-headless.py','--self-test'])
        run([sys.executable, 'tools/test-validate-gpu-headless.py'])
        run([sys.executable, 'tools/test-validate-gpu-output.py'])
        run([sys.executable, 'tools/inspect-gpu-output.py', '--self-test'])
        run([sys.executable, 'tools/inspect-gpu-performance.py', '--self-test'])
        run([sys.executable, 'tools/test-validate-gpu-performance.py'])
        if os.environ.get('SKIP_C_ABI') == '1':
            skips.append('C ABI mirrors explicitly skipped (SKIP_C_ABI=1)')
            print(skips[-1])
        else:
            compiler = os.environ.get('CC') or shutil.which('cc') or shutil.which('clang') or shutil.which('gcc')
            if not compiler:
                raise RuntimeError('C11 compiler missing; set CC, or explicitly SKIP_C_ABI=1 for an incomplete ABI check')
            for name in ('codec','pdf','path-matrix','filter','color-output','runtime','geometry','projective','color-filter','gpu','presentation','cache'):
                target = directory / (name + ('.exe' if os.name == 'nt' else ''))
                run([compiler,'-std=c11','-Wall','-Wextra','-pedantic',f'tools/check-{name}-abi.c','-o',target])
                run([target])
                target.unlink()
        # Explicitly compile every dynamically loaded suite and GPU module.
        modules = ['main.rkt','bitmap.rkt','gpu.rkt','gpu-racket-gl.rkt','gpu-gui.rkt','run-tests.rkt',
                   'tools/doctor.rkt','tools/gpu-doctor.rkt','tools/gpu-gui-host.rkt',
                   'tools/gpu-offscreen-doctor.rkt','tools/gpu-window-doctor.rkt',
                   'tools/gpu-report.rkt','examples/gpu-scenes.rkt',
                   'tools/gpu-image-doctor.rkt','examples/gpu-images.rkt',
                   'tools/gpu-test-host.rkt','tools/gpu-metal-doctor.rkt','tools/gpu-cross-backend-doctor.rkt','examples/gpu-metal.rkt',
                   'tools/portable-drawing-doctor.rkt','tools/color-filter-doctor.rkt','tools/raster-buffer-doctor.rkt',
                   'tools/gpu-presenter-doctor.rkt','tools/gpu-presentation-host.rkt',
                   'examples/gpu-presenters.rkt','examples/gpu-presentation-scene.rkt',
                   'gpu-egl.rkt','gpu-gl-interop.rkt','tools/gpu-egl-doctor.rkt',
                   'tools/gpu-interop-doctor.rkt','examples/gpu-headless.rkt',
                   'gpu-output.rkt','private/output-executor.rkt','tools/gpu-output-doctor.rkt',
                   'examples/gpu-output.rkt','tests/gpu-output-fixtures.rkt',
                   'tools/gpu-performance-doctor.rkt','tools/gpu-performance-work.rkt',
                   'tools/gpu-performance-options.rkt','tools/gpu-redraw-doctor.rkt']
        modules += [str(p.relative_to(ROOT)) for p in sorted((ROOT/'tests').glob('*.rkt'))]
        modules += [str(p.relative_to(ROOT)) for p in sorted((ROOT/'private').glob('gpu*.rkt'))]
        run([racket,'-l','raco','--','make',*modules])
        # Portable native checks; CPU symbol requirements are unchanged.
        run([racket,'-e','(require "main.rkt") (skia-check!) (harfbuzz-check!) (displayln "CPU Skia and HarfBuzz symbol resolution passed; GPU symbols are separate.")'])
        if os.name != 'nt':
            run(['bash','tools/audit-symbols.sh'])
            run(['bash','tools/audit-harfbuzz-symbols.sh'])
        for doctor in ('doctor','portable-drawing-doctor','color-filter-doctor','raster-buffer-doctor'):
            run([racket,f'tools/{doctor}.rkt'])
        run([racket,'run-tests.rkt'])
        if mode == 'off':
            skips.append('Live GPU checks explicitly not run (GPU_MODE=off)')
            print(skips[-1])
        else:
            backends = ['opengl'] + (['metal'] if identity.startswith('macosx/') else [])
            if 'metal' not in backends:
                skips.append('Metal construction probe is macOS-only; not run on this host')
            for backend in backends:
                prefix = directory / backend
                arguments = [racket,'tools/gpu-doctor.rkt','--backend',backend,'--prefix',prefix]
                if mode == 'optional': arguments.append('--optional')
                if hardware and backend == 'opengl': arguments.append('--require-hardware')
                run(arguments)
                diagnostic = json.loads(Path(str(prefix)+'.diagnostic.json').read_text())
                if diagnostic['status'] == 'unavailable' and mode == 'optional':
                    skips.append(f'{backend} unavailable: {diagnostic.get("message")}')
                else:
                    # Inspection JSON and HTML are published only after all
                    # actual samples, PNG pixels, ownership and cleanup pass.
                    run([sys.executable,'tools/inspect-gpu-probe.py','--probe-prefix',prefix])
            passed = {}
            def probe(kind, prefix_name, *, backend=None, inspector=None):
                prefix = directory / prefix_name
                arguments = [racket, f'tools/gpu-{kind}-doctor.rkt', '--prefix', prefix]
                if backend: arguments += ['--backend', backend]
                if mode == 'optional': arguments.append('--optional')
                if hardware: arguments.append('--require-hardware')
                run(arguments)
                diagnostic = json.loads(Path(str(prefix)+'.diagnostic.json').read_text())
                if diagnostic['status'] == 'unavailable' and mode == 'optional':
                    skips.append(f'{prefix_name} unavailable: {diagnostic.get("message")}')
                    print(skips[-1])
                    return False
                if diagnostic['status'] != 'passed':
                    raise RuntimeError(f'{prefix_name}: backend diagnostic did not pass: {diagnostic.get("status")}')
                run([sys.executable, inspector or 'tools/inspect-gpu-offscreen.py', '--probe-prefix', prefix])
                return True
            for kind in ('offscreen', 'window', 'image'):
                prefix_name = 'window' if kind == 'window' else ('images' if kind == 'image' else kind)+'-opengl'
                passed[('opengl', kind)] = probe(kind, prefix_name,
                    backend=None if kind == 'window' else 'opengl',
                    inspector='tools/inspect-gpu-images.py' if kind == 'image' else None)
            if identity.startswith('macosx/'):
                for kind in ('offscreen', 'image'):
                    passed[('metal', kind)] = probe(kind, ('images' if kind == 'image' else kind)+'-metal',
                        backend='metal', inspector='tools/inspect-gpu-images.py' if kind == 'image' else None)
                lifecycle = probe('metal', 'metal-lifecycle', inspector='tools/inspect-gpu-parity.py')
                crossing = probe('cross-backend', 'cross-backend', inspector='tools/inspect-gpu-parity.py')
                metal_rendering = lifecycle and passed[('metal', 'offscreen')] and passed[('metal', 'image')]
                if metal_rendering and crossing and passed[('opengl', 'offscreen')] and passed[('opengl', 'image')]:
                    run([sys.executable, 'tools/inspect-gpu-parity.py', '--directory', directory])
                    backend_parity = True
                else:
                    skips.append('OpenGL/Metal parity not established: an explicitly optional backend probe was unavailable')
            else:
                skips.append('Metal rendering/lifecycle and OpenGL/Metal parity are macOS-only; not run on this host')
            # Presentation is a separate acceptance layer above offscreen parity.
            # Do not infer successful on-screen pixels from a swap/present call.
            for backend in backends:
                presentation_passed[backend] = probe('presenter', 'presentation-'+backend,
                    backend=backend, inspector='tools/inspect-gpu-presentation.py')
            if all(presentation_passed.values()):
                run([sys.executable, 'tools/inspect-gpu-presentation.py', '--directory', directory])
                presentation_summary = True
            else:
                skips.append('Combined presentation submission check not established: an optional presenter was unavailable')
            gl_interop = probe('interop', 'interop-opengl', inspector='tools/inspect-gpu-headless.py')
            for backend in backends:
                gpu_output_passed[backend] = probe('output', 'output-'+backend, backend=backend,
                                                  inspector='tools/inspect-gpu-output.py')
            for backend in backends:
                performance_passed[backend] = probe('performance', 'performance-'+backend, backend=backend,
                                                     inspector='tools/inspect-gpu-performance.py')
                redraw_passed[backend] = probe('redraw', 'redraw-'+backend, backend=backend,
                                                inspector='tools/inspect-gpu-performance.py')
        # Repository manifest regeneration is deliberately LAST, after every
        # selected check succeeds. Optional/off runs retain explicit skips.
        run([sys.executable,'tools/update-source-sums.py'])
        report = {'status':'passed-selected-checks','stage':'0.45','gpu_mode':mode,'identity':identity.strip(),
                  'commands':commands,'skips':skips,'hardware_string_requirement':hardware,
                  'performance_measured':any(performance_passed.values()) or any(redraw_passed.values()),
                  'performance_measurements_verified':performance_passed, 'redraw_stress_verified':redraw_passed,
                  'visible_window_pixels_verified':False,
                  'validation_run':directory.name, 'metal_rendering_verified':metal_rendering,
                  'backend_parity_verified':backend_parity, 'metal_presentation_verified':False,
                  'presentation_submission_verified':presentation_passed,
                  'presentation_summary_verified':presentation_summary,
                  'window_manual_review_required':mode != 'off', 'gl_interop_verified':gl_interop,
                  'gpu_document_output_verified':gpu_output_passed,
                  'egl_headless_verified':False,
                  'egl_validation_note':'Linux EGL end-to-end acceptance deferred by maintainer to future GitHub Actions CI; not a desktop baseline blocker'}
        destination = directory/'validation.json'
        destination.write_text(json.dumps(report,indent=2)+'\n')
        print(f'Validation report: {destination}')
        print(f'Review files: {directory} (passed checks only)')
        if mode != 'off':
            print('Submission checks are not visible-pixel certification. Review performance-*.review.html / redraw-*.review.html and raw *.samples.csv, output-opengl.review.html / output-metal.review.html, presentation.review.html and parity.review.html; run examples/gpu-presenters.rkt --backend both on macOS (--backend opengl elsewhere).')
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        # A failure record is explicitly named; no successful inspection report
        # is synthesized, and the source manifest has not been updated early.
        (directory/'validation.failed.json').write_text(json.dumps(
            {'status':'failed','error':str(error),'commands':commands,'skips':skips},indent=2)+'\n')
        print(f'Validation FAILED: {error}\nDetails: {directory}',file=sys.stderr)
        return 1

if __name__ == '__main__':
    raise SystemExit(main())
