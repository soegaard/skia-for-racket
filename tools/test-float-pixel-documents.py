#!/usr/bin/env python3
"""Synthetic document files test the inspector. They are NOT Skia rendering evidence."""
from __future__ import annotations
import base64
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET
from PIL import Image
from pypdf import PdfWriter
from pypdf.generic import (ArrayObject, DictionaryObject, NameObject, NumberObject,
                           TextStringObject, DecodedStreamObject)
import float_pixel_validation as v

def image_bytes(scene):
    return b''.join(bytes(v.quantize(v.sample_oracle(scene,x))[:3]) for y in range(32) for x in range(64))

def rgba(scene):
    image=Image.new('RGBA',(96,64),'white')
    image.paste(Image.frombytes('RGB',(64,32),image_bytes(scene)),(16,16))
    image.paste((0,255,0,255),(2,2,6,6))
    return image.tobytes()

def raw(fmt,scene):
    code='<4e' if fmt=='rgba-f16' else '<4f'
    return b''.join(struct.pack(code,*v.sample_oracle(scene,x)) for y in range(32) for x in range(64))

def synthetic_pdf(path,prefix,scene,*,image_width=64,marker=True,link=True,duplicate=False):
    writer=PdfWriter();page=writer.add_blank_page(width=96,height=64)
    image=DecodedStreamObject();image.set_data(image_bytes(scene))
    image.update({NameObject('/Type'):NameObject('/XObject'),NameObject('/Subtype'):NameObject('/Image'),
                  NameObject('/Width'):NumberObject(image_width),NameObject('/Height'):NumberObject(32),
                  NameObject('/BitsPerComponent'):NumberObject(8),NameObject('/ColorSpace'):NameObject('/DeviceRGB')})
    page[NameObject('/Resources')]=DictionaryObject({NameObject('/XObject'):DictionaryObject({NameObject('/I0'):writer._add_object(image)})})
    content=b'1 1 1 rg 0 0 96 64 re f\n'
    if marker:content+=b'0 1 0 rg 2 58 4 4 re f\n'
    content+=b'q 64 0 0 32 16 16 cm /I0 Do Q\n'
    if duplicate:content+=b'q 64 0 0 32 16 16 cm /I0 Do Q\n'
    stream=DecodedStreamObject();stream.set_data(content)
    page[NameObject('/Contents')]=writer._add_object(stream)
    if link:
        annot=DictionaryObject({NameObject('/Type'):NameObject('/Annot'),NameObject('/Subtype'):NameObject('/Link'),
              NameObject('/Rect'):ArrayObject([NumberObject(n) for n in (2,58,6,62)]),
              NameObject('/Border'):ArrayObject([NumberObject(0),NumberObject(0),NumberObject(0)]),
              NameObject('/A'):DictionaryObject({NameObject('/S'):NameObject('/URI'),NameObject('/URI'):TextStringObject('https://example.invalid/float/'+prefix)})})
        page[NameObject('/Annots')]=ArrayObject([writer._add_object(annot)])
    with Path(path).open('wb') as out:writer.write(out)

def synthetic_svg(path,prefix,scene,*,width=64,marker=True,link=True,external=False):
    memory=io.BytesIO();Image.frombytes('RGB',(64,32),image_bytes(scene)).save(memory,format='PNG')
    href='https://example.invalid/untrusted.png' if external else 'data:image/png;base64,'+base64.b64encode(memory.getvalue()).decode('ascii')
    text='<svg xmlns="http://www.w3.org/2000/svg" width="96pt" height="64pt" viewBox="0 0 96 64">'
    text+='<rect width="96" height="64" fill="white"/>'
    if marker:text+='<rect x="2" y="2" width="4" height="4" fill="#00ff00"/>'
    text+=f'<image x="16" y="16" width="{width}" height="32" href="{href}"/>'
    if link:text+='<a href="https://example.invalid/float/'+prefix+'"><rect x="2" y="2" width="4" height="4" fill="none"/></a>'
    text+='</svg>';Path(path).write_text(text,encoding='utf-8')

def synthetic_row(fmt,scene,kind):
    prefix=fmt+'-'+scene;stem=prefix+'-'+kind
    return dict(source_format=fmt,scene=scene,format=kind,file=stem+'.'+kind,rgba=stem+'.rgba',raw=prefix+'.pixels',
                conversion='explicit-float-to-rgba8888',image_width=64,image_height=32,callback_count=1,
                audit_policy='error',audit=dict(mode='export',backend=kind,blocking=False,vector_only=False,
                    events=[dict(feature='geometry',status='vector'),dict(feature='image',status='embedded-raster'),dict(feature='annotation',status='vector')]))

def synthetic_matrix(directory,token='token'):
    root=Path(directory);root.mkdir(parents=True,exist_ok=True);rows=[]
    for fmt,scene,kind in v.SPECS:
        row=synthetic_row(fmt,scene,kind);rows.append(row);prefix=fmt+'-'+scene
        (synthetic_pdf if kind=='pdf' else synthetic_svg)(root/row['file'],prefix,scene)
        (root/row['rgba']).write_bytes(rgba(scene));(root/row['raw']).write_bytes(raw(fmt,scene))
    value=dict(schema=1,stage='0.71',status='passed',run_token=token,rendering_executed=True,
               gpu_executed=False,hdr_verified=False,byte_order='little-endian',documents=rows)
    (root/'documents.json').write_text(json.dumps(value),encoding='utf-8');return value

