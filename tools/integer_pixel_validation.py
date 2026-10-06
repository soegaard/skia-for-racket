"""0.70 independent pixel/document/receipt inspection; not native execution."""
from __future__ import annotations
import base64
import binascii
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

FORMATS = ('rgba-8888','bgra-8888','rgb-888x','alpha-8','gray-8','rgb-565','rgba-1010102')
WIDTH, HEIGHT = 80, 64
SPECS = tuple((f, out) for f in FORMATS for out in ('pdf','svg'))

def need(ok, message):
    if not ok: raise ValueError(message)

def read_json(path):
    path=Path(path)
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 4*1024*1024, 'invalid JSON file')
    def pairs(items):
        out={}
        for key,value in items:
            need(key not in out,'duplicate JSON key');out[key]=value
        return out
    def invalid(v): raise ValueError('nonfinite JSON: '+v)
    result=json.loads(path.read_text(encoding='utf-8'),object_pairs_hook=pairs,parse_constant=invalid)
    need(type(result) is dict,'JSON object required')
    return result

def evidence_file(directory,name):
    need(type(name) is str and re.fullmatch(r'[a-z0-9-]+\.(rgba|pdf|svg|png)',name),'unsafe filename')
    path=Path(directory)/name
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 16*1024*1024,'missing/oversized file')
    return path

def oracle_color(fmt,x,y):
    need(fmt in FORMATS,'unknown pixel format')
    if 2 <= x < 6 and 2 <= y < 6: return (0,255,0,255)
    if 8 <= x < 72 and 24 <= y < 56:
        col=(x-8)//16
        if fmt=='gray-8': return (85*col,)*3+(255,)
        if fmt=='alpha-8': return (255-85*col,)*3+(255,)
        return ((255,0,0,255),(0,255,0,255),(0,0,255,255),(255,255,255,255))[col]
    return (255,255,255,255)

def safe_probe(x,y):
    if 2 <= x < 6 and 2 <= y < 6: return x in (3,4) and y in (3,4)
    if 0 <= x < 8 and 0 <= y < 8:return False
    if 6 <= x < 74 and 22 <= y < 58:
        return 10 <= x < 70 and 26 <= y < 54 and 2 <= (x-8)%16 < 14
    return True

def pixel_checks(data,fmt,tolerance=2):
    need(fmt in FORMATS and isinstance(data,bytes) and len(data)==WIDTH*HEIGHT*4,'pixel shape or identity')
    need(all(data[n]==255 for n in range(3,len(data),4)),'nonopaque output background')
    checked=0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if not safe_probe(x,y):continue
            at=4*(y*WIDTH+x);expected=oracle_color(fmt,x,y)
            need(all(abs(a-b)<=tolerance for a,b in zip(data[at:at+4],expected)),f'{fmt}: wrong pixel {x},{y}')
            checked+=1
    return checked

def receipt(row,spec):
    fmt,kind=spec
    need(type(row) is dict and (row.get('source_format'),row.get('format'))==spec,'foreign document')
    need(row.get('conversion')=='explicit-rgba-nearest','implicit/unreported conversion')
    for key,n in (('image_width',64),('image_height',32),('callback_count',1)):
        need(type(row.get(key)) is int and row[key]==n,'wrong '+key)
    stem=fmt+'-'+kind
    need(row.get('file')==stem+'.'+kind and row.get('rgba')==stem+'.rgba','foreign filenames')
    need(row.get('audit_policy')=='error','weakened export policy')
    a=row.get('audit',{})
    need(type(a) is dict and a.get('mode')=='export' and a.get('backend')==kind
         and a.get('blocking') is False and a.get('vector_only') is False,'invalid export audit')
    events=a.get('events')
    need(type(events) is list and events and all(type(e) is dict for e in events),'invalid export events')
    need(all(e.get('status') in ('vector','embedded-raster') for e in events),'unexpected fallback')
    image_events=[e for e in events if e.get('feature')=='image']
    need(image_events and all(e.get('status')=='embedded-raster' for e in image_events),'image was not recorded as embedded raster')
    need(all(e.get('status')=='vector' for e in events if e.get('feature')!='image'),'non-image document content was not vector')
    need({'image','geometry','annotation'} <= {e.get('feature') for e in events},'missing image/marker/link evidence')

