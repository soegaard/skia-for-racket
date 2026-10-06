"""0.71 independent raw-float, document and GPU inspectors. No renderer on import."""
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

FORMATS = ('rgba-f16', 'rgba-f32')
SCENES = ('clear', 'solid', 'linear', 'radial', 'sweep', 'conical')
WIDTH, HEIGHT = 96, 64
SPECS = tuple((fmt, scene, kind) for fmt in FORMATS for scene in ('samples','linear') for kind in ('pdf','svg'))

def need(ok, message):
    if not ok: raise ValueError(message)

def read_json(path):
    path=Path(path)
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 4*1024*1024,'invalid JSON file')
    def pairs(items):
        out={}
        for key,value in items:
            need(key not in out,'duplicate JSON key');out[key]=value
        return out
    def invalid(v):raise ValueError('nonfinite JSON: '+v)
    value=json.loads(path.read_text(encoding='utf-8'),object_pairs_hook=pairs,parse_constant=invalid)
    need(type(value) is dict,'JSON object required')
    return value

def evidence_file(directory,name):
    need(type(name) is str and re.fullmatch(r'[a-z0-9-]+\.(rgba|pixels|pdf|svg|png)',name),'unsafe filename')
    path=Path(directory)/name
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 16*1024*1024,'missing/oversized file')
    return path

