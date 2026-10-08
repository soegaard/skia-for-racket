"""Independent evidence checks for 0.75b. Fixtures are not native execution."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
PURE_CASES=26
NATIVE_CASES=42
SIZE=(64,48)
PIXELS=bytes((255,0,0,255,0,255,0,255,0,0,255,255,255,255,255,255))
FILES=('copy.bin','decoded.rgba','image.png','image.jpeg','image.webp','picture.skp','document.pdf','document.svg','native.json')
def need(condition,message):
    if not condition:raise ValueError(message)
def suite_output(text,name,count):
    totals=re.findall(r'(?m)^\s*(\d+) success\(es\) (\d+) failure\(s\) (\d+) error\(s\) (\d+) test\(s\) run\s*$',text)
    need(totals==[(str(count),'0','0',str(count))], 'missing, failed or duplicate RackUnit completion')
    need(len(re.findall(rf'(?m)^{re.escape(name)}: {count} cases, 0 failures\s*$',text))==1,'wrong explicit suite completion')
def receipt(value,token):
    need(type(value) is dict,'invalid receipt')
    expected=dict(schema=1,stage='0.75b',status='passed',run_token=token,native_version='119.0',
                  authoring_calls=3,callbacks_on_service_thread=True,compiler_required=False,active_jobs=0,native_execution=True,gpu_execution=False)
    for k,want in expected.items():
        actual=value.get(k);need(type(actual) is type(want) and actual==want,'wrong execution field: '+k)
    need(type(value.get('write_callbacks')) is int and value['write_callbacks']>0,'no observed port writes')
    need(type(value.get('racket_version')) is str and value['racket_version'],'missing interpreter identity')
    need(value.get('os') in ('unix','macosx','windows'),'missing native OS identity')
    return value

def inspect(root:Path,token:str,*,require_renderers=False,run=None):
    from PIL import Image
    from pypdf import PdfReader
    root=Path(root)
    paths={}
    for name in FILES:
        p=root/name;need(p.is_file() and not p.is_symlink(),'missing/unsafe evidence: '+name)
        need(p.stat().st_size<=16*1024*1024,'oversized evidence: '+name);paths[name]=p
    native=receipt(json.loads(paths['native.json'].read_text()),token)
    need(paths['copy.bin'].read_bytes()==bytes(i%251 for i in range(131079)),'native streamed copy differs')
    need(paths['decoded.rgba'].read_bytes()==PIXELS,'live native decode pixels differ')
    for ext,fmt in (('png','PNG'),('jpeg','JPEG'),('webp','WEBP')):
        with Image.open(paths['image.'+ext]) as image:
            need(image.format==fmt and image.size==(2,2),'wrong native encoded image')
            if ext!='jpeg':need(image.convert('RGBA').tobytes()==PIXELS,'lossless encoded pixels differ')
    skp=paths['picture.skp'].read_bytes();need(len(skp)>=29 and skp[:8]==b'skiapict','wrong SKP header')
    pdf=PdfReader(paths['document.pdf'],strict=True)
    need(len(pdf.pages)==2,'streamed PDF lost a page')
    def dereference(value):return value.get_object() if hasattr(value,'get_object') else value
    for page in pdf.pages:
        need(tuple(float(n) for n in page.mediabox)==(0.,0.,64.,48.),'wrong PDF page extent')
        links=[dereference(dereference(a).get('/A',{})).get('/URI') for a in dereference(page.get('/Annots',[]))]
        need('https://example.test/live' in links,'PDF URL lost')
        resources=dereference(page.get('/Resources',{}))
        def images(r,seen=None):
            seen=set() if seen is None else seen
            count=0
            for obj in dereference(r.get('/XObject',{})).values():
                v=obj.get_object();key=id(v)
                if key in seen:continue
                seen.add(key)
                count+=int(v.get('/Subtype')=='/Image')
                if v.get('/Subtype')=='/Form':count+=images(dereference(v.get('/Resources',{})),seen)
            return count
        need(images(resources)==0,'vector-only page unexpectedly rasterized')
        need(bool(page.get_contents().get_data()),'empty PDF page commands')
    svg=ET.fromstring(paths['document.svg'].read_bytes())
    def local(tag):return tag.rsplit('}',1)[-1]
    need(local(svg.tag)=='svg','wrong SVG root')
    for k,n in zip(('width','height'),SIZE):
        match=re.fullmatch(r'([0-9.]+)pt',svg.get(k,''));need(match is not None and float(match[1])==n,'SVG point dimension lost')
    need([float(v) for v in svg.get('viewBox','').split()]==[0,0,64,48],'SVG viewport lost')
    need(not any(local(e.tag)=='image' for e in svg.iter()),'vector SVG unexpectedly rasterized')
    need(sum(local(e.tag) in ('rect','path') for e in svg.iter())>=2,'SVG vector content absent')
    need(any(v=='https://example.test/live' for e in svg.iter() for v in e.attrib.values()),'SVG URL lost')
    rendered=[]
    for kind,tool in (('pdf','pdftoppm'),('svg','rsvg-convert')):
        executable=shutil.which(tool)
        if not executable:
            need(not require_renderers,'required renderer unavailable: '+tool);continue
        target=root/('rendered-'+kind+'.png')
        if kind=='pdf':command=[executable,'-singlefile','-r','72','-png',str(paths['document.pdf']),str(target.with_suffix(''))]
        else:command=[executable,'--width','64','--height','48','--output',str(target),str(paths['document.svg'])]
        if run:run(command)
        else:subprocess.run(command,check=True,timeout=60,capture_output=True)
        with Image.open(target) as im:
            need(im.size==SIZE,'wrong independent render extent');rgb=im.convert('RGB')
            for point,want in (((2,2),(255,255,255)),((12,12),(255,0,0)),((2,42),(0,0,255))):
                actual=rgb.getpixel(point);need(all(abs(a-b)<=3 for a,b in zip(actual,want)),'independent document pixels differ')
        rendered.append(kind)
    return dict(status='passed',native=native,renderers_executed=rendered,
                files={n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in paths.items()})
