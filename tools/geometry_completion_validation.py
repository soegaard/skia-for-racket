"""0.67 geometry evidence: vector structure, semantic pixels and explicit GPU receipts."""
from __future__ import annotations
import hashlib
import math
import re
from pathlib import Path
import xml.etree.ElementTree as ET
from effects_validation import need, read_json, evidence_file

SCENES = ('arc', 'tangent', 'boolean', 'outline', 'region', 'rrect', 'polygon')
BLUE=(0,64,220,255); RED=(220,32,16,255); GREEN=(0,160,80,255); WHITE=(255,255,255,255)
PROBES={
 'arc':((32,32,BLUE),(12,12,WHITE),(50,40,WHITE)),
 'tangent':((24,8,RED),(40,28,RED),(12,32,WHITE)),
 'boolean':((12,12,BLUE),(24,24,WHITE),(44,36,BLUE)),
 'outline':((32,24,RED),(8,24,RED),(32,10,WHITE)),
 'region':((18,16,BLUE),(34,16,WHITE),(44,16,BLUE)),
 'rrect':((32,24,GREEN),(13,9,WHITE),(58,24,WHITE)),
 'polygon':((32,16,RED),(8,32,WHITE),(56,40,WHITE)),
}

def integer(value, expected, description):
    need(type(value) is int and value == expected, description)

def pixel_checks(data: bytes, name: str, *, tolerance: int = 2):
    need(name in SCENES and len(data)==64*48*4,'invalid scene or pixel buffer')
    need(type(tolerance) is int and 0<=tolerance<=255,'invalid semantic-pixel tolerance')
    need(all(data[i]==255 for i in range(3,len(data),4)), 'reference/viewer background is not opaque')
    for x,y,color in PROBES[name]:
        at=4*(y*64+x)
        need(all(abs(a-b)<=tolerance for a,b in zip(data[at:at+4],color)),
             f'{name}: incorrect pixel at {x},{y}')

def receipt(row, name, fmt):
    need(isinstance(row,dict) and row.get('name')==name and row.get('format')==fmt,'foreign document')
    integer(row.get('callback_count'),1,'authoring did not execute exactly once')
    need(row.get('audit_policy')=='vector-only','vector-only audit not selected')
    audit=row.get('audit',{});group=row.get('group',{})
    need(isinstance(audit,dict) and audit.get('mode')=='export' and audit.get('backend')==fmt
         and audit.get('blocking') is False and audit.get('vector_only') is True, 'nonvector/failed audit')
    events=audit.get('events',[])
    need(isinstance(events,list) and events and all(isinstance(e,dict) and e.get('status')=='vector' for e in events),
         'unverified audit events')
    need(any(e.get('feature')=='geometry' for e in events), 'no geometry audit event')
    need(isinstance(group,dict) and group.get('backend')==fmt and group.get('policy')=='require-vector'
         and group.get('strategy')=='native' and group.get('pixel_size') is False
         and group.get('bounds')==[8,16,64,48], 'unexpected group representation/bounds')

def inspect_svg(path: Path, name: str):
    data=path.read_bytes()
    need(b'<!DOCTYPE' not in data.upper() and b'<!ENTITY' not in data.upper(),'DTD/entity outside fixture scope')
    root=ET.fromstring(data)
    local=lambda e:e.tag.rsplit('}',1)[-1]
    need(local(root)=='svg','not an SVG document')
    def points(text):
        # The exporter writes point dimensions; accept SVG's equivalent CSS
        # pixel spelling while rejecting percentages/unknown units.
        m=re.fullmatch(r'([+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))(pt|px)?',text or '')
        need(m is not None,'missing/nonabsolute SVG dimensions')
        value=float(m[1]);need(math.isfinite(value),'nonfinite SVG dimension')
        return value if m[2]=='pt' else value*0.75
    need(abs(points(root.get('width'))-96)<=1e-6 and abs(points(root.get('height'))-72)<=1e-6,
         'wrong SVG physical page size')
    if root.get('viewBox'):
        view=[float(v) for v in re.split(r'[ ,]+',root.get('viewBox').strip())]
        need(view==[0,0,96,72],'wrong SVG viewBox')
    need(not any(local(e) in ('image','foreignObject') for e in root.iter()), 'raster/foreign SVG fallback')
    shapes=[e for e in root.iter() if local(e) in ('path','rect','polygon','circle','ellipse','line','polyline')]
    need(len(shapes)>=3,'insufficient SVG geometry')
    link='https://example.invalid/geometry/'+name
    need(any(local(e)=='a' and (e.get('href') or e.get('{http://www.w3.org/1999/xlink}href'))==link
             for e in root.iter()),'missing SVG annotation')
    return {'embedded_images':0,'vector_shapes':len(shapes),'link_verified':True}

