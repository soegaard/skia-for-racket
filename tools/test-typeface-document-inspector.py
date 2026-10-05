#!/usr/bin/env python3
"""Synthetic 0.68a document/visual-oracle tests, NOT native Skia execution."""
from __future__ import annotations
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image, ImageDraw
from pypdf import PdfWriter
from pypdf.generic import (ArrayObject, DictionaryObject, FloatObject, NameObject,
                           NumberObject, TextStringObject, DecodedStreamObject)
import typeface_validation as tv


def pixels(face):
    im=Image.new('RGBA',(160,100),'white');d=ImageDraw.Draw(im)
    d.rectangle((2,2,5,5),fill=(0,255,0,255))
    width=28.8 if face=='bold' else 19.2
    advance=38.4 if face=='bold' else 28.8
    d.rectangle((16,39,16+width-1,71),fill=tv.BLUE)
    x=16+advance
    d.polygon(((x,39),(x+width/2,71),(x+width,39)),fill=tv.BLUE)
    tv.pixel_checks(im.tobytes(),face)
    return im


def pdf(path,face='regular',mode='native',*,embed=True,text='AV',image=False,inline=False,
        link=True,blank=False,wrong_size=False,form=False):
    w=PdfWriter();p=w.add_blank_page(width=159 if wrong_size else 160,height=100)
    res=DictionaryObject();p[NameObject('/Resources')]=res
    data=b'1 1 1 rg 0 0 160 100 re f 0 1 0 rg 2 94 4 4 re f\n'
    if not blank:
        if mode=='native':
            # Deliberately synthetic font stream: this exercises structural
            # embedding detection, not font validity or Skia's PDF writer.
            font=DictionaryObject({NameObject('/Type'):NameObject('/Font'),NameObject('/Subtype'):NameObject('/Type1'),
                NameObject('/BaseFont'):NameObject('/Helvetica'),NameObject('/Encoding'):NameObject('/WinAnsiEncoding')})
            if embed:
                dummy=DecodedStreamObject();dummy.set_data(b'synthetic inspector fixture; not a font')
                descriptor=DictionaryObject({NameObject('/Type'):NameObject('/FontDescriptor'),
                                              NameObject('/FontFile2'):w._add_object(dummy)})
                font[NameObject('/FontDescriptor')]=w._add_object(descriptor)
            res[NameObject('/Font')]=DictionaryObject({NameObject('/F1'):w._add_object(font)})
            data+=b'0 0 1 rg BT /F1 48 Tf 16 28 Td ('+text.encode('ascii')+b') Tj ET\n'
        else:data+=b'0 0 1 rg 16 28 20 34 re f\n'
    if image:
        obj=DecodedStreamObject();obj.set_data(b'\x00\x00\x00')
        obj.update({NameObject('/Type'):NameObject('/XObject'),NameObject('/Subtype'):NameObject('/Image'),
                    NameObject('/Width'):NumberObject(1),NameObject('/Height'):NumberObject(1),
                    NameObject('/BitsPerComponent'):NumberObject(8),NameObject('/ColorSpace'):NameObject('/DeviceRGB')})
        res[NameObject('/XObject')]=DictionaryObject({NameObject('/Im'):w._add_object(obj)})
    if inline:data+=b'BI /W 1 /H 1 /CS /RGB /BPC 8 ID \x00\x00\x00 EI\n'
    if form:
        obj=DecodedStreamObject();obj.set_data(data)
        obj.update({NameObject('/Type'):NameObject('/XObject'),NameObject('/Subtype'):NameObject('/Form'),
                    NameObject('/BBox'):ArrayObject([NumberObject(x) for x in (0,0,160,100)]),NameObject('/Resources'):res})
        p[NameObject('/Resources')]=DictionaryObject({NameObject('/XObject'):DictionaryObject({NameObject('/Fm'):w._add_object(obj)})})
        data=b'/Fm Do\n'
    stream=DecodedStreamObject();stream.set_data(data);p[NameObject('/Contents')]=w._add_object(stream)
    if link:
        a=DictionaryObject({NameObject('/Type'):NameObject('/Annot'),NameObject('/Subtype'):NameObject('/Link'),
            NameObject('/Rect'):ArrayObject([NumberObject(x) for x in (2,94,6,98)]),
            NameObject('/A'):DictionaryObject({NameObject('/S'):NameObject('/URI'),
                  NameObject('/URI'):TextStringObject('https://example.invalid/typeface/'+face)})})
        p[NameObject('/Annots')]=ArrayObject([w._add_object(a)])
    with path.open('wb') as f:w.write(f)


def svg(path,face='regular',*,image=False,text=False,link=True,blank=False,width='160pt',doctype=False):
    shapes='<rect width="160" height="100" fill="white"/>'
    if not blank:shapes+='<rect x="2" y="2" width="4" height="4" fill="lime"/><path d="M16 38h20v34H16Z" fill="blue"/>'
    if image:shapes+='<image width="1" height="1" href="data:image/png;base64,eA=="/>'
    if text:shapes+='<text>AV</text>'
    if link:shapes+=f'<a href="https://example.invalid/typeface/{face}"><rect width="4" height="4" fill="none"/></a>'
    s=f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="100pt" viewBox="0 0 160 100">{shapes}</svg>'
    if doctype:s='<!DOCTYPE svg [<!ENTITY x "x">]>'+s
    path.write_text(s)


def receipt(spec):
    face,fmt,mode=spec;stem=f'{face}-{fmt}-{mode}'
    features=['geometry','annotation']+(['native-text'] if mode=='native' else [])
    return dict(face=face,format=fmt,text_mode=mode,file=stem+'.'+fmt,rgba=stem+'.rgba',callback_count=1,
        audit_policy='vector-only',audit=dict(mode='export',backend=fmt,blocking=False,vector_only=True,
            events=[dict(feature=f,status='vector') for f in features]))


