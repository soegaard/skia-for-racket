"""0.72 independent image/filter placement, raw precision, PDF/SVG and GPU checks.

Importing this module never loads Skia, starts a renderer, or creates a GPU.
"""
from __future__ import annotations
import base64
import binascii
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import xml.etree.ElementTree as ET

SCENES=('offset','clip','blur','shadow','scale','raw')
SPECS=tuple((scene,kind) for scene in SCENES for kind in ('pdf','svg'))
WIDTH,HEIGHT=96,64
BLUE=(32,96,192,255)
WHITE=(255,255,255,255)
CLIPS={'offset':[-8,-8,48,40],'clip':[12,9,5,3], 'blur':[-8,-8,32,28],'shadow':[-8,-8,48,40]}

def need(ok,message):
    if not ok:raise ValueError(message)

def read_json(path):
    path=Path(path)
    need(path.is_file() and not path.is_symlink() and path.stat().st_size<=4*1024*1024,'invalid JSON file')
    def pairs(items):
        out={}
        for key,value in items:
            need(key not in out,'duplicate JSON key');out[key]=value
        return out
    def invalid(value):raise ValueError('nonfinite JSON: '+value)
    result=json.loads(path.read_text(encoding='utf-8'),object_pairs_hook=pairs,parse_constant=invalid)
    need(type(result) is dict,'JSON object required')
    return result

def evidence_file(directory,name):
    need(type(name) is str and re.fullmatch(r'[a-z0-9-]+\.(rgba|f32|pdf|svg|png)',name),'unsafe evidence filename')
    path=Path(directory)/name
    need(path.is_file() and not path.is_symlink() and path.stat().st_size<=16*1024*1024,'missing/oversized evidence')
    return path

def ints(value,n,label):
    need(type(value) is list and len(value)==n and all(type(x) is int for x in value),'invalid '+label)
    return value

def geometry(row):
    scene=row.get('scene');need(scene in SCENES,'foreign scene')
    w,h=ints(row.get('image_dimensions'),2,'image dimensions')
    px,py=ints(row.get('placement'),2,'placement')
    need(1<=w<=64 and 1<=h<=48,'oversized scene image')
    meta=row.get('metadata');need(type(meta) is dict,'missing metadata')
    if scene in CLIPS:
        bw,bh=ints(meta.get('backing_dimensions'),2,'backing dimensions')
        sx,sy,sw,sh=ints(meta.get('valid_subset'),4,'valid subset')
        ox,oy=ints(meta.get('offset'),2,'offset')
        cx,cy,cw,ch=ints(meta.get('clip'),4,'clip')
        need(meta['clip']==CLIPS[scene],'filter clip drift')
        need(1<=bw<=32768 and 1<=bh<=32768 and sx>=0 and sy>=0 and sw>0 and sh>0
             and sx+sw<=bw and sy+sh<=bh,'subset exceeds backing image')
        need((w,h)==(sw,sh),'cropped image extent does not match valid subset')
        need(cx<=ox and cy<=oy and ox+sw<=cx+cw and oy+sh<=cy+ch,'placed result outside clip')
        need((px,py)==(24+ox,20+oy),'geometric offset dropped or confused with texture coordinates')
        if scene=='offset':need((ox,oy,sw,sh)==(7,5,16,12),'incorrect translation result')
        if scene=='clip':need((ox,oy,sw,sh)==(12,9,5,3),'incorrect nonzero subset/clip result')
        if scene=='blur':need(ox<0 and oy<0 and sw>16 and sh>12,'blur halo was clipped')
        if scene=='shadow':need(sw>16 and sh>12,'shadow extent was clipped')
        need(row.get('raw') is False,'foreign float evidence')
    elif scene=='scale':
        need((w,h,px,py)==(16,12,24,20),'wrong scale extent/placement')
        need(meta.get('conversion')=='explicit-f32-to-rgba8888' and meta.get('source_dimensions')==[4,3],
             'scale quantization/source shape not explicit')
        need(row.get('raw')=='scale.f32','missing prequantization evidence')
    else:
        need((w,h,px,py)==(16,12,24,20),'wrong raw shader extent/placement')
        need(meta.get('conversion')=='explicit-raw-shader-rasterization','raw shader not explicitly rasterized')
        need(row.get('raw') is False,'foreign raw evidence')
    return w,h