def inspect_pdf(path: Path, name: str):
    from pypdf import PdfReader
    from pypdf.generic import ContentStream
    reader=PdfReader(path,strict=True)
    need(not reader.is_encrypted and len(reader.pages)==1,'unexpected PDF encryption/page count')
    page=reader.pages[0]
    need([float(x) for x in page.mediabox]==[0,0,96,72],'wrong MediaBox')
    segments=0;paints=0
    def inspect_resources(resources, seen=None, depth=0):
        seen=set() if seen is None else seen
        need(depth<16,'resource nesting exceeds fixture bound')
        xobjects=resources.get('/XObject',{})
        if hasattr(xobjects,'get_object'):xobjects=xobjects.get_object()
        for ref in xobjects.values():
            obj=ref.get_object()
            need(obj.get('/Subtype')!='/Image','PDF raster fallback resource')
            ident=id(obj)
            if obj.get('/Subtype')=='/Form' and ident not in seen:
                seen.add(ident)
                inspect_resources(obj.get('/Resources',resources).get_object(),seen,depth+1)
    def walk(stream, resources, active=None, depth=0):
        nonlocal segments,paints
        active=set() if active is None else active
        need(depth<16,'form nesting exceeds fixture bound')
        for operands,op in ContentStream(stream,reader).operations:
            if op in (b'm',b'l',b'c',b're',b'v',b'y'): segments+=1
            if op in (b'f',b'f*',b'F',b'S',b's',b'B',b'B*',b'b',b'b*'): paints+=1
            need(op!=b'INLINE IMAGE','inline raster fallback')
            if op==b'Do':
                obj=resources['/XObject'].get_object()[operands[0]].get_object()
                need(obj.get('/Subtype')=='/Form','invoked non-vector XObject')
                ident=id(obj);need(ident not in active,'cyclic PDF form')
                walk(obj,obj.get('/Resources',resources).get_object(),active|{ident},depth+1)
    resources=page['/Resources'].get_object()
    inspect_resources(resources)
    walk(page.get_contents(),resources)
    need(segments>=3 and paints>=3,'insufficient painted PDF paths')
    url='https://example.invalid/geometry/'+name
    actions=[a.get_object()['/A'].get_object() for a in page.get('/Annots',[]) if '/A' in a.get_object()]
    need(any(a.get('/URI')==url for a in actions),'missing PDF annotation')
    return {'embedded_images':0,'path_segments':segments,'painted_paths':paints,'link_verified':True}

def inspect_render(path: Path, name: str, reference: bytes):
    from PIL import Image
    with Image.open(path) as im:
        need(im.size==(96,72),'wrong rendered page dimensions')
        im=im.convert('RGBA')
        need(all(abs(x-y)<=2 for x,y in zip(im.getpixel((4,4)),(0,255,0,255))), 'vector marker missing')
        actual=im.crop((8,16,72,64)).tobytes()
        # Independent PDF/SVG viewers antialias vector edges even when the
        # direct Skia raster reference was authored with antialiasing disabled.
        # Keep direct-reference probes strict, but allow modest edge coverage
        # here; the global divergence checks below still reject missing/wrong
        # geometry, and a filled rrect corner remains far outside this tolerance.
        pixel_checks(actual,name,tolerance=32)
        # Bounded edge rasterization differences; interior semantic probes are
        # tested separately, so a missing shape cannot pass just by being small.
        errors=[abs(a-b) for i,(a,b) in enumerate(zip(actual,reference)) if i%4!=3]
        mean=sum(errors)/len(errors);fraction=sum(v>32 for v in errors)/len(errors)
        need(mean<=5 and fraction<=0.06,f'{name}: viewer divergence mean={mean:.3f}, fraction={fraction:.3f}')
        for y in range(72):
            for x in range(96):
                if (1<=x<=7 and 1<=y<=7) or (7<=x<=73 and 15<=y<=65):continue
                need(im.getpixel((x,y))==WHITE,'paint escaped the scene boundary')
    return {'mean_channel_error':mean,'fraction_channel_errors_over_32':fraction,'semantic_probes_passed':True}

def inspect_documents(directory: Path, token: str, *, render=None):
    data=read_json(directory/'documents.json')
    integer(data.get('schema'),1,'wrong schema')
    need(data.get('stage')=='0.67' and data.get('run_token')==token and data.get('status')=='passed', 'foreign/failed document gate')
    rows=data.get('documents');need(isinstance(rows,list) and len(rows)==len(SCENES)*2,'incomplete document matrix')
    expected={(n,f) for n in SCENES for f in ('pdf','svg')};seen=set();results=[]
    for row in rows:
        need(isinstance(row,dict),'non-object document row')
        key=(row.get('name'),row.get('format'));need(key in expected and key not in seen,'duplicate/foreign scene')
        seen.add(key);name,fmt=key;receipt(row,name,fmt)
        need(row.get('file')==f'{name}.{fmt}' and row.get('rgba')==f'{name}.rgba','foreign filenames')
        doc=evidence_file(directory,row['file']);ref=evidence_file(directory,row['rgba']).read_bytes()
        pixel_checks(ref,name)
        item=(inspect_pdf if fmt=='pdf' else inspect_svg)(doc,name)
        item.update(name=name,format=fmt,sha256=hashlib.sha256(doc.read_bytes()).hexdigest())
        if render:item.update(inspect_render(render(doc,fmt),name,ref))
        results.append(item)
    need(seen==expected,'missing scene')
    return {'schema':1,'stage':'0.67','status':'passed','run_token':token,'documents':results,
            'independent_rendering_executed':render is not None}

def gpu_receipt(path: Path, token: str, backend: str, adapter: str):
    r=read_json(path)
    integer(r.get('schema'),1,'wrong GPU schema')
    need(r.get('stage')=='0.67' and r.get('run_token')==token and r.get('status')=='passed','foreign/failed GPU run')
    need(r.get('backend')==backend and r.get('adapter')==adapter,'backend/adapter mismatch')
    for key,expected in [('failures',0),('frames',len(SCENES)),('drawing_readbacks',0),('inspection_readbacks',len(SCENES)),
                         ('reset_drawing_readbacks',0),('reset_inspection_readbacks',1)]:
        integer(r.get(key),expected,'invalid '+key)
    need(r.get('scenes')==list(SCENES),'incomplete/reordered GPU scenes')
    need(r.get('reset_transfer_test_passed') is True and r.get('contexts_closed') is True, 'reset/cleanup failed')
    need(r.get('gui_executed') is False and r.get('physical_display_verified') is False,'unverified display claim')
    return r
