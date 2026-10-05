"""0.66 evidence checks. Parsing/inspection is not a substitute for native execution."""
from __future__ import annotations
import base64
import hashlib
import io
import json
from pathlib import Path
import xml.etree.ElementTree as ET

SCENES = ('stamp-1d','stamp-2d','line-2d','table-mask','gamma-mask','clip-mask',
          'shader-mask','fractal-noise','turbulence','shader-color-filter',
          'shader-blender','runtime-blender','arithmetic-blender','image-blender',
          'picture-target','empty-shader')

def need(value, message):
    if not value:
        raise ValueError(message)

def unique_object(pairs):
    out = {}
    for key, value in pairs:
        need(key not in out, 'duplicate JSON key: ' + key)
        out[key] = value
    return out

def read_json(path: Path):
    need(path.is_file() and not path.is_symlink(), 'missing/symlink JSON')
    need(path.stat().st_size <= 4*1024*1024, 'oversized JSON')
    def nonfinite(value):
        raise ValueError('nonfinite JSON: ' + value)
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_object,
                      parse_constant=nonfinite)

def evidence_file(root: Path, name: str) -> Path:
    need(isinstance(name,str) and name and Path(name).name == name
         and name not in ('.','..') and ':' not in name and '\\' not in name
         and not any(ord(c)<32 for c in name), 'unsafe evidence filename')
    p = root/name
    need(p.is_file() and not p.is_symlink() and p.stat().st_size <= 8*1024*1024,
         'missing/symlink/oversized evidence file: ' + name)
    return p

def receipt(row, name, fmt):
    need(isinstance(row,dict), 'document row is not an object')
    need(row.get('name') == name and row.get('format') == fmt, 'document identity mismatch')
    need(type(row.get('callback_count')) is int and row['callback_count']==1, 'callback count')
    need(row.get('vector_rejected') is True, 'require-vector rejection not observed')
    need(row.get('audit_policy') == 'error', 'strict audit policy not selected')
    a = row.get('audit', {})
    need(isinstance(a,dict), 'audit is not an object')
    need(a.get('mode') == 'export' and a.get('backend') == fmt and a.get('blocking') is False,
         'strict export audit failed')
    need(any(e.get('feature') == 'raster-group' for e in a.get('events', [])), 'missing raster audit boundary')
    g = row.get('group', {})
    need(isinstance(g,dict), 'group is not an object')
    need(g.get('backend')==fmt and g.get('strategy')=='raster' and g.get('policy')=='raster',
         'wrong output group strategy')
    need(g.get('pixel_size') == [64,48] and g.get('bounds') == [8,16,64,48], 'unbounded or misplaced group')
    need('unknown-resource' not in g.get('features',[]) and 'unknown-operation' not in g.get('features',[]),
         'unknown resource was accepted')

def white_composite(premul: bytes) -> bytes:
    need(len(premul)==64*48*4,'wrong RGBA byte count')
    out = bytearray()
    for i in range(0,len(premul),4):
        r,g,b,a = premul[i:i+4]
        need(max(r,g,b)<=a+1,'invalid premultiplied samples')
        out.extend((min(255,r+255-a),min(255,g+255-a),min(255,b+255-a),255))
    return bytes(out)

