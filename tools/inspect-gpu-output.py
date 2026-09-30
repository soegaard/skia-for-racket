#!/usr/bin/env python3
"""Inspect actual bounded-output PDF/SVG files and their execution diagnostics.

Standard library only. The PDF reader accepts the plain-xref subset emitted by
our pinned Skia diagnostic, not arbitrary PDFs. Numerical checks decode SVG's
embedded PNG pixels. PDF checks verify page/resources/placement/vector/links,
not a rendered PDF screenshot or PDF/A/ICC/font certification.
"""
from __future__ import annotations
import argparse
import base64
import copy
import html
import importlib.util
import json
import math
from pathlib import Path
import re
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zlib

_spec = importlib.util.spec_from_file_location('output_png', Path(__file__).with_name('inspect-gpu-offscreen.py'))
_png = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_png)
NATIVE_TEST_CASES = 42
SIZE = (210, 144)
PAGE = (240, 180)
NAMES = ('pattern', 'effects', 'perspective', 'nested')
BACKENDS = _png.BACKEND_IDS
URL = 'https://example.org/gpu-output'
LIMIT = 32 * 1024 * 1024
TOLERANCES = {'pattern': (0, 0), 'effects': (3.0, .06),
              'perspective': (3.0, .06), 'nested': (3.0, .06)}


def need(value, message):
    if not value:
        raise ValueError(message)


def integer(value, low=0):
    return type(value) is int and value >= low


def file_path(directory, name, extension):
    need(isinstance(name, str) and name not in ('', '.', '..') and
         not any(c in name for c in '/\\:') and name.endswith(extension), 'unsafe document filename')
    path = directory / name
    need(not path.is_symlink() and path.is_file() and path.stat().st_size <= LIMIT,
         'missing, symbolic, or excessive document file')
    return path


def inflate(data):
    decoder = zlib.decompressobj()
    result = decoder.decompress(data, LIMIT + 1)
    need(len(result) <= LIMIT and decoder.eof and not decoder.unused_data and
         not decoder.unconsumed_tail, 'invalid/excessive Flate stream')
    return result


# Small strict PDF syntax reader for generated test artifacts. References and
# names stay distinct from strings; no object is discovered by regex in pixels.
class Name(str):
    pass


class Ref(tuple):
    pass


class Syntax:
    def __init__(self, data, start=0):
        self.data, self.pos = data, start

    def space(self):
        while self.pos < len(self.data):
            if self.data[self.pos] in b'\x00\t\n\f\r ':
                self.pos += 1
            elif self.data[self.pos:self.pos+1] == b'%':
                end = self.data.find(b'\n', self.pos)
                self.pos = len(self.data) if end < 0 else end+1
            else:
                break

    def value(self, depth=0):
        need(depth < 40, 'excessive PDF nesting')
        self.space()
        data = self.data
        if data[self.pos:self.pos+2] == b'<<':
            self.pos += 2
            result = {}
            while True:
                self.space()
                if data[self.pos:self.pos+2] == b'>>':
                    self.pos += 2
                    return result
                key = self.value(depth+1)
                need(isinstance(key, Name) and key not in result, 'invalid/duplicate PDF dictionary key')
                result[key] = self.value(depth+1)
        if data[self.pos:self.pos+1] == b'[':
            self.pos += 1
            result = []
            while True:
                self.space()
                if data[self.pos:self.pos+1] == b']':
                    self.pos += 1
                    return result
                need(len(result) < 10000, 'excessive PDF array')
                result.append(self.value(depth+1))
        if data[self.pos:self.pos+1] == b'(':
            self.pos += 1
            out, nesting = bytearray(), 1
            while self.pos < len(data):
                char = data[self.pos]; self.pos += 1
                if char == 92:
                    need(self.pos < len(data), 'truncated PDF string')
                    char = data[self.pos]; self.pos += 1
                    escapes = {110:10, 114:13, 116:9, 98:8, 102:12}
                    if char in escapes:
                        out.append(escapes[char])
                    elif char in (10, 13):
                        if char == 13 and data[self.pos:self.pos+1] == b'\n': self.pos += 1
                    elif 48 <= char <= 55:
                        digits = bytes([char])
                        for _ in range(2):
                            if self.pos < len(data) and 48 <= data[self.pos] <= 55:
                                digits += data[self.pos:self.pos+1]; self.pos += 1
                            else: break
                        out.append(int(digits, 8) & 255)
                    else: out.append(char)
                elif char == 40:
                    nesting += 1; out.append(char)
                elif char == 41:
                    nesting -= 1
                    if not nesting: return bytes(out)
                    out.append(char)
                else: out.append(char)
            raise ValueError('unterminated PDF string')
        if data[self.pos:self.pos+1] == b'<':
            end = data.find(b'>', self.pos+1)
            need(end >= 0, 'unterminated hex string')
            text = re.sub(rb'\s', b'', data[self.pos+1:end])
            if len(text) % 2: text += b'0'
            self.pos = end+1
            return bytes.fromhex(text.decode('ascii'))
        if data[self.pos:self.pos+1] == b'/':
            self.pos += 1
            match = re.match(rb'[^\x00\s()<>\[\]{}/%]+', data[self.pos:])
            need(match, 'empty PDF name')
            self.pos += len(match[0])
            raw = re.sub(rb'#([0-9a-fA-F]{2})', lambda m: bytes([int(m[1], 16)]), match[0])
            return Name(raw.decode('latin1'))
        match = re.match(rb'[+-]?(?:\d+(?:\.\d*)?|\.\d+)', data[self.pos:])
        if match:
            self.pos += len(match[0]); number = match[0]
            if b'.' not in number:
                reference = re.match(rb'\s+(\d+)\s+R\b', data[self.pos:])
                if reference:
                    self.pos += len(reference[0])
                    return Ref((int(number), int(reference[1])))
                return int(number)
            return float(number)
        for word, value in ((b'true', True), (b'false', False), (b'null', None)):
            if data[self.pos:self.pos+len(word)] == word:
                self.pos += len(word); return value
        raise ValueError(f'unsupported PDF token at {self.pos}')


