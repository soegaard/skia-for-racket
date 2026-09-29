#!/usr/bin/env python3
"""Inspect 0.45 native timing/resource reports. No third-party packages required.

Raw timings are host observations, not GPU timestamps or display latency.
Self-tests are synthetic and do not establish native execution or performance.
"""
from __future__ import annotations
import argparse, csv, html, importlib.util, io, json, math, os, re, statistics, tempfile
from pathlib import Path

NATIVE_CACHE_CASES = 20
SCENES = ('paths', 'text', 'runtime')
SOURCE_PATHS = ('examples/gpu-scenes.rkt','examples/gpu-presentation-scene.rkt',
 'private/gpu-performance-util.rkt','private/gpu-cache.rkt','tools/gpu-performance-options.rkt',
 'tools/gpu-performance-work.rkt','tools/gpu-performance-doctor.rkt','tools/gpu-redraw-doctor.rkt')
CACHE_SYMBOLS = {'gr_direct_context_is_abandoned', 'gr_direct_context_get_resource_cache_limit',
 'gr_direct_context_get_resource_cache_usage', 'gr_direct_context_set_resource_cache_limit',
 'gr_direct_context_purge_unlocked_resources', 'gr_direct_context_purge_unlocked_resources_bytes',
 'gr_direct_context_perform_deferred_cleanup', 'gr_direct_context_free_gpu_resources'}
HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('_performance_png', HERE/'inspect-gpu-offscreen.py')
_png = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_png)

def need(condition, message):
    if not condition: raise ValueError(message)

def integer(x, lo=0): return type(x) is int and x >= lo

def clock_ms(x): return type(x) in (int, float) and math.isfinite(x)

def finite(x): return type(x) in (int, float) and math.isfinite(x) and x >= 0

def equal_number(a, b):
    return finite(a) and finite(b) and math.isclose(a, b, rel_tol=1e-7, abs_tol=1e-7)

def config_check(c):
    for k,lo,hi in [('samples',3,500),('warmup',1,100),('frames',60,9990),('cycles',3,50),
                    ('width',128,4096),('height',128,4096),('sample_count',0,16)]:
        need(integer(c.get(k),lo) and c[k]<=hi, 'invalid configuration '+k)
    need(c['frames']%30 == 0 and c.get('checkpoint_interval') == 30,'checkpoint configuration')
    need(c['frames']*c['cycles']<=30000,'raw report size bound')
    for k,v in {'cache_limit_bytes':32*1024**2,'cache_growth_allowance_bytes':16*1024**2,
                'cache_growth_allowance_resources':64,'cpu_pressure_bytes':4*1024**2}.items():
        need(type(c.get(k)) is int and c[k]==v,'unrecognized resource envelope '+k)

def context_check(c, backend, state='ready', generation=None, live=0):
    need(c.get('state')==state and c.get('backend')==backend,'context state/backend')
    need(integer(c.get('generation'),1),'context generation')
    if generation is not None: need(c['generation']==generation,'foreign context generation')
    for k,v in [('live_children',live),('pending_releases',0),('failed_releases',0)]:
        need(type(c.get(k)) is int and c[k]==v, 'resource leak: '+k)
    need(c.get('shutdown_requested') is False,'shutdown requested')
    need(type(c.get('native_backend')) is int and c['native_backend']=={'opengl':0,'metal':2}[backend], 'native backend ID')
    need(c.get('binding_package')=='3.119.1' and c.get('native_version')=='119.0', 'native version mismatch')
    for key in ('renderer','renderer_class','api_version','vendor'):
        need(isinstance(c.get(key),str) and c[key], 'missing driver identity '+key)
    if backend=='metal': need(c.get('owns_command_queue') is True,'Metal queue ownership')
    return c['generation']

