"""Independent 0.73 evidence checks. Synthetic receipts are test data only."""
from __future__ import annotations
import json
import math
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

FORMATS = {'rgba-8888':4, 'bgra-8888':4, 'rgb-888x':4, 'alpha-8':1, 'gray-8':1,
           'rgb-565':2, 'rgba-1010102':4, 'rgba-f16':8, 'rgba-f32':16}
REQUIRED = {'rgba-8888','bgra-8888','rgba-f16'}
GPU_CASES = 20  # current test! calls: eleven fixed plus nine format cases
DESCRIPTOR_SYMBOLS = {
 'gr_backendtexture_get_width','gr_backendtexture_get_height','gr_backendtexture_has_mipmaps',
 'gr_backendtexture_get_backend','gr_backendtexture_is_valid','gr_backendtexture_get_gl_textureinfo',
 'gr_backendtexture_delete','gr_backendrendertarget_get_width','gr_backendrendertarget_get_height',
 'gr_backendrendertarget_get_samples','gr_backendrendertarget_get_stencils',
 'gr_backendrendertarget_get_backend','gr_backendrendertarget_get_gl_framebufferinfo'}
URL='https://example.invalid/gpu-formats'

def require(ok, reason):
    if not ok: raise ValueError(reason)

def integer(v, lo=0): return type(v) is int and v>=lo

def pairs(items):
    result={}
    for k,v in items:
        require(k not in result,'duplicate JSON key: '+k);result[k]=v
    return result

def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'),object_pairs_hook=pairs,
                      parse_constant=lambda s:(_ for _ in ()).throw(ValueError('nonfinite JSON: '+s)))

def safe_file(root, name):
    require(isinstance(name,str) and name and Path(name).name==name
            and name not in ('.','..') and ':' not in name and '\\' not in name
            and not any(ord(c)<32 for c in name), 'unsafe evidence filename')
    path=Path(root)/name
    require(not path.is_symlink() and path.is_file(), 'missing/symlink evidence: '+name)
    return path

def pixel_checks(data, color, stride, order):
    require(color in FORMATS,'unreviewed format')
    bpp=FORMATS[color]
    require(type(stride) is int and stride==10*bpp,'wrong padded stride')
    require(order in ('little-endian','big-endian'),'unknown byte order')
    require(isinstance(data,bytes) and len(data)==stride*6,'wrong raw byte count')
    endian='<' if order=='little-endian' else '>'
    samples=[]
    for y in range(6):
        require(data[y*stride+8*bpp:(y+1)*stride]==bytes([165])*(2*bpp),'padding canary changed')
        for x in range(8):
            p=data[y*stride+x*bpp:y*stride+(x+1)*bpp];right=x>=4
            if color in ('rgba-f16','rgba-f32'):
                value=struct.unpack(endian+('4e' if color=='rgba-f16' else '4f'),p)
                expected=(.501953125 if right else .5009765625,-.125,1.25,1)
                require(all(math.isfinite(v) for v in value),'nonfinite float capture')
                require(all(abs(a-b)<=.00002 for a,b in zip(value,expected)),
                        'float precision/range lost or source pattern missing')
                samples.append(value[0])
            elif color in ('rgba-8888','bgra-8888'):
                expected=(192,96,32,255) if right else (32,96,192,255)
                if color=='bgra-8888':expected=(expected[2],expected[1],expected[0],255)
                require(all(abs(a-b)<=1 for a,b in zip(p,expected)), 'integer channel order/pixel mismatch')
            elif color=='rgb-888x':
                require(p[:3]==bytes([255 if right else 0])*3,'RGBX color mismatch')
            elif color=='alpha-8':
                require(abs(p[0]-(192 if right else 64))<=1,'alpha-only pixel mismatch')
            elif color=='gray-8':require(p[0]==(255 if right else 0),'gray pixel mismatch')
            elif color=='rgb-565':
                require(int.from_bytes(p,order.split('-')[0])==(65535 if right else 0),'RGB565 packing mismatch')
            elif color=='rgba-1010102':
                word=int.from_bytes(p,order.split('-')[0]);channel=1023 if right else 0
                require(word==((3<<30)|(channel<<20)|(channel<<10)|channel),'RGB10A2 packing mismatch')
    if samples:
        difference=samples[4]-samples[0]
        require(0<difference<1/255,'sub-byte distinction not retained')
    return dict(pixels_checked=48,padding_checked=True,float_precision_checked=bool(samples))

