#!/usr/bin/env python3
"""Linux-only EGL validation without a display server or GUI host.

Uses the selected RACKET for compilation and every Racket subprocess. Explicit
EGL configuration is shared by all probes. Display variables are removed, not
replaced with a hidden window/Xvfb. GPU_MODE=optional permits only initial
unavailability; source sums are updated last after the selected gates succeed.
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
DISPLAY_VARIABLES = ('DISPLAY','WAYLAND_DISPLAY','MIR_SOCKET')
PYTHON_CHECKS = ('test-install-native-windows.py','test-validate-gpu-headless.py',
                 'inspect-gpu-probe.py','inspect-gpu-offscreen.py','inspect-gpu-images.py',
                 'inspect-gpu-parity.py','inspect-gpu-presentation.py','inspect-gpu-headless.py',
                 'test-patch-delivery.py','test-validate-gpu-output.py','inspect-gpu-output.py',
                 'inspect-gpu-performance.py','test-validate-gpu-performance.py')


def main() -> int:
    os.chdir(ROOT)
    racket = os.environ.get('RACKET','racket')
    mode = os.environ.get('GPU_MODE','required')
    platform = os.environ.get('SKIA_EGL_PLATFORM','surfaceless')
    index_text = os.environ.get('SKIA_EGL_DEVICE_INDEX','0')
    surface = os.environ.get('SKIA_EGL_SURFACE','surfaceless')
    hardware = os.environ.get('REQUIRE_HARDWARE','0') == '1'
    commands=[];skips=[];verified=False; output_verified=False; performance_verified=False; identity=''
    (ROOT/'output').mkdir(exist_ok=True)
    directory=Path(tempfile.mkdtemp(prefix='gpu-0.45-headless-',dir=ROOT/'output'))
    env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1',SKIA_GPU_VALIDATION_RUN=directory.name)
    for key in DISPLAY_VARIABLES: env.pop(key,None)
    def run(argv, *, capture=False):
        argv=[str(x) for x in argv]
        print('+',subprocess.list2cmdline(argv),flush=True)
        start=time.monotonic()
        result=subprocess.run(argv,text=True,env=env,stdout=subprocess.PIPE if capture else None)
        commands.append(dict(argv=argv,returncode=result.returncode,elapsed_seconds=round(time.monotonic()-start,3)))
        if result.returncode: raise subprocess.CalledProcessError(result.returncode,argv)
        return result.stdout
    try:
        if not sys.platform.startswith('linux'): raise RuntimeError('the EGL headless validator requires Linux; use validate-gpu.sh on macOS/Windows')
        if mode not in ('required','optional','off'): raise ValueError('GPU_MODE must be required, optional, or off')
        if platform not in ('surfaceless','device') or surface not in ('surfaceless','pbuffer'):
            raise ValueError('explicit EGL platform is surfaceless/device and surface is surfaceless/pbuffer')
        if not index_text.isascii() or not index_text.isdecimal(): raise ValueError('SKIA_EGL_DEVICE_INDEX must be a nonnegative integer')
        index=int(index_text)
        if platform=='surfaceless' and index: raise ValueError('device index applies only to SKIA_EGL_PLATFORM=device')
        identity=run([racket,'-e','(printf "~a/~a; Racket ~a; VM ~a\\n" (system-type (quote os)) (system-type (quote arch)) (version) (system-type (quote vm)))'],capture=True)
        print(identity,end='')
        if not identity.startswith('unix/'): raise RuntimeError('selected Racket does not report a Unix/Linux host')
        run([sys.executable,'tools/static-check.py'])
        run([sys.executable,'tools/check-gpu-source.py','--require-integration'])
        for name in PYTHON_CHECKS:
            run([sys.executable,'tools/'+name,*(['--self-test'] if name.startswith('inspect-') else [])])
        if os.environ.get('SKIP_C_ABI')=='1': skips.append('C mirrors explicitly skipped (SKIP_C_ABI=1)')
        else:
            compiler=os.environ.get('CC') or shutil.which('cc') or shutil.which('clang') or shutil.which('gcc')
            if not compiler: raise RuntimeError('C11 compiler missing; set CC or explicitly SKIP_C_ABI=1')
            for name in ('codec','pdf','path-matrix','filter','color-output','runtime','geometry','projective','color-filter','gpu','presentation','cache'):
                target=directory/name
                run([compiler,'-std=c11','-Wall','-Wextra','-pedantic',f'tools/check-{name}-abi.c','-o',target]);run([target]);target.unlink()
        modules=['main.rkt','bitmap.rkt','gpu.rkt','gpu-egl.rkt','gpu-gl-interop.rkt','run-tests.rkt',
                 'tools/doctor.rkt','tools/portable-drawing-doctor.rkt','tools/color-filter-doctor.rkt','tools/raster-buffer-doctor.rkt',
                 'tools/gpu-egl-doctor.rkt','tools/gpu-offscreen-doctor.rkt','tools/gpu-image-doctor.rkt','tools/gpu-interop-doctor.rkt',
                 'tools/gpu-test-host.rkt','examples/gpu-headless.rkt','examples/gpu-scenes.rkt','examples/gpu-images.rkt',
                 'gpu-output.rkt','private/output-executor.rkt','tools/gpu-output-doctor.rkt',
                 'examples/gpu-output.rkt','tests/gpu-output-fixtures.rkt',
                 'tools/gpu-performance-doctor.rkt','tools/gpu-performance-work.rkt',
                   'tools/gpu-performance-options.rkt']
        # The suites below load no GUI. GUI-native suites and their doctors are
        # intentionally absent, rather than relying on a DISPLAY being present.
        modules += [str(p.relative_to(ROOT)) for p in sorted((ROOT/'tests').glob('*.rkt'))
                    if p.name not in ('gpu-presenter-native-test.rkt','gpu-cross-backend-native-test.rkt')]
        modules += [str(p.relative_to(ROOT)) for p in sorted((ROOT/'private').glob('gpu-egl*.rkt'))]
        modules += [str(p.relative_to(ROOT)) for p in sorted((ROOT/'private').glob('gpu-gl*.rkt'))]
        modules += ['private/gpu-driver-egl.rkt','private/gpu-interop-guard.rkt']
        run([racket,'-l','raco','--','make',*dict.fromkeys(modules)])
        run([racket,'-e','(require "main.rkt") (skia-check!) (harfbuzz-check!)'])
        run(['bash','tools/audit-symbols.sh']);run(['bash','tools/audit-harfbuzz-symbols.sh'])
        for name in ('doctor','portable-drawing-doctor','color-filter-doctor','raster-buffer-doctor'):
            run([racket,f'tools/{name}.rkt'])
        run([racket,'run-tests.rkt'])
        if mode=='off': skips.append('Live EGL checks not run (GPU_MODE=off)')
        else:
            options=['--egl-platform',platform,'--egl-device-index',str(index),'--egl-surface',surface]
            extra=(['--require-hardware'] if hardware else [])
            prefix=directory/'egl-lifecycle'
            args=[racket,'tools/gpu-egl-doctor.rkt','--prefix',prefix,*options,*extra]
            if mode=='optional': args+=['--optional']
            run(args)
            data=json.loads(Path(str(prefix)+'.diagnostic.json').read_text())
            if mode=='optional' and data.get('status')=='unavailable':
                skips.append('EGL initialization unavailable: '+str(data.get('message')))
            else:
                if data.get('status')!='passed': raise RuntimeError('EGL lifecycle did not pass')
                run([sys.executable,'tools/inspect-gpu-headless.py','--probe-prefix',prefix])
                for kind,name,inspector in (('offscreen','offscreen-egl','inspect-gpu-offscreen.py'),
                                           ('image','images-egl','inspect-gpu-images.py'),
                                           ('interop','interop-egl','inspect-gpu-headless.py')):
                    prefix=directory/name
                    # Once EGL has initialized, optional mode cannot hide a
                    # later Ganesh, test, workflow, readback, or cleanup failure.
                    args=[racket,f'tools/gpu-{kind}-doctor.rkt','--prefix',prefix,'--host','egl',*options,*extra]
                    if kind!='interop': args+=['--backend','opengl']
                    run(args)
                    data=json.loads(Path(str(prefix)+'.diagnostic.json').read_text())
                    if data.get('status')!='passed': raise RuntimeError(f'{name}: diagnostic did not pass')
                    run([sys.executable,'tools/'+inspector,'--probe-prefix',prefix])
                run([sys.executable,'tools/inspect-gpu-headless.py','--directory',directory])
                verified=True
                prefix=directory/'output-egl'
                run([racket,'tools/gpu-output-doctor.rkt','--prefix',prefix,'--host','egl',
                     '--backend','opengl',*options,*extra])
                data=json.loads(Path(str(prefix)+'.diagnostic.json').read_text())
                if data.get('status')!='passed': raise RuntimeError('EGL document output did not pass')
                run([sys.executable,'tools/inspect-gpu-output.py','--probe-prefix',prefix])
                output_verified=True
                performance_prefix=directory/'performance-opengl'
                run([racket,'tools/gpu-performance-doctor.rkt','--prefix',performance_prefix,'--backend','opengl',
                     '--host','egl','--egl-platform',platform,'--egl-device-index',str(index),
                     '--egl-surface',surface,*extra])
                run([sys.executable,'tools/inspect-gpu-performance.py','--probe-prefix',performance_prefix])
                performance_verified=True
        run([sys.executable,'tools/update-source-sums.py'])
        report=dict(status='passed-selected-checks',stage='0.45',gpu_mode=mode,identity=identity.strip(),
          validation_run=directory.name,commands=commands,skips=skips,display_variables_removed=list(DISPLAY_VARIABLES),
          egl_platform=platform,egl_device_index=index,egl_surface=surface,headless_rendering_verified=verified,
          gl_interop_verified=verified,gpu_document_output_verified=output_verified,hardware_string_requirement=hardware,performance_measured=performance_verified,
          performance_measurements_verified=performance_verified,redraw_stress_verified=False,
          presentation_verified=False,window_created=False)
        (directory/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
        print(f'Validation report: {directory}/validation.json')
        print(f'Headless review: {directory}/headless.review.html (published only after live gates pass)')
        return 0
    except (OSError,ValueError,RuntimeError,subprocess.CalledProcessError) as e:
        (directory/'validation.failed.json').write_text(json.dumps(dict(status='failed',stage='0.45',
            error=str(e),commands=commands,skips=skips),indent=2)+'\n')
        print(f'Headless validation FAILED: {e}\nDetails: {directory}',file=sys.stderr)
        return 1

if __name__=='__main__': raise SystemExit(main())
