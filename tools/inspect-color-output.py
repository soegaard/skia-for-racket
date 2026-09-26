#!/usr/bin/env python3
"""Inspect probe containers and ICC semantics, not visual appearance/PDF-A compliance.

Only Python's standard library is required; --pdf additionally uses pypdf.
Self-tests use synthetic containers and are NOT native Skia encoder tests.
"""
from __future__ import annotations
import argparse, base64, binascii, json, math, re, struct, unittest, zlib
from pathlib import Path
from xml.etree import ElementTree as ET

LIMIT = 16 * 1024 * 1024
PNG = b'\x89PNG\r\n\x1a\n'

def need(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)

def u32(b: bytes, p: int) -> int:
    need(0 <= p <= len(b)-4, 'truncated integer')
    return struct.unpack_from('>I', b, p)[0]

def fixed(b: bytes, p: int) -> float:
    need(0 <= p <= len(b)-4, 'truncated fixed-point number')
    return struct.unpack_from('>i', b, p)[0]/65536

def bounded_inflate(data: bytes) -> bytes:
    d = zlib.decompressobj()
    out = d.decompress(data, LIMIT+1)
    need(len(out) <= LIMIT and d.eof and not d.unused_data and not d.unconsumed_tail,
         'invalid/truncated/oversized compressed ICC profile')
    return out

def png_chunks(data: bytes) -> list[tuple[bytes, bytes]]:
    need(data.startswith(PNG), 'PNG signature')
    p, chunks = 8, []
    while p < len(data):
        need(p+12 <= len(data), 'truncated PNG chunk')
        n = u32(data, p); tag = data[p+4:p+8]
        need(p+12+n <= len(data), 'PNG chunk length')
        body = data[p+8:p+8+n]
        need((binascii.crc32(tag+body)&0xffffffff) == u32(data,p+8+n), 'PNG CRC')
        chunks.append((tag,body));p+=12+n
        if tag == b'IEND':
            need(n == 0 and p == len(data), 'PNG IEND/trailing data');break
    need(chunks and chunks[0][0] == b'IHDR' and len(chunks[0][1]) == 13 and chunks[-1][0] == b'IEND', 'PNG critical ordering')
    return chunks

def png_icc(data: bytes) -> bytes:
    chunks=png_chunks(data);profiles=[b for t,b in chunks if t==b'iCCP']
    need(len(profiles)==1 and not any(t==b'sRGB' for t,b in chunks), 'exactly one PNG ICC profile, no conflicting sRGB chunk')
    tags=[t for t,b in chunks]
    need(b'IDAT' in tags and tags.index(b'iCCP') < tags.index(b'IDAT'), 'ICC before PNG pixels')
    body=profiles[0];zero=body.find(b'\0')
    need(1<=zero<=79 and zero+2<len(body) and body[zero+1]==0, 'PNG ICC compression header')
    return bounded_inflate(body[zero+2:])

def jpeg_icc(data: bytes) -> bytes:
    need(data[:2]==b'\xff\xd8', 'JPEG SOI')
    p=2; parts={};count=None
    while p<len(data):
        need(data[p]==255, 'JPEG marker expected')
        while p<len(data) and data[p]==255:p+=1
        need(p<len(data), 'truncated JPEG marker')
        marker=data[p];p+=1
        if marker in (0xd9,0xda):break
        if marker==1 or 0xd0<=marker<=0xd7:continue
        need(p+2<=len(data), 'JPEG segment length')
        n=int.from_bytes(data[p:p+2], 'big');need(n>=2 and p+n<=len(data), 'JPEG segment bounds')
        body=data[p+2:p+n];p+=n
        if marker==0xe2 and body.startswith(b'ICC_PROFILE\0'):
            need(len(body)>=14, 'short JPEG ICC marker')
            seq,total=body[12:14]
            need(1<=seq<=total and (count is None or count==total) and seq not in parts, 'JPEG ICC sequence/duplicate')
            count=total;parts[seq]=body[14:]
    need(count is not None and len(parts)==count, 'missing JPEG ICC segments')
    profile=b''.join(parts[i] for i in range(1,count+1))
    need(len(profile)<=LIMIT, 'ICC byte limit')
    return profile