def receipt(row,spec):
    scene,kind=spec
    need(type(row) is dict and (row.get('scene'),row.get('format'))==spec,'foreign document')
    need(type(row.get('callback_count')) is int and row['callback_count']==1,'authoring callback count')
    stem=scene+'-'+kind
    need(row.get('file')==stem+'.'+kind and row.get('rgba')==stem+'.rgba','foreign document filenames')
    geometry(row)
    need(row.get('audit_policy')=='error','incorrect export policy')
    audit=row.get('audit',{})
    need(type(audit) is dict and audit.get('mode')=='export' and audit.get('backend')==kind
         and audit.get('blocking') is False and audit.get('vector_only') is False,'invalid export audit')
    events=audit.get('events')
    need(type(events) is list and events and all(type(e) is dict for e in events),'missing audit events')
    images=[e for e in events if e.get('feature')=='image']
    need(len(images)==1 and images[0].get('status')=='embedded-raster','expected exactly one intentional image')
    allowed={'geometry','annotation','transform','source-replace','clip-intersect'}
    for event in events:
        if event.get('feature')=='image':continue
        need(event.get('feature') in allowed and event.get('status')=='vector','implicit fallback or unreconciled precision')
    need({'geometry','annotation'}<={e.get('feature') for e in events},'vector marker/link absent')

def raw_checks(data,byte_order):
    need(byte_order in ('little-endian','big-endian'),'unknown sample byte order')
    need(type(data) is bytes and len(data)==16*12*16,'wrong F32 storage extent')
    parser=struct.Struct(('<' if byte_order=='little-endian' else '>')+'4f')
    expected=(.5009765625,.25,.75,1.)
    for i in range(16*12):
        sample=parser.unpack_from(data,16*i)
        need(all(math.isfinite(x) for x in sample),'nonfinite scale samples')
        need(all(abs(a-b)<.00001 for a,b in zip(sample,expected)),'scaling lost float precision or sample values')
    return dict(pixels=192,format='rgba-f32',sub_byte_precision_verified=True)

def pixel_checks(data,scene,tolerance=3):
    need(scene in SCENES and type(data) is bytes and len(data)==WIDTH*HEIGHT*4,'pixel shape/identity')
    need(all(data[i]==255 for i in range(3,len(data),4)),'nonopaque fixture background')
    def pixel(x,y):return tuple(data[4*(y*WIDTH+x):4*(y*WIDTH+x+1)])
    probes=[(4,4,(0,255,0,255)),(90,58,WHITE),(10,30,WHITE),(80,26,WHITE)]
    if scene=='offset':probes += [(36,30,BLUE),(25,21,WHITE),(45,30,BLUE),(48,30,WHITE)]
    elif scene=='clip':probes += [(38,30,BLUE),(34,30,WHITE),(43,30,WHITE)]
    elif scene=='scale':probes += [(32,26,(128,64,191,255)),(20,26,WHITE),(42,26,WHITE)]
    elif scene=='raw':probes += [(32,26,BLUE),(20,26,WHITE),(42,26,WHITE)]
    elif scene=='blur':
        need(all(abs(a-b)<=max(tolerance,15) for a,b in zip(pixel(32,26),BLUE)),'blur center incorrect')
        need(pixel(22,26)[0]<250,'blur halo absent')
    else:
        probes += [(32,26,BLUE)]
        need(all(x<110 for x in pixel(44,34)[:3]),'offset shadow absent')
    for x,y,expected in probes:
        need(all(abs(a-b)<=tolerance for a,b in zip(pixel(x,y),expected)),f'{scene}: incorrect pixel at {x},{y}')
    return len(probes)+(2 if scene=='blur' else 1 if scene=='shadow' else 0)