def document_receipt(row):
    require(type(row) is dict,'document receipt is not an object')
    color=row.get('color_type');kind=row.get('format')
    require(color in ('rgba-8888','rgba-f16') and kind in ('pdf','svg'),'unreviewed document')
    require(row.get('file')==color+'.'+kind,'document filename mismatch')
    require(row.get('conversion')=='explicit-rgba8888','document quantization not explicit')
    audit=row.get('audit');require(type(audit) is dict,'missing document audit')
    require(audit.get('mode')=='export' and audit.get('backend')==kind,'wrong audit scope')
    require(audit.get('blocking') is False and audit.get('vector_only') is False,'invalid document policy result')
    events=audit.get('events');require(type(events) is list and bool(events),'missing drawing events')
    image_events=[e for e in events if e.get('feature')=='image']
    require(len(image_events)==1 and image_events[0].get('status')=='embedded-raster','missing/false embedded image')
    require(all(e.get('status')=='vector' for e in events if e.get('feature')!='image'),
            'surrounding drawing rasterized or unresolved')
    require(any(e.get('feature') in ('annotation','url-annotation','link','annotations')
                or 'annotation' in str(e.get('operation','')) for e in events), 'missing link audit')

def document_structure(path, kind):
    if kind=='pdf':
        from pypdf import PdfReader
        from pypdf.generic import ContentStream
        reader=PdfReader(str(path));require(len(reader.pages)==1,'wrong PDF page count')
        page=reader.pages[0]
        require(abs(float(page.mediabox.width)-40)<.01 and abs(float(page.mediabox.height)-28)<.01,'wrong PDF extent')
        ops=ContentStream(page.get_contents(),reader).operations
        require(any(op in (b're',b'm') for _,op in ops),'missing PDF vector marker')
        images=list(page.images);require(len(images)==1,'wrong PDF image count')
        require(images[0].image.size==(8,6),'wrong embedded image extent')
        links=[a.get_object().get('/A',{}).get('/URI') for a in page.get('/Annots',[])]
        require(URL in links,'missing PDF hyperlink')
    else:
        root=ET.parse(path).getroot();images=[];links=[];geometry=0
        for e in root.iter():
            tag=e.tag.rsplit('}',1)[-1]
            require(tag not in ('foreignObject','script'),'unsafe SVG construct')
            if tag=='image':images.append(e)
            if tag=='a':links.extend(v for k,v in e.attrib.items() if k.rsplit('}',1)[-1]=='href')
            if tag in ('rect','path','polygon'):geometry+=1
        require(len(images)==1 and geometry>0,'wrong SVG image/vector composition')
        image=images[0]
        require(float(image.get('width',0))==8 and float(image.get('height',0))==6,'wrong SVG image extent')
        # Skia represents annotations using <a> overlays. Do not infer a link
        # solely from arbitrary prose or an external filename.
        require(URL in links,'missing SVG hyperlink')
    return dict(structure_checked=True)

def rendered_checks(path,color):
    from PIL import Image
    with Image.open(path) as im:
        rgba=im.convert('RGBA');require(rgba.size==(40,28),'wrong rendered page extent')
        expected=[((3,3),(0,255,0,255)),((35,24),(255,255,255,255))]
        if color=='rgba-f16':expected.extend([((17,13),(128,0,255,255)),((22,13),(128,0,255,255))])
        else:expected.extend([((17,13),(32,96,192,255)),((22,13),(192,96,32,255))])
        for xy,values in expected:
            require(all(abs(a-b)<=2 for a,b in zip(rgba.getpixel(xy),values)),'independent document pixel mismatch')
    return dict(pixel_probes=4)