def metadata():
    return [dict(face=f,postscript_name='SkiaRacketFixture-'+f.title(),glyph_count=4,units_per_em=1000,
                 fixed_pitch=True,table_tags=[0x6e616d65,0x6d617870,0x636d6170],font_data_bytes=1600,
                 font_data_index=0,kerning_available=False,kerning=False) for f in ('regular','bold')]


class Documents(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
    def pdf(self,mode='native',**kw):
        p=self.root/'x.pdf';pdf(p,mode=mode,**kw);return tv.inspect_pdf(p,'regular',mode)
    def svg(self,**kw):
        p=self.root/'x.svg';svg(p,**kw);return tv.inspect_svg(p,'regular')
    def test_native_embedding_and_extraction(self):self.assertEqual(self.pdf()['extracted'],'AV')
    def test_native_text_in_nested_form(self):self.assertEqual(self.pdf(form=True)['extracted'],'AV')
    def test_outline_pdf(self):self.assertFalse(self.pdf(mode='outline')['native_text'])
    def test_missing_embedding_rejected(self):
        with self.assertRaises(ValueError):self.pdf(embed=False)
    def test_wrong_text_rejected(self):
        with self.assertRaises(ValueError):self.pdf(text='AA')
    def test_missing_native_text_rejected(self):
        with self.assertRaises(ValueError):self.pdf(blank=True)
    def test_raster_pdf_resource_rejected(self):
        with self.assertRaises(ValueError):self.pdf(image=True)
    def test_nested_raster_pdf_resource_rejected(self):
        with self.assertRaises(ValueError):self.pdf(image=True,form=True)
    def test_inline_pdf_image_rejected(self):
        with self.assertRaises(ValueError):self.pdf(inline=True)
    def test_wrong_pdf_size_rejected(self):
        with self.assertRaises(ValueError):self.pdf(wrong_size=True)
    def test_missing_pdf_link_rejected(self):
        with self.assertRaises(ValueError):self.pdf(link=False)
    def test_outlined_svg(self):self.assertFalse(self.svg()['native_text'])
    def test_svg_raster_rejected(self):
        with self.assertRaises(ValueError):self.svg(image=True)
    def test_svg_native_text_rejected(self):
        with self.assertRaises(ValueError):self.svg(text=True)
    def test_svg_blank_rejected(self):
        with self.assertRaises(ValueError):self.svg(blank=True)
    def test_svg_link_required(self):
        with self.assertRaises(ValueError):self.svg(link=False)
    def test_svg_external_entity_rejected(self):
        with self.assertRaises(ValueError):self.svg(doctype=True)
    def test_svg_size_must_be_physical(self):
        for v in ('160','100%','159pt'):
            with self.subTest(v=v),self.assertRaises(ValueError):self.svg(width=v)
    def test_six_document_inspection_and_viewer_pipeline(self):
        rows=[]
        for spec in tv.SPECS:
            f,fmt,mode=spec;r=receipt(spec);rows.append(r)
            if fmt=='pdf':pdf(self.root/r['file'],f,mode)
            else:svg(self.root/r['file'],f)
            pixels(f).save(self.root/(r['file']+'.png'))
            (self.root/r['rgba']).write_bytes(pixels(f).tobytes())
        (self.root/'documents.json').write_text(json.dumps(dict(schema=1,stage='0.68a',run_token='synthetic',
             status='passed',rendering_executed=True,gpu_executed=False,gui_executed=False,documents=rows,typefaces=metadata())))
        report=tv.inspect_documents(self.root,'synthetic',render=lambda path,fmt:path.with_name(path.name+'.png'))
        self.assertEqual(len(report['documents']),6)
        self.assertTrue(report['independent_renderers_executed'])
        # This callback supplies synthetic pixels; the flag means an inspector
        # render callback ran, not that this unit test executed Poppler or Skia.


class Viewer(unittest.TestCase):
    def check(self,face='regular',modify=None):
        reference=pixels(face);actual=reference.copy()
        if modify:modify(actual)
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'x.png';actual.save(p)
            return tv.inspect_render(p,face,reference.tobytes())
    def test_both_reference_faces(self):
        for f in ('regular','bold'):self.check(f)
    def test_blank_fails(self):
        with self.assertRaises(ValueError):self.check(modify=lambda im:im.paste('white',(0,0,160,100)))
    def test_missing_marker_fails(self):
        with self.assertRaises(ValueError):self.check(modify=lambda im:im.paste('white',(2,2,6,6)))
    def test_missing_second_glyph_fails(self):
        with self.assertRaises(ValueError):self.check(modify=lambda im:im.paste('white',(44,38,65,73)))
    def test_wrong_face_fails(self):
        with self.assertRaises(ValueError):self.check(modify=lambda im:im.paste(pixels('bold')))
    def test_wrong_text_color_fails(self):
        with self.assertRaises(ValueError):self.check(modify=lambda im:im.putpixel((20,50),(255,0,0,255)))
    def test_antialias_at_edge_tolerated(self):self.check(modify=lambda im:im.putpixel((16,39),(150,170,230,255)))
    def test_broad_corruption_fails(self):
        with self.assertRaises(ValueError):self.check(modify=lambda im:im.paste('black',(105,20,150,85)))
    def test_nonopaque_background_fails(self):
        with self.assertRaises(ValueError):self.check(modify=lambda im:im.putpixel((159,99),(255,255,255,0)))


if __name__=='__main__':unittest.main(verbosity=2)