def cache_check(s, backend, gen):
    need(s.get('backend')==backend and type(s.get('context_generation')) is int and s.get('context_generation')==gen, 'foreign cache snapshot')
    for k in ('limit_bytes','budgeted_resources','budgeted_bytes'): need(integer(s.get(k)), 'bad cache '+k)
    need(s.get('total_gpu_bytes') is False and s.get('purgeable_bytes') is False,
         'unsupported total/purgeable-memory claim')
    need(s.get('limit_is_hard_allocation_cap') is False, 'cache budget is not a hard allocation cap')

def envelope(row, base, conf, backend, gen, live):
    context_check(row['context'],backend,generation=gen,live=live)
    cache_check(row['cache'],backend,gen)
    need(row['cache']['budgeted_bytes'] <= base['budgeted_bytes']+conf['cache_growth_allowance_bytes'],'cache bytes growth')
    need(row['cache']['budgeted_resources'] <= base['budgeted_resources']+conf['cache_growth_allowance_resources'],'cache count growth')
    need(integer(row.get('heap_bytes')), 'heap telemetry missing')

def one(row):
    for k in ('start_ms','end_ms'):
        need(clock_ms(row.get(k)), 'invalid clock reading '+k)
    for k in ('elapsed_ms','host_cpu_ms','gc_cpu_ms'):
        need(finite(row.get(k)), 'invalid timing '+k)
    need(row['end_ms']>=row['start_ms'] and equal_number(row['elapsed_ms'],row['end_ms']-row['start_ms']), 'inconsistent elapsed time')

def io_check(events, *, complete=False, present=False, upload=False, readback=False, frames=None):
    need(isinstance(events,list),'missing I/O trace')
    need(all(isinstance(e,dict) for e in events),'bad I/O event')
    kinds=[e.get('kind') for e in events]
    if complete:
        need(kinds[-4:]==['flush','submit','flush','submit'],'missing completion sequence')
        need(events[-3].get('wait_requested') is False and events[-1].get('wait_requested') is True, 'no-wait is not GPU completion')
        need('readback' not in kinds, 'readback mixed into completion-only workload')
        if not upload: need(kinds==['flush','submit','flush','submit'],'unexpected resident work')
        else: need(kinds[0] in ('upload','image-upload'),'upload trace missing')
    elif readback:
        need(kinds.count('readback')==1 and kinds[-2:]==['flush','submit'] and events[-1].get('wait_requested') is True,'unsynchronized readback')
    else:
        need('readback' not in kinds,'resident/presentation readback')
        need(not any(e.get('wait_requested') is True for e in events),'normal frame CPU wait')
        need('cache' not in kinds and 'cancelled-frame-sync' not in kinds,'cleanup hidden in normal frame')
        if present:
            need(kinds==['flush','submit','present-request'],'presentation order')
            need(events[1].get('wait_requested') is False and events[2].get('wait_requested') is False,'presentation wait flag')
        if frames is not None:
            need(kinds.count('flush')==frames and kinds.count('submit')==frames,'stress submission count')

def completed(row, upload=False):
    ts=row.get('timepoints_ms'); need(isinstance(ts,list) and len(ts)==5 and all(clock_ms(x) for x in ts),'timing phases')
    need(all(a<=b for a,b in zip(ts,ts[1:])),'nonmonotonic timing phases')
    for k,a,b in zip(('draw_ms','flush_ms','submit_ms','completion_wait_ms'),ts,ts[1:]):
        need(equal_number(row.get(k),b-a),'inconsistent phase '+k)
    need(equal_number(row.get('completed_ms'),ts[-1]-ts[0]),'inconsistent completion duration')
    need(row.get('completion')=='explicit CPU synchronization','GPU completion not established')
    need(finite(row.get('host_cpu_ms')) and finite(row.get('gc_cpu_ms')),'CPU/GC time')
    io_check(row['io_events'],complete=True,upload=upload)