def inspect(root,token,backend,adapter,render=None):
    root=Path(root);data=read_json(root/'gpu.json')
    require(data.get('schema')==1 and type(data.get('schema')) is int and data.get('stage')=='0.73','wrong report schema/stage')
    require(data.get('run_token')==token and data.get('status')=='passed','failed/foreign invocation')
    require(data.get('backend')==backend and data.get('adapter')==adapter,'wrong execution backend/adapter')
    require(type(data.get('cases')) is int and data['cases']==GPU_CASES and type(data.get('failures')) is int and data['failures']==0,'missing/failing test cases')
    require(data.get('context_closed') is True,'contexts did not close')
    require(data.get('physical_display_verified') is False and data.get('hdr_verified') is False,'unsupported display claim')
    require(type(data.get('drawing_readbacks')) is int and data['drawing_readbacks']==0,'hidden drawing readback')
    symbols=data.get('descriptor_symbols');require(type(symbols) is list,'missing native inventory')
    require(len(symbols)==len(DESCRIPTOR_SYMBOLS) and {r.get('name') for r in symbols}==DESCRIPTOR_SYMBOLS,'wrong/duplicate descriptor symbols')
    require(all(r.get('available') is True for r in symbols),'missing native descriptor symbol')
    staging=data.get('staging');require(type(staging) is dict,'missing staging evidence')
    for k,v in dict(creations=4,reuses=1,retirements=3,live_targets=1).items():
        require(type(staging.get(k)) is int and staging[k]==v,'wrong native staging count: '+k)
    rows=data.get('formats');require(type(rows) is list and len(rows)==len(FORMATS),'missing format rows')
    require({r.get('color_type') for r in rows}==set(FORMATS),'wrong/duplicate format rows')
    successful=set();unsupported=0;results={}
    for row in rows:
        color=row['color_type'];cap=row.get('capability');require(type(cap) is dict,'missing native capability')
        require(cap.get('color_type_name')==color,'capability color mismatch')
        require(cap.get('backend')==('opengl' if backend=='egl' else backend),'capability backend mismatch')
        require(integer(cap.get('context_generation'),1),'invalid context generation')
        require(cap.get('allocation_verified') is False and cap.get('actual_sample_count') is False,'maximum is not allocation/sample evidence')
        require(integer(cap.get('max_sample_count')),'invalid maximum samples')
        require(cap.get('renderable') is (cap['max_sample_count']>0),'inconsistent native capability')
        if row.get('status')=='unsupported':
            require(cap['renderable'] is False and color not in REQUIRED,'required/native-supported format skipped')
            require('file' not in row,'unsupported format has fabricated capture');unsupported+=1;continue
        require(row.get('status')=='passed' and cap['renderable'] is True,'failed format cannot count as support')
        for k,v in dict(width=8,height=6,bytes_per_pixel=FORMATS[color],readbacks=1).items():
            require(type(row.get(k)) is int and row[k]==v,'wrong capture field: '+k)
        require(row.get('alpha_type')==('opaque' if color in ('rgb-888x','gray-8','rgb-565') else 'premul'),'wrong alpha type')
        require(row.get('file')==color+'.pixels','wrong capture filename')
        require(type(row.get('properties',{}).get('flags')) is int,'invalid property flags type')
        require(row.get('properties')=={'pixel_geometry':'unknown','flags':0,'device_independent_fonts':False,'dynamic_msaa':False,'always_dither':False},'defaults changed')
        results[color]=pixel_checks(safe_file(root,row['file']).read_bytes(),color,row.get('row_bytes'),data.get('byte_order'))
        successful.add(color)
    require(REQUIRED<=successful,'required native formats unexercised')
    require(type(data.get('unsupported_rejections')) is int and data['unsupported_rejections']==unsupported,'unsupported rejection count mismatch')
    docs=data.get('documents');require(type(docs) is list and len(docs)==4,'missing GPU-derived documents')
    require({r.get('file') for r in docs}=={c+'.'+k for c in ('rgba-8888','rgba-f16') for k in ('pdf','svg')},'wrong/duplicate documents')
    for row in docs:
        document_receipt(row);path=safe_file(root,row['file']);document_structure(path,row['format'])
        if render:rendered_checks(render(path,row['format']),row['color_type'])
    return dict(status='passed',formats=results,unsupported_formats=unsupported,
                documents=4,independent_renderers_executed=bool(render),
                physical_display_verified=False,hdr_verified=False)
