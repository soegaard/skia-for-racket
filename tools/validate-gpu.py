#!/usr/bin/env python3
"""One selected Racket for CPU regression tests and explicit GPU validation.

GPU_MODE=required (default), optional, or off. REQUIRE_HARDWARE=1 rejects
software/unclassified GL driver strings. An explicit render/cleanup failure
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
    directory = Path(tempfile.mkdtemp(prefix='gpu-0.40-', dir=ROOT/'output'))
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
        if os.environ.get('SKIP_C_ABI') == '1':
            skips.append('C ABI mirrors explicitly skipped (SKIP_C_ABI=1)')
            print(skips[-1])
        else:
            compiler = os.environ.get('CC') or shutil.which('cc') or shutil.which('clang') or shutil.which('gcc')
            if not compiler:
                raise RuntimeError('C11 compiler missing; set CC, or explicitly SKIP_C_ABI=1 for an incomplete ABI check')
            for name in ('codec','pdf','path-matrix','filter','color-output','runtime','geometry','projective','color-filter','gpu'):
                target = directory / (name + ('.exe' if os.name == 'nt' else ''))
                run([compiler,'-std=c11','-Wall','-Wextra','-pedantic',f'tools/check-{name}-abi.c','-o',target])
                run([target])
                target.unlink()
        # Explicitly compile every dynamically loaded suite and GPU module.
        modules = ['main.rkt','bitmap.rkt','gpu.rkt','gpu-racket-gl.rkt','run-tests.rkt',
                   'tools/doctor.rkt','tools/gpu-doctor.rkt','tools/gpu-gui-host.rkt',
                   'tools/gpu-offscreen-doctor.rkt','tools/gpu-window-doctor.rkt',
                   'tools/gpu-report.rkt','examples/gpu-scenes.rkt',
                   'tools/gpu-image-doctor.rkt','examples/gpu-images.rkt',
                   'tools/portable-drawing-doctor.rkt','tools/color-filter-doctor.rkt','tools/raster-buffer-doctor.rkt']
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
            for kind in ('offscreen','window','image'):
                prefix = directory / ('images' if kind == 'image' else kind)
                arguments = [racket,f'tools/gpu-{kind}-doctor.rkt','--prefix',prefix]
                if mode == 'optional': arguments.append('--optional')
                if hardware: arguments.append('--require-hardware')
                run(arguments)
                diagnostic = json.loads(Path(str(prefix)+'.diagnostic.json').read_text())
                if diagnostic['status'] == 'unavailable' and mode == 'optional':
                    skips.append(f'{kind} unavailable: {diagnostic.get("message")}')
                    print(skips[-1])
                else:
                    inspector = 'tools/inspect-gpu-images.py' if kind == 'image' else 'tools/inspect-gpu-offscreen.py'
                    run([sys.executable,inspector,'--probe-prefix',prefix])
        # Repository manifest regeneration is deliberately LAST, after every
        # selected check succeeds. Optional/off runs retain explicit skips.
        run([sys.executable,'tools/update-source-sums.py'])
        report = {'status':'passed-selected-checks','stage':'0.40','gpu_mode':mode,'identity':identity.strip(),
                  'commands':commands,'skips':skips,'hardware_string_requirement':hardware,
                  'performance_measured':False, 'visible_window_pixels_verified':False,
                  'window_manual_review_required':mode != 'off'}
        destination = directory/'validation.json'
        destination.write_text(json.dumps(report,indent=2)+'\n')
        print(f'Validation report: {destination}')
        print(f'Review files: {directory} (passed checks only)')
        if mode != 'off':
            print('Window API checks are not visible-pixel certification. Review images.review.html and offscreen.review.html; run gpu-window-doctor.rkt --interactive.')
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