def inspect_svg(path,fmt):
    raw=Path(path).read_bytes()
    need(b'<!DOCTYPE' not in raw.upper() and b'<!ENTITY' not in raw.upper(),'DTD/entity forbidden')
    root=ET.fromstring(raw);local=lambda e:e.tag.rsplit('}',1)[-1]
    need(local(root)=='svg','not SVG')
    def points(s):
        m=re.fullmatch(r'(\d+(?:\.\d+)?)(pt|px)?',s or '')
        need(m is not None,'nonabsolute SVG extent')
        return float(m[1])*(1 if m[2]=='pt' else .75)
    need(abs(points(root.get('width'))-WIDTH)<1e-5 and abs(points(root.get('height'))-HEIGHT)<1e-5,'wrong SVG size')
    need(not any(local(e) in ('foreignObject','text') for e in root.iter()),'unexpected SVG content')
    images=[e for e in root.iter() if local(e)=='image']
    need(len(images)==1,'expected one explicitly authored raster image')
    href=images[0].get('href') or images[0].get('{http://www.w3.org/1999/xlink}href') or ''
    need(href.startswith('data:image/png;base64,'),'image must be embedded PNG')
    try:png=base64.b64decode(href.split(',',1)[1],validate=True)
    except (ValueError,binascii.Error) as error:raise ValueError('invalid embedded PNG') from error
    need(len(png)>=24 and png[:8]==b'\x89PNG\r\n\x1a\n' and png[12:16]==b'IHDR'
         and (int.from_bytes(png[16:20],'big'),int.from_bytes(png[20:24],'big'))==(64,32),
         'embedded PNG dimensions do not match declared image extent')
    need(float(images[0].get('width','0'))==64 and float(images[0].get('height','0'))==32,'image dimension drift')
    need(len([e for e in root.iter() if local(e) in ('rect','path','polygon')])>=2,'vector background/marker lost')
    url='https://example.invalid/integer-pixels/'+fmt
    need(any(local(e)=='a' and (e.get('href') or e.get('{http://www.w3.org/1999/xlink}href'))==url for e in root.iter()),'missing SVG link')
    return dict(embedded_images=1,image_dimensions=[64,32],vector_marker=True,link=True)

def inspect_pdf(path,fmt):
    from pypdf import PdfReader
    from pypdf.generic import ContentStream
    reader=PdfReader(path,strict=True)
    need(not reader.is_encrypted and len(reader.pages)==1,'wrong PDF page count/encryption')
    page=reader.pages[0]
    need(list(map(float,page.mediabox))==[0,0,WIDTH,HEIGHT],'PDF dimensions')
    paint_ops=0;image_ops=0;seen=set()
    def walk(stream,resources,depth=0):
        nonlocal paint_ops,image_ops
        need(depth<16,'PDF form recursion')
        for args,op in ContentStream(stream,reader).operations:
            need(op not in (b'INLINE IMAGE',b'Tj',b'TJ',b"'",b'"'),'unexpected text or inline image')
            if op in (b'f',b'f*',b'F',b'S',b's',b'B',b'B*'):paint_ops+=1
            if op==b'Do':
                obj=resources['/XObject'].get_object()[args[0]].get_object()
                if obj.get('/Subtype')=='/Image':
                    need((obj.get('/Width'),obj.get('/Height'))==(64,32),'full-page or wrong-size rasterization')
                    image_ops+=1
                    mask=obj.get('/SMask')
                    if mask:
                        mask=mask.get_object()
                        need((mask.get('/Width'),mask.get('/Height'))==(64,32),'wrong alpha mask size')
                else:
                    need(obj.get('/Subtype')=='/Form' and id(obj) not in seen,'cyclic/unknown PDF resource')
                    seen.add(id(obj));walk(obj,obj.get('/Resources',resources).get_object(),depth+1)
    walk(page.get_contents(),page['/Resources'].get_object())
    need(image_ops==1 and paint_ops>=2,'missing explicitly sized image or vector marker')
    url='https://example.invalid/integer-pixels/'+fmt
    need(any(a.get_object().get('/A') and a.get_object()['/A'].get_object().get('/URI')==url for a in page.get('/Annots',[])),'missing PDF link')
    return dict(embedded_image_draws=image_ops,image_dimensions=[64,32],paint_operations=paint_ops,link=True)