class PDF(unittest.TestCase):
    def test_positive_float_document_structures(self):
        with tempfile.TemporaryDirectory() as tmp:
            for fmt in v.FORMATS:
                for scene in ('samples','linear'):
                    prefix=fmt+'-'+scene;p=Path(tmp)/(prefix+'.pdf');synthetic_pdf(p,prefix,scene)
                    self.assertEqual(v.inspect_pdf(p,prefix)['image_dimensions'],[64,32])
    def reject(self,**kwargs):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'f.pdf';synthetic_pdf(p,'rgba-f16-samples','samples',**kwargs)
            with self.assertRaises(ValueError):v.inspect_pdf(p,'rgba-f16-samples')
    def test_full_page_image(self):self.reject(image_width=96)
    def test_missing_vector_marker(self):self.reject(marker=False)
    def test_missing_link(self):self.reject(link=False)
    def test_duplicate_image(self):self.reject(duplicate=True)
    def test_wrong_scene_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'f.pdf';synthetic_pdf(p,'rgba-f16-linear','linear')
            with self.assertRaises(ValueError):v.inspect_pdf(p,'rgba-f16-samples')

class SVG(unittest.TestCase):
    def test_positive_float_document_structures(self):
        with tempfile.TemporaryDirectory() as tmp:
            for fmt in v.FORMATS:
                for scene in ('samples','linear'):
                    prefix=fmt+'-'+scene;p=Path(tmp)/(prefix+'.svg');synthetic_svg(p,prefix,scene)
                    self.assertEqual(v.inspect_svg(p,prefix)['image_dimensions'],[64,32])
    def reject(self,**kwargs):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'f.svg';synthetic_svg(p,'rgba-f16-samples','samples',**kwargs)
            with self.assertRaises(ValueError):v.inspect_svg(p,'rgba-f16-samples')
    def test_external_image(self):self.reject(external=True)
    def test_wrong_size(self):self.reject(width=96)
    def test_missing_link(self):self.reject(link=False)
    def test_missing_vector_surround(self):self.reject(marker=False,link=False)
    def test_dtd_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'f.svg';synthetic_svg(p,'rgba-f16-samples','samples');p.write_text('<!DOCTYPE svg>'+p.read_text())
            with self.assertRaises(ValueError):v.inspect_svg(p,'rgba-f16-samples')
    def test_embedded_png_dimensions_verified(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'f.svg';synthetic_svg(p,'rgba-f16-samples','samples')
            root=ET.fromstring(p.read_text());image=next(e for e in root.iter() if e.tag.endswith('image'))
            out=io.BytesIO();Image.new('RGB',(1,1)).save(out,format='PNG')
            image.set('href','data:image/png;base64,'+base64.b64encode(out.getvalue()).decode('ascii'))
            p.write_bytes(ET.tostring(root))
            with self.assertRaises(ValueError):v.inspect_svg(p,'rgba-f16-samples')
    def test_duplicate_image(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'f.svg';synthetic_svg(p,'rgba-f16-samples','samples')
            text=p.read_text();start=text.index('<image');end=text.index('/>',start)+2
            p.write_text(text[:end]+text[start:end]+text[end:])
            with self.assertRaises(ValueError):v.inspect_svg(p,'rgba-f16-samples')

class Matrix(unittest.TestCase):
    def test_complete_synthetic_matrix(self):
        with tempfile.TemporaryDirectory() as tmp:
            synthetic_matrix(tmp);result=v.inspect_documents(tmp,'token')
            self.assertEqual(len(result['documents']),8)
            self.assertFalse(result['independent_renderers_executed'])
    def reject(self,mutate):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp);d=synthetic_matrix(p);mutate(p,d);(p/'documents.json').write_text(json.dumps(d))
            with self.assertRaises(ValueError):v.inspect_documents(p,'token')
    def test_stale_token(self):self.reject(lambda p,d:d.update(run_token='old'))
    def test_failed_status(self):self.reject(lambda p,d:d.update(status='failed'))
    def test_boolean_schema(self):self.reject(lambda p,d:d.update(schema=True))
    def test_unknown_byte_order(self):self.reject(lambda p,d:d.update(byte_order='guess'))
    def test_duplicate_document(self):self.reject(lambda p,d:d['documents'].__setitem__(0,d['documents'][1]))
    def test_missing_document(self):self.reject(lambda p,d:(p/d['documents'][0]['file']).unlink())
    def test_blank_reference(self):self.reject(lambda p,d:(p/d['documents'][0]['rgba']).write_bytes(bytes([255])*96*64*4))
    def test_lost_raw_precision(self):self.reject(lambda p,d:(p/d['documents'][0]['raw']).write_bytes(bytes(64*32*8)))
    def test_false_gpu_claim(self):self.reject(lambda p,d:d.update(gpu_executed=True))
    def test_false_hdr_claim(self):self.reject(lambda p,d:d.update(hdr_verified=True))
    def test_raw_file_cannot_escape_directory(self):self.reject(lambda p,d:d['documents'][0].update(raw='../escape.pixels'))
    def test_viewer_known_oracle(self):
        with tempfile.TemporaryDirectory() as tmp:
            for scene in ('samples','linear'):
                p=Path(tmp)/(scene+'.png');Image.frombytes('RGBA',(96,64),rgba(scene)).save(p)
                self.assertGreater(v.inspect_render(p,scene)['independent_probes'],3000)
    def test_viewer_blank_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'f.png';Image.new('RGBA',(96,64),'white').save(p)
            with self.assertRaises(ValueError):v.inspect_render(p,'samples')
    def test_viewer_misplacement_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            im=Image.frombytes('RGBA',(96,64),rgba('samples'));bad=Image.new('RGBA',(96,64),'white');bad.paste(im,(3,0))
            p=Path(tmp)/'f.png';bad.save(p)
            with self.assertRaises(ValueError):v.inspect_render(p,'samples')

if __name__=='__main__':unittest.main(verbosity=2)