class PDF:
    def __init__(self, data):
        need(data.startswith(b'%PDF-') and len(data) <= LIMIT, 'not a bounded PDF')
        match = re.search(rb'startxref\s+(\d+)\s+%%EOF\s*$', data)
        need(match, 'missing PDF startxref/EOF')
        position = int(match[1])
        need(data[position:position+4] == b'xref', 'expected pinned plain PDF xref table')
        syntax = Syntax(data, position+4)
        self.data, self.offsets, self.cache, self.busy = data, {}, {}, set()
        while True:
            syntax.space()
            if data[syntax.pos:syntax.pos+7] == b'trailer':
                syntax.pos += 7; break
            line = re.match(rb'(\d+)\s+(\d+)\s*\r?\n', data[syntax.pos:])
            need(line, 'invalid PDF xref subsection')
            start, count = int(line[1]), int(line[2]); syntax.pos += len(line[0])
            need(count <= 10000, 'excessive PDF objects')
            for n in range(start, start+count):
                row = re.match(rb'(\d{10}) (\d{5}) ([nf])[^\S\r\n]*\r?\n', data[syntax.pos:])
                need(row, 'invalid PDF xref row'); syntax.pos += len(row[0])
                if row[3] == b'n':
                    need(n not in self.offsets and int(row[1]) < position, 'duplicate/bad PDF object offset')
                    self.offsets[n] = (int(row[1]), int(row[2]))
        trailer = syntax.value()
        need(isinstance(trailer, dict) and 'Encrypt' not in trailer and 'Prev' not in trailer,
             'encrypted/incremental PDF is outside the diagnostic contract')
        self.trailer = trailer

    def object(self, ref):
        need(isinstance(ref, Ref) and ref[0] in self.offsets, 'missing PDF object reference')
        if ref in self.cache: return self.cache[ref]
        need(ref not in self.busy, 'cyclic PDF object parsing')
        offset, generation = self.offsets[ref[0]]
        need(generation == ref[1], 'PDF generation mismatch')
        header = re.match(rb'(\d+)\s+(\d+)\s+obj\b', self.data[offset:])
        need(header and (int(header[1]), int(header[2])) == ref, 'PDF xref/object mismatch')
        self.busy.add(ref)
        syntax = Syntax(self.data, offset+len(header[0]))
        value = syntax.value(); syntax.space(); stream = None
        if self.data[syntax.pos:syntax.pos+6] == b'stream':
            need(isinstance(value, dict), 'PDF stream is not a dictionary')
            length = self.deref(value.get('Length'))
            need(integer(length) and length <= LIMIT, 'invalid PDF stream length')
            syntax.pos += 6
            newline = re.match(rb'\r?\n', self.data[syntax.pos:])
            need(newline, 'missing stream newline'); syntax.pos += len(newline[0])
            stream = self.data[syntax.pos:syntax.pos+length]; syntax.pos += length
            need(len(stream) == length, 'truncated PDF stream'); syntax.space()
            need(self.data[syntax.pos:syntax.pos+9] == b'endstream', 'PDF stream extent mismatch')
            syntax.pos += 9; syntax.space()
        need(self.data[syntax.pos:syntax.pos+6] == b'endobj', 'unterminated PDF object')
        self.cache[ref] = (value, stream); self.busy.remove(ref)
        return value, stream

    def deref(self, value):
        return self.object(value)[0] if isinstance(value, Ref) else value

    def stream(self, ref):
        value, data = self.object(ref)
        need(data is not None, 'missing PDF content stream')
        filters = value.get('Filter')
        if filters is None: return data
        need(filters in (Name('FlateDecode'), [Name('FlateDecode')]) and not value.get('DecodeParms'),
             'unexpected pinned PDF content-stream encoding')
        return inflate(data)


IDENTITY = (1.,0.,0.,1.,0.,0.)
def multiply(a,b):
    x,y,z,w,u,v=a; A,B,C,D,E,F=b
    return (x*A+z*B,y*A+w*B,x*C+z*D,y*C+w*D,x*E+z*F+u,y*E+w*F+v)

def rectangle(matrix,width,height):
    a,b,c,d,e,f=matrix
    points=[(a*x+c*y+e,b*x+d*y+f) for x,y in ((0,0),(width,0),(0,height),(width,height))]
    xs,ys=zip(*points)
    return [min(xs),min(ys),max(xs)-min(xs),max(ys)-min(ys)]

def close_rectangle(actual,expected):
    return all(math.isfinite(a) and abs(a-b)<=.01 for a,b in zip(actual,expected))

def svg_transform(text):
    result=IDENTITY; pos=0
    for match in re.finditer(r'(matrix|translate|scale)\s*\(([^)]*)\)',text):
        need(not text[pos:match.start()].strip(' ,\t\r\n'), 'unsupported SVG transform')
        args=[float(x) for x in re.split(r'[\s,]+',match[2].strip()) if x]
        need(all(math.isfinite(x) for x in args), 'nonfinite SVG transform')
        if match[1]=='matrix': need(len(args)==6,'bad SVG matrix'); matrix=args
        elif match[1]=='translate':
            need(len(args) in (1,2),'bad SVG translation'); matrix=(1,0,0,1,args[0],args[1] if len(args)==2 else 0)
        else:
            need(len(args) in (1,2),'bad SVG scale'); matrix=(args[0],0,0,args[-1],0,0)
        result=multiply(result,matrix);pos=match.end()
    need(not text[pos:].strip(' ,\t\r\n'), 'unsupported SVG transform suffix')
    return result