def inspect_svg(path,row):
    raw=Path(path).read_bytes()
    need(b'<!DOCTYPE' not in raw.upper() and b'<!ENTITY' not in raw.upper(),'DTD/entity forbidden')
    root=ET.fromstring(raw);local=lambda e:e.tag.rsplit('}',1)[-1]
    need(local(root)=='svg','not SVG')
    def points(value):
        m=re.fullmatch(r'(\d+(?:\.\d+)?)(pt|px)?',value or '')
        need(m is not None,'nonabsolute SVG extent')
        return float(m[1])*(1 if m[2]=='pt' else .75)
    need(abs(points(root.get('width'))-WIDTH)<1e-5 and abs(points(root.get('height'))-HEIGHT)<1e-5,'SVG physical size')
    need(not any(local(e) in ('foreignObject','text') for e in root.iter()),'unexpected SVG content')
    images=[e for e in root.iter() if local(e)=='image'];need(len(images)==1,'expected one embedded image')
    href=images[0].get('href') or images[0].get('{http://www.w3.org/1999/xlink}href') or ''
    need(href.startswith('data:image/png;base64,'),'image must be embedded PNG')
    try:png=base64.b64decode(href.split(',',1)[1],validate=True)
    except (ValueError,binascii.Error) as error:raise ValueError('invalid embedded PNG') from error
    dims=tuple(row['image_dimensions'])
    need(len(png)>=24 and png[:8]==b'\x89PNG\r\n\x1a\n' and png[12:16]==b'IHDR'
         and (int.from_bytes(png[16:20],'big'),int.from_bytes(png[20:24],'big'))==dims,'PNG extent mismatch')
    need((float(images[0].get('width','0')),float(images[0].get('height','0')))==dims,'SVG image extent mismatch')
    need(len([e for e in root.iter() if local(e) in ('rect','path','polygon')])>=2,'vector marker/background absent')
    url='https://example.invalid/image-operations/'+row['scene']
    need(any(local(e)=='a' and (e.get('href') or e.get('{http://www.w3.org/1999/xlink}href'))==url for e in root.iter()),'SVG hyperlink absent')
    return dict(embedded_images=1,image_dimensions=list(dims),vector_marker=True,link=True)

def inspect_pdf(path,row):
    from pypdf import PdfReader
    from pypdf.generic import ContentStream
    reader=PdfReader(path,strict=True)
    need(not reader.is_encrypted and len(reader.pages)==1,'PDF encryption/page count')
    page=reader.pages[0];need(list(map(float,page.mediabox))==[0,0,WIDTH,HEIGHT],'PDF dimensions')
    paint_ops=0;image_ops=0;dims=tuple(row['image_dimensions'])
    def walk(stream,resources,active=None,depth=0):
        nonlocal paint_ops,image_ops
        active=set() if active is None else active
        need(depth<16,'PDF form depth')
        for args,op in ContentStream(stream,reader).operations:
            need(op not in (b'INLINE IMAGE',b'Tj',b'TJ',b"'",b'"'),'unexpected text or inline image')
            if op in (b'f',b'f*',b'F',b'S',b's',b'B',b'B*'):paint_ops+=1
            if op==b'Do':
                obj=resources['/XObject'].get_object()[args[0]].get_object()
                if obj.get('/Subtype')=='/Image':
                    need((obj.get('/Width'),obj.get('/Height'))==dims,'wrong image extent or full-page rasterization')
                    image_ops+=1
                    mask=obj.get('/SMask')
                    if mask:
                        mask=mask.get_object();need((mask.get('/Width'),mask.get('/Height'))==dims,'mask extent')
                else:
                    need(obj.get('/Subtype')=='/Form' and id(obj) not in active,'cyclic/unknown PDF form')
                    walk(obj,obj.get('/Resources',resources).get_object(),active|{id(obj)},depth+1)
    walk(page.get_contents(),page['/Resources'].get_object())
    need(image_ops==1 and paint_ops>=2,'missing image or vector marker')
    url='https://example.invalid/image-operations/'+row['scene']
    need(any(a.get_object().get('/A') and a.get_object()['/A'].get_object().get('/URI')==url for a in page.get('/Annots',[])),'PDF hyperlink absent')
    return dict(embedded_image_draws=image_ops,image_dimensions=list(dims),paint_operations=paint_ops,link=True)

