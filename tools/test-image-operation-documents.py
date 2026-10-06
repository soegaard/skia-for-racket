#!/usr/bin/env python3
"""Synthetic PDF/SVG and full-receipt tests for the 0.72 inspectors, not Skia rendering."""
from __future__ import annotations
import base64
import copy
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET
import image_operation_validation as iv

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('image_tests_for_documents',HERE/'test-image-operations.py')
src=importlib.util.module_from_spec(spec);spec.loader.exec_module(src)

def scene_image(scene,row):
    from PIL import Image,ImageFilter
    w,h=row['image_dimensions']
    if scene=='blur':
        im=Image.new('RGBA',(w,h),(32,96,192,0))
        a=Image.new('L',(w,h),0);a.paste(255,(6,6,22,18));a=a.filter(ImageFilter.GaussianBlur(2));im.putalpha(a)
    elif scene=='shadow':
        a=Image.new('L',(w,h),0);a.paste(255,(8,6,24,18));a=a.filter(ImageFilter.GaussianBlur(2))
        im=Image.new('RGBA',(w,h),(0,0,0,0));im.putalpha(a);im.paste((32,96,192,255),(0,0,16,12))
    else:im=Image.new('RGBA',(w,h),(128,64,191,255) if scene=='scale' else iv.BLUE)
    return im

def make_reference(image,row):
    from PIL import Image,ImageDraw
    result=Image.new('RGBA',(iv.WIDTH,iv.HEIGHT),iv.WHITE)
    ImageDraw.Draw(result).rectangle((2,2,6,6),fill=(0,255,0,255))
    result.alpha_composite(image,tuple(row['placement']))
    return result.tobytes()

def make_svg(path,row,image,*,link=True,dimensions=None):
    dimensions=dimensions or row['image_dimensions'];w,h=dimensions;x,y=row['placement']
    stream=io.BytesIO();image.save(stream,format='PNG');encoded=base64.b64encode(stream.getvalue()).decode('ascii')
    url='https://example.invalid/image-operations/'+row['scene'] if link else 'https://example.invalid/other'
    text=f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="96pt" height="64pt" viewBox="0 0 96 64">
