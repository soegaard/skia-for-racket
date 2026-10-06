"""Independent 0.69 receipt, geometry, pixel and PDF/SVG inspection.

The fixture geometry below is not read from the Racket-generated reference.
Native execution and independent viewer execution are reported separately.
"""
from __future__ import annotations
from bisect import bisect_left
from functools import lru_cache
import json
import math
from pathlib import Path
import re
import xml.etree.ElementTree as ET

WIDTH, HEIGHT = 192, 128
BLUE, WHITE, GREEN = (24, 64, 192, 255), (255, 255, 255, 255), (0, 255, 0, 255)
SCENES = ('multi', 'transformed', 'curve')
SPECS = (('multi', 'pdf', 'native'),) + tuple((scene, fmt, 'outline') for scene in SCENES for fmt in ('pdf', 'svg'))
GPU_SPECS = tuple((scene, mode) for scene in SCENES for mode in ('native', 'outline'))

def need(ok, message):
    if not ok: raise ValueError(message)

def read_json(path: Path):
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 4 * 1024 * 1024, 'missing/oversized JSON')
    def pairs(items):
        out = {}
        for k, v in items:
            need(k not in out, 'duplicate JSON key'); out[k] = v
        return out
    def invalid(v): raise ValueError('nonfinite JSON value: ' + v)
    value = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=pairs, parse_constant=invalid)
    need(type(value) is dict, 'JSON object required')
    return value

def evidence_file(directory: Path, name: str):
    need(type(name) is str and re.fullmatch(r'[A-Za-z0-9_-]+\.(rgba|pdf|svg|png)', name), 'unsafe evidence filename')
    p = directory / name
    need(not p.is_symlink() and p.is_file() and p.stat().st_size <= 16 * 1024 * 1024, 'missing/oversized evidence file')
    return p

def transformed(poly, cs):
    c, s, tx, ty = cs
    return tuple((c*x-s*y+tx, s*x+c*y+ty) for x, y in poly)

RECT = ((0., 0.), (16., 0.), (16., -28.), (0., -28.))
VEE = ((0., -28.), (8., 0.), (16., -28.))
CUBIC = ((55., 105.), (75., 35.), (140., 35.), (165., 105.))

def cubic(t):
    a, b, c, d = CUBIC; u=1-t
    return tuple(u**3*a[i] + 3*u*u*t*b[i] + 3*u*t*t*c[i] + t**3*d[i] for i in range(2))

def derivative(t):
    a,b,c,d=CUBIC;u=1-t
    return tuple(3*u*u*(b[i]-a[i])+6*u*t*(c[i]-b[i])+3*t*t*(d[i]-c[i]) for i in range(2))

@lru_cache(maxsize=1)
def curve_lengths():
    count=8192; lengths=[0.];last=cubic(0)
    for i in range(1,count+1):
        p=cubic(i/count); lengths.append(lengths[-1]+math.hypot(p[0]-last[0],p[1]-last[1]));last=p
    return tuple(lengths)

def curve_frame(distance):
    lengths=curve_lengths();i=bisect_left(lengths,distance)
    need(0<i<len(lengths),'fixture distance outside curve')
    t=(i-1+(distance-lengths[i-1])/(lengths[i]-lengths[i-1]))/(len(lengths)-1)
    x,y=cubic(t);dx,dy=derivative(t);n=math.hypot(dx,dy)
    return dx/n,dy/n,x,y

@lru_cache(maxsize=3)
def polygons(scene):
    need(scene in SCENES,'foreign scene')
    if scene=='multi':
        bold_vee=((0.,-28.),(12.,0.),(24.,-28.))
        return (transformed(RECT,(1,0,20,70)), transformed(bold_vee,(1,0,60,70)), transformed(RECT,(1,0,100,70)))
    if scene=='transformed':
        return (transformed(RECT,(0,1,24,36)), transformed(VEE,(1,0,75,75)), transformed(RECT,(.5,0,120,65)))
    # The original fixture has 600-unit advances at 40 units and no AA kerning.
    return tuple(transformed(RECT,curve_frame(d)) for d in (10.,34.,58.))

