#!/usr/bin/env python3
"""0.70 acceptance: full regressions, native PDF/SVG, optional required GPU/viewers."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from integer_pixel_validation import inspect_documents, inspect_gpu

ROOT=Path(__file__).resolve().parents[1]

def compile_targets(root):
    text=(root/'run-tests.rkt').read_text(encoding='utf-8')
    dynamic=sorted(set(re.findall(r'\(define-runtime-path\s+\S+\s+"(tests/[^"\n]+\.rkt)"\)',text)))
    if not dynamic:raise ValueError('empty dynamic regression graph')
    for name in dynamic:
        if any(p in ('','.','..') for p in name.split('/')) or '\\' in name or ':' in name:
            raise ValueError('unsafe compile target')
    return [root/p for p in dict.fromkeys(('main.rkt','image-info.rkt','raster-buffers.rkt','run-tests.rkt',*dynamic,
                                         'tests/integer-pixel-gpu-test.rkt','tools/integer-pixel-doctor.rkt','examples/integer-pixels.rkt'))]

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket',default='racket')
    parser.add_argument('--directory',type=Path)
    parser.add_argument('--require-gpu',action='store_true')
    parser.add_argument('--require-renderers',action='store_true')
    parser.add_argument('--backend',choices=('auto','egl','metal','direct3d'),default='auto')
    parser.add_argument('--adapter',choices=('hardware','warp'),default='hardware')
    parser.add_argument('--timeout',type=float,default=1200)
    args=parser.parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout<=0:parser.error('positive finite timeout required')
    executable=shutil.which(args.racket)
    if not executable:parser.error('selected Racket executable not found')
    racket=str(Path(executable).resolve())
    backend=args.backend
    if backend=='auto':backend={'Darwin':'metal','Windows':'direct3d'}.get(platform.system(),'egl')
    if args.adapter=='warp' and backend!='direct3d':parser.error('WARP requires the direct3d backend')
    if args.directory:
        if args.directory.exists():parser.error('evidence directory already exists')
        args.directory.mkdir(parents=True);out=args.directory.resolve()
    else:
        (ROOT/'output').mkdir(exist_ok=True)
        out=Path(tempfile.mkdtemp(prefix='integer-pixels-0.70-',dir=ROOT/'output'))
    (out/'logs').mkdir();token=uuid.uuid4().hex;commands=[]
    report=dict(schema=1,stage='0.70',package_version='0.70.0',status='failed',run_token=token,
                regressions_passed=False,documents_passed=False,rendering_executed=False,rendering_attempted=False,
                gpu_required=args.require_gpu,gpu_attempted=False,gpu_executed=False,gpu_passed=False,
                independent_renderers_required=args.require_renderers,independent_renderers_attempted=False,independent_renderers_executed=False,
                independent_renderers_passed=False,gui_executed=False,physical_display_verified=False)
    def run(command):
        command=list(map(str,command));commands.append(command);log=out/'logs'/f'{len(commands):03d}.log'
        print('+ '+' '.join(command),flush=True)
        with log.open('w',encoding='utf-8') as stream:
            stream.write('$ '+repr(command)+'\n');stream.flush()
            try:
                subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,check=True,
                               timeout=args.timeout,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1','PYTHONUTF8':'1'})
            except (OSError,subprocess.SubprocessError):
                report.update(failed_command=command,failed_log=str(log));raise
    try:
        run([sys.executable,ROOT/'tools/update-source-sums.py','--check'])
        before=hashlib.sha256((ROOT/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest();report['manifest_before']=before
        run([sys.executable,ROOT/'tools/api-inventory.py','--check'])
        run([sys.executable,ROOT/'tools/test-integer-pixels.py'])
        run([sys.executable,ROOT/'tools/test-integer-pixel-documents.py'])
        run([racket,'-l','raco','--','make',*compile_targets(ROOT)])
        run([racket,ROOT/'run-tests.rkt']);report['regressions_passed']=True
        report['rendering_attempted']=True
        run([racket,ROOT/'tools/integer-pixel-doctor.rkt','--directory',out/'documents','--token',token])
        report['rendering_executed']=True
        render=None
        if args.require_renderers:
            poppler,rsvg=shutil.which('pdftoppm'),shutil.which('rsvg-convert')
            if not poppler or not rsvg:raise ValueError('pdftoppm and rsvg-convert are both required')
            (out/'rendered').mkdir()
            def render(path,fmt):
                report['independent_renderers_attempted']=True
                png=out/'rendered'/(path.name+'.png')
                if fmt=='pdf':run([poppler,'-singlefile','-r','72','-png',path,png.with_suffix('')])
                else:run([rsvg,'--width','80','--height','64','--output',png,path])
                return png
        result=inspect_documents(out/'documents',token,render=render)
        (out/'inspection.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
        report.update(documents_passed=True,independent_renderers_executed=args.require_renderers,
                      independent_renderers_passed=args.require_renderers)
        if args.require_gpu:
            report['gpu_attempted']=True
            run([racket,ROOT/'tests/integer-pixel-gpu-test.rkt','--backend',backend,'--adapter',args.adapter,
                 '--directory',out/'gpu','--token',token])
            report['gpu_executed']=True
            gpu=inspect_gpu(out/'gpu',token,backend,args.adapter)
            (out/'gpu-inspection.json').write_text(json.dumps(gpu,indent=2)+'\n',encoding='utf-8')
            report['gpu_passed']=True
        run([sys.executable,ROOT/'tools/update-source-sums.py','--check'])
        after=hashlib.sha256((ROOT/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest()
        if after!=before:raise ValueError('source manifest changed during validation')
        report.update(manifest_after=after,status='passed')
    except Exception as error:
        report['error']=type(error).__name__+': '+str(error)
        print('Integer pixels FAILED: '+report['error'],file=sys.stderr)
    finally:
        for name,value in (('commands.json',commands),('validation.json',report)):
            (out/name).write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
        print('Evidence: '+str(out))
        if report.get('failed_log'):
            print('Failed command log: '+report['failed_log'])
            try:
                tail=Path(report['failed_log']).read_bytes()[-24000:].decode('utf-8',errors='replace')
                print('--- failed command log tail ---',file=sys.stderr)
                print(tail,file=sys.stderr)
            except OSError as error:print('Cannot read failure log: '+str(error),file=sys.stderr)
    return 0 if report['status']=='passed' else 1

if __name__=='__main__':raise SystemExit(main())
