#!/usr/bin/env python3
"""0.73 acceptance: source, full regression graph, typed GPU captures and documents."""
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
from gpu_format_validation import inspect
ROOT=Path(__file__).resolve().parents[1]

def compile_targets(root):
    text=(root/'run-tests.rkt').read_text(encoding='utf-8')
    dynamic=sorted(set(re.findall(r'\(define-runtime-path\s+\S+\s+"(tests/[^"\n]+\.rkt)"\)',text)))
    if not dynamic:raise ValueError('empty regression compile graph')
    for p in dynamic:
        if '..' in p.split('/') or '\\' in p or ':' in p:raise ValueError('unsafe compile target')
    return [root/p for p in dict.fromkeys(('main.rkt','gpu.rkt','gpu-dc.rkt','surface-properties.rkt',
         'run-tests.rkt',*dynamic,'tests/gpu-format-gpu-test.rkt','examples/gpu-formats.rkt'))]

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
    if args.require_renderers and not args.require_gpu:parser.error('--require-renderers requires --require-gpu: these documents originate on GPU targets')
    executable=shutil.which(args.racket)
    if not executable:parser.error('selected Racket executable not found')
    racket=str(Path(executable).resolve())
    backend=args.backend
    if backend=='auto':backend={'Darwin':'metal','Windows':'direct3d'}.get(platform.system(),'egl')
    if args.adapter=='warp' and backend!='direct3d':parser.error('WARP requires direct3d')
    if args.directory:
        if args.directory.exists():parser.error('evidence directory exists')
        args.directory.mkdir(parents=True);out=args.directory.resolve()
    else:
        (ROOT/'output').mkdir(exist_ok=True)
        out=Path(tempfile.mkdtemp(prefix='gpu-formats-0.73-',dir=ROOT/'output'))
    (out/'logs').mkdir();token=uuid.uuid4().hex;commands=[]
    report=dict(schema=1,stage='0.73',package_version='0.73',run_token=token,status='failed',
       regressions_passed=False,gpu_required=args.require_gpu,gpu_attempted=False,gpu_executed=False,gpu_passed=False,
       documents_passed=False,independent_renderers_required=args.require_renderers,
       independent_renderers_executed=False,physical_display_verified=False,hdr_verified=False)
    def run(command):
        command=list(map(str,command));commands.append(command);log=out/'logs'/f'{len(commands):03d}.log'
        print('+ '+' '.join(command),flush=True)
        with log.open('w',encoding='utf-8') as stream:
            stream.write('$ '+repr(command)+'\n');stream.flush()
            try:subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,check=True,
                         timeout=args.timeout,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1','PYTHONUTF8':'1'})
            except (OSError,subprocess.SubprocessError):report.update(failed_command=command,failed_log=str(log));raise
    try:
        run([sys.executable,ROOT/'tools/update-source-sums.py','--check'])
        before=hashlib.sha256((ROOT/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest();report['manifest_before']=before
        run([sys.executable,ROOT/'tools/api-inventory.py','--check'])
        run([sys.executable,ROOT/'tools/test-gpu-formats.py'])
        run([racket,ROOT/'tools/check-package-version.rkt'])
        run([racket,'-l','raco','--','make',*compile_targets(ROOT)])
        run([racket,ROOT/'run-tests.rkt']);report['regressions_passed']=True
        if args.require_gpu:
            report['gpu_attempted']=True;(out/'gpu').mkdir()
            run([racket,ROOT/'tests/gpu-format-gpu-test.rkt','--backend',backend,'--adapter',args.adapter,
                 '--report',out/'gpu/gpu.json','--token',token]);report['gpu_executed']=True
            render=None
            if args.require_renderers:
                poppler,rsvg=shutil.which('pdftoppm'),shutil.which('rsvg-convert')
                if not poppler or not rsvg:raise ValueError('pdftoppm and rsvg-convert are both required')
                (out/'rendered').mkdir()
                def render(path,kind):
                    png=out/'rendered'/(path.name+'.png')
                    if kind=='pdf':run([poppler,'-singlefile','-r','72','-png',path,png.with_suffix('')])
                    else:run([rsvg,'--width','40','--height','28','--output',png,path])
                    return png
            result=inspect(out/'gpu',token,backend,args.adapter,render)
            (out/'inspection.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
            report.update(gpu_passed=True,documents_passed=True,independent_renderers_executed=args.require_renderers)
        run([sys.executable,ROOT/'tools/update-source-sums.py','--check'])
        after=hashlib.sha256((ROOT/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest()
        if after!=before:raise ValueError('manifest changed during validation')
        report.update(manifest_after=after,status='passed')
    except Exception as e:
        report['error']=type(e).__name__+': '+str(e);print('GPU formats FAILED: '+report['error'],file=sys.stderr)
    finally:
        for name,value in (('commands.json',commands),('validation.json',report)):
            (out/name).write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
        print('Evidence: '+str(out))
        if report.get('failed_log'):
            print('Failed command log: '+report['failed_log'])
            try:print(Path(report['failed_log']).read_bytes()[-24000:].decode('utf-8',errors='replace'),file=sys.stderr)
            except OSError:pass
    return 0 if report['status']=='passed' else 1
if __name__=='__main__':raise SystemExit(main())
