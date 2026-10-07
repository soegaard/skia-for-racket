#!/usr/bin/env python3
"""0.67 geometry gate: regression graph, vector documents, optional GPU and independent viewers."""
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
from geometry_completion_validation import inspect_documents, gpu_receipt

ROOT=Path(__file__).resolve().parents[1]

def compile_targets(root, regressions='full'):
    if checked_mode(regressions) == 'none':
        # Compile feature roots only; do not traverse unrelated regression suites.
        return [root / p for p in (
            'main.rkt',
            'geometry.rkt',
            'tests/geometry-completion-gpu-test.rkt',
            'tools/geometry-completion-doctor.rkt',
            'examples/geometry.rkt',
        )]
    runner=root/'run-tests.rkt'
    dynamic=sorted(set(re.findall(r'\(define-runtime-path\s+\S+\s+"(tests/[^"]+\.rkt)"\)', runner.read_text(encoding='utf-8'))))
    if not dynamic:raise ValueError('no dynamically required regression suites discovered')
    targets=['main.rkt','geometry.rkt','run-tests.rkt',*dynamic,'tests/geometry-completion-gpu-test.rkt',
             'tools/geometry-completion-doctor.rkt','examples/geometry.rkt']
    return [root/n for n in dict.fromkeys(targets)]

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    add_regression_argument(p)
    p.add_argument('--racket',default='racket');p.add_argument('--directory',type=Path)
    p.add_argument('--require-gpu',action='store_true');p.add_argument('--require-renderers',action='store_true')
    p.add_argument('--backend',choices=('auto','egl','metal','direct3d'),default='auto')
    p.add_argument('--adapter',choices=('hardware','warp'),default='hardware')
    p.add_argument('--timeout',type=float,default=1200)
    args=p.parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout<=0:p.error('positive finite timeout required')
    executable=shutil.which(args.racket)
    if not executable:p.error('selected Racket executable not found')
    racket=str(Path(executable).resolve())
    if args.directory:
        if args.directory.exists():p.error('evidence directory already exists')
        args.directory.mkdir(parents=True);out=args.directory.resolve()
    else:
        (ROOT/'output').mkdir(exist_ok=True)
        out=Path(tempfile.mkdtemp(prefix='geometry-completion-0.67-',dir=ROOT/'output'))
    (out/'logs').mkdir();token=uuid.uuid4().hex;commands=[]
    report=dict(schema=1,stage='0.67',run_token=token,status='failed',regressions_passed=False,
                documents_passed=False,gpu_required=args.require_gpu,gpu_passed=False,
                independent_renderers_required=args.require_renderers,independent_renderers_passed=False,
                rendering_executed=False,gui_executed=False,physical_display_verified=False)
    def run(command):
        command=[str(a) for a in command];commands.append(command)
        log=out/'logs'/f'{len(commands):03d}.log'
        print('+ '+' '.join(command),flush=True)
        with log.open('w',encoding='utf-8') as f:
            f.write('$ '+repr(command)+'\n');f.flush()
            try:
                subprocess.run(command,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,check=True,
                               timeout=args.timeout,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'})
            except (OSError,subprocess.SubprocessError):
                report['failed_command']=command;report['failed_log']=str(log)
                raise
    regressions = RegressionGate(args.regressions, report)
    try:
        run([sys.executable,ROOT/'tools/update-source-sums.py','--check'])
        before=hashlib.sha256((ROOT/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest();report['manifest_before']=before
        run([sys.executable,ROOT/'tools/api-inventory.py','--check'])
        run([sys.executable,ROOT/'tools/test-geometry-completion.py'])
        run([sys.executable,ROOT/'tools/test-geometry-document-inspector.py'])
        run([racket,'-l','raco','--','make',*compile_targets(ROOT, args.regressions)])
        regressions.run(lambda: run([racket,ROOT/'run-tests.rkt']))
        run([racket,ROOT/'tools/geometry-completion-doctor.rkt','--directory',out/'documents','--token',token])
        render=None
        if args.require_renderers:
            poppler=shutil.which('pdftoppm');rsvg=shutil.which('rsvg-convert')
            if not poppler or not rsvg:raise ValueError('pdftoppm and rsvg-convert are required')
            (out/'rendered').mkdir()
            def render(path,fmt):
                png=out/'rendered'/(path.name+'.png')
                if fmt=='pdf':run([poppler,'-singlefile','-r','72','-png',path,png.with_suffix('')])
                else:run([rsvg,'--width','96','--height','72','--output',png,path])
                return png
        result=inspect_documents(out/'documents',token,render=render)
        (out/'inspection.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
        report.update(documents_passed=True,rendering_executed=True,independent_renderers_passed=args.require_renderers)
        if args.require_gpu:
            backend=args.backend
            if backend=='auto':backend='metal' if sys.platform=='darwin' else 'direct3d' if os.name=='nt' else 'egl'
            run([racket,ROOT/'tests/geometry-completion-gpu-test.rkt','--backend',backend,'--adapter',args.adapter,
                 '--report',out/'gpu.json','--token',token])
            gpu_receipt(out/'gpu.json',token,backend,args.adapter)
            report.update(gpu_passed=True,backend=backend)
        run([sys.executable,ROOT/'tools/update-source-sums.py','--check'])
        after=hashlib.sha256((ROOT/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest()
        if before!=after:raise ValueError('source manifest changed during validation')
        report.update(manifest_after=after,status='passed')
    except (OSError,ValueError,ImportError,subprocess.SubprocessError) as error:
        report['error']=type(error).__name__+': '+str(error)
        print('Geometry FAILED: '+report['error'],file=sys.stderr)
    finally:
        for name,value in [('commands.json',commands),('validation.json',report)]:
            (out/name).write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
        print('Evidence: '+str(out))
        if report.get('failed_log'):print('Failed command log: '+report['failed_log'])
    if report['status']=='passed':
        print('Geometry selected gates passed; no GUI/display certification.')
        return 0
    return 1

if __name__=='__main__':raise SystemExit(main())