def webp_icc(data: bytes) -> bytes:
    need(data[:4]==b'RIFF' and data[8:12]==b'WEBP' and len(data)>=12, 'WebP RIFF')
    need(int.from_bytes(data[4:8],'little')+8==len(data), 'WebP RIFF length')
    p=12;chunks=[]
    while p<len(data):
        need(p+8<=len(data),'WebP chunk header')
        t=data[p:p+4];n=int.from_bytes(data[p+4:p+8],'little')
        need(p+8+n+(n&1)<=len(data),'WebP chunk bounds')
        chunks.append((t,data[p+8:p+8+n]));p+=8+n+(n&1)
    need(chunks and chunks[0][0]==b'VP8X' and len(chunks[0][1])==10, 'extended WebP required')
    need(bool(chunks[0][1][0]&0x20), 'WebP ICC feature flag')
    tags=[t for t,b in chunks];profiles=[b for t,b in chunks if t==b'ICCP']
    need(len(profiles)==1, 'exactly one WebP ICCP chunk')
    pixel_positions=[i for i,t in enumerate(tags) if t in (b'VP8 ',b'VP8L')]
    need(pixel_positions and tags.index(b'ICCP') < min(pixel_positions),'WebP ICC must precede image data')
    return profiles[0]

def curve_values(tag: bytes) -> list[float]:
    samples=(0.0,0.01,0.04,0.1,0.25,0.5,0.75,1.0)
    if tag[:4]==b'curv':
        count=u32(tag,8);need(12+2*count<=len(tag), 'ICC curve table bounds')
        if count==0:return list(samples)
        values=struct.unpack_from('>'+str(count)+'H',tag,12)
        if count==1:return [x**(values[0]/256) for x in samples]
        def lookup(x: float) -> float:
            p=x*(count-1);i=min(int(p),count-2);f=p-i
            return ((1-f)*values[i]+f*values[i+1])/65535
        return [lookup(x) for x in samples]
    need(tag[:4]==b'para' and len(tag)>=12,'ICC TRC type')
    kind=int.from_bytes(tag[8:10],'big');need(kind in range(5),'ICC parametric kind')
    sizes=(1,3,4,5,7);n=sizes[kind];need(12+4*n<=len(tag),'ICC parameter bounds')
    v=[fixed(tag,12+4*i) for i in range(n)]
    def evaluate(x: float) -> float:
        if kind==0:return x**v[0]
        g,a,b=v[:3]
        if kind==1:return (a*x+b)**g if a!=0 and x>=-b/a else 0.0
        if kind==2:return (a*x+b)**g+v[3] if a!=0 and x>=-b/a else v[3]
        c,d=v[3:5]
        if kind==3:return (a*x+b)**g if x>=d else c*x
        e,f=v[5:7]
        return (a*x+b)**g+e if x>=d else c*x+f
    vals=[evaluate(x) for x in samples];need(all(isinstance(x,(int,float)) and math.isfinite(x) for x in vals), 'nonfinite ICC TRC')
    return vals

def description_text(tag: bytes) -> str | None:
    if tag[:4] == b'desc':
        count = u32(tag, 8)
        need(12 + count <= len(tag), 'ICC description bounds')
        return tag[12:12+count].rstrip(b'\0').decode('latin-1')
    if tag[:4] != b'mluc':
        return None
    count, size = u32(tag, 8), u32(tag, 12)
    need(count >= 1 and size >= 12 and 16 + count*size <= len(tag), 'ICC localized-description records')
    texts = []
    for i in range(count):
        at = 16 + i*size
        n, pos = u32(tag, at+4), u32(tag, at+8)
        need(n % 2 == 0 and pos >= 16 + count*size and pos+n <= len(tag), 'ICC localized-description bounds')
        texts.append(tag[pos:pos+n].decode('utf-16-be').rstrip('\0'))
    return texts[0]

