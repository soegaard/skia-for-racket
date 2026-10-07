#!/usr/bin/env python3
"""Synthetic parser regression tests. These PDFs/SVGs were NOT emitted by Skia."""
import base64
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zlib

from PIL import Image
from pypdf import PdfWriter
from pypdf.generic import (ArrayObject, DictionaryObject, NameObject, NumberObject,
                           TextStringObject, DecodedStreamObject, EncodedStreamObject)
import advanced_canvas_validation as v

TOKEN='synthetic-document-parser-074'


def pdf_bytes(mode, *, url=v.URL, size=v.SIZE):
    writer=PdfWriter();page=writer.add_blank_page(*size)
    content=b'q 1 0 0 -1 0 48 cm\n1 1 1 rg 0 0 64 48 re f\n'
    if mode=='vector':
        content+=b'1 0 0 rg 8 8 24 24 re f\n0 0 1 rg 36 16 20 16 re f\n'
    else:
        image=EncodedStreamObject()
        rgba=v.expected_rgba('layer')
        image._data=zlib.compress(b''.join(rgba[i:i+3] for i in range(0,len(rgba),4)))
        image.update({NameObject('/Type'):NameObject('/XObject'),NameObject('/Subtype'):NameObject('/Image'),
                      NameObject('/Width'):NumberObject(64),NameObject('/Height'):NumberObject(48),
                      NameObject('/ColorSpace'):NameObject('/DeviceRGB'),NameObject('/BitsPerComponent'):NumberObject(8),
                      NameObject('/Filter'):NameObject('/FlateDecode')})
        page[NameObject('/Resources')]=DictionaryObject({NameObject('/XObject'):
            DictionaryObject({NameObject('/Im1'):writer._add_object(image)})})
        content+=b'q 64 0 0 -48 0 48 cm /Im1 Do Q\n'
    content+=b'0 1 0 rg 2 2 4 4 re f\nQ\n'
    stream=DecodedStreamObject();stream.set_data(content)
    page[NameObject('/Contents')]=writer._add_object(stream)
    if url:
        annotation=DictionaryObject({NameObject('/Type'):NameObject('/Annot'),NameObject('/Subtype'):NameObject('/Link'),
            NameObject('/Rect'):ArrayObject([NumberObject(n) for n in (2,42,6,46)]),
            NameObject('/Border'):ArrayObject([NumberObject(0)]*3),NameObject('/A'):DictionaryObject({
                NameObject('/S'):NameObject('/URI'),NameObject('/URI'):TextStringObject(url)})})
        page[NameObject('/Annots')]=ArrayObject([writer._add_object(annotation)])
    result=io.BytesIO();writer.write(result);return result.getvalue()


def svg_bytes(mode, *, url=v.URL, pixels=None):
    if mode=='vector':
        body='<rect x="8" y="8" width="24" height="24" fill="red"/><rect x="36" y="16" width="20" height="16" fill="blue"/>'
    else:
        png=io.BytesIO();Image.frombytes('RGBA',v.SIZE,pixels or v.expected_rgba('layer')).save(png,format='PNG')
        body='<image width="64" height="48" href="data:image/png;base64,'+base64.b64encode(png.getvalue()).decode()+'"/>'
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="48">'
            '<rect width="64" height="48" fill="white"/>'+body+
            '<a href="'+url+'"><rect x="2" y="2" width="4" height="4" fill="#00ff00"/></a></svg>').encode()


def fixture(directory):
    rows=[]
    for mode,kind in v.DOCUMENTS:
        name=f'{mode}.{kind}'
        (directory/name).write_bytes(pdf_bytes(mode) if kind=='pdf' else svg_bytes(mode))
        events=[dict(page=1,feature=f,status='vector') for f in ('geometry','annotation')]
        events.append(dict(page=1,feature='drawable' if mode=='vector' else 'image',
                           status='vector' if mode=='vector' else 'embedded-raster'))
        rows.append(dict(mode=mode,format=kind,file=name,boundary='native-drawable' if mode=='vector' else 'explicit-integer-snapshot',
                         audit=dict(backend=kind,mode='export',pages=1,blocking=False,vector_only=(mode=='vector'),events=events)))
    report=dict(schema=1,stage='0.74',run_token=TOKEN,status='passed',layer_source='cpu',documents=rows)
    (directory/'documents.json').write_text(json.dumps(report))
    return report


class Documents(unittest.TestCase):
    def invoke(self, change=lambda d:None):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);fixture(root);change(root)
            return v.inspect_documents(root,TOKEN,'cpu',render=False)
    def reject(self,change):
        with self.assertRaises((ValueError,KeyError,TypeError)):self.invoke(change)
    def test_all_four(self):self.assertEqual(len(self.invoke()['documents']),4)
    def test_pdf_url_required(self):self.reject(lambda d:(d/'vector.pdf').write_bytes(pdf_bytes('vector',url=None)))
    def test_pdf_wrong_url(self):self.reject(lambda d:(d/'vector.pdf').write_bytes(pdf_bytes('vector',url='https://wrong.invalid')))
    def test_pdf_wrong_size(self):self.reject(lambda d:(d/'vector.pdf').write_bytes(pdf_bytes('vector',size=(65,48))))
    def test_pdf_hidden_image(self):self.reject(lambda d:(d/'vector.pdf').write_bytes(pdf_bytes('layer')))
    def test_pdf_missing_image(self):self.reject(lambda d:(d/'layer.pdf').write_bytes(pdf_bytes('vector')))
    def test_svg_wrong_url(self):self.reject(lambda d:(d/'vector.svg').write_bytes(svg_bytes('vector',url='https://wrong.invalid')))
    def test_svg_hidden_image(self):self.reject(lambda d:(d/'vector.svg').write_bytes(svg_bytes('layer')))
    def test_svg_missing_image(self):self.reject(lambda d:(d/'layer.svg').write_bytes(svg_bytes('vector')))
    def test_svg_bad_embedded_pixels(self):self.reject(lambda d:(d/'layer.svg').write_bytes(svg_bytes('layer',pixels=bytes([0,0,0,255])*64*48)))
    def test_svg_external_image(self):
        def change(d):
            path=d/'layer.svg';tree=ET.fromstring(path.read_bytes())
            for node in tree.iter():
                if node.tag.endswith('image'):node.set('href','https://example.invalid/image.png')
            path.write_bytes(ET.tostring(tree))
        self.reject(change)
    def test_svg_script(self):
        self.reject(lambda d:(d/'vector.svg').write_bytes(svg_bytes('vector').replace(b'</svg>',b'<script>bad</script></svg>')))
    def test_svg_dtd(self):
        self.reject(lambda d:(d/'vector.svg').write_bytes(b'<!DOCTYPE svg SYSTEM "file:///tmp/no">'+svg_bytes('vector')))
    def test_missing_file(self):self.reject(lambda d:(d/'vector.pdf').unlink())
    def test_no_renderer_is_not_success_when_required(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);fixture(root)
            with patch.object(v.shutil,'which',return_value=None),self.assertRaisesRegex(ValueError,'renderer missing'):
                v.inspect_documents(root,TOKEN,'cpu',render=True)


if __name__=='__main__':unittest.main(verbosity=2)
