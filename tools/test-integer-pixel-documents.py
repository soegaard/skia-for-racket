#!/usr/bin/env python3
"""Synthetic PDF/SVG fixtures exercise the inspector, not native Skia drawing."""
from __future__ import annotations
import base64
import io
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
from PIL import Image
from pypdf import PdfWriter
from pypdf.generic import (ArrayObject, DictionaryObject, FloatObject, NameObject,
                           NumberObject, TextStringObject, DecodedStreamObject)
import integer_pixel_validation as v


def rgba(fmt):
    return b''.join(bytes(v.oracle_color(fmt,x,y)) for y in range(v.HEIGHT) for x in range(v.WIDTH))


def image_bytes(fmt):
    return b''.join(bytes(v.oracle_color(fmt,x,y)[:3]) for y in range(24,56) for x in range(8,72))


def synthetic_pdf(path,fmt,*,image_width=64,marker=True,link=True,duplicate=False):
    writer=PdfWriter(); page=writer.add_blank_page(width=v.WIDTH,height=v.HEIGHT)
    im=DecodedStreamObject();im.set_data(image_bytes(fmt))
    im.update({NameObject('/Type'):NameObject('/XObject'),NameObject('/Subtype'):NameObject('/Image'),
               NameObject('/Width'):NumberObject(image_width),NameObject('/Height'):NumberObject(32),
               NameObject('/BitsPerComponent'):NumberObject(8),NameObject('/ColorSpace'):NameObject('/DeviceRGB')})
    page[NameObject('/Resources')]=DictionaryObject({NameObject('/XObject'):DictionaryObject({NameObject('/I0'):writer._add_object(im)})})
    content=b'1 1 1 rg 0 0 80 64 re f\n'
    if marker:content+=b'0 1 0 rg 2 58 4 4 re f\n'
    content+=b'q 64 0 0 32 8 8 cm /I0 Do Q\n'
    if duplicate:content+=b'q 64 0 0 32 8 8 cm /I0 Do Q\n'
    stream=DecodedStreamObject();stream.set_data(content);page[NameObject('/Contents')]=writer._add_object(stream)
    if link:
        a=DictionaryObject({NameObject('/Type'):NameObject('/Annot'),NameObject('/Subtype'):NameObject('/Link'),
             NameObject('/Rect'):ArrayObject([NumberObject(n) for n in (2,58,6,62)]),
             NameObject('/A'):DictionaryObject({NameObject('/S'):NameObject('/URI'),
                NameObject('/URI'):TextStringObject('https://example.invalid/integer-pixels/'+fmt)})})
        page[NameObject('/Annots')]=ArrayObject([writer._add_object(a)])
    with Path(path).open('wb') as out:writer.write(out)


def synthetic_svg(path,fmt,*,marker=True,link=True,width=64,external=False):
    memory=io.BytesIO();Image.frombytes('RGB',(64,32),image_bytes(fmt)).save(memory,format='PNG')
    href='https://example.invalid/image.png' if external else 'data:image/png;base64,'+base64.b64encode(memory.getvalue()).decode('ascii')
    text='<svg xmlns="http://www.w3.org/2000/svg" width="80pt" height="64pt" viewBox="0 0 80 64">'
    text+='<rect width="80" height="64" fill="white"/>'
    if marker:text+='<rect x="2" y="2" width="4" height="4" fill="#00ff00"/>'
    text+=f'<image x="8" y="24" width="{width}" height="32" href="{href}"/>'
    if link:text+='<a href="https://example.invalid/integer-pixels/'+fmt+'"><rect x="2" y="2" width="4" height="4" fill="none"/></a>'
    text+='</svg>';Path(path).write_text(text,encoding='utf-8')


def synthetic_row(fmt,kind):
    stem=fmt+'-'+kind
    return dict(source_format=fmt,format=kind,file=stem+'.'+kind,rgba=stem+'.rgba',
                conversion='explicit-rgba-nearest',image_width=64,image_height=32,callback_count=1,
                audit_policy='error',audit=dict(mode='export',backend=kind,blocking=False,vector_only=False,
                    events=[dict(feature='geometry',status='vector'),
                            dict(feature='image',status='embedded-raster'),
                            dict(feature='annotation',status='vector')]))


def synthetic_matrix(directory,token='token'):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    rows=[]
    for fmt,kind in v.SPECS:
        row=synthetic_row(fmt,kind);rows.append(row)
        (synthetic_pdf if kind=='pdf' else synthetic_svg)(directory/row['file'],fmt)
        (directory/row['rgba']).write_bytes(rgba(fmt))
    value=dict(schema=1,stage='0.70',status='passed',run_token=token,rendering_executed=True,
               gpu_executed=False,gui_executed=False,documents=rows)
    (directory/'documents.json').write_text(json.dumps(value),encoding='utf-8')
    return value