def premultiply_straight(straight: bytes) -> bytes:
    need(len(straight)==64*48*4,'wrong straight RGBA byte count')
    out=bytearray(len(straight))
    for i in range(0,len(straight),4):
        r,g,b,a=straight[i:i+4]
        out[i:i+4]=bytes(((r*a+127)//255,(g*a+127)//255,(b*a+127)//255,a))
    return bytes(out)

def block_rgb_error(actual: bytes, expected: bytes, block: int=8):
    need(len(actual)==len(expected)==64*48*4,'wrong rendered comparison byte count')
    need(type(block) is int and block>0 and 64%block==0 and 48%block==0,'invalid comparison block')
    maximum=0.0;total=0.0;count=0
    for y0 in range(0,48,block):
        for x0 in range(0,64,block):
            n=block*block
            for channel in range(3):
                a=e=0
                for y in range(y0,y0+block):
                    for x in range(x0,x0+block):
                        at=4*(y*64+x)+channel
                        a+=actual[at];e+=expected[at]
                error=abs(a-e)/n
                maximum=max(maximum,error);total+=error;count+=1
    return maximum,total/count

def check_rendered(path: Path, reference: bytes):
    from PIL import Image
    with Image.open(path) as im:
        need(im.size == (96,72),'wrong independently rendered extent')
        im = im.convert('RGBA')
        need(all(abs(x-y)<=2 for x,y in zip(im.getpixel((4,4)),(0,255,0,255))), 'vector marker missing')
        need(im.getpixel((85,65)) == (255,255,255,255),'outside effect boundary changed')
        expected=white_composite(reference)
        actual=im.crop((8,16,72,64)).tobytes()
        # PDF/SVG viewers may resample a 1:1 embedded image at pixel edges. The
        # embedded payload is checked exactly below; this independent-renderer
        # gate therefore compares 8x8 area averages to detect missing, displaced,
        # or grossly altered content without treating viewer filtering as Skia loss.
        maximum,mean=block_rgb_error(actual,expected)
        need(maximum<=40 and mean<=8,
             f'independent document visual divergence: max-block={maximum:.3f}, mean-block={mean:.3f}')
        return {'maximum_8x8_block_error':maximum,'mean_8x8_block_error':mean}

def inspect_svg(path: Path, name: str, reference: bytes):
    from PIL import Image
    data=path.read_bytes()
    need(b'<!DOCTYPE' not in data.upper(),'DTD outside diagnostic scope')
    root=ET.fromstring(data)
    def local(e): return e.tag.rsplit('}',1)[-1]
    images=[e for e in root.iter() if local(e)=='image']
    need(len(images)==1,'SVG must contain exactly one bounded image')
    e=images[0]
    uri=e.get('href') or e.get('{http://www.w3.org/1999/xlink}href') or ''
    need(uri.startswith('data:image/png;base64,'),'SVG image must be embedded PNG')
    raw=base64.b64decode(uri.split(',',1)[1],validate=True)
    with Image.open(io.BytesIO(raw)) as im:
        need(im.size==(64,48),'wrong embedded SVG raster dimensions')
        embedded=premultiply_straight(im.convert('RGBA').tobytes())
    need(embedded==reference,'SVG embedded raster pixels differ from direct Skia reference')
    url='https://example.invalid/effects/'+name
    need(any((e.get('href') or e.get('{http://www.w3.org/1999/xlink}href'))==url
             for e in root.iter() if local(e)=='a'),'SVG link missing')
    need(any(local(e) in ('path','rect') for e in root.iter()),'SVG vector geometry missing')
    return {'embedded_images':1,'pixel_size':[64,48],'link_verified':True,'embedded_pixels_exact':True}

def inspect_pdf(path: Path, name: str, reference: bytes):
    from pypdf import PdfReader
    from pypdf.generic import ContentStream
    reader=PdfReader(path, strict=True)
    need(len(reader.pages)==1,'PDF must have one page')
    page=reader.pages[0]
    need([float(x) for x in page.mediabox]==[0,0,96,72],'wrong PDF page size')
    images=[]
    geometry=[]
    seen=set()
    def walk(stream, resources, depth=0):
        need(depth<16,'excessive PDF form nesting')
        for operands,op in ContentStream(stream,reader).operations:
            if op in (b're',b'm',b'l',b'c'): geometry.append(op)
            if op==b'Do':
                obj=resources['/XObject'].get_object()[operands[0]].get_object()
                if obj.get('/Subtype')=='/Image':
                    images.append(obj)
                elif obj.get('/Subtype')=='/Form':
                    ident=id(obj)
                    need(ident not in seen,'cyclic/repeated diagnostic form')
                    seen.add(ident)
                    walk(obj,obj.get('/Resources',resources).get_object(),depth+1)
    walk(page.get_contents(),page['/Resources'].get_object())
    need(len(images)==1,'PDF must invoke exactly one bounded image')
    image=images[0]
    need((int(image['/Width']),int(image['/Height']))==(64,48),'wrong invoked PDF image dimensions')
    need(image.get('/BitsPerComponent')==8 and str(image.get('/ColorSpace'))=='/DeviceRGB',
         'unexpected PDF raster representation')
    rgb=image.get_data();need(len(rgb)==64*48*3,'wrong PDF RGB payload size')
    smask=image.get('/SMask')
    if smask:
        alpha_obj=smask.get_object()
        need((int(alpha_obj['/Width']),int(alpha_obj['/Height']))==(64,48)
             and alpha_obj.get('/BitsPerComponent')==8
             and str(alpha_obj.get('/ColorSpace'))=='/DeviceGray',
             'unexpected PDF soft-mask representation')
        alpha=alpha_obj.get_data();need(len(alpha)==64*48,'wrong PDF alpha payload size')
    else:
        alpha=bytes([255])*(64*48)
    straight=bytearray(64*48*4)
    for pixel in range(64*48):
        straight[4*pixel:4*pixel+3]=rgb[3*pixel:3*pixel+3]
        straight[4*pixel+3]=alpha[pixel]
    need(premultiply_straight(bytes(straight))==reference,
         'PDF embedded raster pixels differ from direct Skia reference')
    need(bool(geometry),'PDF vector marker geometry missing')
    url='https://example.invalid/effects/'+name
    actions=[a.get_object()['/A'].get_object() for a in page.get('/Annots',[]) if '/A' in a.get_object()]
    need(any(a.get('/URI')==url for a in actions), 'PDF link missing')
    return {'embedded_images':len(images),'pixel_size':[64,48],'link_verified':True,'embedded_pixels_exact':True}

def inspect_documents(directory: Path, token: str, *, render=None):
    data=read_json(directory/'documents.json')
    need(data.get('schema')==1 and data.get('stage')=='0.66' and data.get('status')=='passed'
         and data.get('run_token')==token,'foreign or failed document receipt')
    rows=data.get('documents',[])
    need(isinstance(rows,list) and len(rows)==len(SCENES)*2,'incomplete document matrix')
    expected={(n,f) for n in SCENES for f in ('pdf','svg')}
    observed=set()
    result=[]
    for row in rows:
        key=(row.get('name'),row.get('format'))
        need(key in expected and key not in observed,'duplicate/unknown document')
        observed.add(key)
        name,fmt=key
        receipt(row,name,fmt)
        need(row.get('file')==f'{name}.{fmt}' and row.get('rgba')==f'{name}.rgba','unexpected filenames')
        document=evidence_file(directory,row['file'])
        rgba=evidence_file(directory,row['rgba']).read_bytes()
        white_composite(rgba)
        summary=(inspect_pdf if fmt=='pdf' else inspect_svg)(document,name,rgba)
        summary.update(name=name,format=fmt,sha256=hashlib.sha256(document.read_bytes()).hexdigest())
        if render:
            png=render(document,fmt)
            summary.update(check_rendered(png,rgba))
        result.append(summary)
    need(observed==expected,'missing document')
    return {'schema':1,'stage':'0.66','run_token':token,'status':'passed','documents':result,
            'independent_rendering_executed':render is not None}

def gpu_receipt(path: Path, token: str, backend: str):
    r=read_json(path)
    need(type(r.get('schema')) is int and r['schema']==1 and r.get('stage')=='0.66'
         and r.get('run_token')==token and r.get('status')=='passed','foreign/failed GPU receipt')
    need(r.get('backend')==backend,'wrong GPU backend')
    need(type(r.get('frames')) is int and r['frames']>=16,'missing GPU pixel cases')
    need(type(r.get('inspection_readbacks')) is int and r['inspection_readbacks']==r['frames'], 'GPU capture count')
    need(type(r.get('drawing_readbacks')) is int and r['drawing_readbacks']==0, 'implicit readback')
    need(type(r.get('failures')) is int and r['failures']==0 and r.get('context_closed') is True,'GPU tests or cleanup failed')
    need(r.get('gui_executed') is False and r.get('physical_display_verified') is False,'unjustified GUI/display claim')
    return r