def inspect_pdf(data):
    pdf = PDF(data)
    catalog = pdf.deref(pdf.trailer.get('Root'))
    need(isinstance(catalog, dict) and catalog.get('Type') == Name('Catalog'), 'missing PDF catalog')
    pages = []
    def visit(reference, inherited, depth=0):
        need(depth < 10, 'excessive PDF page tree')
        value = pdf.deref(reference)
        need(isinstance(value, dict), 'bad PDF page tree node')
        inherited = dict(inherited, **{k:value[k] for k in ('MediaBox','Resources') if k in value})
        if value.get('Type') == Name('Page'):
            pages.append(dict(inherited, **value))
        else:
            need(value.get('Type') == Name('Pages'), 'bad page-tree type')
            kids = pdf.deref(value.get('Kids'))
            need(isinstance(kids, list) and 0 < len(kids) <= 2, 'unexpected page count')
            for kid in kids: visit(kid, inherited, depth+1)
    visit(catalog.get('Pages'), {})
    need(len(pages) == 1, 'expected a single PDF page')
    page = pages[0]
    need(pdf.deref(page.get('MediaBox')) == [0,0,*PAGE], 'PDF page bounds changed')
    annotations = pdf.deref(page.get('Annots', []))
    need(isinstance(annotations, list), 'bad PDF annotations')
    links = [pdf.deref(pdf.deref(a).get('A', {})) for a in annotations]
    need(any(a.get('S') == Name('URI') and a.get('URI') == URL.encode() for a in links),
         'outside-group PDF hyperlink was lost')
    contents = page.get('Contents')
    if isinstance(contents, Ref): contents = [contents]
    need(isinstance(contents, list) and contents, 'missing PDF page contents')
    used_images = []; placements = []; vector_ops = 0
    def drawing(stream, resources, depth=0, matrix=IDENTITY):
        nonlocal vector_ops
        need(depth < 8, 'excessive PDF form nesting')
        # These operators certify retained vector paths, not their visual look.
        vector_ops += len(re.findall(rb'(?:^|\s)(?:m|l|c|re|f|f\*|S)(?=\s|$)', stream))
        resources = pdf.deref(resources)
        need(isinstance(resources, dict), 'missing PDF resources')
        xobjects = pdf.deref(resources.get('XObject', {}))
        stack=[]; operands=[]
        tokens=re.findall(rb'%[^\r\n]*|<[^>]*>|\((?:\\.|[^\\)])*\)|/[^\s/<>\[\]()]+|[^\s]+', stream)
        for token in tokens:
            if token.startswith(b'%'): continue
            if token == b'q': stack.append(matrix); operands=[]; continue
            if token == b'Q':
                need(stack,'unbalanced PDF graphics stack');matrix=stack.pop();operands=[];continue
            if token == b'cm':
                need(len(operands)>=6,'missing PDF matrix operands')
                numbers=[float(x) for x in operands[-6:]]
                need(all(math.isfinite(x) for x in numbers),'nonfinite PDF matrix')
                matrix=multiply(matrix,numbers);operands=[];continue
            if token != b'Do':
                if re.fullmatch(rb'[+-]?(?:\d+(?:\.\d*)?|\.\d+)',token) or token.startswith(b'/'):
                    operands.append(token)
                else: operands=[]
                continue
            need(operands and operands[-1].startswith(b'/'),'bad PDF Do operand')
            token=operands[-1][1:];operands=[]
            reference = xobjects.get(Name(token.decode('latin1')))
            need(isinstance(reference, Ref), 'unresolved PDF image/form invocation')
            target = pdf.deref(reference)
            if target.get('Subtype') == Name('Image'):
                need((target.get('Width'), target.get('Height')) == SIZE and target.get('BitsPerComponent') == 8,
                     'PDF contains a wrong-size/whole-page image')
                mask = target.get('SMask')
                if mask:
                    mask_dict = pdf.deref(mask)
                    need(mask_dict.get('Subtype') == Name('Image') and
                         (mask_dict.get('Width'),mask_dict.get('Height')) == SIZE,
                         'PDF alpha mask dimensions mismatch')
                used_images.append(reference)
                placed=rectangle(matrix,1,1)
                need(close_rectangle(placed,[32,40,140,96]), 'PDF image placement/size changed')
                placements.append(placed)
            else:
                need(target.get('Subtype') == Name('Form'), 'unexpected PDF XObject')
                drawing(pdf.stream(reference), target.get('Resources', resources), depth+1, multiply(matrix,target.get('Matrix',IDENTITY)))
    for ref in contents: drawing(pdf.stream(ref), page.get('Resources'))
    need(len(used_images) == 1, 'PDF must invoke exactly one bounded raster image')
    need(vector_ops >= 8, 'PDF vector surroundings were lost')
    return dict(page_size=list(PAGE), embedded_images=1, embedded_pixel_size=list(SIZE),
                vector_path_operators=vector_ops, image_placements=placements, outside_group_link=True,
                pixel_rendering_verified=False)


SVG_NS = 'http://www.w3.org/2000/svg'
XLINK_NS = 'http://www.w3.org/1999/xlink'