def inspect_render(path,scene,reference):
    from PIL import Image
    with Image.open(path) as image:
        need(image.size==(WIDTH,HEIGHT),'viewer dimensions')
        data=image.convert('RGBA').tobytes()
    probes=pixel_checks(data,scene,tolerance=12)
    errors=[abs(a-b) for i,(a,b) in enumerate(zip(data,reference)) if i%4!=3]
    mean=sum(errors)/len(errors);fraction=sum(x>32 for x in errors)/len(errors)
    need(mean<=5 and fraction<=.06,'viewer diverges from native capture')
    return dict(semantic_probes=probes,mean_rgb_error=mean,large_error_fraction=fraction)

def inspect_documents(directory,token,*,render=None):
    directory=Path(directory);value=read_json(directory/'documents.json')
    need(type(value.get('schema')) is int and value['schema']==1 and value.get('stage')=='0.72'
         and value.get('status')=='passed' and value.get('run_token')==token,'stale/incomplete document receipt')
    need(value.get('rendering_executed') is True and value.get('gpu_executed') is False
         and value.get('gui_executed') is False,'unsupported execution claims')
    order=value.get('byte_order');need(order in ('little-endian','big-endian'),'sample byte order absent')
    rows=value.get('documents');need(type(rows) is list and len(rows)==len(SPECS) and all(type(r) is dict for r in rows),'incomplete document matrix')
    lookup={(r.get('scene'),r.get('format')):r for r in rows};need(set(lookup)==set(SPECS),'duplicate/foreign documents')
    results=[]
    for spec in SPECS:
        scene,kind=spec;row=lookup[spec];receipt(row,spec)
        reference=evidence_file(directory,row['rgba']).read_bytes();probes=pixel_checks(reference,scene)
        path=evidence_file(directory,row['file'])
        result=inspect_pdf(path,row) if kind=='pdf' else inspect_svg(path,row)
        result.update(scene=scene,format=kind,placement=row['placement'],metadata=row['metadata'],
                      raster_probes=probes,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        if row['raw']:result['raw']=raw_checks(evidence_file(directory,row['raw']).read_bytes(),order)
        if render:result['viewer']=inspect_render(render(path,kind),scene,reference)
        results.append(result)
    return dict(schema=1,stage='0.72',status='passed',documents=results,independent_renderers_executed=(render is not None))

def inspect_gpu(directory,token,backend,adapter):
    directory=Path(directory);value=read_json(directory/'gpu.json')
    need(type(value.get('schema')) is int and value['schema']==1 and value.get('stage')=='0.72'
         and value.get('status')=='passed' and value.get('run_token')==token,'GPU receipt identity')
    need(value.get('backend')==backend and value.get('adapter')==adapter,'wrong GPU backend/adapter')
    for key,expected in (('failures',0),('frames',6),('filter_calls',4),('cpu_rejections',4)):
        need(type(value.get(key)) is int and value[key]==expected,'bad GPU '+key)
    for flag in ('cross_context_rejected','retained_result_tested','contexts_closed'):
        need(value.get(flag) is True,'missing GPU ownership test: '+flag)
    for flag in ('gui_executed','physical_display_verified','float_gpu_storage_verified'):
        need(value.get(flag) is False,'unsupported GPU claim: '+flag)
    rows=value.get('scenes');need(type(rows) is list and len(rows)==len(SCENES) and all(type(r) is dict for r in rows),'missing GPU scenes')
    lookup={r.get('scene'):r for r in rows};need(set(lookup)==set(SCENES),'duplicate/foreign GPU scene')
    results=[]
    for scene in SCENES:
        row=lookup[scene];need(row.get('file')==scene+'.rgba','foreign GPU filename')
        for key,expected in (('drawing_readbacks',0),('inspection_readbacks',1)):
            need(type(row.get(key)) is int and row[key]==expected,'unexpected '+key)
        offset=ints(row.get('offset'),2,'GPU offset')
        if scene in ('offset','clip','scale','raw'):
            need(offset=={'offset':[7,5],'clip':[12,9],'scale':[0,0],'raw':[0,0]}[scene],'GPU offset changed')
        results.append(dict(scene=scene,probes=pixel_checks(evidence_file(directory,row['file']).read_bytes(),scene,5)))
    return dict(schema=1,stage='0.72',status='passed',backend=backend,adapter=adapter,
                captures=results,drawing_readbacks=0,inspection_readbacks=6,float_gpu_storage_verified=False)
