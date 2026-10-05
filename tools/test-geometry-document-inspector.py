#!/usr/bin/env python3
"""Synthetic parser/viewer-oracle regressions. These files are NOT Skia output."""
from __future__ import annotations
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image, ImageDraw
from pypdf import PdfWriter
from pypdf.generic import (ArrayObject, DictionaryObject, FloatObject, NameObject,
                           NumberObject, TextStringObject, DecodedStreamObject)
import geometry_completion_validation as g


def good_receipt(name='boolean',fmt='pdf'):
    return dict(name=name,format=fmt,file=f'{name}.{fmt}',rgba=f'{name}.rgba',callback_count=1,
                audit_policy='vector-only',audit=dict(mode='export',backend=fmt,blocking=False,
                vector_only=True,events=[dict(feature='geometry',status='vector')]),
                group=dict(backend=fmt,policy='require-vector',strategy='native',
                           bounds=[8,16,64,48],pixel_size=False))


def synthetic_pixels(name):
    """Coherent local scene fixtures, not expected Skia pixel buffers."""
    im=Image.new('RGBA',(64,48),'white');draw=ImageDraw.Draw(im)
    if name=='arc':draw.pieslice((8,8,40,40),0,90,fill=g.BLUE)
    elif name=='tangent':
        draw.line((8,8,40,8,40,40),fill=g.RED,width=4)
    elif name=='boolean':
        draw.rectangle((8,8,47,39),fill=g.BLUE);draw.rectangle((20,16,31,31),fill=g.WHITE)
    elif name=='outline':draw.line((8,24,56,24),fill=g.RED,width=8)
    elif name=='region':
        draw.rectangle((16,12,31,31),fill=g.BLUE);draw.rectangle((40,12,47,31),fill=g.BLUE)
    elif name=='rrect':draw.rounded_rectangle((12,8,52,40),radius=6,fill=g.GREEN)
    elif name=='polygon':draw.polygon(((8,8),(56,8),(32,40)),fill=g.RED)
    else:raise ValueError(name)
    g.pixel_checks(im.tobytes(),name)
    return im


def synthetic_page(name):
    page=Image.new('RGBA',(96,72),'white')
    ImageDraw.Draw(page).rectangle((2,2,5,5),fill=(0,255,0,255))
    page.paste(synthetic_pixels(name),(8,16))
    return page


def pdf_fixture(path,name='boolean',*,image=False,inline=False,form=False,nested_image=False,
                no_link=False,blank=False,wrong_size=False,cycle=False):
    writer=PdfWriter();page=writer.add_blank_page(width=95 if wrong_size else 96,height=72)
    resources=DictionaryObject();page[NameObject('/Resources')]=resources
    data=b'1 1 1 rg 0 0 96 72 re f 0 1 0 rg 2 66 4 4 re f 0 0 1 rg 16 16 32 32 re f\n'
    if blank:data=b'1 1 1 rg 0 0 96 72 re f\n'
    if inline:data+=b'BI /W 1 /H 1 /CS /RGB /BPC 8 ID \x00\x00\x00 EI\n'
    xobjs=DictionaryObject();resources[NameObject('/XObject')]=xobjs
    if image or nested_image:
        im=DecodedStreamObject();im.set_data(b'\xff\x00\x00')
        im.update({NameObject('/Type'):NameObject('/XObject'),NameObject('/Subtype'):NameObject('/Image'),
                   NameObject('/Width'):NumberObject(1),NameObject('/Height'):NumberObject(1),
                   NameObject('/BitsPerComponent'):NumberObject(8),NameObject('/ColorSpace'):NameObject('/DeviceRGB')})
        image_ref=writer._add_object(im)
        if image:xobjs[NameObject('/Im')]=image_ref
    if form or nested_image or cycle:
        obj=DecodedStreamObject();obj.set_data(data)
        obj[NameObject('/Type')]=NameObject('/XObject');obj[NameObject('/Subtype')]=NameObject('/Form')
        obj[NameObject('/BBox')]=ArrayObject([NumberObject(x) for x in (0,0,96,72)])
        inner=DictionaryObject();inner_x=DictionaryObject();inner[NameObject('/XObject')]=inner_x
        obj[NameObject('/Resources')]=inner
        ref=writer._add_object(obj);xobjs[NameObject('/Fm')]=ref
        if nested_image:inner_x[NameObject('/Im')]=image_ref
        if cycle:inner_x[NameObject('/Loop')]=ref;obj.set_data(b'/Loop Do\n')
        data=b'/Fm Do\n'
    stream=DecodedStreamObject();stream.set_data(data);page[NameObject('/Contents')]=writer._add_object(stream)
    if not no_link:
        action=DictionaryObject({NameObject('/S'):NameObject('/URI'),
                                 NameObject('/URI'):TextStringObject('https://example.invalid/geometry/'+name)})
        annot=DictionaryObject({NameObject('/Type'):NameObject('/Annot'),NameObject('/Subtype'):NameObject('/Link'),
             NameObject('/Rect'):ArrayObject([FloatObject(x) for x in (2,64,6,70)]),NameObject('/A'):action})
        page[NameObject('/Annots')]=ArrayObject([writer._add_object(annot)])
    with path.open('wb') as f:writer.write(f)