def inspect_svg(data):
    need(len(data) <= LIMIT and b'<!ENTITY' not in data and b'<!DOCTYPE' not in data,
         'unexpected XML declarations')
    root = ET.fromstring(data)
    need(root.tag == '{'+SVG_NS+'}svg', 'missing SVG root')
    viewbox = [float(x) for x in re.split(r'[\s,]+', root.get('viewBox','').strip()) if x]
    need(viewbox == [0,0,*PAGE], 'SVG page bounds changed')
    images = list(root.iter('{'+SVG_NS+'}image'))
    need(len(images) == 1, 'SVG must embed exactly one bounded image')
    image = images[0]
    need(float(image.get('width','0')) == SIZE[0] and float(image.get('height','0')) == SIZE[1],
         'SVG image dimensions changed/whole-page raster')
    href = image.get('{'+XLINK_NS+'}href', image.get('href',''))
    need(href.startswith('data:image/png;base64,'), 'SVG image is not an embedded PNG')
    encoded = base64.b64decode(re.sub(r'\s', '', href.split(',',1)[1]), validate=True)
    pixels = _png.png(encoded, SIZE)
    anchors = list(root.iter('{'+SVG_NS+'}a'))
    need(any(a.get('{'+XLINK_NS+'}href', a.get('href')) == URL for a in anchors),
         'outside-group SVG hyperlink was lost')
    shapes = [e for e in root.iter() if e.tag.rsplit('}',1)[-1] in ('path','rect','line','polyline')]
    need(len(shapes) >= 3, 'SVG vector surroundings were lost')
    placements=[]
    def walk(element,matrix=IDENTITY,in_defs=False):
        tag=element.tag.rsplit('}',1)[-1]
        current=multiply(matrix,svg_transform(element.get('transform','')))
        in_defs=in_defs or tag=='defs'
        href=element.get('{'+XLINK_NS+'}href',element.get('href',''))
        if not in_defs and (element is image or (tag=='use' and href=='#'+image.get('id',''))):
            current=multiply(current,(1,0,0,1,float(element.get('x',0)),float(element.get('y',0))))
            placed=rectangle(current,*SIZE)
            need(close_rectangle(placed,[32,44,140,96]),'SVG image placement/size changed')
            placements.append(placed)
        for child in element: walk(child,current,in_defs)
    walk(root)
    need(len(placements)==1, 'SVG must render its embedded image once')
    return dict(page_size=list(PAGE), embedded_images=1, embedded_pixel_size=list(SIZE),
                vector_shapes=len(shapes), image_placements=placements, outside_group_link=True), pixels


def pattern_pixels():
    pixels = bytearray(SIZE[0]*SIZE[1]*4)
    def rect(x,y,w,h,color):
        left,top = int((x+8)*1.5), int((y+10)*1.5)
        for yy in range(top, top+int(h*1.5)):
            for xx in range(left, left+int(w*1.5)):
                start = 4*(xx+yy*SIZE[0]); pixels[start:start+4] = bytes(color)
    rect(16,16,56,32,(128,0,0,128))
    rect(0,0,8,6,(255,0,0,255)); rect(112,0,8,10,(0,255,0,255))
    rect(0,60,12,12,(0,0,255,255)); rect(108,64,12,8,(255,255,0,255))
    return bytes(pixels)


def pixel(pixels,x,y):
    start = 4*(x+y*SIZE[0]); return pixels[start:start+4]


def markers(pixels):
    for (x,y), expected in [((15,18),(255,0,0,255)), ((185,18),(0,255,0,255)),
                           ((18,115),(0,0,255,255)), ((178,117),(255,255,0,255)),
                           ((0,0),(0,0,0,0)), ((209,0),(0,0,0,0))]:
        need(pixel(pixels,x,y) == bytes(expected), f'orientation/alpha marker wrong at {(x,y)}')


def compare(cpu,gpu,name):
    markers(cpu); markers(gpu)
    if name == 'pattern':
        expected = pattern_pixels()
        need(cpu == expected and gpu == expected, 'pattern differs from independent exact expected pixels')
    # Compare associated color plus alpha, so RGB hidden behind alpha zero
    # cannot dominate an otherwise correct transparent filter margin.
    total = maximum = large = foreground_cpu = foreground_gpu = count = 0
    for y in range(15,123):
        for x in range(12,192):
            a,b = pixel(cpu,x,y),pixel(gpu,x,y)
            aa = [round(v*a[3]/255) for v in a[:3]]+[a[3]]
            bb = [round(v*b[3]/255) for v in b[:3]]+[b[3]]
            differences = [abs(u-v) for u,v in zip(aa,bb)]
            total += sum(differences); maximum = max(maximum,max(differences))
            large += max(differences)>24; count += 1
            foreground_cpu += a[3]>16; foreground_gpu += b[3]>16
    mean,fraction = total/(4*count),large/count
    need(foreground_cpu>100 and .8 <= foreground_gpu/foreground_cpu <= 1.2, 'missing/extra GPU artwork')
    ml,fl = TOLERANCES[name]
    need(mean<=ml and fraction<=fl, f'{name}: pixel comparison failed ({mean:.5f}, {fraction:.5f})')
    return dict(name=name, mean_absolute_channel_error=round(mean,6), max_channel_error=maximum,
                large_error_pixel_fraction=round(fraction,6), large_error_threshold=24,
                mean_limit=ml, large_fraction_limit=fl, roi=[12,15,180,108],
                comparison_space='premultiplied RGBA', exact_orientation_alpha_markers=True)


def context(value, backend, closed=False):
    _png.context(value, backend=backend, closed=closed)


def raster_group(group, *, backend, generation, variant, name, nested=False):
    need(isinstance(group,dict) and group.get('strategy')=='raster', 'missing raster-selected group')
    need(group.get('pixel_size') == list(SIZE) and group.get('scale') == 1.5, 'group pixel size/scale mismatch')
    bounds = [0,0,120,72] if nested else [40,54,120,72]
    padded = [-8,-10,140,96] if nested else [32,44,140,96]
    need(group.get('bounds') == bounds and group.get('padded_bounds') == padded, 'group padding/placement changed')
    need(group.get('policy') == ('raster' if name=='pattern' else 'prefer-vector'), 'representation policy changed')
    need(group.get('reason') == ('explicit-raster' if name=='pattern' else 'backend-fallback'), 'representation reason changed')
    need(group.get('captured_children') == [], 'unexpected raster descendants')
    execution = group.get('execution',{})
    need(execution.get('phase')=='completed' and execution.get('fallback') is False and
         execution.get('image_storage')=='cpu-owned', 'incomplete/fallback/non-detached execution')
    expected_backend = backend if variant=='gpu' else 'raster'
    need(execution.get('requested')==variant and execution.get('backend')==expected_backend,
         'execution backend/request mismatch')
    transfers = execution.get('readback_count')
    need(type(transfers) is int and transfers==(1 if variant=='gpu' else 0), 'invalid transfer count')
    need(execution.get('transfer')==('gpu-to-cpu' if variant=='gpu' else 'none'), 'hidden/missing transfer')
    if variant=='cpu':
        need(execution.get('target') is False and execution.get('context_generation') is False,
             'CPU execution claimed a GPU target')
    else:
        target = execution.get('target',{})
        need(integer(execution.get('context_generation'),1) and execution['context_generation']==generation,
             'foreign executor generation')
        need(target.get('storage')=='gpu' and target.get('backend')==backend and
             type(target.get('native_backend')) is int and target['native_backend']==BACKENDS[backend] and
             target.get('context_matches') is True and target.get('context_generation')==generation,
             'target is not the selected native GPU')
        need((target.get('width'),target.get('height'))==SIZE and target.get('origin')=='top-left' and
             target.get('color_type')=='RGBA8888' and target.get('alpha_type')=='premultiplied' and
             target.get('render_path')=='sk_surface_new_render_target', 'incorrect GPU target geometry/format')
        need(type(target.get('requested_sample_count')) is int and target['requested_sample_count']==0 and
             target.get('actual_sample_count') is False, 'unverified sample count')
    return execution


