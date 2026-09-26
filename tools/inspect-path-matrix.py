#!/usr/bin/env python3
"""Inspect actual 0.24 output structure. Does not render SVG/PDF.
Standard library only, except optional --pdf which requires pypdf.
"""
import argparse
import base64
from collections import Counter
import json
from pathlib import Path
import re
import struct
import unittest
import xml.etree.ElementTree as ET
import zlib

SVG = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"
EXPECTED = {"inspection": [], "frames": [], "shaders": [(1220, 212)]}

def png_size(data):
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("embedded image is not PNG")
    at = 8
    size = None
    has_data = False
    while at < len(data):
        if at + 12 > len(data):
            raise ValueError("truncated PNG chunk")
        length = struct.unpack_from(">I", data, at)[0]
        kind = data[at + 4:at + 8]
        end = at + 12 + length
        if end > len(data):
            raise ValueError("PNG chunk exceeds input")
        payload = data[at + 8:at + 8 + length]
        if zlib.crc32(kind + payload) != struct.unpack_from(">I", data, at + 8 + length)[0]:
            raise ValueError("PNG CRC mismatch")
        if size is None:
            if kind != b"IHDR" or length != 13:
                raise ValueError("missing first IHDR")
            size = struct.unpack_from(">II", payload)
        if kind == b"IDAT":
            has_data = True
        if kind == b"IEND":
            if length or end != len(data) or not has_data:
                raise ValueError("invalid PNG end or no image data")
            return size
        at = end
    raise ValueError("missing PNG IEND")

def inspect_svg(data, kind):
    root = ET.fromstring(data)
    if root.tag != "{" + SVG + "}svg":
        raise ValueError("not an SVG root")
    for name, expected in (("width", 720), ("height", 500)):
        value = root.get(name, "")
        if not value.endswith("pt") or abs(float(value[:-2]) - expected) > 0.001:
            raise ValueError("incorrect physical " + name)
    if [float(v) for v in root.get("viewBox", "").split()] != [0, 0, 720, 500]:
        raise ValueError("incorrect viewBox")
    counts = Counter(e.tag.split("}")[-1] for e in root.iter())
    if counts["text"] or counts["path"] < 1:
        raise ValueError("expected outlined labels and vector paths")
    ids = [e.attrib["id"] for e in root.iter() if "id" in e.attrib]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate SVG id")
    images = []
    for element in root.iter():
        for name, value in element.attrib.items():
            for ref in re.findall(r"url\(#([^)]*)\)", value):
                if ref not in ids:
                    raise ValueError("unresolved SVG resource")
            if name.split("}")[-1] == "href" and value.startswith("#") and value[1:] not in ids:
                raise ValueError("unresolved SVG href")
        if element.tag == "{" + SVG + "}image":
            href = element.get("{" + XLINK + "}href", element.get("href", ""))
            prefix = "data:image/png;base64,"
            if not href.startswith(prefix):
                raise ValueError("external or non-PNG image")
            images.append(png_size(base64.b64decode(href[len(prefix):], validate=True)))
    if images != EXPECTED[kind]:
        raise ValueError("unexpected image sizes: " + repr(images))
    return {"size_points": [720, 500], "elements": dict(counts),
            "embedded_png_sizes": images, "resource_count": len(ids)}

def inspect_pdf(path):
    try:
        from pypdf import PdfReader
    except ImportError as error:
        raise SystemExit("--pdf requires pypdf; install it in your Python environment") from error
    reader = PdfReader(str(path))
    if len(reader.pages) != 3:
        raise ValueError("PDF should have three pages")
    sizes = []
    for page in reader.pages:
        size = [float(page.mediabox.width), float(page.mediabox.height)]
        if any(abs(a - b) > 0.01 for a, b in zip(size, (720, 500))):
            raise ValueError("wrong PDF MediaBox")
        sizes.append(size)
    return {"page_sizes": sizes, "text_samples": [p.extract_text()[:100] for p in reader.pages]}

def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

def synthetic_png():
    ihdr = struct.pack(">IIBBBBB", 1220, 212, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress((b"\0" + b"\0" * 1220 * 4) * 212)) + chunk(b"IEND", b""))

def synthetic_svg(body=""):
    return ('<svg xmlns="' + SVG + '" xmlns:xlink="' + XLINK
            + '" width="720pt" height="500pt" viewBox="0 0 720 500"><path d="M0 0L1 1"/>'
            + body + '</svg>').encode()

class Checks(unittest.TestCase):
    def test_vector(self):
        self.assertEqual(inspect_svg(synthetic_svg(), "frames")["embedded_png_sizes"], [])
    def test_units(self):
        with self.assertRaises(ValueError):
            inspect_svg(synthetic_svg().replace(b'720pt', b'720px'), "frames")
    def test_outline(self):
        with self.assertRaises(ValueError):
            inspect_svg(synthetic_svg('<text>unoutlined</text>'), "frames")
    def test_ids(self):
        with self.assertRaises(ValueError):
            inspect_svg(synthetic_svg('<path id="a"/><path id="a"/>'), "frames")
    def test_reference(self):
        with self.assertRaises(ValueError):
            inspect_svg(synthetic_svg('<path fill="url(#missing)"/>'), "frames")
    def test_external(self):
        with self.assertRaises(ValueError):
            inspect_svg(synthetic_svg('<image href="image.png"/>'), "shaders")
    def test_image(self):
        body = '<image xlink:href="data:image/png;base64,' + base64.b64encode(synthetic_png()).decode() + '"/>'
        self.assertEqual(inspect_svg(synthetic_svg(body), "shaders")["embedded_png_sizes"], [(1220, 212)])
    def test_crc(self):
        data = bytearray(synthetic_png())
        data[30] ^= 1
        with self.assertRaises(ValueError):
            png_size(data)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--probe-prefix", type=Path)
    parser.add_argument("--pdf", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks))
        if not result.wasSuccessful():
            raise SystemExit(1)
    if args.probe_prefix:
        prefix = str(args.probe_prefix)
        result = {"svg": {kind: inspect_svg(Path(prefix + "." + kind + ".svg").read_bytes(), kind)
                          for kind in EXPECTED},
                  "pdf": inspect_pdf(Path(prefix + ".pdf")) if args.pdf else "NOT CHECKED (use --pdf)",
                  "visual_review": "NOT PERFORMED by structural inspector"}
        print(json.dumps(result, indent=2))
    elif not args.self_test:
        parser.error("supply --self-test or --probe-prefix")

if __name__ == "__main__":
    main()