def icc_info(data: bytes) -> dict:
    need(132<=len(data)<=LIMIT and u32(data,0)==len(data), 'ICC declared size')
    need(data[36:40]==b'acsp' and data[16:20]==b'RGB ' and data[20:24]==b'XYZ ', 'RGB/XYZ ICC signature')
    count=u32(data,128);end=132+12*count;need(end<=len(data),'ICC directory bounds')
    tags={}
    for i in range(count):
        at=132+12*i;name=data[at:at+4];p=u32(data,at+4);n=u32(data,at+8)
        need(name not in tags and p>=end and p%4==0 and n>=8 and p+n<=len(data),'ICC tag bounds/duplicate')
        tags[name]=data[p:p+n]
    columns=[];trcs=[]
    for name in (b'r',b'g',b'b'):
        need(name+b'XYZ' in tags and name+b'TRC' in tags,'ICC matrix/TRC missing')
        t=tags[name+b'XYZ'];need(t[:4]==b'XYZ ' and len(t)>=20,'ICC colorant')
        columns.append([fixed(t,8+4*i) for i in range(3)])
        trcs.append(curve_values(tags[name+b'TRC']))
    return {'bytes':len(data),'xyz_d50':[columns[c][r] for r in range(3) for c in range(3)],
            'trc_samples':trcs,'tags':[t.decode('ascii','replace') for t in tags],
            'description':description_text(tags[b'desc']) if b'desc' in tags else None}

def equivalent(a: dict,b: dict) -> None:
    need(all(abs(x-y)<=5e-4 for x,y in zip(a['xyz_d50'],b['xyz_d50'])), 'ICC gamut changed')
    need(all(abs(x-y)<=2e-3 for aa,bb in zip(a['trc_samples'],b['trc_samples']) for x,y in zip(aa,bb)), 'ICC transfer changed')

def inspect_svg(path: Path, images: int) -> dict:
    data=path.read_bytes();need(b'<!DOCTYPE' not in data and b'<!ENTITY' not in data,'unexpected XML DTD')
    root=ET.fromstring(data);ns='{http://www.w3.org/2000/svg}'
    need(root.tag==ns+'svg','SVG root')
    need([float(x) for x in root.attrib['viewBox'].split()]==[0,0,720,500],'SVG viewBox')
    for key,value in (('width',720),('height',500)):
        s=root.attrib[key];need(s.endswith('pt') and abs(float(s[:-2])-value)<1e-6,'SVG physical size')
    need(not list(root.iter(ns+'text')),'SVG text must be outlined')
    ids=[e.attrib['id'] for e in root.iter() if 'id' in e.attrib]
    need(len(ids)==len(set(ids)),'duplicate SVG IDs')
    refs=[]
    for el in root.iter():
        for key,value in el.attrib.items():
            refs+=re.findall(r'url\(#([^)]*)\)',value)
            if key in ('href','{http://www.w3.org/1999/xlink}href') and value.startswith('#'):refs.append(value[1:])
    need(all(ref in ids for ref in refs),'missing SVG resource')
    nodes=list(root.iter(ns+'image'));need(len(nodes)==images,'unexpected embedded image count')
    sizes=[]
    for node in nodes:
        href=node.attrib.get('{http://www.w3.org/1999/xlink}href',node.attrib.get('href',''))
        need(href.startswith('data:image/png;base64,'),'external/non-PNG image')
        raw=base64.b64decode(href.split(',',1)[1],validate=True);chunks=png_chunks(raw)
        sizes.append(list(struct.unpack('>II',chunks[0][1][:8])))
    return {'size_points':[720,500],'embedded_png_sizes':sizes,'outlined_text':True}

