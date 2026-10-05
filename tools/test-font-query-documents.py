#!/usr/bin/env python3
"""Synthetic PDF structural regressions; requires the pinned document inspector dependencies."""
from pathlib import Path
import tempfile
import unittest
from pypdf import PdfWriter
from pypdf.generic import DictionaryObject, NameObject, NumberObject, DecodedStreamObject
import font_query_validation as fv


def stream(data):
    value=DecodedStreamObject();value.set_data(data);return value


class PDFInspector(unittest.TestCase):
    def inspect(self, configure=lambda w,p:None, scene='batch', width=160):
        with tempfile.TemporaryDirectory() as directory:
            writer=PdfWriter();page=writer.add_blank_page(width=width,height=100)
            page[NameObject('/Contents')]=writer._add_object(stream(b'1 1 1 rg 0 0 160 100 re f\n0 0 0 rg 20 40 20 20 re f'))
            page[NameObject('/Resources')]=DictionaryObject()
            configure(writer,page)
            path=Path(directory)/'synthetic.pdf'
            with path.open('wb') as out:writer.write(out)
            return fv.inspect_pdf(path,scene)
    def test_vector_only_synthetic_pdf(self):
        self.assertEqual(self.inspect()['text_operations'],0)
    def test_outlines_cannot_claim_preserved_native_text(self):
        with self.assertRaises(ValueError):self.inspect(scene='snapshot')
    def test_wrong_page_dimensions(self):
        with self.assertRaises(ValueError):self.inspect(width=200)
    def test_raster_resource_is_rejected_even_if_not_drawn(self):
        def configure(w,p):
            image=stream(bytes([0,0,0]));image.update({NameObject('/Type'):NameObject('/XObject'),NameObject('/Subtype'):NameObject('/Image'),
                NameObject('/Width'):NumberObject(1),NameObject('/Height'):NumberObject(1),NameObject('/ColorSpace'):NameObject('/DeviceRGB'),
                NameObject('/BitsPerComponent'):NumberObject(8)})
            p['/Resources'][NameObject('/XObject')]=DictionaryObject({NameObject('/Image0'):w._add_object(image)})
        with self.assertRaises(ValueError):self.inspect(configure)
    def test_inline_image_rejected(self):
        def configure(w,p):
            p[NameObject('/Contents')]=w._add_object(stream(b'BI /W 1 /H 1 /CS /RGB /BPC 8 ID \x00\x00\x00 EI\n'))
        with self.assertRaises(ValueError):self.inspect(configure)
    def test_indirect_resources_and_vector_form(self):
        def configure(w,p):
            form=stream(b'0 0 0 rg 1 1 3 3 re f');form[NameObject('/Subtype')]=NameObject('/Form')
            res=DictionaryObject({NameObject('/XObject'):DictionaryObject({NameObject('/F0'):w._add_object(form)})})
            p[NameObject('/Resources')]=w._add_object(res)
            p[NameObject('/Contents')]=w._add_object(stream(b'q /F0 Do Q\n'))
        self.assertEqual(self.inspect(configure)['raster_images'],0)
    def test_unembedded_text_is_rejected(self):
        def configure(w,p):
            font=DictionaryObject({NameObject('/Type'):NameObject('/Font'),NameObject('/Subtype'):NameObject('/Type1'),
                                   NameObject('/BaseFont'):NameObject('/Helvetica')})
            p['/Resources'][NameObject('/Font')]=w._add_object(DictionaryObject({NameObject('/F1'):w._add_object(font)}))
            p[NameObject('/Contents')]=w._add_object(stream(b'BT /F1 20 Tf 20 40 Td (AV) Tj ET\n'))
        with self.assertRaises(ValueError):self.inspect(configure,scene='mutated')


if __name__=='__main__':unittest.main(verbosity=2)