def inspect(data, directory, *, hardware=False):
    need(data.get('schema_version')==1 and type(data['schema_version']) is int and
         data.get('stage')=='0.44' and data.get('kind')=='gpu-output' and data.get('status')=='passed',
         'wrong schema/stage or failed native diagnostic')
    backend = data.get('backend'); need(backend in BACKENDS,'unsupported backend')
    _png.check_backend_host(data, backend)
    need(isinstance(data.get('validation_run'),str) and data['validation_run'], 'missing run identity')
    need(data.get('performance_measured') is False, 'unmeasured performance claim')
    need(type(data.get('native_test_cases')) is int and data['native_test_cases']==NATIVE_TEST_CASES and
         type(data.get('native_test_failures')) is int and data['native_test_failures']==0,
         'missing/failed native tests')
    context(data.get('initial_context'),backend)
    for key in ('closed_context','other_closed_context'): context(data.get(key),backend,True)
    generation = data['initial_context']['generation']
    need(data['closed_context']['generation']==generation and
         data['other_closed_context']['generation']!=generation,'wrong/same foreign-context teardown')
    if hardware or data.get('require_hardware'):
        need(data['initial_context']['renderer_class']=='hardware-reported', 'hardware-reported renderer required')
    need(data.get('documents_serialized_after_gpu_teardown') is True, 'documents serialized before GPU teardown')
    documents=data.get('documents')
    expected={(name,variant,fmt) for name in NAMES for variant in ('cpu','gpu') for fmt in ('pdf','svg')}
    need(isinstance(documents,list) and len(documents)==len(expected),'missing/extra documents')
    seen=set(); paths=set(); pixels={}; summaries=[]
    for document in documents:
        name,variant,fmt=(document.get(k) for k in ('name','variant','format'))
        key=(name,variant,fmt)
        need(key in expected and key not in seen,'duplicate/unexpected document'); seen.add(key)
        need(document.get('serialized_after_gpu_teardown') is True,'document retained no post-teardown evidence')
        need(document.get('page_size')==list(PAGE) and document.get('expected_image_size')==list(SIZE),
             'document geometry declaration mismatch')
        need(type(document.get('authoring_calls')) is int and document['authoring_calls']==(2 if name=='nested' else 1),
             'authoring callback was rerun')
        group=document.get('group',{}); need(group.get('backend')==fmt,'wrong document representation backend')
        if name=='nested':
            need(group.get('strategy')=='native' and len(group.get('captured_children',[]))==1 and
                 group.get('pixel_size') is False,'nested outer group should remain native')
            execution=group.get('execution',{})
            need(execution.get('phase')=='native' and execution.get('backend')==fmt and
                 type(execution.get('readback_count')) is int and execution['readback_count']==0 and
                 execution.get('transfer')=='none', 'native parent incorrectly claims raster execution')
            raster=group['captured_children'][0]
            need(raster.get('backend')==fmt,'nested child lost document target')
        else: raster=group
        raster_group(raster,backend=backend,generation=generation,variant=variant,name=name,nested=name=='nested')
        audit=document.get('audit',{})
        need(audit.get('backend')==fmt and audit.get('blocking') is False and audit.get('vector_only') is False,
             'document audit did not preserve vector/raster distinction')
        events=audit.get('events',[])
        need(any(e.get('feature')=='geometry' and e.get('status')=='vector' for e in events) and
             any(e.get('feature')=='annotation' and e.get('status')=='vector' for e in events),
             'missing outer vector/annotation audit evidence')
        if name!='nested':
            executions=[e for e in events if e.get('operation')=='execute-output-group']
            need(len(executions)==1 and executions[0].get('status')=='rasterized', 'missing actual execution audit')
            actual=executions[0].get('details',{}).get('execution',{})
            need(actual.get('backend')==raster['execution']['backend'] and
                 actual.get('transfer')==raster['execution']['transfer'] and
                 actual.get('readback_count')==raster['execution']['readback_count'] and
                 actual.get('phase')==('rasterized' if variant=='gpu' else 'completed'),
                 'execution audit describes a plan rather than actual raster transfer')
        io=document.get('io_events',[]); need(isinstance(io,list),'missing IO ledger')
        downloads=[i for i,e in enumerate(io) if e.get('kind')=='readback']
        need(len(downloads)==(1 if variant=='gpu' else 0),'unexpected/missing CPU readback')
        if variant=='gpu':
            pos=downloads[0]; transfer=io[pos]
            need((transfer.get('width'),transfer.get('height'),transfer.get('row_bytes'))==(210,144,840),
                 'wrong download dimensions/stride')
            need(any(e.get('kind')=='flush' for e in io[pos+1:]) and
                 any(e.get('kind')=='submit' and e.get('wait_requested') is True for e in io[pos+1:]),
                 'readback did not explicitly complete GPU work')
        else: need(io==[],'CPU reference unexpectedly used GPU IO')
        file=document.get('file'); need(file not in paths,'document path reused'); paths.add(file)
        path=file_path(directory,file,'.'+fmt)
        if fmt=='svg':
            structure,p=inspect_svg(path.read_bytes()); pixels[(name,variant)]=p
        else: structure=inspect_pdf(path.read_bytes())
        summaries.append(dict(name=name,variant=variant,format=fmt,file=file,**structure))
    comparisons=[compare(pixels[(name,'cpu')],pixels[(name,'gpu')],name) for name in NAMES]
    return dict(schema_version=1,stage='0.44',kind='gpu-output',status='passed',backend=backend,
                validation_run=data['validation_run'],native_test_cases=NATIVE_TEST_CASES,
                documents_checked=len(documents),comparisons=comparisons,documents=summaries,
                vector_surroundings_and_links_verified=True,bounded_image_dimensions_verified=True,
                documents_serialized_after_gpu_teardown=True,gpu_group_readbacks=8,
                embedded_svg_pixels_verified=True,pdf_structure_verified=True,pdf_rendered_pixels_verified=False,
                renderer=data['initial_context']['renderer'],renderer_class=data['initial_context']['renderer_class'],
                performance_measured=False),pixels


