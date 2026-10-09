"""Independent 0.77c evidence inspection; no native calls or GPU initialization.

GPU dump records are not summed into VRAM/process memory. Overlapping attributes
(e.g. size and purgeable_size) are retained as individual observations.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re

PURE_CASES = 38
NATIVE_CASES = 13
GPU_CASES = 20
SIZE = (32, 24)
GPU_SCOPE = 'gpu-context-skia-resources'
GLOBAL_SCOPE = 'process-global-skia-caches'
MAX_JSON = 16 * 1024 * 1024
LABELS = (
 'create a real context and allocated surface',
 'light GPU report contains native resource sizes',
 'detailed report uses the same bounded collector',
 'dump-wrapped option remains explicit',
 'entry limit reports dropped records',
 'string budget cannot silently shorten a resource name',
 'total byte budget is separate from entry count',
 'global and GPU reports coexist without provider replacement',
 'diagnostic queries leave limits and pixels intact',
 'snapshot stays immutable across subsequent allocation and GC',
 'inactive GPU diagnostic access is rejected',
 'foreign Racket owner is rejected',
 'live port service cannot enter the native diagnostic collector',
 'invalid limits and extension names fail before native entry',
 'selected backend interface contract is explicit',
 'explicit assembly routes render or reject non-GL selection',
 'incompatible GLES WebGL factories fail without a standard fallback',
 'healthy abandonment invalidates live diagnostic access',
 'children retire before final close and saved diagnostics survive',
 'fresh context after cleanup still diagnoses and renders',
)
TRACE_NAMES = ('light', 'detailed', 'wrapped', 'zero-entries', 'zero-strings',
               'zero-bytes', 'after-global', 'extra-resource')
GL_TRACE_NAMES = ('gl-info', 'gl-present', 'gl-absent', 'auto', 'desktop')

def need(ok, message):
    if not ok:
        raise ValueError(message)

def integer(value, minimum=0, maximum=(1 << 64)-1):
    return type(value) is int and minimum <= value <= maximum

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'duplicate JSON key: '+key)
        result[key] = value
    return result

def read_json(path):
    path = Path(path)
    need(path.is_file() and not path.is_symlink(), 'missing/symlink receipt')
    need(path.stat().st_size <= MAX_JSON, 'oversized receipt')
    def nonfinite(v):
        raise ValueError('nonfinite JSON: '+v)
    data = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_object,
                      parse_constant=nonfinite)
    need(type(data) is dict, 'receipt must be an object')
    return data

def safe_file(root, name):
    need(type(name) is str and bool(name), 'missing artifact name')
    need(not name.startswith('/') and '\\' not in name and ':' not in name
         and all(c not in ('', '.', '..') for c in name.split('/'))
         and all(ord(c) >= 32 for c in name), 'unsafe artifact path')
    root = Path(root).resolve()
    path = root.joinpath(*name.split('/'))
    cursor = path
    while cursor != root:
        need(not cursor.is_symlink(), 'symlink artifact')
        cursor = cursor.parent
    need(path.resolve().is_relative_to(root) and path.is_file(), 'missing/outside artifact')
    return path

def suite_output(text, suite, count):
    normalized = text.replace('\r\n', '\n')
    ends = re.findall(r'^'+re.escape(suite)+r': (\d+) cases, (\d+) failures\s*$', normalized, re.M)
    need(ends == [(str(count), '0')], 'missing/duplicate/failed '+suite+' completion')
    totals = re.findall(r'(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run', normalized)
    need(totals == [(str(count), '0', '0', str(count))], 'wrong '+suite+' RackUnit results')
    need(not re.search(r'^\s*(?:FAILURE|ERROR|FAIL:|ERROR:)(?:\s|$)', normalized, re.M), 'RackUnit failure text')

def pixels():
    out = bytearray()
    for y in range(SIZE[1]):
        for x in range(SIZE[0]):
            rgb = ((229,41,53) if 2 <= x < 13 and 3 <= y < 10 else
                   (11,179,67) if 15 <= x < 28 and 10 <= y < 20 else (17,34,51))
            out.extend((*rgb, 255))
    return bytes(out)

def memory_report(report, *, scope=GPU_SCOPE, detailed=False, wrapped=False, truncated=False,
                  require_resource=True):
    need(type(report) is dict, 'memory report missing')
    need(set(report) == {'scope','atomic','detailed','dump_wrapped','truncated','dropped_count','string_bytes','entries'},
         'unexpected memory-report fields')
    need(report['scope'] == scope and report['atomic'] is False, 'wrong memory scope/atomic claim')
    need(report['detailed'] is detailed and report['dump_wrapped'] is wrapped, 'wrong capture options')
    need(report['truncated'] is truncated, 'wrong truncation status')
    need(integer(report['dropped_count']) and integer(report['string_bytes'], 0, 1048576), 'invalid bounds counters')
    need((report['dropped_count'] > 0) is truncated, 'inconsistent dropped records')
    rows = report['entries']
    need(type(rows) is list and len(rows) <= 4096, 'invalid entry list/count')
    if truncated:
        need(rows == [] and report['string_bytes'] == 0, 'zero-cap capture retained records')
    strings = 0
    resource_sizes = []
    for row in rows:
        need(type(row) is dict and set(row)=={'kind','name','value_name','units','value'}, 'invalid memory record')
        for name in ('name','value_name'):
            need(type(row[name]) is str and '\0' not in row[name], 'invalid native text')
        need(row['kind'] in ('numeric','string'), 'invalid statistic kind')
        if row['kind'] == 'numeric':
            need(type(row['units']) is str and '\0' not in row['units'] and integer(row['value']), 'invalid numeric statistic')
            text = [row['name'], row['value_name'], row['units']]
            if (row['name'].startswith('skia/gpu_resources/resource_') and row['value_name']=='size'
                and row['units']=='bytes'):
                resource_sizes.append(row['value'])
        else:
            need(row['units'] is False and type(row['value']) is str and '\0' not in row['value'], 'invalid string statistic')
            text = [row['name'], row['value_name'], row['value']]
        lengths = [len(v.encode('utf-8')) for v in text]
        need(all(n <= 4096 for n in lengths), 'native string exceeds limit')
        strings += sum(lengths)
    need(strings == report['string_bytes'], 'string-byte accounting differs')
    if require_resource and not truncated:
        need(any(n >= SIZE[0]*SIZE[1]*4 for n in resource_sizes), 'no native allocated GPU resource size')
    if scope == GLOBAL_SCOPE:
        need(any(r['name']=='skia/sk_glyph_cache' and r['kind']=='numeric' and r['value_name']=='size' for r in rows),
             'missing global native glyph-cache observation')
    return {'entries':len(rows),'scope':scope,'truncated':truncated,
            'string_bytes':strings,'numeric_resource_sizes_observed':len(resource_sizes)}

def inspect(path, token, backend, adapter):
    path=Path(path); data=read_json(path)
    need(type(token) is str and bool(token), 'empty invocation token')
    need(backend in ('egl','metal','direct3d') and adapter in ('hardware','warp'), 'invalid selected backend/adapter')
    need(integer(data.get('schema'),1,1) and data.get('stage')=='0.77c', 'wrong receipt schema/stage')
    need(data.get('status')=='passed' and data.get('run_token')==token, 'failed/stale receipt')
    need(data.get('native_version')=='119.0' and data.get('backend')==backend and data.get('adapter')==adapter, 'wrong native/backend identity')
    need(data.get('gpu_executed') is True, 'GPU execution missing')
    for field in ('driver_memory_measured','process_memory_measured','gles_rendering_executed','webgl_rendering_executed'):
        need(data.get(field) is False, 'unsupported execution/accounting claim: '+field)
    need(integer(data.get('cases'),GPU_CASES,GPU_CASES) and integer(data.get('failures'),0,0), 'wrong native test completion')
    need(data.get('labels')==list(LABELS) and data.get('cleanup_errors')==[], 'native test coverage/cleanup failed')
    reports=data.get('reports')
    expected={'cache_before','cache_after','light','detailed','wrapped','zero_entries','zero_strings','zero_bytes','global','extra'}
    need(type(reports) is dict and set(reports)==expected, 'missing/extra diagnostic captures')
    inspected={}
    for key in ('light','detailed','wrapped','zero_entries','zero_strings','zero_bytes','extra','global'):
        inspected[key]=memory_report(reports[key],scope=GLOBAL_SCOPE if key=='global' else GPU_SCOPE,
          detailed=key=='detailed',wrapped=key=='wrapped',truncated=key.startswith('zero_'),
          require_resource=key!='global')
    native_backend='opengl' if backend=='egl' else backend
    for key in ('cache_before','cache_after'):
        r=reports[key]
        need(type(r) is dict and r.get('backend')==native_backend, 'wrong cache backend')
        need(integer(r.get('context_generation'),1), 'missing cache generation')
        for f in ('limit_bytes','budgeted_resources','budgeted_bytes'):
            need(integer(r.get(f)), 'invalid cache counter '+f)
        need(r.get('total_gpu_bytes') is False and r.get('limit_is_hard_allocation_cap') is False,
             'budgeted cache presented as total GPU memory')
    need(reports['cache_before']['context_generation']==reports['cache_after']['context_generation'], 'cache context changed')
    need(reports['cache_before']['limit_bytes']==reports['cache_after']['limit_bytes'], 'diagnostics mutated cache policy')
    traces=data.get('diagnostic_traces')
    names=list(TRACE_NAMES)+(list(GL_TRACE_NAMES) if backend=='egl' else [])
    need(type(traces) is list and len(traces)==len(names), 'missing diagnostic traces')
    need([t.get('name') for t in traces if type(t) is dict]==names, 'wrong trace names/order')
    for trace in traces:
        need(set(trace)=={'name','events'} and trace['events']==[], 'hidden GPU I/O/cache mutation in diagnostic')
    captures=data.get('captures')
    names=['before','after']+(['auto','desktop'] if backend=='egl' else [])+['after-close']
    need(type(captures) is list and len(captures)==len(names), 'wrong pixel capture count')
    need([r.get('name') for r in captures if type(r) is dict]==names, 'missing/duplicate capture')
    hashes={}
    for row in captures:
        need(integer(row.get('width'),SIZE[0],SIZE[0]) and integer(row.get('height'),SIZE[1],SIZE[1]), 'wrong pixel dimensions')
        need(row.get('file')==row['name']+'.rgba', 'unexpected capture path')
        p=safe_file(path.parent,row['file'])
        need(p.stat().st_size==SIZE[0]*SIZE[1]*4, 'wrong pixel byte count')
        raw=p.read_bytes(); need(raw==pixels(), 'GPU pixels changed or differ from reference')
        hashes[row['name']]=hashlib.sha256(raw).hexdigest()
    interfaces=data.get('interfaces')
    need(type(interfaces) is list, 'missing interface results')
    if backend=='egl':
        need([r.get('mode') for r in interfaces if type(r) is dict]==['default','auto','desktop'], 'missing GL factory coverage')
        extension=None
        for row in interfaces:
            name=row.get('extension')
            need(type(name) is str and re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,254}',name) is not None, 'invalid independent GL extension')
            if extension is None:extension=name
            need(name==extension and row.get('host_extension_present') is True and row.get('fabricated_extension_present') is False,
                 'GL extension observations disagree')
            info=row.get('info');need(type(info) is dict, 'missing retained interface metadata')
            need(info.get('requested')==row['mode'], 'wrong requested GL factory')
            need(info.get('factory')==('assembled-auto' if row['mode']=='auto' else 'assembled-desktop-gl'), 'wrong native GL factory')
            need(info.get('validated') is True and info.get('extension_source')=='context-owned-skia-interface', 'not the retained native interface')
    else:need(interfaces==[], 'non-GL backend claimed GL interface execution')
    life=data.get('lifecycle');need(type(life) is dict and set(life)=={'after_release','after_close'}, 'missing lifecycle evidence')
    for phase,state in (('after_release','abandoned'),('after_close','closed')):
        r=life[phase]
        need(type(r) is dict and r.get('state')==state and r.get('backend')==native_backend, 'wrong lifecycle state')
        need(r.get('generation')==reports['cache_before']['context_generation'] and integer(r.get('generation'),1), 'wrong lifecycle generation')
        for f in ('live_children','pending_releases','failed_releases'):
            need(integer(r.get(f)), 'invalid lifetime counter')
        need(r['failed_releases']==0, 'native release failed')
    need(life['after_release']['live_children']>=2, 'healthy abandonment was not tested with live children')
    need(life['after_close']['live_children']==0 and life['after_close']['pending_releases']==0, 'native children not retired')
    return {'status':'passed','stage':'0.77c','backend':backend,'cases':GPU_CASES,
            'memory_reports':inspected,'pixel_sha256':hashes,'gl_factories_executed': [r['mode'] for r in interfaces],
            'no_hidden_gpu_io':True,'driver_or_process_memory_measured':False,
            'gles_rendering_executed':False,'webgl_rendering_executed':False}