def target_check(t,backend,gen,w,h,conf=None):
    need(t.get('storage')=='gpu' and t.get('context_matches') is True,'target not proved GPU-backed')
    need(t.get('backend')==backend and t.get('context_generation')==gen,'foreign target')
    need(type(t.get('native_backend')) is int and t['native_backend']=={'opengl':0,'metal':2}[backend],'target native backend')
    need(t.get('width')==w and t.get('height')==h,'target extent')
    if conf:
        need(t.get('render_path')=='sk_surface_new_render_target' and t.get('origin')=='top-left','offscreen path/origin')
        need(type(t.get('requested_sample_count')) is int and t.get('requested_sample_count')==conf['sample_count'] and t.get('actual_sample_count') is False,'unproven actual sampling')
    else:
        need(t.get('render_path')=='sk_surface_new_backend_render_target','presenter target path')
        need(integer(t.get('actual_sample_count')),'queried presenter samples')
        need(t.get('origin')==('top-left' if backend=='metal' else 'bottom-left'),'presenter origin')

def safe_file(directory,name):
    need(isinstance(name,str) and name and Path(name).name==name and '/' not in name and '\\' not in name,'unsafe artifact filename')
    p=directory/name
    need(p.is_file() and not p.is_symlink(),'missing artifact '+name)
    return p

