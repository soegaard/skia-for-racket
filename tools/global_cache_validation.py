"""Independent checks of actual cache, diagnostic and raster evidence.

Synthetic tests exercise this inspector but are never native execution evidence.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
PURE_CASES=28
NATIVE_CASES=31
SCOPE='process-global-skia-caches'
REQUESTED=[8388608,256,4194304,524288]
LIMIT_KEYS=('font-byte-limit','font-count-limit','resource-byte-limit','resource-single-allocation-byte-limit')
COUNTER_KEYS=(*LIMIT_KEYS,'font-bytes-used','font-count-used','resource-bytes-used')

def need(value,message):
    if not value:raise ValueError(message)

def number(v,max_value=(1<<64)-1):return type(v) is int and 0<=v<=max_value

def suite_output(text,name,count):
    summaries=re.findall(r'(?m)^\s*(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run\s*$',text)
    need(summaries==[(str(count),'0','0',str(count))], 'missing/failed/duplicate RackUnit completion: '+name)
    done=re.findall(r'(?m)^'+re.escape(name)+r': (\d+) cases, (\d+) failures\s*$',text)
    need(done==[(str(count),'0')], 'missing/failed/duplicate suite receipt: '+name)
    need(not re.search(r'(?m)^\s*(ERROR|FAILURE)\s*$',text),'RackUnit error marker')

def unique(pairs):
    out={}
    for k,v in pairs:
        need(k not in out,'duplicate evidence key');out[k]=v
    return out

def pixels():
    return b''.join(bytes((255,0,0,255) if 2<=x<6 and 1<=y<5 else (255,255,255,255)) for y in range(6) for x in range(8))

def snapshot(value, detailed, *, truncated=False):
    need(type(value) is dict,'missing memory snapshot')
    need(value.get('scope')==SCOPE and value.get('atomic') is False,'wrong snapshot scope/atomicity')
    need(value.get('detailed') is detailed and value.get('dump_wrapped') is False,'wrong trace options')
    need(value.get('truncated') is truncated,'unexpected snapshot truncation')
    dropped=value.get('dropped_count');cost=value.get('string_bytes');rows=value.get('entries')
    need(number(dropped) and number(cost) and type(rows) is list,'invalid snapshot counters')
    need(dropped>0 if truncated else dropped==0,'inconsistent dropped-entry count')
    need(len(rows)<=4096 and cost<=1048576,'unbounded memory snapshot')
    if truncated:need(rows==[] and cost==0,'zero-entry snapshot retained data')
    measured=0;positive=False
    for row in rows:
        need(type(row) is dict and set(row)=={'kind','name','value_name','units','value'},'malformed statistic')
        need(type(row['name']) is str and type(row['value_name']) is str,'bad statistic labels')
        texts=[row['name'],row['value_name']]
        if row['kind']=='numeric':
            need(type(row['units']) is str and number(row['value']),'invalid uint64 numeric statistic')
            texts.append(row['units'])
            positive|=row['units']=='bytes' and row['value']>0
        else:
            need(row['kind']=='string' and row['units'] is False and type(row['value']) is str,'invalid string statistic')
            texts.append(row['value'])
        encoded=[s.encode('utf-8') for s in texts]
        need(all(len(s)<=4096 for s in encoded),'unbounded native string copy')
        measured+=sum(map(len,encoded))
    need(measured==cost,'copied string byte accounting differs')
    if not truncated:need(positive,'native dump contains no positive measured byte entry after font work')
    return len(rows)

def inspect(directory,token):
    directory=Path(directory)
    def read(name,limit):
        p=directory/name
        need(p.is_file() and not p.is_symlink() and p.stat().st_size<=limit,'missing/symlink/oversized evidence: '+name)
        return p.read_bytes()
    data=read('global-caches.json',4*1024*1024)
    r=json.loads(data,object_pairs_hook=unique)
    need(type(r) is dict and type(r.get('schema')) is int and r['schema']==1,'wrong evidence schema')
    need(r.get('stage')=='0.77a' and r.get('status')=='passed' and r.get('run_token')==token,'failed or foreign evidence')
    need(r.get('native_version')=='119.0' and r.get('scope')==SCOPE,'wrong native scope/version')
    for key in ('gpu_executed','process_memory_measured','driver_memory_measured'):
        need(r.get(key) is False,'unjustified memory/backend claim: '+key)
    need(type(r.get('trace_extension_symbols_resolved')) is int and r['trace_extension_symbols_resolved']==3,'trace extension symbols unverified')
    for key in ('limits_before','limits_requested','setter_previous','limits_observed','limits_restored'):
        need(type(r.get(key)) is list and len(r[key])==4 and all(number(v) for v in r[key]),'bad limits: '+key)
        need(r[key][1]<=0x7fffffff,'font entry count out of ABI range')
    need(r['limits_before']==r['setter_previous']==r['limits_restored'],'previous/restore settings disagree')
    need(r['limits_requested']==r['limits_observed']==REQUESTED,'setter round trip differs')
    purges=r.get('purges')
    need(type(purges) is list and len(purges)==3,'missing purge evidence')
    for row,name in zip(purges,('font','resource','all')):
        need(type(row) is dict and row.get('cache')==name and row.get('before')==row.get('after')==[1,1,1,524288],'purge changed configuration')
    counters=r.get('counters')
    need(type(counters) is dict and counters.get('scope')==SCOPE and counters.get('atomic?') is False,'cache counter snapshot scope differs')
    need(all(number(counters.get(k)) for k in COUNTER_KEYS),'invalid native counter')
    need([counters[k] for k in LIMIT_KEYS]==REQUESTED,'counter snapshot limits differ')
    need(counters['font-bytes-used']>0 and counters['font-count-used']>0,'font work did not exercise the native cache')
    counts=[snapshot(r['light'],False),snapshot(r['detailed'],True),snapshot(r['truncated'],False,truncated=True)]
    # The pinned SkStrikeCache dump reports these exact root measurements.
    # Do not mistake a positive budget for evidence of actual cached objects.
    expected_font={'size':counters['font-bytes-used'], 'budget_size':counters['font-byte-limit'],
                   'glyph_count':counters['font-count-used'], 'budget_glyph_count':counters['font-count-limit']}
    for report in (r['light'],r['detailed']):
        for key,value in expected_font.items():
            rows=[row for row in report['entries'] if row['name']=='skia/sk_glyph_cache'
                  and row['value_name']==key and row['kind']=='numeric']
            need(len(rows)==1 and rows[0]['value']==value
                 and rows[0]['units']==('bytes' if key in ('size','budget_size') else 'objects'),
                 'native glyph-cache measurement differs from scalar query: '+key)

    expected=pixels();hashes={}
    for name in ('before.rgba','limited.rgba','purge-font.rgba','purge-resource.rgba','purge-all.rgba'):
        raw=read(name,len(expected));need(raw==expected,'rendering changed under cache control: '+name)
        hashes[name]=hashlib.sha256(raw).hexdigest()
    font=read('font.rgba',80*48*4)
    need(len(font)==80*48*4 and all(font[i]==255 for i in range(3,len(font),4)),'bad font raster')
    ink=sum(font[i]<128 for i in range(0,len(font),4))
    need(0<ink<80*48,'fixture font not rendered')
    return {'status':'passed','scope':SCOPE,'native_version':r['native_version'],'limits_restored':True,
            'numeric_measurements_verified':True,'snapshot_entry_counts':counts,
            'font_ink_pixels':ink,'pixel_sha256':hashes,'gpu_executed':False}