def inspect_render(path,fmt):
    from PIL import Image
    with Image.open(path) as im:
        need(im.size==(WIDTH,HEIGHT),'viewer dimensions')
        data=im.convert('RGBA').tobytes()
    return dict(independent_probes=pixel_checks(data,fmt,tolerance=12))

def inspect_documents(directory,token,*,render=None):
    directory=Path(directory);value=read_json(directory/'documents.json')
    need(type(value.get('schema')) is int and value['schema']==1 and value.get('stage')=='0.70'
         and value.get('status')=='passed' and value.get('run_token')==token,'stale/incomplete receipt')
    need(value.get('rendering_executed') is True and value.get('gpu_executed') is False
         and value.get('gui_executed') is False,'false execution claims')
    rows=value.get('documents')
    need(type(rows) is list and len(rows)==len(SPECS) and all(type(r) is dict for r in rows),'incomplete matrix')
    lookup={(r.get('source_format'),r.get('format')):r for r in rows}
    need(set(lookup)==set(SPECS),'duplicate/foreign document')
    results=[]
    for spec in SPECS:
        fmt,kind=spec;row=lookup[spec];receipt(row,spec)
        path=evidence_file(directory,row['file']);rgba=evidence_file(directory,row['rgba']).read_bytes()
        probes=pixel_checks(rgba,fmt)
        result=inspect_pdf(path,fmt) if kind=='pdf' else inspect_svg(path,fmt)
        result.update(source_format=fmt,format=kind,raster_probes=probes,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        if render:result['viewer']=inspect_render(render(path,kind),fmt)
        results.append(result)
    return dict(schema=1,stage='0.70',status='passed',documents=results,independent_renderers_executed=(render is not None))

def inspect_gpu(directory,token,backend,adapter):
    directory=Path(directory);v=read_json(directory/'gpu.json')
    need(type(v.get('schema')) is int and v['schema']==1 and v.get('stage')=='0.70'
         and v.get('status')=='passed' and v.get('run_token')==token,'GPU receipt identity')
    need(v.get('backend')==backend and v.get('adapter')==adapter,'wrong GPU backend')
    for key,n in (('failures',0),('frames',7),('drawing_readbacks',0),('inspection_readbacks',7),('layout_rejections',7)):
        need(type(v.get(key)) is int and v[key]==n,'bad GPU '+key)
    need(v.get('contexts_closed') is True and v.get('gui_executed') is False
         and v.get('physical_display_verified') is False,'GPU lifetime/display claims')
    need(v.get('conversion')=='explicit-rgba-nearest' and v.get('gpu_target_format')=='rgba-8888','GPU format expansion must be explicit')
    rows=v.get('captures')
    need(type(rows) is list and len(rows)==7 and all(type(r) is dict for r in rows),'missing GPU captures')
    lookup={r.get('source_format'):r for r in rows};need(set(lookup)==set(FORMATS),'duplicate/foreign GPU capture')
    results=[]
    for fmt in FORMATS:
        row=lookup[fmt];need(row.get('file')==fmt+'.rgba','foreign GPU filename')
        results.append(dict(source_format=fmt,probes=pixel_checks(evidence_file(directory,row['file']).read_bytes(),fmt)))
    return dict(schema=1,stage='0.70',status='passed',backend=backend,adapter=adapter,captures=results,
                target_format='rgba-8888',drawing_readbacks=0,inspection_readbacks=7)