def inside(point, poly):
    x,y=point; odd=False
    for a,b in zip(poly,poly[1:]+poly[:1]):
        if (a[1]>y)!=(b[1]>y) and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]: odd=not odd
    return odd

def edge_distance(point, poly):
    x,y=point;result=math.inf
    for a,b in zip(poly,poly[1:]+poly[:1]):
        vx,vy=b[0]-a[0],b[1]-a[1];den=vx*vx+vy*vy
        t=max(0.,min(1.,((x-a[0])*vx+(y-a[1])*vy)/den)) if den else 0.
        result=min(result,math.hypot(x-a[0]-t*vx,y-a[1]-t*vy))
    return result

@lru_cache(maxsize=3)
def safe_probes(scene):
    ps=polygons(scene);ink=[[] for _ in ps];blank=[]
    for y in range(HEIGHT):
        for x in range(WIDTH):
            point=(x+.5,y+.5)
            if any(edge_distance(point,p)<=2.25 for p in ps):continue
            hits=[i for i,p in enumerate(ps) if inside(point,p)]
            if hits:
                for i in hits:ink[i].append(4*(WIDTH*y+x))
            elif not (0<=x<9 and 0<=y<9):blank.append(4*(WIDTH*y+x))
    need(all(len(p)>=8 for p in ink),'insufficient independent fixture interior')
    return tuple(tuple(p) for p in ink),tuple(blank)

def pixel_checks(data: bytes, scene: str, tolerance=8):
    need(len(data)==WIDTH*HEIGHT*4, 'incorrect pixel dimensions')
    need(all(a==255 for a in data[3::4]), 'nonopaque background')
    def wrong(at, color):return any(abs(a-b)>tolerance for a,b in zip(data[at:at+4],color))
    need(not wrong(4*(WIDTH*4+4),GREEN),'vector marker missing')
    ink,blank=safe_probes(scene)
    for i,sites in enumerate(ink):
        bad=sum(wrong(at,BLUE) for at in sites)
        need(bad<=max(1,int(len(sites)*.01)), f'{scene}: glyph {i} misplaced/missing ({bad}/{len(sites)} interior probes)')
    bad=sum(wrong(at,WHITE) for at in blank)
    need(bad<=3,f'{scene}: unexpected ink outside glyph contours ({bad} probes)')
    return dict(interior_probes=[len(p) for p in ink], background_probes=len(blank))

def receipt(row, spec):
    scene,fmt,mode=spec
    need(type(row) is dict and (row.get('scene'),row.get('format'),row.get('text_mode'))==spec,'foreign document')
    need(type(row.get('callback_count')) is int and row['callback_count']==1,'authoring count changed')
    need(type(row.get('run_count')) is int and row['run_count']==(3 if scene=='multi' else 1),'retained run count changed')
    stem='-'.join(spec)
    need(row.get('file')==stem+'.'+fmt and row.get('rgba')==stem+'.rgba','foreign document filenames')
    audit=row.get('audit',{})
    need(type(audit) is dict and audit.get('mode')=='export' and audit.get('backend')==fmt
         and audit.get('blocking') is False and audit.get('vector_only') is True,'not a successful vector export')
    events=audit.get('events',[])
    need(type(events) is list and events and all(type(e) is dict and e.get('status')=='vector' for e in events),'nonvector audit events')
    features={e.get('feature') for e in events}
    need({'geometry','annotation'}<=features,'marker or link audit missing')
    need(('native-text' in features)==(mode=='native'),'native/outline text representation mismatch')

