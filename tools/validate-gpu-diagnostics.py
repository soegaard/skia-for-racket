#!/usr/bin/env python3
"""0.77c required GPU gate. Full global regressions remain the local default."""
from __future__ import annotations
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
import gpu_diagnostics_validation as v
ROOT=Path(__file__).resolve().parents[1]

def main(argv=None,*,root=ROOT):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket',default='racket')
    parser.add_argument('--regressions',choices=('full','none'),default='full')
    parser.add_argument('--backend',choices=('auto','egl','metal','direct3d'),default='auto')
    parser.add_argument('--adapter',choices=('hardware','warp'),default='hardware')
    parser.add_argument('--require-gpu',action='store_true',help='Explicitly select the always-required GPU gate; no skip mode exists')
    parser.add_argument('--directory',type=Path)
    parser.add_argument('--timeout',type=float,default=900)
    args=parser.parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout<=0:parser.error('--timeout must be finite and positive')
    backend=args.backend if args.backend!='auto' else ('metal' if sys.platform=='darwin' else 'direct3d' if os.name=='nt' else 'egl')
    root=Path(root).resolve()
    if args.directory:
        out=args.directory.resolve();out.mkdir(parents=True,exist_ok=False)
    else:
        (root/'output').mkdir(exist_ok=True)
        out=Path(tempfile.mkdtemp(prefix='gpu-diagnostics-0.77c-',dir=root/'output'))
    logs=out/'logs';logs.mkdir();(out/'gpu').mkdir()
    token=uuid.uuid4().hex
    report=dict(schema=1,stage='0.77c',status='failed',run_token=token,backend=backend,adapter=args.adapter,
                regressions_mode=args.regressions,regressions_attempted=False,regressions_passed=False,
                regressions_status='not-run',pure_passed=False,native_passed=False,gpu_attempted=False,gpu_executed=False,
                byte_oracles_passed=False,gpu_required=True,commands=[])
    last=None
    def run(command):
        nonlocal last
        command=list(map(str,command));last=logs/f'{len(report["commands"])+1:03}.log'
        row=dict(command=command,log=str(last.relative_to(out)),status='running');report['commands'].append(row)
        print('+ '+' '.join(command),flush=True)
        with last.open('w',encoding='utf-8') as log:
            log.write('$ '+repr(command)+'\n');log.flush()
            try:
                subprocess.run(command,cwd=root,check=True,timeout=args.timeout,stdout=log,stderr=subprocess.STDOUT,
                               env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',PYTHONUTF8='1'))
                row['status']='passed'
            except BaseException:
                row['status']='failed';raise
        return last.read_text(encoding='utf-8',errors='replace')
    try:
        racket=shutil.which(args.racket)
        if not racket and Path(args.racket).is_file():racket=str(Path(args.racket).resolve())
        v.need(bool(racket),'Racket interpreter not found')
        manifest=(root/'SOURCE-SHA256SUMS.txt').read_bytes()
        for tool,extra in [('update-source-sums.py',['--check']),('api-inventory.py',['--check']),('test-gpu-diagnostics.py',[])]:
            run([sys.executable,root/'tools'/tool,*extra])
        run([racket,root/'tools/check-package-version.rkt'])
        roots=['main.rkt','gpu.rkt','gpu-egl.rkt','gpu-diagnostics.rkt',
               'tests/gpu-diagnostics-pure-test.rkt','tests/gpu-diagnostics-native-test.rkt',
               'tests/gpu-diagnostics-gpu-test.rkt','examples/gpu-diagnostics.rkt']
        if args.regressions=='full':
            roots.append('run-tests.rkt')
            roots+=re.findall(r'"(tests/[^"\n]+-native-test\.rkt)"',(root/'run-tests.rkt').read_text(encoding='utf-8'))
        run([racket,'-l','raco','--','make',*[root/p for p in dict.fromkeys(roots)]])
        if args.regressions=='full':
            report.update(regressions_attempted=True,regressions_status='running')
            run([racket,root/'run-tests.rkt'])
            report.update(regressions_passed=True,regressions_status='passed')
        else:print('Global regressions: NOT RUN (--regressions=none).')
        for suite,count,key in [('gpu-diagnostics-pure',v.PURE_CASES,'pure_passed'),('gpu-diagnostics-native',v.NATIVE_CASES,'native_passed')]:
            text=run([racket,root/'tests'/(suite+'-test.rkt')]);v.suite_output(text,suite,count);report[key]=True
        run([racket,root/'examples/gpu-diagnostics.rkt','--backend',backend,'--adapter',args.adapter])
        receipt=out/'gpu/gpu.json'
        report['gpu_attempted']=True
        run([racket,root/'tests/gpu-diagnostics-gpu-test.rkt','--backend',backend,'--adapter',args.adapter,'--report',receipt,'--token',token])
        result=v.inspect(receipt,token,backend,args.adapter)
        report.update(gpu_executed=True,byte_oracles_passed=True,inspection=result)
        v.need((root/'SOURCE-SHA256SUMS.txt').read_bytes()==manifest,'source manifest changed during validation')
        report['source_manifest_sha256']=hashlib.sha256(manifest).hexdigest()
        report['status']='passed'
        print('GPU diagnostics passed.')
        code=0
    except Exception as exc:
        if report['regressions_status']=='running':report['regressions_status']='failed'
        report['error']=type(exc).__name__+': '+str(exc);code=1
        print('GPU diagnostics FAILED: '+report['error'],file=sys.stderr)
        if last and last.is_file():
            print('Failed/last command log: '+str(last),file=sys.stderr)
            print('\n'.join(last.read_text(encoding='utf-8',errors='replace').splitlines()[-20:]),file=sys.stderr)
    (out/'validation.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('Evidence: '+str(out))
    return code
if __name__=='__main__':raise SystemExit(main())
