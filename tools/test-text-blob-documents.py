#!/usr/bin/env python3
"""Synthetic PDF/SVG inspector regressions; these are NOT Skia execution evidence."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import tempfile
import unittest
from pypdf import PdfWriter
from pypdf.generic import (ArrayObject, DictionaryObject, NameObject, NumberObject,
                           TextStringObject, DecodedStreamObject)
from PIL import Image
import text_blob_validation as tv


def stream(data):
    result=DecodedStreamObject();result.set_data(data);return result

def polygon_commands(points):
    first,*rest=points
    return (f'{first[0]:.6f} {first[1]:.6f} m\n'+''.join(f'{x:.6f} {y:.6f} l\n' for x,y in rest)+'h f\n').encode()

def make_pdf(path,scene='multi',configure=lambda w,p:None):
    writer=PdfWriter();page=writer.add_blank_page(width=tv.WIDTH,height=tv.HEIGHT)
    data=b'1 0 0 -1 0 128 cm\n1 1 1 rg 0 0 192 128 re f\n0 1 0 rg 2 2 4 4 re f\n'
    data+=b'0.094117647 0.250980392 0.752941176 rg\n'
    data+=b''.join(polygon_commands(p) for p in tv.polygons(scene))
    page[NameObject('/Contents')]=writer._add_object(stream(data))
    page[NameObject('/Resources')]=DictionaryObject()
    link=DictionaryObject({NameObject('/Type'):NameObject('/Annot'),NameObject('/Subtype'):NameObject('/Link'),
        NameObject('/Rect'):ArrayObject([NumberObject(v) for v in (2,122,6,126)]),
        NameObject('/Border'):ArrayObject([NumberObject(0)]*3),
        NameObject('/A'):DictionaryObject({NameObject('/S'):NameObject('/URI'),
            NameObject('/URI'):TextStringObject('https://example.invalid/text-blob/'+scene)})})
    page[NameObject('/Annots')]=ArrayObject([writer._add_object(link)])
    configure(writer,page)
    with Path(path).open('wb') as out:writer.write(out)

def make_svg(scene='multi'):
    shapes=''.join('<polygon points="'+ ' '.join(f'{x:.6f},{y:.6f}' for x,y in p)+'" fill="#1840c0"/>' for p in tv.polygons(scene))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="192pt" height="128pt" viewBox="0 0 192 128">'
            '<rect width="192" height="128" fill="white"/>'
            '<a href="https://example.invalid/text-blob/'+scene+'"><rect x="2" y="2" width="4" height="4" fill="#00ff00"/></a>'
            +shapes+'</svg>')

class PDFInspector(unittest.TestCase):
    def inspect(self,configure=lambda w,p:None,scene='multi',mode='outline'):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'synthetic.pdf';make_pdf(p,scene,configure)
            return tv.inspect_pdf(p,scene,mode)
    def test_all_synthetic_outline_scenes(self):
        for s in tv.SCENES:self.assertFalse(self.inspect(scene=s)['native_text'])
    def test_outlines_do_not_establish_native_text_preservation(self):
        with self.assertRaises(ValueError):self.inspect(mode='native')
    def test_wrong_dimensions(self):
        def config(w,p):p.mediabox.upper_right=(193,128)
        with self.assertRaises(ValueError):self.inspect(config)
    def test_missing_link(self):
        def config(w,p):del p['/Annots']
        with self.assertRaises(ValueError):self.inspect(config)
    def test_foreign_link(self):
        def config(w,p):p['/Annots'][0].get_object()['/A'][NameObject('/URI')]=TextStringObject('https://example.invalid/other')
        with self.assertRaises(ValueError):self.inspect(config)
    def test_undrawn_image_resource_rejects(self):
        def config(w,p):
            image=stream(b'\0\0\0');image.update({NameObject('/Type'):NameObject('/XObject'),NameObject('/Subtype'):NameObject('/Image'),
                NameObject('/Width'):NumberObject(1),NameObject('/Height'):NumberObject(1),
                NameObject('/ColorSpace'):NameObject('/DeviceRGB'),NameObject('/BitsPerComponent'):NumberObject(8)})
            p['/Resources'][NameObject('/XObject')]=DictionaryObject({NameObject('/Im'):w._add_object(image)})
        with self.assertRaises(ValueError):self.inspect(config)
    def test_inline_image_rejects(self):
        def config(w,p):p[NameObject('/Contents')]=w._add_object(stream(b'BI /W 1 /H 1 /CS /RGB /BPC 8 ID \x00\x00\x00 EI\n'))
        with self.assertRaises(ValueError):self.inspect(config)
    def test_indirect_vector_form_resources(self):
        def config(w,p):
            form=stream(p['/Contents'].get_data());form[NameObject('/Subtype')]=NameObject('/Form')
            form[NameObject('/BBox')]=ArrayObject([NumberObject(v) for v in (0,0,192,128)])
            form[NameObject('/Resources')]=w._add_object(DictionaryObject())
            resources=DictionaryObject({NameObject('/XObject'):w._add_object(DictionaryObject({NameObject('/F'):w._add_object(form)}))})
            p[NameObject('/Resources')]=w._add_object(resources)
            p[NameObject('/Contents')]=w._add_object(stream(b'q /F Do Q\n'))
        self.assertEqual(self.inspect(config)['embedded_images'],0)
    def test_unembedded_native_text_rejects(self):
        def config(w,p):
            font=DictionaryObject({NameObject('/Type'):NameObject('/Font'),NameObject('/Subtype'):NameObject('/Type1'),NameObject('/BaseFont'):NameObject('/Helvetica')})
            p['/Resources'][NameObject('/Font')]=w._add_object(DictionaryObject({NameObject('/F'):w._add_object(font)}))
            data=p['/Contents'].get_data()+b'BT /F 20 Tf 20 70 Td (AVA) Tj ET\n'
            p[NameObject('/Contents')]=w._add_object(stream(data))
        with self.assertRaisesRegex(ValueError,'embedded'):self.inspect(config,mode='native')
    def test_native_text_is_not_an_outline(self):
        def config(w,p):
            font=DictionaryObject({NameObject('/Type'):NameObject('/Font'),NameObject('/Subtype'):NameObject('/Type1'),NameObject('/BaseFont'):NameObject('/Helvetica')})
            p['/Resources'][NameObject('/Font')]=DictionaryObject({NameObject('/F'):w._add_object(font)})
            p[NameObject('/Contents')]=w._add_object(stream(p['/Contents'].get_data()+b'BT /F 20 Tf 20 70 Td (AVA) Tj ET\n'))
        with self.assertRaises(ValueError):self.inspect(config)
    def test_extra_page_rejects(self):
        with self.assertRaises(ValueError):self.inspect(lambda w,p:w.add_blank_page(width=192,height=128))

class SVGInspector(unittest.TestCase):
    def inspect(self,edit=lambda text:text,scene='multi'):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'synthetic.svg';p.write_text(edit(make_svg(scene)),encoding='utf-8')
            return tv.inspect_svg(p,scene)
    def test_all_synthetic_vector_scenes(self):
        for s in tv.SCENES:self.assertGreaterEqual(self.inspect(scene=s)['vector_shapes'],3)
    def test_wrong_physical_size(self):
        with self.assertRaises(ValueError):self.inspect(lambda t:t.replace('192pt','192px'))
    def test_missing_annotation(self):
        with self.assertRaises(ValueError):self.inspect(lambda t:t.replace('text-blob/multi','text-blob/other'))
    def test_text_not_outline(self):
        with self.assertRaises(ValueError):self.inspect(lambda t:t.replace('</svg>','<text x="1" y="1">AVA</text></svg>'))
    def test_raster_image_rejects(self):
        with self.assertRaises(ValueError):self.inspect(lambda t:t.replace('</svg>','<image href="x.png"/></svg>'))
    def test_DTD_rejects(self):
        with self.assertRaises(ValueError):self.inspect(lambda t:'<!DOCTYPE svg>'+t)
    def test_foreignObject_rejects(self):
        with self.assertRaises(ValueError):self.inspect(lambda t:t.replace('</svg>','<foreignObject/></svg>'))

class ViewerInspector(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec=importlib.util.spec_from_file_location('synthetic_text_blob_tests',Path(__file__).with_name('test-text-blobs.py'))
        cls.tests=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.tests)
    def test_synthetic_matching_pixels(self):
        with tempfile.TemporaryDirectory() as d:
            for s in tv.SCENES:
                data=self.tests.synthetic_pixels(s);p=Path(d)/(s+'.png')
                Image.frombytes('RGBA',(192,128),data).save(p)
                self.assertEqual(tv.inspect_render(p,s,data)['mean_rgb_error'],0)
    def test_wrong_viewer_size_rejects(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'small.png';Image.new('RGBA',(1,1)).save(p)
            with self.assertRaises(ValueError):tv.inspect_render(p,'multi',self.tests.synthetic_pixels('multi'))
    def test_blank_viewer_rejects_even_with_matching_blank_reference(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'blank.png';Image.new('RGBA',(192,128),'white').save(p)
            with self.assertRaises(ValueError):tv.inspect_render(p,'multi',bytes(tv.WHITE)*(192*128))

if __name__=='__main__':unittest.main(verbosity=2)