def inspect_pdf(path: Path,pdfa: bool) -> dict:
    from pypdf import PdfReader
    r=PdfReader(path);need(len(r.pages)==3,'PDF page count')
    for page in r.pages:
        need(abs(float(page.mediabox.width)-720)<0.01 and abs(float(page.mediabox.height)-500)<0.01,'PDF page size')
    root=r.trailer['/Root'];intents=root.get('/OutputIntents');meta=root.get('/Metadata')
    if intents is not None:intents=intents.get_object()
    if pdfa:
        need(bool(intents) and meta is not None,'PDF-A mode intent/metadata missing')
        intent=intents[0].get_object();profile=intent['/DestOutputProfile'].get_object()
        need(profile['/N']==3 and profile.get_data()[16:20]==b'RGB ','RGB PDF output intent')
        xml=ET.fromstring(meta.get_object().get_data())
        parts=[e.text for e in xml.iter() if e.tag=='{http://www.aiim.org/pdfa/ns/id/}part']
        need(parts==['2'],'PDF/A identification part')
        levels=[e.text for e in xml.iter() if e.tag=='{http://www.aiim.org/pdfa/ns/id/}conformance']
        need(levels==['B'],'PDF/A identification conformance level')
    else:need(not intents,'normal PDF unexpectedly has output intent')
    return {'pages':3,'output_intent':bool(intents),'xmp':bool(meta),'certified_pdfa':False}

def inspect_probe(prefix: Path,pdf: bool) -> dict:
    def path(s):return Path(str(prefix)+s)
    output={'images':{},'svg':{}}
    extractors={'png':png_icc,'jpeg':jpeg_icc,'webp':webp_icc}
    for space in ('p3','srgb'):
        baseline=icc_info(path('.'+space+'.icc').read_bytes())
        for fmt,extract in extractors.items():
            info=icc_info(extract(path('.'+space+'.'+fmt).read_bytes()));equivalent(info,baseline)
            need(info['description']=='Color output '+space, 'explicit ICC description was not forwarded')
            output['images'][space+'.'+fmt]=info
    for stem,count in (('gamma',3),('gamuts',4),('encoded',6)):
        output['svg'][stem]=inspect_svg(path('.'+stem+'.svg'),count)
    trace=json.loads(path('.trace.json').read_text())['spaces']
    need(trace[0]['first-pixel']!=trace[1]['first-pixel'],'native gamut conversion did not change samples')
    output['trace']=trace
    output['pdf']=({'normal':inspect_pdf(path('.pdf'),False),'pdfa_mode':inspect_pdf(path('.pdfa.pdf'),True)}
                   if pdf else 'NOT CHECKED (use --pdf)')
    output['visual_review']='NOT PERFORMED by structural inspector'
    output['pdfa_conformance']='NOT VALIDATED; output intent and XMP are not conformance certification'
    return output

# Synthetic fixtures for inspector-only tests.
def synthetic_icc() -> bytes:
    xyz=b'XYZ '+b'\0'*4+struct.pack('>iii',65536,0,0)
    curve=b'curv'+b'\0'*4+struct.pack('>IH',1,256)+b'\0'*2
    tags=[(c+b'XYZ',xyz) for c in (b'r',b'g',b'b')]+[(c+b'TRC',curve) for c in (b'r',b'g',b'b')]
    pos=132+12*len(tags);table=b'';body=b''
    for tag,payload in tags:table+=tag+struct.pack('>II',pos,len(payload));body+=payload;pos+=len(payload)
    h=bytearray(132);h[:4]=struct.pack('>I',pos);h[16:24]=b'RGB XYZ ';h[36:40]=b'acsp';h[128:]=struct.pack('>I',len(tags))
    return bytes(h)+table+body

def png_chunk(t,b):return struct.pack('>I',len(b))+t+b+struct.pack('>I',binascii.crc32(t+b)&0xffffffff)
def synthetic_png(profile):
    return PNG+png_chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,2,0,0,0))+png_chunk(b'iCCP',b'ICC\0\0'+zlib.compress(profile))+png_chunk(b'IDAT',zlib.compress(b'\0\0\0\0'))+png_chunk(b'IEND',b'')
def synthetic_jpeg(profile,split=False):
    values=[profile[:180],profile[180:]] if split else [profile]
    out=b'\xff\xd8'
    for i,b in enumerate(values,1):
        body=b'ICC_PROFILE\0'+bytes((i,len(values)))+b;out+=b'\xff\xe2'+struct.pack('>H',len(body)+2)+body
    return out+b'\xff\xd9'
