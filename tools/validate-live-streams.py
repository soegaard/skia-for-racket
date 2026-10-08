#!/usr/bin/env python3
"""0.75b live port/consumer acceptance. Full global regressions remain the default."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid
from validation_regressions import add_regression_argument,global_compile_targets,RegressionGate
import live_stream_validation as checks
import live_ffi_probe as probe
ROOT=Path(__file__).resolve().parents[1]
def main(argv=None,*,root=ROOT):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket',default=os.environ.get('RACKET','racket'))
    parser.add_argument('--directory',type=Path)
    parser.add_argument('--require-renderers',action='store_true')
    parser.add_argument('--timeout',type=float,default=1200)
    add_regression_argument(parser);args=parser.parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout<=0:parser.error('positive finite timeout required')
    racket=shutil.which(args.racket)
    if not racket:parser.error('selected Racket executable not found')
    root=Path(root).resolve();(root/'output').mkdir(exist_ok=True)
    output=args.directory.resolve() if args.directory else Path(tempfile.mkdtemp(prefix='live-streams-0.75b-',dir=root/'output'))
    if args.directory:output.mkdir(parents=True,exist_ok=False)
    (output/'logs').mkdir();token=uuid.uuid4().hex;commands=[]
    report=dict(schema=1,stage='0.75b',status='failed',run_token=token,pure_passed=False,native_passed=False,
                evidence_passed=False,probe_passed=False,compiler_required=False,commands=commands)
    gate=RegressionGate(args.regressions,report)
    def run(command):
        command=list(map(str,command));commands.append(command);log=output/'logs'/f'{len(commands):03d}.log'
        print('+ '+subprocess.list2cmdline(command),flush=True)
        try:
            with log.open('w',encoding='utf-8') as out:
                out.write('$ '+repr(command)+'\n');out.flush()
                subprocess.run(command,cwd=root,stdout=out,stderr=subprocess.STDOUT,timeout=args.timeout,check=True,
                               env={**os.environ,'PYTHONUTF8':'1','PYTHONDONTWRITEBYTECODE':'1'})
            return log.read_text(encoding='utf-8',errors='replace').split('\n',1)[1]
        except (OSError,subprocess.SubprocessError):
            report.update(failed_command=command,failed_log=str(log));raise
    try:
        run([sys.executable,root/'tools/update-source-sums.py','--check'])
        before=hashlib.sha256((root/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest()
        run([sys.executable,root/'tools/api-inventory.py','--check'])
        run([sys.executable,root/'tools/test-live-streams.py'])
        run([racket,root/'tools/check-package-version.rkt'])
        targets=[root/n for n in ('main.rkt','live-streams.rkt','file-streams.rkt',
                 'tests/live-stream-pure-test.rkt','tests/live-stream-native-test.rkt','tools/live-stream-doctor.rkt','examples/live-streams.rkt',
                 'tests/live-ffi-probe/probe.rkt','tools/live-stream-identity.rkt')]
        if args.regressions=='full':targets+=global_compile_targets(root)
        run([racket,'-l','raco','--','make',*dict.fromkeys(targets)])
        gate.run(lambda:run([racket,root/'run-tests.rkt']))
        for kind,count in (('pure',checks.PURE_CASES),('native',checks.NATIVE_CASES)):
            text=run([racket,root/f'tests/live-stream-{kind}-test.rkt'])
            checks.suite_output(text,'live-stream-'+kind,count);report[kind+'_passed']=True
        run([racket,root/'examples/live-streams.rkt'])
        run([racket,root/'tools/live-stream-doctor.rkt','--directory',output/'native','--token',token])
        evidence=checks.inspect(output/'native',token,require_renderers=args.require_renderers,run=run)
        (output/'inspection.json').write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
        report['evidence_passed']=True
        report['probe']=probe.run_probe(root,output/'probe',racket,run,args.require_renderers)
        checks.need(report['probe'].get('status')=='passed','retained probe did not pass')
        report['probe_passed']=True
        run([sys.executable,root/'tools/update-source-sums.py','--check'])
        checks.need(before==hashlib.sha256((root/'SOURCE-SHA256SUMS.txt').read_bytes()).hexdigest(),'source changed during validation')
        report.update(status='passed',source_manifest_sha256=before)
    except Exception as error:
        report['error']=type(error).__name__+': '+str(error);print('Live streams FAILED: '+report['error'],file=sys.stderr)
        if report.get('failed_log'):
            try:print(Path(report['failed_log']).read_bytes()[-20000:].decode('utf-8','replace'),file=sys.stderr)
            except OSError:pass
    finally:
        (output/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
        print('Evidence: '+str(output))
    return 0 if report['status']=='passed' else 1
if __name__=='__main__':raise SystemExit(main())
