#!/usr/bin/env python3
"""0.66 effect gate: regressions, real document capture, optional GPU and independent renderers."""
from __future__ import annotations
from validation_regressions import RegressionGate, add_regression_argument, checked_mode, global_compile_targets
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from effects_validation import inspect_documents, gpu_receipt

ROOT=Path(__file__).resolve().parents[1]

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    add_regression_argument(parser)
    parser.add_argument('--racket',default='racket')
    parser.add_argument('--directory',type=Path)
    parser.add_argument('--require-gpu',action='store_true')
    parser.add_argument('--backend',choices=('auto','egl','metal','direct3d'),default='auto')
    parser.add_argument('--adapter',choices=('hardware','warp'),default='hardware')
    parser.add_argument('--require-renderers',action='store_true')
    parser.add_argument('--timeout',type=float,default=1200)
    args=parser.parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout<=0: parser.error('positive finite timeout required')
    resolved=shutil.which(args.racket)
    if not resolved: parser.error('selected Racket executable not found')
    racket=str(Path(resolved).resolve())
    if args.directory:
        if args.directory.exists(): parser.error('evidence directory already exists')
        args.directory.mkdir(parents=True)
        out=args.directory.resolve()
    else:
        (ROOT/'output').mkdir(exist_ok=True)
        out=Path(tempfile.mkdtemp(prefix='effects-0.66-',dir=ROOT/'output'))
    (out/'logs').mkdir()
    token=uuid.uuid4().hex
    report={'schema':1,'stage':'0.66','run_token':token,'status':'failed',
            'gpu_required':args.require_gpu,'gpu_passed':False,
            'independent_renderers_required':args.require_renderers,'independent_renderers_passed':False,
            'documents_passed':False,'regressions_passed':False,'gui_executed':False}
    commands=[]
    def run(command):
        command=[str(x) for x in command]
        commands.append(command)
        log=out/'logs'/f'{len(commands):03d}.log'
        with log.open('w',encoding='utf-8') as f:
            f.write('$ '+repr(command)+'\n');f.flush()
            subprocess.run(command,cwd=ROOT,check=True,stdout=f,stderr=subprocess.STDOUT,
                           timeout=args.timeout,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'})
    regressions = RegressionGate(args.regressions, report)
    try:
        run([sys.executable,ROOT/'tools/update-source-sums.py','--check'])
        manifest=hashlib.sha256((ROOT/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest()
        report['manifest_before']=manifest
        run([sys.executable,ROOT/'tools/api-inventory.py','--check'])
        run([sys.executable,ROOT/'tools/test-effects.py'])
        if args.regressions == 'full':
            # Recompile the complete regression graph before running it. Pure tests
            # are reached transitively from run-tests.rkt; native suites are loaded
            # dynamically, so compile every define-runtime-path test target too.
            # This prevents stale .zo linklets after an implementation module changes
            # without deleting compiled directories or hiding real compile failures.
            run_tests=ROOT/'run-tests.rkt'
            dynamic_targets=sorted(set(re.findall(
                r'\(define-runtime-path\s+\S+\s+"(tests/[^"]+\.rkt)"\)',
                run_tests.read_text(encoding='utf-8'))))
            modules=[ROOT/'main.rkt',ROOT/'effects.rkt',run_tests,
                     *[ROOT/name for name in dynamic_targets],
                     ROOT/'tests/effects-gpu-test.rkt',ROOT/'tools/effects-doctor.rkt',ROOT/'examples/effects.rkt']
        else:
            modules = [ROOT/'main.rkt', ROOT/'effects.rkt', ROOT/'tests/effects-gpu-test.rkt',
                       ROOT/'tools/effects-doctor.rkt', ROOT/'examples/effects.rkt']
        run([racket,'-l','raco','--','make',*modules])
        regressions.run(lambda: run([racket,ROOT/'run-tests.rkt']))
        run([racket,ROOT/'tools/effects-doctor.rkt','--directory',out/'documents','--token',token])
        render=None
        if args.require_renderers:
            poppler=shutil.which('pdftoppm');rsvg=shutil.which('rsvg-convert')
            if not poppler or not rsvg: raise ValueError('pdftoppm and rsvg-convert are required')
            (out/'rendered').mkdir()
            def render(path,fmt):
                dest=out/'rendered'/(path.name+'.png')
                if fmt=='pdf':
                    run([poppler,'-singlefile','-r','72','-png',path,dest.with_suffix('')])
                else:
                    run([rsvg,'--width','96','--height','72','--output',dest,path])
                return dest
        inspection=inspect_documents(out/'documents',token,render=render)
        (out/'inspection.json').write_text(json.dumps(inspection,indent=2)+'\n',encoding='utf-8')
        report['documents_passed']=True
        report['independent_renderers_passed']=args.require_renderers
        if args.require_gpu:
            backend=args.backend
            if backend=='auto':
                backend='metal' if sys.platform=='darwin' else 'direct3d' if os.name=='nt' else 'egl'
            run([racket,ROOT/'tests/effects-gpu-test.rkt','--backend',backend,'--adapter',args.adapter,
                 '--report',out/'gpu.json','--token',token])
            gpu_receipt(out/'gpu.json',token,backend)
            report['gpu_passed']=True; report['backend']=backend
        run([sys.executable,ROOT/'tools/update-source-sums.py','--check'])
        after=hashlib.sha256((ROOT/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest()
        if after!=manifest: raise ValueError('source manifest changed during validation')
        report['manifest_after']=after
        report['status']='passed'
    except (OSError,ValueError,ImportError,subprocess.SubprocessError) as error:
        report['error']=type(error).__name__+': '+str(error)
        print('Effects FAILED: '+report['error'],file=sys.stderr)
    finally:
        (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n',encoding='utf-8')
        (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
        print('Evidence: '+str(out))
    if report['status']=='passed':
        print('Effects selected gates passed; no GUI/display claim.')
        return 0
    return 1

if __name__=='__main__': raise SystemExit(main())