class PDF(unittest.TestCase):
    def test_seven_positive_formats(self):
        with tempfile.TemporaryDirectory() as t:
            for fmt in v.FORMATS:
                p=Path(t)/(fmt+'.pdf');synthetic_pdf(p,fmt)
                self.assertEqual(v.inspect_pdf(p,fmt)['image_dimensions'],[64,32])
    def reject(self,**kwargs):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'f.pdf';synthetic_pdf(p,'rgba-8888',**kwargs)
            with self.assertRaises(ValueError):v.inspect_pdf(p,'rgba-8888')
    def test_full_page_image_rejected(self):self.reject(image_width=80)
    def test_missing_marker_rejected(self):self.reject(marker=False)
    def test_missing_link_rejected(self):self.reject(link=False)
    def test_duplicate_image_draw_rejected(self):self.reject(duplicate=True)
    def test_wrong_source_identity_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'f.pdf';synthetic_pdf(p,'rgb-565')
            with self.assertRaises(ValueError):v.inspect_pdf(p,'rgba-8888')


class SVG(unittest.TestCase):
    def test_seven_positive_formats(self):
        with tempfile.TemporaryDirectory() as t:
            for fmt in v.FORMATS:
                p=Path(t)/(fmt+'.svg');synthetic_svg(p,fmt)
                self.assertEqual(v.inspect_svg(p,fmt)['image_dimensions'],[64,32])
    def reject(self,**kwargs):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'f.svg';synthetic_svg(p,'rgba-8888',**kwargs)
            with self.assertRaises(ValueError):v.inspect_svg(p,'rgba-8888')
    def test_external_image_rejected(self):self.reject(external=True)
    def test_full_page_image_rejected(self):self.reject(width=80)
    def test_missing_link_rejected(self):self.reject(link=False)
    def test_no_vector_shapes_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'f.svg';synthetic_svg(p,'gray-8',marker=False,link=False)
            with self.assertRaises(ValueError):v.inspect_svg(p,'gray-8')
    def test_dtd_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'f.svg';synthetic_svg(p,'gray-8');p.write_text('<!DOCTYPE svg>'+p.read_text())
            with self.assertRaises(ValueError):v.inspect_svg(p,'gray-8')
    def test_embedded_png_dimensions_are_not_trusted_from_attributes(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'f.svg';synthetic_svg(p,'gray-8')
            tree=ET.fromstring(p.read_text())
            im=next(e for e in tree.iter() if e.tag.rsplit('}',1)[-1]=='image')
            out=io.BytesIO();Image.new('RGB',(1,1)).save(out,format='PNG')
            im.set('href','data:image/png;base64,'+base64.b64encode(out.getvalue()).decode('ascii'))
            p.write_bytes(ET.tostring(tree))
            with self.assertRaises(ValueError):v.inspect_svg(p,'gray-8')
    def test_multiple_images_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'f.svg';synthetic_svg(p,'rgb-565');s=p.read_text();a=s.index('<image');b=s.index('/>',a)+2
            p.write_text(s[:b]+s[a:b]+s[b:])
            with self.assertRaises(ValueError):v.inspect_svg(p,'rgb-565')


class Matrix(unittest.TestCase):
    def test_complete_synthetic_matrix(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);synthetic_matrix(p);r=v.inspect_documents(p,'token')
            self.assertEqual(len(r['documents']),14);self.assertFalse(r['independent_renderers_executed'])
    def reject(self,mutate):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);d=synthetic_matrix(p);mutate(p,d);(p/'documents.json').write_text(json.dumps(d))
            with self.assertRaises(ValueError):v.inspect_documents(p,'token')
    def test_stale_token(self):self.reject(lambda p,d:d.update(run_token='old'))
    def test_duplicate_document(self):self.reject(lambda p,d:d['documents'].__setitem__(0,d['documents'][1]))
    def test_blank_reference(self):self.reject(lambda p,d:(p/d['documents'][0]['rgba']).write_bytes(bytes([255])*80*64*4))
    def test_missing_document(self):self.reject(lambda p,d:(p/d['documents'][0]['file']).unlink())
    def test_false_gpu_claim(self):self.reject(lambda p,d:d.update(gpu_executed=True))
    def test_viewer_rejects_blank_image(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'blank.png';Image.new('RGBA',(80,64),'white').save(p)
            with self.assertRaises(ValueError):v.inspect_render(p,'gray-8')
    def test_viewer_positive_oracle(self):
        with tempfile.TemporaryDirectory() as t:
            for f in v.FORMATS:
                p=Path(t)/(f+'.png');Image.frombytes('RGBA',(80,64),rgba(f)).save(p)
                self.assertGreater(v.inspect_render(p,f)['independent_probes'],2000)

if __name__=='__main__':unittest.main(verbosity=2)