def inspect_svg(path,scene):
    raw=path.read_bytes()
    need(b'<!DOCTYPE' not in raw.upper() and b'<!ENTITY' not in raw.upper(),'DTD/entities not permitted')
    root=ET.fromstring(raw);local=lambda e:e.tag.rsplit('}',1)[-1]
    need(local(root)=='svg','not an SVG document')
    def points(value):
        m=re.fullmatch(r'(\d+(?:\.\d+)?)(pt|px)?',value or '')
        need(m is not None,'SVG dimensions not absolute')
        return float(m[1])*(1 if m[2]=='pt' else .75)
    need(abs(points(root.get('width'))-WIDTH)<1e-6 and abs(points(root.get('height'))-HEIGHT)<1e-6,'SVG physical size mismatch')
    need(not any(local(e) in ('image','text','foreignObject') for e in root.iter()),'SVG is not vector outlines')
    shapes=sum(local(e) in ('path','rect','polygon') for e in root.iter())
    need(shapes>=3,'SVG drawing missing')
    need(any(local(e)=='a' and (e.get('href') or e.get('{http://www.w3.org/1999/xlink}href'))==
             'https://example.invalid/text-blob/'+scene for e in root.iter()),'SVG annotation missing')
    return dict(vector_shapes=shapes,embedded_images=0,native_text=False)

def inspect_pdf(path,scene,mode):
    from pypdf import PdfReader
    from pypdf.generic import ContentStream
    reader=PdfReader(path,strict=True)
    need(not reader.is_encrypted and len(reader.pages)==1,'invalid PDF page count/encryption')
    page=reader.pages[0];need([float(x) for x in page.mediabox]==[0,0,WIDTH,HEIGHT],'PDF dimensions mismatch')
    fonts=[];text_ops=0;paint_ops=0
    def obj(value):return value.get_object() if hasattr(value,'get_object') else value
    def resources(res,active=frozenset(),depth=0):
        need(depth<16,'PDF resource depth exceeded');res=obj(res)
        fonts.extend(obj(f) for f in obj(res.get('/Font',{})).values())
        for ref in obj(res.get('/XObject',{})).values():
            x=obj(ref);need(x.get('/Subtype')!='/Image','PDF contains an embedded raster')
            if x.get('/Subtype')=='/Form':
                need(id(x) not in active,'cyclic PDF form resources')
                resources(x.get('/Resources',res),active|{id(x)},depth+1)
    def walk(stream,res,active=frozenset(),depth=0):
        nonlocal text_ops,paint_ops
        need(depth<16,'PDF form depth exceeded');res=obj(res)
        for vals,op in ContentStream(stream,reader).operations:
            need(op!=b'INLINE IMAGE','PDF contains inline raster data')
            if op in (b'Tj',b'TJ',b"'",b'"'):text_ops+=1
            if op in (b'f',b'f*',b'F',b'S',b's',b'B',b'B*'):paint_ops+=1
            if op==b'Do':
                x=obj(obj(res['/XObject'])[vals[0]])
                need(x.get('/Subtype')=='/Form' and id(x) not in active,'nonvector or cyclic PDF form')
                walk(x,x.get('/Resources',res),active|{id(x)},depth+1)
    res=obj(page['/Resources']);resources(res);walk(page.get_contents(),res)
    need(paint_ops>=2,'PDF marker/background missing')
    extracted=''.join(page.extract_text().split())
    def embedded(font,depth=0):
        need(depth<8,'PDF font depth exceeded')
        descriptor=obj(font.get('/FontDescriptor',{}))
        if any(k in descriptor and len(obj(descriptor[k]).get_data())>0 for k in ('/FontFile','/FontFile2','/FontFile3')):return True
        return any(embedded(obj(f),depth+1) for f in obj(font.get('/DescendantFonts',[])))
    if mode=='native':
        need(scene=='multi' and extracted=='AVA' and text_ops>0,'native multi-run PDF text was not preserved')
        need(sum(embedded(f) for f in fonts)>=2,'distinct native fixture fonts were not embedded')
    else:
        need(text_ops==0 and extracted=='' and paint_ops>=3,'PDF did not preserve vector outlines')
    link='https://example.invalid/text-blob/'+scene
    need(any(obj(a).get('/A') and obj(obj(a)['/A']).get('/URI')==link for a in obj(page.get('/Annots',[]))), 'PDF annotation missing')
    return dict(text_operations=text_ops,paint_operations=paint_ops,extracted=extracted,embedded_images=0,native_text=(mode=='native'))