def compare_pngs(directory,a,b,size):
    need(a!=b,'CPU/GPU images must be separate artifacts')
    aa=_png.png(safe_file(directory,a).read_bytes(),size); bb=_png.png(safe_file(directory,b).read_bytes(),size)
    w,h=size
    for data in (aa,bb):
        for x,y,col in [(0,0,(255,0,0,255)),(w-1,0,(0,255,0,255)),(0,h-1,(0,0,255,255)),(w-1,h-1,(255,255,0,255))]:
            off=4*(x+y*w); need(tuple(data[off:off+4])==col,'orientation marker mismatch')
        need(data[4*(w//2)+3]==0,'transparent top margin mismatch')
        # Reject an empty/marker-only image independently of pairwise similarity.
        need(sum(1 for i in range(0,len(data),4) if data[i+3] and max(data[i:i+3])-min(data[i:i+3])>20)>w*h*.01, 'empty scene')
    total=0; large=0; peak=0
    for i in range(0,len(aa),4):
        dif=[abs((aa[i+j]*aa[i+3]+127)//255-(bb[i+j]*bb[i+3]+127)//255) for j in range(3)]+[abs(aa[i+3]-bb[i+3])]
        total+=sum(dif); peak=max(peak,*dif);large+=max(dif)>24
    mean=total/(w*h*4); fraction=large/(w*h)
    need(mean<=3 and fraction<=.10,'CPU/GPU pixels exceed explicit tolerance')
    return dict(mean_error=mean,max_error=peak,large_error_fraction=fraction,mean_limit=3,large_fraction_limit=.10)

def statistics_row(label,phase,values,unit='ms'):
    need(values and all(finite(x) for x in values),'invalid statistics input')
    xs=sorted(values);n=len(xs)
    return dict(workload=label,phase=phase,count=n,min=xs[0],median=statistics.median(xs),
                p95=xs[math.ceil(.95*n)-1],max=xs[-1],mean=statistics.mean(xs),unit=unit)

def validate(report,directory):
    need(report.get('schema_version')==1 and report.get('stage')=='0.45' and report.get('status')=='passed','not a successful 0.45 report')
    backend=report.get('backend'); need(backend in ('opengl','metal'),'backend')
    need(isinstance(report.get('validation_run'),str) and report['validation_run'],'run identity')
    for k in ('os','architecture','racket_version'): need(isinstance(report.get(k),str) and report[k],'host identity')
    need(report.get('clock')=='current-inexact-monotonic-milliseconds','clock not monotonic')
    need(report.get('performance_measured') is True and report.get('speedup_claimed') is False,'unsupported performance claim')
    need(report.get('display_latency_measured') is False,'display latency unmeasured')
    sources=report.get('workload_sources',[])
    need(isinstance(sources,list) and all(isinstance(x,dict) for x in sources),'source fingerprint list')
    need([x.get('path') for x in sources]==list(SOURCE_PATHS),'source fingerprint paths')
    need(all(isinstance(x.get('sha1'),str) and re.fullmatch('[0-9a-f]{40}',x['sha1']) for x in sources),'source fingerprints')
    conf=report['config']; config_check(conf); stats=[]; generations=[]; comparisons=[]; identities=[]
    def identity(c):
        gen=context_check(c,backend)
        if report.get('require_hardware') is True: need(c['renderer_class']=='hardware-reported','hardware requirement')
        signature=tuple(c[k] for k in ('renderer','vendor','api_version','native_version','binding_package'))
        need(not identities or identities[0]==signature, 'driver/device changed within one measurement report')
        identities.append(signature);generations.append(gen);return gen
    if report.get('kind')=='performance':
        need(report.get('isolated_gpu_timestamps') is False and report.get('total_gpu_memory_measured') is False,'unsupported GPU/memory measurement')
        need(type(report.get('native_test_cases')) is int and report['native_test_cases']==NATIVE_CACHE_CASES,'cache suite coverage')
        need(type(report.get('native_test_failures')) is int and report['native_test_failures']==0,'native tests failed')
        syms=report.get('cache_symbols',[])
        need({s.get('name') for s in syms}==CACHE_SYMBOLS and all(s.get('available') is True for s in syms),'cache symbols')
        scenes=report.get('scenes',[]); need([s.get('name') for s in scenes]==list(SCENES),'benchmark scenes')
        filenames=[]
        for s in scenes:
            label=s['name'];gen=identity(s['initial_context']);context_check(s['closed_context'],backend,'closed',gen)
            need(s.get('encoded_after_teardown') is True,'image not detached through teardown')
            need(s.get('scene_version')=='gpu-scenes-0.39/v1' and s.get('logical_size')==[420,260],'scene definition')
            need(s.get('isolated_driver_compile_ms') is False,'driver compile duration not isolated')
            target_check(s['target'],backend,gen,conf['width'],conf['height'],conf)
            cache_check(s['cache_after'],backend,gen)
            need(type(s.get('warmup_completed')) is int and s.get('warmup_completed')==conf['warmup'] and len(s.get('warmup_replay',[]))==conf['warmup'],'warmup count')
            for warm in s['warmup_replay']: completed(warm)
            completed(s['first_use']);stats.append(statistics_row(label,'first-replay-completed',[s['first_use']['completed_ms']]))
            for group in ('authoring_recording','cpu_raster','readback','warm_replay','upload'):
                rows=s.get(group,[]);need(len(rows)==conf['samples'],'sample count '+group)
                for row in rows:
                    if group in ('warm_replay','upload'):
                        completed(row,upload=group=='upload')
                        if group=='upload':
                            need(row.get('fresh_cpu_identity') is True and row.get('pixels_verified') is True,'upload reuse/unverified')
                            need(row.get('bytes')==65536 and row.get('width')==128 and row.get('height')==128,'upload size')
                            im=row['image'];need(im.get('texture_backed') is True and im.get('storage')=='gpu' and im.get('context_matches') is True,'upload not resident')
                            need(im.get('backend')==backend and im.get('context_generation')==gen,'foreign uploaded image')
                    else:
                        one(row)
                        if group=='readback':
                            need(row.get('source_precompleted') is True and row.get('pixels_verified') is True and row.get('bytes')==conf['width']*conf['height']*4,'readback boundary/size')
                            io_check(row['io_events'],readback=True)
                phases=('draw_ms','flush_ms','submit_ms','completion_wait_ms','completed_ms') if group in ('warmup_replay','warm_replay','upload') else ('elapsed_ms',)
                for phase in phases:stats.append(statistics_row(label,group+'/'+phase,[r[phase] for r in rows]))
            rows=s.get('sksl_effect_construction',[])
            need(len(rows)==(conf['samples'] if label=='runtime' else 0),'SkSL constructor coverage')
            for row in rows:one(row)
            if rows:stats.append(statistics_row(label,'sksl-effect-construction',[r['elapsed_ms'] for r in rows]))
            filenames += [s['cpu_image'],s['gpu_image']]
            comparisons.append(dict(name=label,**compare_pngs(directory,s['cpu_image'],s['gpu_image'],(conf['width'],conf['height']))))
        need(len(filenames)==len(set(filenames)),'duplicate PNG resources')
        cycles=report.get('cycles',[]);need(len(cycles)==conf['cycles'],'context recreation coverage')
        for i,c in enumerate(cycles):
            need(type(c.get('index')) is int and c.get('index')==i and c.get('frames')==conf['frames'],'stress cycle identity')
            gen=identity(c['initial_context']);context_check(c['closed_context'],backend,'closed',gen)
            cache_check(c['baseline_cache'],backend,gen)
            need(c.get('content_verified') is True and c.get('final_pixel_samples')==[[255,0,0,255],[0,255,0,255],[0,0,255,255],[255,255,0,255]],'stress contents')
            need(c.get('intentional_gc_wrappers')==conf['frames']//10,'GC exercise count')
            need(integer(c.get('max_observed_live_children'),1) and c['max_observed_live_children']<=4,'live wrapper high-water bound')
            cp=c.get('checkpoints',[]);need(len(cp)==conf['frames']//30,'stress checkpoint count')
            for j,row in enumerate(cp):
                need(row.get('frame')==30*(j+1) and row.get('weak_wrappers_retired') is True,'GC retirement not verified')
                envelope(row,c['baseline_cache'],conf,backend,gen,1)
                need(row['cache']['limit_bytes']==(0 if j%2==0 else conf['cache_limit_bytes']),'cache pressure not exercised')
                io_check(row['resident_io'],frames=30)
    elif report.get('kind')=='redraw':
        need(report.get('visible_pixels_verified') is False,'screen pixels not certified by submission')
        windows=report.get('windows',[]);need(len(windows)==2*conf['cycles'],'window recreation coverage')
        for number,w in enumerate(windows):
            need(type(w.get('cycle')) is int and type(w.get('window')) is int and w.get('cycle')==number//2 and w.get('window')==number%2,'window identity')
            gen=identity(w['initial_context']);base=w['baseline_cache'];cache_check(base,backend,gen)
            frames=w.get('frames',[]);need(len(frames)==conf['frames'],'sustained frame count')
            sizes=set();previous=0
            for row in [w['warmup'],*frames]:
                one(row);one(row['callback'])
                need(row['start_ms']<=row['callback']['start_ms']<=row['callback']['end_ms']<=row['end_ms'],'callback not inside presenter timing')
                need(row.get('frame_expired') is True and row.get('canvas_expired') is True,'expired frame/canvas')
                io_check(row['io_events'],present=True)
                f=row['frame'];need(integer(f.get('frame_index'),1) and f['frame_index']>previous,'frame index reuse');previous=f['frame_index']
                pw,ph=f.get('pixel_width'),f.get('pixel_height');need(integer(pw,1) and integer(ph,1),'drawable extent')
                sizes.add((pw,ph))
                need(f.get('backend')==backend and f.get('visible') is True and f.get('drawable') is True,'frame not drawable')
                for axis in ('x','y'):
                    logical=f['logical_width' if axis=='x' else 'logical_height'];pixel=pw if axis=='x' else ph
                    need(finite(logical) and logical>0 and equal_number(f['scale_'+axis],pixel/logical),'backing scale')
                target_check(f['target'],backend,gen,pw,ph)
            need(len(sizes)>=2,'resize not exercised')
            cp=w.get('checkpoints',[]);need(len(cp)==conf['frames']//30,'redraw checkpoint count')
            for j,row in enumerate(cp):
                need(row.get('frame')==30*(j+1) and row.get('queued_requests')==4 and type(row.get('queued_callbacks')) is int and row.get('queued_callbacks')==1,'queued redraw coalescing')
                envelope(row,base,conf,backend,gen,0)
                p=row['presenter'];need(p.get('last_error') is False and type(p.get('frames_cancelled')) is int and p.get('frames_cancelled')==0,'presenter failure')
                a=p['adapter'];need(type(a.get('live_drawables')) is int and a['live_drawables']==0,'live drawable leak')
                if backend=='metal':need(type(a.get('quarantined_frames')) is int and a.get('quarantined_frames')==0 and integer(a.get('pending_presentation_buffers')) and a['pending_presentation_buffers']<=1,'Metal pending/quarantine growth')
            expected=1+conf['frames']+len(cp)
            need(w.get('render_callbacks')==expected and integer(w.get('retry_skips')),'callback accounting')
            p=w['closed_presenter'];need(p.get('state')=='closed' and p.get('presents_requested')==expected,'presenter closure/accounting')
            a=p['adapter'];context_check(a['context'],backend,'closed',gen)
            need(type(a.get('live_drawables')) is int and a['live_drawables']==0,'closed drawable leak')
            if backend=='metal': need(a.get('layer_closed') is True and type(a.get('pending_presentation_buffers')) is int and a['pending_presentation_buffers']==0 and type(a.get('quarantined_frames')) is int and a.get('quarantined_frames')==0,'Metal teardown')
            else:need(a.get('owns_host_framebuffer') is False,'host framebuffer adopted')
            label=f'cycle-{number//2+1}/window-{number%2+1}'
            stats += [statistics_row(label,'presenter-call',[r['elapsed_ms'] for r in frames]),
                      statistics_row(label,'drawing-callback',[r['callback']['elapsed_ms'] for r in frames])]
    else: raise ValueError('unknown measurement kind')
    need(len(generations)==len(set(generations)),'context generation reused')
    return dict(schema_version=1,stage='0.45',status='passed',kind=report['kind'],backend=backend,
                validation_run=report['validation_run'],config=conf,workload_sources=sources,statistics=stats,comparisons=comparisons,
                fresh_contexts_checked=len(generations),resource_envelopes_verified=True,
                performance_measured=True,isolated_gpu_timestamps=False,display_latency_measured=False,
                total_gpu_memory_measured=False,speedup_claimed=False)

def atomic(path, data):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    fd,temp=tempfile.mkstemp(prefix='.performance-',dir=path.parent)
    try:
        with os.fdopen(fd,'w',encoding='utf-8',newline='') as out:out.write(data)
        os.replace(temp,path)
    finally:
        if os.path.exists(temp):os.unlink(temp)

def publish(prefix):
    prefix=Path(prefix);outputs=[Path(str(prefix)+s) for s in ('.inspection.json','.review.html','.samples.csv')]
    for p in outputs:p.unlink(missing_ok=True)
    raw=json.loads(Path(str(prefix)+'.diagnostic.json').read_text(),parse_constant=lambda x:(_ for _ in ()).throw(ValueError('nonfinite JSON')))
    result=validate(raw,prefix.parent)
    buf=io.StringIO();writer=csv.writer(buf)
    writer.writerow(['run','backend','workload','phase','sample','duration_ms'])
    # CSV retains individual observations, never just summary averages.
    if raw['kind']=='performance':
        for s in raw['scenes']:
            for group in ('authoring_recording','sksl_effect_construction','cpu_raster','warmup_replay','warm_replay','upload','readback'):
                for i,row in enumerate(s[group]):
                    fields=('draw_ms','flush_ms','submit_ms','completion_wait_ms','completed_ms') if group in ('warmup_replay','warm_replay','upload') else ('elapsed_ms',)
                    for field in fields:writer.writerow([raw['validation_run'],raw['backend'],s['name'],group+'/'+field,i,row[field]])
            for field in ('draw_ms','flush_ms','submit_ms','completion_wait_ms','completed_ms'):
                writer.writerow([raw['validation_run'],raw['backend'],s['name'],'first_use/'+field,0,s['first_use'][field]])
    else:
        for w in raw['windows']:
            for i,row in enumerate(w['frames']):
                for phase,value in [('presenter-call',row['elapsed_ms']),('callback',row['callback']['elapsed_ms'])]:
                    writer.writerow([raw['validation_run'],raw['backend'],f"{w['cycle']}/{w['window']}",phase,i,value])
    esc=lambda x:html.escape(str(x),quote=True)
    rows=''.join('<tr>'+''.join('<td>'+esc(s[k])+'</td>' for k in ('workload','phase','count','median','p95','min','max'))+'</tr>' for s in result['statistics'])
    images=''
    if raw['kind']=='performance':
        images=''.join(f'<h2>{esc(s["name"])}</h2><img width="420" src="{esc(s["cpu_image"])}" alt="CPU"><img width="420" src="{esc(s["gpu_image"])}" alt="GPU">' for s in raw['scenes'])
    first=(raw['scenes'][0] if raw['kind']=='performance' else raw['windows'][0])['initial_context']
    page=f'''<!doctype html><meta charset="utf-8"><title>Skia 0.45 {esc(raw['kind'])}</title>
<style>body{{font:16px system-ui;max-width:1250px;margin:35px auto;padding:0 20px}}table{{border-collapse:collapse;width:100%}}td,th{{padding:7px;border-bottom:1px solid #ddd;text-align:left}}img{{max-width:48%;height:auto;border:1px solid #ddd}}pre{{white-space:pre-wrap}}</style>
<h1>0.45 — {esc(raw['backend'])} {esc(raw['kind'])}</h1>
<p>{esc(first['renderer'])} · {esc(first['renderer_class'])} · {esc(first['api_version'])} · Skia {esc(first['native_version'])} · {esc(raw['os'])}/{esc(raw['architecture'])} · Racket {esc(raw['racket_version'])}</p>
<p><strong>Measured host latency, not isolated GPU timestamps or display latency.</strong> No performance ranking is inferred. First-use means a new Ganesh context, not cold OS/driver caches. Completion-only, transfer, CPU raster and window workloads are different measurements.</p>
<p>Cache envelopes cover budgeted Ganesh resources and live wrapper counts, not total VRAM or process RSS. Checkpoint waits/purges and GC are outside normal-frame timing. Physical screen inspection is separate.</p>
<pre>{esc(json.dumps(raw['config'],indent=2))}</pre><p>Raw observations: <a href="{esc(outputs[2].name)}">CSV</a>; <a href="{esc(prefix.name+'.diagnostic.json')}">complete JSON</a>.</p>
<table><thead><tr><th>Workload</th><th>Phase</th><th>N</th><th>Median ms</th><th>P95 ms</th><th>Min ms</th><th>Max ms</th></tr></thead><tbody>{rows}</tbody></table>{images}'''
    try:
        atomic(outputs[2],buf.getvalue());atomic(outputs[1],page)
        # Success marker LAST, after data and review are available.
        atomic(outputs[0],json.dumps(result,indent=2,allow_nan=False)+'\n')
    except BaseException:
        for p in outputs:p.unlink(missing_ok=True)
        raise
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--probe-prefix',type=Path);parser.add_argument('--self-test',action='store_true');args=parser.parse_args()
    if args.self_test:
        import runpy
        runpy.run_path(str(HERE/'test-gpu-performance-inspector.py'),run_name='__main__');return 0
    if not args.probe_prefix:parser.error('--probe-prefix is required')
    try:print(json.dumps(publish(args.probe_prefix),indent=2));return 0
    except (OSError,ValueError,KeyError,TypeError,IndexError) as e:
        print('Performance inspection FAILED:',e);return 1
if __name__=='__main__':raise SystemExit(main())