def riff_chunk(t,b):return t+struct.pack('<I',len(b))+b+b'\0'*(len(b)%2)
def synthetic_webp(profile):
    body=b'WEBP'+riff_chunk(b'VP8X',b'\x20'+b'\0'*9)+riff_chunk(b'ICCP',profile)+riff_chunk(b'VP8L',b'\0'*5)
    return b'RIFF'+struct.pack('<I',len(body))+body

class Checks(unittest.TestCase):
    def test_png_profile(self):self.assertEqual(png_icc(synthetic_png(synthetic_icc())),synthetic_icc())
    def test_png_crc(self):
        b=bytearray(synthetic_png(synthetic_icc()));b[20]^=1
        with self.assertRaises(ValueError):png_icc(bytes(b))
    def test_png_truncation(self):
        with self.assertRaises(ValueError):png_icc(synthetic_png(synthetic_icc())[:-3])
    def test_profile_bounded_inflate(self):
        with self.assertRaises(ValueError):bounded_inflate(zlib.compress(b'a')[:-1])
    def test_jpeg_multisegment(self):self.assertEqual(jpeg_icc(synthetic_jpeg(synthetic_icc(),True)),synthetic_icc())
    def test_jpeg_missing_segment(self):
        b=bytearray(synthetic_jpeg(synthetic_icc()));b[19]=2
        with self.assertRaises(ValueError):jpeg_icc(bytes(b))
    def test_jpeg_duplicate_segment(self):
        b=synthetic_jpeg(synthetic_icc());b=b[:-2]+b[2:]
        with self.assertRaises(ValueError):jpeg_icc(b)
    def test_webp_profile(self):self.assertEqual(webp_icc(synthetic_webp(synthetic_icc())),synthetic_icc())
    def test_webp_flag(self):
        b=bytearray(synthetic_webp(synthetic_icc()));b[20]=0
        with self.assertRaises(ValueError):webp_icc(bytes(b))
    def test_webp_length(self):
        with self.assertRaises(ValueError):webp_icc(synthetic_webp(synthetic_icc())+b'x')
    def test_icc_tag_bounds(self):
        b=bytearray(synthetic_icc());b[136:140]=struct.pack('>I',0xffffffff)
        with self.assertRaises(ValueError):icc_info(bytes(b))
    def test_icc_semantics(self):
        a=icc_info(synthetic_icc());equivalent(a,a)
        b=dict(a);b['xyz_d50']=[0.0]*9
        with self.assertRaises(ValueError):equivalent(a,b)
    def test_icc_localized_description(self):
        text='Color output p3'.encode('utf-16-be')
        tag=b'mluc'+b'\0'*4+struct.pack('>II',1,12)+b'enUS'+struct.pack('>II',len(text),28)+text
        self.assertEqual(description_text(tag),'Color output p3')
        with self.assertRaises(ValueError):description_text(tag[:-1])
    def test_icc_transfer_order(self):
        b=b'para'+b'\0'*4+struct.pack('>HH',4,0)+b''.join(struct.pack('>i',round(v*65536)) for v in (2,1,0,0.1,0.5,0.2,0.3))
        a=curve_values(b)
        self.assertAlmostEqual(a[4],0.325,places=4);self.assertAlmostEqual(a[6],0.7625,places=4)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--self-test',action='store_true');p.add_argument('--probe-prefix',type=Path);p.add_argument('--pdf',action='store_true');args=p.parse_args()
    if args.self_test:
        suite=unittest.defaultTestLoader.loadTestsFromTestCase(Checks)
        if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():raise SystemExit(1)
    if args.probe_prefix:
        try:print(json.dumps(inspect_probe(args.probe_prefix,args.pdf),indent=2))
        except ImportError as exc:raise SystemExit('--pdf requires pypdf; install it in your Python environment') from exc
        except (ValueError,KeyError,OSError,UnicodeError,ET.ParseError) as exc:raise SystemExit(str(exc)) from exc
    if not args.self_test and not args.probe_prefix:p.error('use --self-test and/or --probe-prefix')