def inspect_render(path,scene,reference):
    from PIL import Image
    with Image.open(path) as image:
        need(image.size==(WIDTH,HEIGHT),'independent renderer dimensions mismatch')
        data=image.convert('RGBA').tobytes()
    checks=pixel_checks(data,scene,tolerance=24)
    errors=[abs(a-b) for i,(a,b) in enumerate(zip(data,reference)) if i%4!=3]
    mean=sum(errors)/len(errors);fraction=sum(v>32 for v in errors)/len(errors)
    need(mean<=5 and fraction<=.06,f'independent renderer divergence: mean={mean}, fraction={fraction}')
    return dict(**checks,mean_rgb_error=mean,large_error_fraction=fraction)

def inspect_documents(directory,token,*,render=None):
    value=read_json(directory/'documents.json')
    need(type(value.get('schema')) is int and value['schema']==1 and value.get('stage')=='0.69'
         and value.get('run_token')==token and value.get('status')=='passed','stale/incomplete document receipt')
    for key in ('source_owners_closed','rendering_executed'):need(value.get(key) is True,'missing evidence: '+key)
    for key in ('gpu_executed','gui_executed'):need(value.get(key) is False,'unexecuted capability claim: '+key)
    rows=value.get('documents');need(type(rows) is list and len(rows)==len(SPECS),'incomplete document matrix')
    indexed={(r.get('scene'),r.get('format'),r.get('text_mode')):r for r in rows if type(r) is dict}
    need(set(indexed)==set(SPECS),'duplicate/foreign document specifications')
    reports=[]
    for spec in SPECS:
        row=indexed[spec];scene,fmt,mode=spec;receipt(row,spec)
        file=evidence_file(directory,row['file']);reference=evidence_file(directory,row['rgba']).read_bytes()
        pixels=pixel_checks(reference,scene)
        report=inspect_pdf(file,scene,mode) if fmt=='pdf' else inspect_svg(file,scene)
        report.update(scene=scene,format=fmt,text_mode=mode,reference_pixels=pixels)
        if render:report['viewer']=inspect_render(render(file,fmt),scene,reference)
        reports.append(report)
    return dict(schema=1,stage='0.69',status='passed',documents=reports,independent_renderers_executed=render is not None)

def inspect_gpu(directory,token,backend,adapter):
    value=read_json(directory/'gpu.json')
    need(type(value.get('schema')) is int and value['schema']==1 and value.get('stage')=='0.69'
         and value.get('run_token')==token and value.get('status')=='passed','stale/incomplete GPU receipt')
    need(value.get('backend')==backend and value.get('adapter')==adapter,'foreign GPU backend/adapter')
    for key,expected in (('failures',0),('drawing_readbacks',0),('inspection_readbacks',len(GPU_SPECS))):
        need(type(value.get(key)) is int and value[key]==expected,'invalid GPU count: '+key)
    need(value.get('contexts_closed') is True,'GPU context did not close')
    need(value.get('gui_executed') is False and value.get('physical_display_verified') is False,'unsupported GPU display claim')
    rows=value.get('frames');need(type(rows) is list and len(rows)==len(GPU_SPECS),'incomplete GPU frame matrix')
    indexed={(r.get('scene'),r.get('text_mode')):r for r in rows if type(r) is dict}
    need(set(indexed)==set(GPU_SPECS),'duplicate/foreign GPU frames')
    for scene,mode in GPU_SPECS:
        row=indexed[scene,mode];need(row.get('file')==scene+'-'+mode+'.rgba','foreign GPU filename')
        pixel_checks(evidence_file(directory,row['file']).read_bytes(),scene)
    return dict(schema=1,stage='0.69',status='passed',backend=backend,adapter=adapter,frames=len(rows),
                drawing_readbacks=0,inspection_readbacks=len(rows),contexts_closed=True,physical_display_verified=False)