def publish(prefix, *, hardware=False):
    inspection=Path(str(prefix)+'.inspection.json'); review=Path(str(prefix)+'.review.html')
    # A failed reinspection must not leave an old success looking current.
    for path in (inspection,review): path.unlink(missing_ok=True)
    data=json.loads(Path(str(prefix)+'.diagnostic.json').read_text())
    result,pixels=inspect(data,prefix.parent,hardware=hardware)
    rows=[]
    for name in NAMES:
        images=[]
        for variant in ('cpu','gpu'):
            uri=base64.b64encode(_png.png_bytes(pixels[(name,variant)],SIZE)).decode()
            links=' '.join(f'<a href="{html.escape(d["file"],quote=True)}">{d["format"].upper()}</a>'
                           for d in result['documents'] if d['name']==name and d['variant']==variant)
            images.append(f'<td><img alt="{name} {variant}" src="data:image/png;base64,{uri}"><p>{links}</p></td>')
        rows.append('<tr><th>'+name+'</th>'+''.join(images)+'</tr>')
    text=('''<!doctype html><meta charset="utf-8"><title>Bounded document fallbacks</title>
<style>body{font:16px system-ui;max-width:1100px;margin:3em auto;padding:0 1em}table{border-collapse:collapse;width:100%}td,th{padding:1em;border:1px solid #ccc}img{width:420px;max-width:100%;image-rendering:pixelated;background:repeating-conic-gradient(#eee 0 25%,white 0 50%) 0/16px 16px}code{overflow-wrap:anywhere}</style>
<h1>Bounded GPU document fallbacks</h1><p>Embedded PNGs from the actual SVG documents, not separate screenshots. Open PDF/SVG links to review vector surroundings, links and placement.</p>'''
          +'<p>Backend: '+html.escape(result['backend'])+'; renderer: '+html.escape(result['renderer'])
          +'; run: <code>'+html.escape(result['validation_run'])+'</code></p>'
          +'<p>PDF structure is checked; PDF rendered pixels, ICC/PDF-A compliance and performance are not certified.</p>'
          +'<table><tr><th>Scene</th><th>CPU</th><th>GPU → CPU image</th></tr>'+''.join(rows)+'</table>'
          +'<pre>'+html.escape(json.dumps(result['comparisons'],indent=2))+'</pre>')
    for destination,content in ((inspection,json.dumps(result,indent=2)+'\n'),(review,text)):
        with tempfile.NamedTemporaryFile('w',dir=destination.parent,delete=False,encoding='utf-8') as out:
            out.write(content); temporary=Path(out.name)
        temporary.replace(destination)
    return result


# Synthetic fixtures validate inspection logic only, never Racket/Ganesh.
def synthetic_pdf(pixels=None, *, size=SIZE, link=URL, vectors=True, placement=(140,0,0,96,32,40)):
    if pixels is None: pixels=pattern_pixels()
    rgb=bytes(c for i,c in enumerate(pixels) if i%4!=3)
    alpha=pixels[3::4]
    def stream(dictionary,raw):
        compressed=zlib.compress(raw)
        return b'<< '+dictionary+b' /Filter /FlateDecode /Length '+str(len(compressed)).encode()+b' >>\nstream\n'+compressed+b'\nendstream'
    content=(b'0 0 240 180 re f 20 34 m 216 34 l S 31 43 142 98 re S 20 20 m 30 20 l S\n' if vectors else b'')
    content += b'q '+(' '.join(str(x) for x in placement)).encode()+b' cm /X1 Do Q\n'
    objects=[b'<< /Type /Catalog /Pages 2 0 R >>',
             b'<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
             b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 240 180] /Resources << /XObject << /X1 5 0 R >> >> /Contents 4 0 R /Annots [7 0 R] >>',
             stream(b'',content),
             stream(f'/Type /XObject /Subtype /Image /Width {size[0]} /Height {size[1]} /BitsPerComponent 8 /ColorSpace /DeviceRGB /SMask 6 0 R'.encode(),rgb),
             stream(f'/Type /XObject /Subtype /Image /Width {size[0]} /Height {size[1]} /BitsPerComponent 8 /ColorSpace /DeviceGray'.encode(),alpha),
             b'<< /Type /Annot /Subtype /Link /Rect [20 148 190 166] /A << /S /URI /URI ('+link.encode()+b') >> >>']
    out=bytearray(b'%PDF-1.4\n');offsets=[]
    for index,body in enumerate(objects,1):
        offsets.append(len(out));out+=f'{index} 0 obj\n'.encode()+body+b'\nendobj\n'
    xref=len(out);out+=f'xref\n0 {len(objects)+1}\n0000000000 65535 f \n'.encode()
    for offset in offsets: out+=f'{offset:010d} 00000 n \n'.encode()
    out+=f'trailer\n<< /Size {len(objects)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
    return bytes(out)