<rect x="0" y="0" width="96" height="64" fill="white"/>
<rect x="2" y="2" width="5" height="5" fill="#00ff00"/>
<image x="{x}" y="{y}" width="{w}" height="{h}" xlink:href="data:image/png;base64,{encoded}"/>
<a xlink:href="{url}"><rect x="2" y="2" width="5" height="5" fill="none"/></a>
</svg>'''
    Path(path).write_text(text,encoding='utf-8')

def make_pdf(path,row,image,*,link=True,dimensions=None,marker=True,text=False):
    from pypdf import PdfWriter
    from pypdf.generic import (ArrayObject,DictionaryObject,DecodedStreamObject,FloatObject,
                                NameObject,NumberObject,TextStringObject)
    w,h=dimensions or row['image_dimensions'];x,y=row['placement']
    writer=PdfWriter();page=writer.add_blank_page(iv.WIDTH,iv.HEIGHT)
    raster=DecodedStreamObject();raster.set_data(image.convert('RGB').tobytes())
    raster.update({NameObject('/Type'):NameObject('/XObject'),NameObject('/Subtype'):NameObject('/Image'),
                   NameObject('/Width'):NumberObject(w),NameObject('/Height'):NumberObject(h),
                   NameObject('/ColorSpace'):NameObject('/DeviceRGB'),NameObject('/BitsPerComponent'):NumberObject(8)})
    if image.getchannel('A').getextrema()!=(255,255):
        mask=DecodedStreamObject();mask.set_data(image.getchannel('A').tobytes())
        mask.update({NameObject('/Type'):NameObject('/XObject'),NameObject('/Subtype'):NameObject('/Image'),
                     NameObject('/Width'):NumberObject(w),NameObject('/Height'):NumberObject(h),
                     NameObject('/ColorSpace'):NameObject('/DeviceGray'),NameObject('/BitsPerComponent'):NumberObject(8)})
        raster[NameObject('/SMask')]=writer._add_object(mask)
    page[NameObject('/Resources')]=DictionaryObject({NameObject('/XObject'):DictionaryObject({NameObject('/Im0'):writer._add_object(raster)})})
    commands='1 1 1 rg 0 0 96 64 re f\n'
    if marker:commands+='0 1 0 rg 2 57 5 5 re f\n'
    commands+=f'q {w} 0 0 {h} {x} {iv.HEIGHT-y-h} cm /Im0 Do Q\n'
    if text:commands+='BT (unexpected) Tj ET\n'
    content=DecodedStreamObject();content.set_data(commands.encode('ascii'));page[NameObject('/Contents')]=writer._add_object(content)
    url='https://example.invalid/image-operations/'+row['scene'] if link else 'https://example.invalid/other'
    annotation=DictionaryObject({NameObject('/Type'):NameObject('/Annot'),NameObject('/Subtype'):NameObject('/Link'),
                                 NameObject('/Rect'):ArrayObject(list(map(NumberObject,(2,57,7,62)))),
                                 NameObject('/Border'):ArrayObject([NumberObject(0)]*3),
                                 NameObject('/A'):DictionaryObject({NameObject('/S'):NameObject('/URI'),NameObject('/URI'):TextStringObject(url)})})
    page[NameObject('/Annots')]=ArrayObject([writer._add_object(annotation)])
    writer.add_metadata({'/Title':'SYNTHETIC 0.72 inspector fixture; not Skia output'})
    with Path(path).open('wb') as stream:writer.write(stream)

def make_matrix(directory,token='synthetic-only'):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True);rows=[]
    for scene,kind in iv.SPECS:
        row=src.synthetic_row(scene,kind);image=scene_image(scene,row)
        (make_pdf if kind=='pdf' else make_svg)(directory/row['file'],row,image)
        reference=make_reference(image,row);iv.pixel_checks(reference,scene)
        (directory/row['rgba']).write_bytes(reference);rows.append(row)
    (directory/'scale.f32').write_bytes(struct.pack('<4f',.5009765625,.25,.75,1)*192)
    receipt=dict(schema=1,stage='0.72',status='passed',run_token=token,rendering_executed=True,
                 gpu_executed=False,gui_executed=False,byte_order='little-endian',documents=rows)
    (directory/'documents.json').write_text(json.dumps(receipt),encoding='utf-8')
    return receipt

def make_gpu(directory,token='synthetic-only'):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True);rows=[]
    for scene in iv.SCENES:
        row=src.synthetic_row(scene);im=scene_image(scene,row)
        (directory/(scene+'.rgba')).write_bytes(make_reference(im,row))
        offset=[row['placement'][0]-24,row['placement'][1]-20]
        rows.append(dict(scene=scene,file=scene+'.rgba',offset=offset,drawing_readbacks=0,inspection_readbacks=1))
    value=dict(schema=1,stage='0.72',status='passed',run_token=token,backend='egl',adapter='hardware',
               failures=0,frames=6,filter_calls=4,cpu_rejections=4,cross_context_rejected=True,
               retained_result_tested=True,contexts_closed=True,gui_executed=False,physical_display_verified=False,
               float_gpu_storage_verified=False,scenes=rows)
    (directory/'gpu.json').write_text(json.dumps(value),encoding='utf-8');return value

class Documents(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
    def test_full_synthetic_document_matrix(self):
        make_matrix(self.root);result=iv.inspect_documents(self.root,'synthetic-only')
        self.assertEqual(len(result['documents']),12);self.assertFalse(result['independent_renderers_executed'])
    def test_wrong_PDF_image_dimensions(self):
        row=src.synthetic_row();make_pdf(self.root/'bad.pdf',row,scene_image('offset',row),dimensions=(96,64))
        with self.assertRaises(ValueError):iv.inspect_pdf(self.root/'bad.pdf',row)
    def test_wrong_PDF_link(self):
        row=src.synthetic_row();make_pdf(self.root/'bad.pdf',row,scene_image('offset',row),link=False)
        with self.assertRaises(ValueError):iv.inspect_pdf(self.root/'bad.pdf',row)
    def test_PDF_vector_marker_missing(self):
        row=src.synthetic_row();make_pdf(self.root/'bad.pdf',row,scene_image('offset',row),marker=False)
        with self.assertRaises(ValueError):iv.inspect_pdf(self.root/'bad.pdf',row)
    def test_PDF_unexpected_text(self):
        row=src.synthetic_row();make_pdf(self.root/'bad.pdf',row,scene_image('offset',row),text=True)
        with self.assertRaises(ValueError):iv.inspect_pdf(self.root/'bad.pdf',row)
    def test_wrong_SVG_image_dimensions(self):
        row=src.synthetic_row(kind='svg');make_svg(self.root/'bad.svg',row,scene_image('offset',row),dimensions=(96,64))
        with self.assertRaises(ValueError):iv.inspect_svg(self.root/'bad.svg',row)
    def test_wrong_SVG_link(self):
        row=src.synthetic_row(kind='svg');make_svg(self.root/'bad.svg',row,scene_image('offset',row),link=False)
        with self.assertRaises(ValueError):iv.inspect_svg(self.root/'bad.svg',row)
    def test_SVG_external_image(self):
        row=src.synthetic_row(kind='svg');p=self.root/'bad.svg';make_svg(p,row,scene_image('offset',row))
        text=p.read_text();start=text.index('data:image/png;base64,');end=text.index('"',start)
        p.write_text(text[:start]+'https://example.invalid/image.png'+text[end:])
        with self.assertRaises(ValueError):iv.inspect_svg(p,row)
    def test_SVG_DTD_rejected(self):
        row=src.synthetic_row(kind='svg');p=self.root/'bad.svg';make_svg(p,row,scene_image('offset',row))
        p.write_text('<!DOCTYPE svg>'+p.read_text())
        with self.assertRaises(ValueError):iv.inspect_svg(p,row)
    def test_GPU_synthetic_matrix(self):
        make_gpu(self.root);result=iv.inspect_gpu(self.root,'synthetic-only','egl','hardware')
        self.assertEqual(len(result['captures']),6)

def reject_document(change):
    def test(self):
        value=make_matrix(self.root);change(value)
        (self.root/'documents.json').write_text(json.dumps(value))
        with self.assertRaises((ValueError,TypeError,KeyError)):iv.inspect_documents(self.root,'synthetic-only')
    return test
for name,change in {
 'stale_token':lambda v:v.update(run_token='different'),
 'boolean_schema':lambda v:v.update(schema=True),
 'wrong_stage':lambda v:v.update(stage='0.71'),
 'failed_status':lambda v:v.update(status='failed'),
 'false_execution':lambda v:v.update(rendering_executed=False),
 'GPU_claim':lambda v:v.update(gpu_executed=True),
 'missing_document':lambda v:v['documents'].pop(),
 'duplicate_document':lambda v:v['documents'].__setitem__(1,v['documents'][0]),
 'wrong_byte_order':lambda v:v.update(byte_order='unknown')}.items():setattr(Documents,'test_reject_'+name,reject_document(change))

def reject_GPU(change):
    def test(self):
        value=make_gpu(self.root);change(value)
        (self.root/'gpu.json').write_text(json.dumps(value))
        with self.assertRaises((ValueError,TypeError,KeyError)):iv.inspect_gpu(self.root,'synthetic-only','egl','hardware')
    return test
for name,change in {
 'hidden_readback':lambda v:v['scenes'][0].update(drawing_readbacks=1),
 'missing_inspection':lambda v:v['scenes'][0].update(inspection_readbacks=0),
 'filter_not_executed':lambda v:v.update(filter_calls=0),
 'CPU_rejection_missing':lambda v:v.update(cpu_rejections=0),
 'foreign_backend':lambda v:v.update(backend='metal'),
 'stale_GPU_token':lambda v:v.update(run_token='different'),
 'unclosed_context':lambda v:v.update(contexts_closed=False),
 'cross_context_missing':lambda v:v.update(cross_context_rejected=False),
 'lifetime_not_checked':lambda v:v.update(retained_result_tested=False),
 'float_GPU_overclaim':lambda v:v.update(float_gpu_storage_verified=True),
 'duplicate_GPU_scene':lambda v:v['scenes'].__setitem__(1,v['scenes'][0]),
 'GPU_offset_lost':lambda v:v['scenes'][0].update(offset=[0,0]),
 'boolean_filter_count':lambda v:v.update(filter_calls=True)}.items():setattr(Documents,'test_reject_'+name,reject_GPU(change))

if __name__=='__main__':unittest.main(verbosity=2)