def svg_fixture(path,name='boolean',*,width='96pt',height='72pt',image=False,no_link=False,blank=False,doctype=False):
    shapes='<rect width="96" height="72" fill="white"/>'
    if not blank:shapes+='<rect x="2" y="2" width="4" height="4" fill="lime"/><path d="M 16 16 h 32 v 32 h -32 Z" fill="blue"/>'
    if image:shapes+='<image width="64" height="48" href="data:image/png;base64,eA=="/>'
    if not no_link:shapes+=f'<a href="https://example.invalid/geometry/{name}"><rect fill="none" width="4" height="4"/></a>'
    text=f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 96 72">{shapes}</svg>'
    if doctype:text='<!DOCTYPE svg [<!ENTITY a "x">]>'+text
    path.write_text(text,encoding='utf-8')


class Documents(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
    def pdf(self,**kw):
        p=self.root/'x.pdf';pdf_fixture(p,**kw);return g.inspect_pdf(p,'boolean')
    def svg(self,**kw):
        p=self.root/'x.svg';svg_fixture(p,**kw);return g.inspect_svg(p,'boolean')
    def test_vector_pdf(self):self.assertEqual(self.pdf()['painted_paths'],3)
    def test_nested_vector_pdf_form(self):self.assertEqual(self.pdf(form=True)['painted_paths'],3)
    def test_unused_pdf_image_resource_rejected(self):
        with self.assertRaises(ValueError):self.pdf(image=True)
    def test_nested_pdf_image_resource_rejected(self):
        with self.assertRaises(ValueError):self.pdf(nested_image=True)
    def test_inline_pdf_image_rejected(self):
        with self.assertRaises(ValueError):self.pdf(inline=True)
    def test_cyclic_pdf_form_rejected(self):
        with self.assertRaises(ValueError):self.pdf(cycle=True)
    def test_missing_pdf_annotation_rejected(self):
        with self.assertRaises(ValueError):self.pdf(no_link=True)
    def test_blank_pdf_rejected(self):
        with self.assertRaises(ValueError):self.pdf(blank=True)
    def test_wrong_pdf_dimensions_rejected(self):
        with self.assertRaises(ValueError):self.pdf(wrong_size=True)
    def test_vector_svg(self):self.assertEqual(self.svg()['embedded_images'],0)
    def test_css_pixel_dimensions_are_physical(self):self.svg(width='128px',height='96px')
    def test_svg_raster_rejected(self):
        with self.assertRaises(ValueError):self.svg(image=True)
    def test_svg_missing_link_rejected(self):
        with self.assertRaises(ValueError):self.svg(no_link=True)
    def test_svg_blank_rejected(self):
        with self.assertRaises(ValueError):self.svg(blank=True)
    def test_svg_doctype_rejected(self):
        with self.assertRaises(ValueError):self.svg(doctype=True)
    def test_svg_dimensions_are_not_guessed(self):
        for width in ('95pt','96','100%','Infinitypt'):
            with self.subTest(width=width),self.assertRaises(ValueError):self.svg(width=width)
    def test_full_synthetic_fourteen_document_matrix(self):
        rows=[]
        for name in g.SCENES:
            (self.root/f'{name}.rgba').write_bytes(synthetic_pixels(name).tobytes())
            for fmt in ('pdf','svg'):
                (pdf_fixture if fmt=='pdf' else svg_fixture)(self.root/f'{name}.{fmt}',name)
                rows.append(good_receipt(name,fmt))
        (self.root/'documents.json').write_text(json.dumps(dict(schema=1,stage='0.67',run_token='synthetic',status='passed',documents=rows)))
        report=g.inspect_documents(self.root,'synthetic')
        self.assertEqual(len(report['documents']),14)
        self.assertFalse(report['independent_rendering_executed'])
        # A supplied renderer here is a synthetic image factory, not an external
        # renderer. This tests plumbing and the oracle, never a Skia claim.
        def render(path,fmt):
            out=self.root/(path.name+'.png');synthetic_page(path.stem).save(out);return out
        checked=g.inspect_documents(self.root,'synthetic',render=render)
        self.assertTrue(checked['independent_rendering_executed'])
        rows[0]['audit']['vector_only']=False
        (self.root/'documents.json').write_text(json.dumps(dict(schema=1,stage='0.67',run_token='synthetic',status='passed',documents=rows)))
        with self.assertRaises(ValueError):g.inspect_documents(self.root,'synthetic')


class ViewerOracle(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.path=Path(self.temp.name)/'x.png'
    def check(self,page,name='boolean'):
        page.save(self.path);return g.inspect_render(self.path,name,synthetic_pixels(name).tobytes())
    def test_all_reference_scenes(self):
        for name in g.SCENES:
            with self.subTest(scene=name):self.assertEqual(self.check(synthetic_page(name),name)['mean_channel_error'],0)
    def test_missing_scene_rejected(self):
        page=synthetic_page('boolean');ImageDraw.Draw(page).rectangle((8,16,71,63),fill='white')
        with self.assertRaises(ValueError):self.check(page)
    def test_erased_hole_rejected(self):
        page=synthetic_page('boolean');ImageDraw.Draw(page).rectangle((28,32,39,47),fill=g.BLUE)
        with self.assertRaises(ValueError):self.check(page)
    def test_moved_scene_rejected(self):
        page=Image.new('RGBA',(96,72),'white');ImageDraw.Draw(page).rectangle((2,2,5,5),fill='lime')
        page.paste(synthetic_pixels('boolean'),(15,23))
        with self.assertRaises(ValueError):self.check(page)
    def test_marker_required(self):
        page=synthetic_page('boolean');ImageDraw.Draw(page).rectangle((2,2,5,5),fill='white')
        with self.assertRaises(ValueError):self.check(page)
    def test_outside_ink_rejected(self):
        page=synthetic_page('boolean');page.putpixel((88,68),g.BLUE)
        with self.assertRaises(ValueError):self.check(page)
    def test_size_required(self):
        with self.assertRaises(ValueError):self.check(synthetic_page('boolean').resize((95,72)))
    def test_small_edge_change_tolerated(self):
        page=synthetic_page('boolean');page.putpixel((16,24),(10,70,225,255))
        self.check(page)
    def test_rrect_vector_edge_antialiasing_tolerated_but_filled_corner_rejected(self):
        page=synthetic_page('rrect')
        # Poppler on the host produced this modest coverage at local (13,9).
        page.putpixel((8+13,16+9),(234,247,240,255))
        self.check(page,'rrect')
        page.putpixel((8+13,16+9),g.GREEN)
        with self.assertRaises(ValueError):self.check(page,'rrect')
    def test_large_interior_corruption_rejected(self):
        page=synthetic_page('boolean');ImageDraw.Draw(page).rectangle((42,27,52,46),fill=(255,0,255,255))
        with self.assertRaises(ValueError):self.check(page)


if __name__=='__main__':unittest.main(verbosity=2)