def synthetic_svg(pixels=None, *, size=SIZE, link=URL, vectors=True, placement='matrix(.666666667 0 0 .666666667 32 44)'):
    if pixels is None: pixels=pattern_pixels()
    encoded=base64.b64encode(_png.png_bytes(pixels,size)).decode()
    shapes='<rect width="240" height="180"/><path d="M20 34L216 34"/><rect x="31" y="43" width="142" height="98"/>' if vectors else ''
    return (f'<svg xmlns="{SVG_NS}" xmlns:xlink="{XLINK_NS}" width="240" height="180" viewBox="0 0 240 180">'
            +shapes+f'<a xlink:href="{html.escape(link,quote=True)}"><rect fill-opacity="0" x="20" y="14" width="170" height="18"/></a>'
            +f'<defs><image id="im1" width="{size[0]}" height="{size[1]}" xlink:href="data:image/png;base64,{encoded}"/></defs>'
            +f'<use xlink:href="#im1" transform="{placement}"/></svg>').encode()


def synthetic(directory, backend='opengl'):
    context0=dict(backend=backend,native_backend=BACKENDS[backend],state='ready',generation=17,
                  live_children=0,pending_releases=0,failed_releases=0,binding_package='3.119.1',
                  native_version='119.0',renderer='synthetic test renderer',renderer_class='software',
                  owns_command_queue=True,requires_gl_context=False,requires_window=False,device='synthetic device')
    data=dict(schema_version=1,stage='0.44',kind='gpu-output',status='passed',backend=backend,
              validation_run='synthetic-test-run',performance_measured=False,
              native_test_cases=NATIVE_TEST_CASES,native_test_failures=0,
              initial_context=context0,closed_context=dict(context0,state='closed'),
              other_closed_context=dict(context0,state='closed',generation=18),
              documents_serialized_after_gpu_teardown=True,documents=[])
    for name in NAMES:
        for variant in ('cpu','gpu'):
            for fmt in ('pdf','svg'):
                target=dict(storage='gpu',backend=backend,native_backend=BACKENDS[backend],
                            context_matches=True,context_generation=17,width=210,height=144,origin='top-left',
                            color_type='RGBA8888',alpha_type='premultiplied',render_path='sk_surface_new_render_target',
                            requested_sample_count=0,actual_sample_count=False)
                execution=dict(phase='completed',requested=variant,backend=backend if variant=='gpu' else 'raster',
                               context_generation=17 if variant=='gpu' else False,fallback=False,image_storage='cpu-owned',
                               readback_count=1 if variant=='gpu' else 0,transfer='gpu-to-cpu' if variant=='gpu' else 'none',
                               target=target if variant=='gpu' else False)
                group=dict(backend=fmt,strategy='raster',pixel_size=list(SIZE),scale=1.5,
                           bounds=[40,54,120,72],padded_bounds=[32,44,140,96],
                           policy='raster' if name=='pattern' else 'prefer-vector',
                           reason='explicit-raster' if name=='pattern' else 'backend-fallback',
                           captured_children=[],execution=execution)
                events=[dict(feature='geometry',status='vector'),dict(feature='annotation',status='vector')]
                if name=='nested':
                    child=copy.deepcopy(group);child.update(bounds=[0,0,120,72],padded_bounds=[-8,-10,140,96])
                    group.update(strategy='native',pixel_size=False,captured_children=[child],
                                 execution=dict(phase='native',backend=fmt,readback_count=0,transfer='none'))
                else:
                    actual=copy.deepcopy(execution);actual['phase']='rasterized' if variant=='gpu' else 'completed'
                    events.append(dict(operation='execute-output-group',status='rasterized',details=dict(execution=actual)))
                file=f'{name}.{variant}.{fmt}'
                (directory/file).write_bytes(synthetic_pdf() if fmt=='pdf' else synthetic_svg())
                data['documents'].append(dict(name=name,variant=variant,format=fmt,file=file,
                     serialized_after_gpu_teardown=True,page_size=list(PAGE),expected_image_size=list(SIZE),
                     authoring_calls=2 if name=='nested' else 1,group=group,
                     audit=dict(backend=fmt,blocking=False,vector_only=False,events=events),
                     io_events=[dict(kind='readback',width=210,height=144,row_bytes=840),dict(kind='flush'),
                                dict(kind='submit',wait_requested=True)] if variant=='gpu' else []))
    return data


