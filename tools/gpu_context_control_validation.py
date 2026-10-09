"""Independent 0.77b evidence checks. Request metadata is not option readback."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re

PURE_CASES=22
NATIVE_CASES=12
GPU_CASES=20
SIZE=(32,24)
DEFAULTS=dict(avoid_stencil_buffers=False,runtime_program_cache_size=256,
              glyph_cache_texture_maximum_bytes=8388608,allow_path_mask_caching=True,
              manual_mipmapping=False,buffer_map_threshold=-1)
TUNED=dict(DEFAULTS,avoid_stencil_buffers=True,runtime_program_cache_size=16,
           glyph_cache_texture_maximum_bytes=1048576,allow_path_mask_caching=False,buffer_map_threshold=4096)
MANUAL=dict(DEFAULTS,manual_mipmapping=True,buffer_map_threshold=0)
CONFIGS={'native-defaults':False,'explicit-defaults':DEFAULTS,'tuned':TUNED,'manual':MANUAL,'after-release':TUNED}
LABELS=[
 'native-default factory pixels','explicit-default factory pixels','tuned context pixels',
 'manual mipmap context pixels','surface targeted flush only','image targeted flush only',
 'explicit completion stays separate','unbalanced surface state is rejected','CPU resources are rejected',
 'closed GPU resources are rejected','inactive targeted flush is rejected','foreign context resources are rejected',
 'healthy teardown rejects active scope','healthy teardown rejects foreign owner','free resources does not abandon',
 'healthy release invalidates live children without readback','retire children then close native context',
 'closed release operation is rejected','existing loss abandonment still works','new context renders after teardown']

def need(ok,message):
    if not ok:raise ValueError(message)

def integer(v,minimum=0):return type(v) is int and v>=minimum

def same_value(a,b):
    if type(a) is not type(b):return False
    if isinstance(a,dict):return a.keys()==b.keys() and all(same_value(a[k],b[k]) for k in a)
    if isinstance(a,list):return len(a)==len(b) and all(same_value(x,y) for x,y in zip(a,b))
    return a==b

def unique(pairs):
    out={}
    for k,v in pairs:
        need(k not in out,'duplicate JSON key: '+k);out[k]=v
    return out

def read_json(path):
    path=Path(path)
    need(path.is_file() and not path.is_symlink(),'missing/symlink report')
    need(path.stat().st_size<=4*1024*1024,'oversized report')
    def bad(v):raise ValueError('nonfinite JSON: '+v)
    obj=json.loads(path.read_text(encoding='utf-8'),object_pairs_hook=unique,parse_constant=bad)
    need(type(obj) is dict,'report must be an object');return obj

def pixels():
    out=bytearray()
    for y in range(SIZE[1]):
        for x in range(SIZE[0]):
            v=(17,34,51,255)
            if 2<=x<13 and 3<=y<10:v=(229,41,53,255)
            if 15<=x<28 and 10<=y<20:v=(11,179,67,255)
            out.extend(v)
    return bytes(out)

def suite_output(text,name,count):
    need(not re.search(r'^\s*(ERROR|FAILURE)\s*$',text,re.M),'RackUnit failure in '+name)
    summary=re.findall(r'(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run',text)
    need(summary==[(str(count),'0','0',str(count))],'incomplete/duplicate RackUnit summary: '+name)
    marker=re.findall(r'^'+re.escape(name)+r': (\d+) cases, (\d+) failures\s*$',text,re.M)
    need(marker==[(str(count),'0')],'missing/duplicate completion marker: '+name)

def flush(e,target,generation=None):
    need(type(e) is dict and e.get('kind')=='flush' and e.get('target')==target,'missing targeted flush')
    need(e.get('submission_requested') is False and e.get('completion_guaranteed') is False,'flush falsely claims submission/completion')
    need(integer(e.get('context_generation'),1),'missing target generation')
    if generation is not None:need(e['context_generation']==generation,'foreign target generation')

def inspect(path:Path,token:str,backend:str,adapter:str):
    path=Path(path);r=read_json(path)
    need(type(r.get('schema')) is int and r['schema']==1,'wrong schema')
    need(r.get('stage')=='0.77b' and r.get('status')=='passed','wrong stage or failed native result')
    need(type(token) is str and token and r.get('run_token')==token,'foreign run token')
    need(r.get('native_version')=='119.0','wrong native ABI')
    need(r.get('backend')==backend and r.get('adapter')==adapter,'wrong selected backend')
    need(r.get('gpu_executed') is True and r.get('native_option_readback') is False,'invalid execution/readback claim')
    need(type(r.get('cases')) is int and r['cases']==GPU_CASES and type(r.get('failures')) is int and r['failures']==0,'wrong native test counts')
    need(r.get('labels')==LABELS,'missing/reordered test coverage')
    need(r.get('cleanup_errors')==[],'native cleanup did not finish')
    actual_backend={'egl':'opengl','metal':'metal','direct3d':'direct3d'}[backend]
    factory={'egl':'gr_direct_context_make_gl','metal':'gr_direct_context_make_metal','direct3d':'gr_direct_context_make_direct3d'}[backend]
    captures=r.get('captures')
    need(type(captures) is list and len(captures)==len(CONFIGS),'missing pixel captures')
    names=[];results=[]
    for row in captures:
        need(type(row) is dict,'invalid capture')
        name=row.get('name');need(name in CONFIGS and name not in names,'duplicate/unknown capture');names.append(name)
        expected_options=CONFIGS[name]
        need(same_value(row.get('requested_options'),expected_options),'wrong requested option value')
        for k in ('width','height'):need(integer(row.get(k),1),'non-integer dimensions')
        need((row['width'],row['height'])==SIZE,'wrong capture dimensions')
        info=row.get('info');need(type(info) is dict,'missing native context info')
        need(info.get('backend')==actual_backend and info.get('state')=='ready','wrong context backend/state')
        need(integer(info.get('generation'),1),'missing context generation')
        explicit=expected_options is not False
        need(info.get('context_factory')==factory+('_with_options' if explicit else ''),'wrong constructor route')
        need(info.get('context_options_source')==('explicit' if explicit else 'native-defaults'),'wrong options provenance')
        need(same_value(info.get('context_options'),expected_options) and info.get('context_options_native_readback') is False,'request metadata misrepresented')
        if backend=='direct3d':need(info.get('adapter_selection')==adapter,'wrong D3D adapter')
        need(row.get('drawing_readbacks')==0 and type(row.get('drawing_readbacks')) is int,'hidden drawing readback')
        need(row.get('readbacks')==1 and type(row.get('readbacks')) is int,'wrong explicit readback count')
        need(row.get('file')==name+'.rgba','unsafe or unexpected capture filename')
        p=path.parent/(name+'.rgba')
        need(p.is_file() and not p.is_symlink(),'missing/symlink pixel capture')
        need(p.stat().st_size==SIZE[0]*SIZE[1]*4,'wrong pixel byte count')
        data=p.read_bytes();need(data==pixels(),'selected GPU pixels differ: '+name)
        events=row.get('events');need(type(events) is list and all(type(e) is dict for e in events),'missing I/O ledger')
        targeted=[e for e in events if e.get('kind')=='flush' and 'target' in e]
        need(len(targeted)==2,'wrong targeted flush count')
        flush(targeted[0],'surface',info['generation']);flush(targeted[1],'image',info['generation'])
        kinds=[e.get('kind') for e in events]
        need(kinds.count('readback')==1 and 'upload' not in kinds,'unexpected GPU I/O')
        first_submit=next((i for i,e in enumerate(events) if e.get('kind')=='submit'),-1)
        need(first_submit>=0 and events[first_submit].get('wait_requested') is True,'missing explicit completion request')
        need(events.index(targeted[1])<first_submit<kinds.index('readback'),'targeted flush/order changed')
        read_index=kinds.index('readback')
        need(any(e.get('kind')=='submit' and e.get('wait_requested') is True for e in events[read_index+1:]),'readback lacks its completion boundary')
        results.append(dict(name=name,pixels_checked=SIZE[0]*SIZE[1],sha256=hashlib.sha256(data).hexdigest()))
    need(names==list(CONFIGS),'wrong capture matrix order')
    life=r.get('lifecycle');need(type(life) is dict,'missing lifecycle receipt')
    need(life.get('children_invalidated') is True and life.get('child_close_required') is True,'invalid child lifetime evidence')
    before,after,closed=[life.get(k) for k in ('before','after_release','after_close')]
    need(all(type(v) is dict for v in (before,after,closed)),'missing lifecycle states')
    need([v.get('state') for v in (before,after,closed)]==['ready','abandoned','closed'],'wrong teardown state sequence')
    need(integer(before.get('live_children'),2),'missing retained children')
    need(after.get('live_children')==before['live_children'],'abandon silently closed wrappers')
    need(closed.get('live_children')==0 and closed.get('pending_releases')==0,'teardown left pending children')
    generation=before.get('generation');need(integer(generation,1) and all(v.get('generation')==generation for v in (after,closed)),'lifecycle generation changed')
    traces=r.get('targeted_traces')
    need(type(traces) is list and [t.get('name') for t in traces]==['surface','image','submit','release'],'missing targeted traces')
    for t in traces[:2]:
        need(type(t.get('events')) is list and len(t['events'])==1,'extra targeted I/O')
        flush(t['events'][0],t['name'],generation)
    es=traces[2].get('events');need(type(es) is list and len(es)==2,'wrong submission trace')
    flush(es[0],'surface',generation)
    need(es[1].get('kind')=='submit' and es[1].get('wait_requested') is True,'missing wait flag')
    es=traces[3].get('events');need(type(es) is list and len(es)==1,'release triggered extra public I/O')
    e=es[0]
    need(e.get('kind')=='context-release-and-abandon' and e.get('context_generation')==generation,'wrong release event')
    need(e.get('completion_guaranteed') is False and e.get('readback') is False,'invalid release completion claim')
    return dict(status='passed',backend=backend,gpu_executed=True,native_option_readback=False,
                captures=results,total_pixels_checked=SIZE[0]*SIZE[1]*len(results),lifecycle_verified=True)