def sample_oracle(scene,x):
    if scene=='samples':
        return ((1.5,-.25,.5,1),(.25,.5,.75,1),(.5009765625,.5,.5,1),(.125,.875,.375,1))[x//16]
    if scene=='linear':
        t=(x+.5)/64
        return (.25+.5*t,.5,.75-.5*t,1)
    need(scene in SCENES,'unknown scene')
    return (.125,.375,.625,1)

def quantize(sample):
    return tuple(int(math.floor(max(0.,min(1.,v))*255+.5)) for v in sample)

def raw_checks(data,fmt,scene,byte_order):
    need(fmt in FORMATS and scene in ('samples','linear') and byte_order in ('little-endian','big-endian'),'raw identity')
    width=2 if fmt=='rgba-f16' else 4
    need(isinstance(data,bytes) and len(data)==64*32*4*width,'raw pixel size')
    parser=struct.Struct(('<' if byte_order=='little-endian' else '>')+('4e' if width==2 else '4f'))
    tolerance=.001 if width==2 else .0001
    for i in range(64*32):
        sample=parser.unpack_from(data,i*parser.size)
        need(all(math.isfinite(v) for v in sample),'nonfinite native sample')
        expected=sample_oracle(scene,i%64)
        need(all(abs(a-b)<=tolerance for a,b in zip(sample,expected)),f'{fmt}/{scene}: float precision or range lost at {i%64},{i//64}')
    # A dedicated, tighter probe prevents eight-bit quantization passing the
    # looser geometric/native tolerance above.
    if scene=='samples':
        a=parser.unpack_from(data,32*parser.size)[0]
        need(abs(a-.5009765625)<.00025,'sub-byte distinction was quantized')
        first=parser.unpack_from(data,0)
        need(first[0]>1 and first[1]<0,'extended RGB was clamped')
    return dict(pixels=2048,sample_type=fmt,extended_rgb_verified=(scene=='samples'),
                sub_byte_precision_verified=(scene=='samples'))

def pixel_checks(data,scene,*,document=True,tolerance=3):
    need(scene in SCENES or scene=='samples','unknown pixel scene')
    w,h=(WIDTH,HEIGHT) if document else (64,32)
    need(isinstance(data,bytes) and len(data)==w*h*4,'pixel shape')
    need(all(data[i]==255 for i in range(3,len(data),4)),'nonopaque output')
    count=0
    for y in range(h):
        for x in range(w):
            if document:
                if 0<=x<8 and 0<=y<8:
                    if (x,y) not in ((3,3),(4,4)):continue
                    expected=(0,255,0,255)
                elif 14<=x<82 and 14<=y<50:
                    if not (18<=x<78 and 18<=y<46):continue
                    sx=x-16
                    if scene=='samples' and sx%16 in (0,1,14,15):continue
                    expected=quantize(sample_oracle(scene,sx))
                else:expected=(255,255,255,255)
            else:
                if not (2<=x<62 and 2<=y<30):continue
                expected=quantize(sample_oracle(scene,x))
            at=4*(y*w+x)
            need(all(abs(a-b)<=tolerance for a,b in zip(data[at:at+4],expected)),f'{scene}: wrong pixel at {x},{y}')
            count+=1
    return count

def receipt(row,spec):
    fmt,scene,kind=spec
    need(type(row) is dict and (row.get('source_format'),row.get('scene'),row.get('format'))==spec,'foreign document')
    need(row.get('conversion')=='explicit-float-to-rgba8888','unreported quantization')
    for key,n in (('image_width',64),('image_height',32),('callback_count',1)):
        need(type(row.get(key)) is int and row[key]==n,'wrong '+key)
    prefix=fmt+'-'+scene;stem=prefix+'-'+kind
    need(row.get('file')==stem+'.'+kind and row.get('rgba')==stem+'.rgba' and row.get('raw')==prefix+'.pixels','foreign filenames')
    need(row.get('audit_policy')=='error','incorrect export policy')
    audit=row.get('audit',{})
    need(type(audit) is dict and audit.get('mode')=='export' and audit.get('backend')==kind
         and audit.get('blocking') is False and audit.get('vector_only') is False,'invalid export audit')
    events=audit.get('events')
    need(type(events) is list and events and all(type(e) is dict for e in events),'missing audit events')
    images=[e for e in events if e.get('feature')=='image']
    need(len(images)==1 and images[0].get('status')=='embedded-raster','expected one explicit image')
    allowed={'geometry','annotation','transform','source-replace','clip-intersect'}
    for event in events:
        if event.get('feature')=='image':continue
        need(event.get('feature') in allowed and event.get('status')=='vector','implicit fallback or unconverted float precision')
    need({'geometry','annotation'} <= {e.get('feature') for e in events},'missing marker/link evidence')

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
    url='https://example.invalid/float/'+fmt
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
    url='https://example.invalid/float/'+fmt
    need(any(a.get_object().get('/A') and a.get_object()['/A'].get_object().get('/URI')==url for a in page.get('/Annots',[])),'missing PDF link')
    return dict(embedded_image_draws=image_ops,image_dimensions=[64,32],paint_operations=paint_ops,link=True)

def inspect_render(path,scene):
    from PIL import Image
    with Image.open(path) as im:
        need(im.size==(WIDTH,HEIGHT),'viewer dimensions')
        data=im.convert('RGBA').tobytes()
    return dict(independent_probes=pixel_checks(data,scene,tolerance=12))

def inspect_documents(directory,token,*,render=None):
    directory=Path(directory);value=read_json(directory/'documents.json')
    need(type(value.get('schema')) is int and value['schema']==1 and value.get('stage')=='0.71'
         and value.get('status')=='passed' and value.get('run_token')==token,'stale/incomplete receipt')
    need(value.get('rendering_executed') is True and value.get('gpu_executed') is False
         and value.get('hdr_verified') is False,'false execution claims')
    byte_order=value.get('byte_order')
    need(byte_order in ('little-endian','big-endian'),'unknown sample byte order')
    rows=value.get('documents')
    need(type(rows) is list and len(rows)==len(SPECS) and all(type(r) is dict for r in rows),'incomplete document matrix')
    lookup={(r.get('source_format'),r.get('scene'),r.get('format')):r for r in rows}
    need(set(lookup)==set(SPECS),'duplicate/foreign documents')
    results=[]
    for spec in SPECS:
        fmt,scene,kind=spec;row=lookup[spec];receipt(row,spec)
        path=evidence_file(directory,row['file'])
        raw=raw_checks(evidence_file(directory,row['raw']).read_bytes(),fmt,scene,byte_order)
        probes=pixel_checks(evidence_file(directory,row['rgba']).read_bytes(),scene)
        prefix=fmt+'-'+scene
        result=inspect_pdf(path,prefix) if kind=='pdf' else inspect_svg(path,prefix)
        result.update(source_format=fmt,scene=scene,format=kind,raw=raw,raster_probes=probes,
                      sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        if render:result['viewer']=inspect_render(render(path,kind),scene)
        results.append(result)
    return dict(schema=1,stage='0.71',status='passed',documents=results,
                independent_renderers_executed=(render is not None),hdr_verified=False)

def inspect_gpu(directory,token,backend,adapter):
    directory=Path(directory);value=read_json(directory/'gpu.json')
    need(type(value.get('schema')) is int and value['schema']==1 and value.get('stage')=='0.71'
         and value.get('status')=='passed' and value.get('run_token')==token,'GPU receipt identity')
    need(value.get('backend')==backend and value.get('adapter')==adapter,'wrong GPU backend/adapter')
    for key,n in (('failures',0),('frames',6),('drawing_readbacks',0),('inspection_readbacks',6),('float_readback_rejections',2)):
        need(type(value.get(key)) is int and value[key]==n,'bad GPU '+key)
    need(value.get('context_closed') is True,'GPU context not closed')
    for flag in ('float_gpu_storage_verified','hdr_verified','physical_display_verified'):
        need(value.get(flag) is False,'unsupported GPU claim: '+flag)
    need(value.get('gpu_target_format')=='rgba-8888','unexpected GPU storage claim')
    rows=value.get('captures')
    need(type(rows) is list and len(rows)==len(SCENES) and all(type(r) is dict for r in rows),'missing GPU captures')
    lookup={r.get('scene'):r for r in rows};need(set(lookup)==set(SCENES),'duplicate/foreign GPU captures')
    results=[]
    for scene in SCENES:
        row=lookup[scene];need(row.get('file')==scene+'.rgba','foreign GPU filename')
        results.append(dict(scene=scene,probes=pixel_checks(evidence_file(directory,row['file']).read_bytes(),scene,document=False,tolerance=5)))
    return dict(schema=1,stage='0.71',status='passed',backend=backend,adapter=adapter,captures=results,
                target_format='rgba-8888',drawing_readbacks=0,inspection_readbacks=6,hdr_verified=False)