class Checks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.data=synthetic(self.root)
    def reject(self):
        with self.assertRaises((ValueError,ET.ParseError)): inspect(self.data,self.root)
    def gpu(self): return next(d for d in self.data['documents'] if d['variant']=='gpu' and d['name']=='pattern' and d['format']=='svg')
    def test_valid_opengl(self): self.assertEqual(inspect(self.data,self.root)[0]['documents_checked'],16)
    def test_valid_metal(self): self.assertEqual(inspect(synthetic(self.root,'metal'),self.root)[0]['backend'],'metal')
    def test_wrong_stage(self): self.data['stage']='0.43';self.reject()
    def test_unavailable_not_success(self): self.data['status']='unavailable';self.reject()
    def test_missing_native_case(self): self.data['native_test_cases']-=1;self.reject()
    def test_native_failure(self): self.data['native_test_failures']=1;self.reject()
    def test_false_is_not_zero_failures(self): self.data['native_test_failures']=False;self.reject()
    def test_context_not_closed(self): self.data['closed_context']['state']='ready';self.reject()
    def test_live_children(self): self.data['closed_context']['live_children']=1;self.reject()
    def test_pending_release(self): self.data['closed_context']['pending_releases']=1;self.reject()
    def test_foreign_teardown(self): self.data['closed_context']['generation']=32;self.reject()
    def test_second_context_must_be_distinct(self): self.data['other_closed_context']['generation']=17;self.reject()
    def test_no_run_identity(self): self.data['validation_run']=False;self.reject()
    def test_unmeasured_performance(self): self.data['performance_measured']=True;self.reject()
    def test_software_not_hardware(self):
        with self.assertRaises(ValueError): inspect(self.data,self.root,hardware=True)
    def test_missing_document(self): self.data['documents'].pop();self.reject()
    def test_duplicate_document(self): self.data['documents'][-1]=self.data['documents'][0];self.reject()
    def test_unsafe_filename(self): self.gpu()['file']='../image.svg';self.reject()
    def test_rerun_authoring(self): self.gpu()['authoring_calls']=2;self.reject()
    def test_serialize_before_teardown(self): self.gpu()['serialized_after_gpu_teardown']=False;self.reject()
    def test_gpu_target_required(self): self.gpu()['group']['execution']['target']['storage']='cpu';self.reject()
    def test_exact_context_affinity(self): self.gpu()['group']['execution']['context_generation']=99;self.reject()
    def test_cpu_fallback_not_an_acceleration_pass(self): self.gpu()['group']['execution']['fallback']={'reason':'absent'};self.reject()
    def test_size_report(self): self.gpu()['group']['pixel_size']=[360,270];self.reject()
    def test_actual_target_size(self): self.gpu()['group']['execution']['target']['width']=360;self.reject()
    def test_unproven_samples(self): self.gpu()['group']['execution']['target']['actual_sample_count']=0;self.reject()
    def test_false_native_backend(self): self.gpu()['group']['execution']['target']['native_backend']=False;self.reject()
    def test_planned_is_not_actual(self): self.gpu()['group']['execution']['phase']='planned';self.reject()
    def test_hidden_extra_readback(self): self.gpu()['io_events'].append(dict(kind='readback'));self.reject()
    def test_missing_cpu_completion(self): self.gpu()['io_events'][-1]['wait_requested']=False;self.reject()
    def test_wrong_transfer_stride(self): self.gpu()['io_events'][0]['row_bytes']=844;self.reject()
    def test_audit_stays_representation_based(self): self.gpu()['audit']['events'][0]['status']='rasterized';self.reject()
    def test_audit_records_actual_transfer(self): self.gpu()['audit']['events'][-1]['details']['execution']['transfer']='none';self.reject()
    def test_nested_executor_not_silent_cpu(self):
        item=next(d for d in self.data['documents'] if d['variant']=='gpu' and d['name']=='nested')
        item['group']['captured_children'][0]['execution']['backend']='raster';self.reject()
    def test_svg_link_preserved(self): (self.root/self.gpu()['file']).write_bytes(synthetic_svg(link='https://wrong.example/'));self.reject()
    def test_svg_vector_surroundings_preserved(self): (self.root/self.gpu()['file']).write_bytes(synthetic_svg(vectors=False));self.reject()
    def test_svg_image_placement(self): (self.root/self.gpu()['file']).write_bytes(synthetic_svg(placement='matrix(1 0 0 1 32 44)'));self.reject()
    def test_svg_corrupt_png(self):
        p=self.root/self.gpu()['file'];text=p.read_text().replace('iVBOR','AAAAA');p.write_text(text);self.reject()
    def test_exact_pattern_not_just_pairwise_similarity(self):
        pixels=bytearray(pattern_pixels());pixels[4*(60+60*210)]=0
        for variant in ('cpu','gpu'): (self.root/f'pattern.{variant}.svg').write_bytes(synthetic_svg(pixels));
        self.reject()
    def test_orientation_marker(self):
        pixels=bytearray(pattern_pixels());offset=4*(15+18*210);pixels[offset:offset+4]=b'\0\0\0\0'
        (self.root/'pattern.gpu.svg').write_bytes(synthetic_svg(pixels));self.reject()
    def test_pdf_vector_surroundings_preserved(self): (self.root/'pattern.gpu.pdf').write_bytes(synthetic_pdf(vectors=False));self.reject()
    def test_pdf_link_preserved(self): (self.root/'pattern.gpu.pdf').write_bytes(synthetic_pdf(link='https://wrong.example/'));self.reject()
    def test_pdf_not_whole_page_raster(self): (self.root/'pattern.gpu.pdf').write_bytes(synthetic_pdf(size=(360,270)));self.reject()
    def test_pdf_image_placement(self): (self.root/'pattern.gpu.pdf').write_bytes(synthetic_pdf(placement=(140,0,0,96,0,0)));self.reject()
    def test_pdf_xref_is_used(self):
        p=self.root/'pattern.gpu.pdf';data=p.read_bytes().replace(b'0000000009',b'9999999999');p.write_bytes(data);self.reject()
    def test_pdf_truncated(self): p=self.root/'pattern.gpu.pdf';p.write_bytes(p.read_bytes()[:-8]);self.reject()
    def test_publication_rechecks_files(self):
        prefix=self.root/'output';Path(str(prefix)+'.diagnostic.json').write_text(json.dumps(self.data))
        result=publish(prefix);self.assertEqual(result['status'],'passed')
        (self.root/'pattern.gpu.pdf').write_bytes(b'corrupt')
        with self.assertRaises(ValueError): publish(prefix)
        self.assertFalse(Path(str(prefix)+'.inspection.json').exists());self.assertFalse(Path(str(prefix)+'.review.html').exists())
    def test_review_escapes_renderer(self):
        self.data['initial_context']['renderer']='<script>alert(1)</script>'
        prefix=self.root/'output';Path(str(prefix)+'.diagnostic.json').write_text(json.dumps(self.data));publish(prefix)
        text=Path(str(prefix)+'.review.html').read_text();self.assertNotIn('<script>',text)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--probe-prefix',type=Path)
    parser.add_argument('--require-hardware',action='store_true')
    parser.add_argument('--self-test',action='store_true')
    args=parser.parse_args()
    if args.self_test:
        return 0 if unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks)).wasSuccessful() else 1
    parser.error('--probe-prefix is required') if args.probe_prefix is None else None
    try:
        print(json.dumps(publish(args.probe_prefix,hardware=args.require_hardware),indent=2));return 0
    except (OSError,ValueError,TypeError,KeyError,ET.ParseError,zlib.error) as error:
        print('GPU output inspection FAILED: '+str(error));return 1

if __name__=='__main__': raise SystemExit(main())
