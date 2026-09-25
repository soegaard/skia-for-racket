#!/usr/bin/env python3
"""Inspect the 0.23 probe's real SVG/PDF output (not its raster references).

SVG checks use only the Python standard library. --pdf additionally requires
pypdf. This is structural inspection, not a substitute for opening the files.
"""
from __future__ import annotations
import argparse
import base64
from collections import Counter
from fractions import Fraction
import json
import math
from pathlib import Path
import re
import struct
import unittest
import xml.etree.ElementTree as ET
import zlib

SVG = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"
SIZES = {
    "units": (float(Fraction(210 * 360, 127)), float(Fraction(140 * 360, 127))),
    "text": (600.0, 400.0),
    "effects": (float(Fraction(180 * 360, 127)), float(Fraction(125 * 360, 127))),
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def png_size(data: bytes) -> tuple[int, int]:
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), "embedded image is not PNG")
    offset = 8
    size = None
    have_data = False
    ended = False
    while offset + 12 <= len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        tag = data[offset + 4:offset + 8]
        end = offset + 12 + length
        require(end <= len(data), "truncated PNG chunk")
        payload = data[offset + 8:offset + 8 + length]
        checksum = struct.unpack_from(">I", data, offset + 8 + length)[0]
        require(zlib.crc32(tag + payload) & 0xffffffff == checksum, "PNG chunk CRC mismatch")
        if tag == b"IHDR":
            require(size is None and offset == 8 and length == 13, "invalid PNG IHDR")
            size = struct.unpack_from(">II", payload)
            require(min(size) > 0, "empty embedded PNG")
        elif tag == b"IDAT":
            have_data = True
        elif tag == b"IEND":
            require(length == 0 and end == len(data), "invalid PNG end")
            ended = True
            break
        offset = end
    require(size is not None and have_data and ended, "incomplete PNG")
    return size


def inspect_svg(data: bytes, expected_size: tuple[float, float] | None = None) -> dict:
    root = ET.fromstring(data)
    require(root.tag == f"{{{SVG}}}svg", "not an SVG document")
    physical = []
    for key in ("width", "height"):
        match = re.fullmatch(r"([0-9.eE+-]+)pt", root.get(key, ""))
        require(match is not None, f"root {key} must use physical pt units")
        n = float(match.group(1))
        require(math.isfinite(n) and n > 0, "invalid physical size")
        physical.append(n)
    view = [float(s) for s in root.get("viewBox", "").split()]
    require(len(view) == 4 and view[:2] == [0.0, 0.0], "invalid viewBox")
    for a, b in zip(view[2:], physical):
        require(math.isclose(a, b, rel_tol=1e-7, abs_tol=1e-5), "viewBox/physical size mismatch")
    if expected_size:
        for a, b in zip(physical, expected_size):
            require(math.isclose(a, b, rel_tol=1e-7, abs_tol=1e-4), "wrong page size")
    elements = list(root.iter())
    counts = Counter(e.tag.rsplit("}", 1)[-1] for e in elements)
    ids = [e.get("id") for e in elements if e.get("id")]
    require(len(ids) == len(set(ids)), "duplicate resource ID")
    id_set = set(ids)
    image_sizes = []
    for e in elements:
        for key, value in e.attrib.items():
            for target in re.findall(r"url\(#([^)]*)\)", value):
                require(target in id_set, f"unresolved resource {target}")
            if key in ("href", f"{{{XLINK}}}href") and value.startswith("#"):
                require(value[1:] in id_set, f"unresolved href {value}")
        if e.tag == f"{{{SVG}}}image":
            href = e.get(f"{{{XLINK}}}href", e.get("href", ""))
            require(href.startswith("data:image/png;base64,"), "image must be an embedded PNG")
            pixels = base64.b64decode(href.split(",", 1)[1], validate=True)
            image_sizes.append(png_size(pixels))
    return {"size_points": physical, "viewBox": view, "elements": dict(sorted(counts.items())),
            "embedded_png_sizes": image_sizes, "resource_ids": len(ids)}


def inspect_pdf(filename: Path) -> dict:
    try:
        from pypdf import PdfReader
        from pypdf.generic import ContentStream
    except ImportError as exc:
        raise RuntimeError("--pdf requires pypdf; SVG-only inspection needs no extra package") from exc
    reader = PdfReader(filename, strict=True)
    require(len(reader.pages) == 3, "PDF must contain three pages")
    reports = []
    for page, (name, size) in zip(reader.pages, SIZES.items()):
        actual = (float(page.mediabox.width), float(page.mediabox.height))
        for a, b in zip(actual, size):
            require(math.isclose(a, b, abs_tol=0.002), f"PDF {name} size mismatch")
        content = ContentStream(page.get_contents(), reader)
        operators = Counter(op.decode("ascii") for _, op in content.operations)
        require(operators["BT"] > 0, f"PDF {name} is expected to retain native text operators")
        resources = page.get("/Resources", {})
        if hasattr(resources, "get_object"):
            resources = resources.get_object()
        font_resources = resources.get("/Font", {})
        if hasattr(font_resources, "get_object"):
            font_resources = font_resources.get_object()
        fonts = []
        for key, ref in font_resources.items():
            font = ref.get_object()
            descriptors = []
            if "/FontDescriptor" in font:
                descriptors.append(font["/FontDescriptor"].get_object())
            for child in font.get("/DescendantFonts", []):
                child = child.get_object()
                if "/FontDescriptor" in child:
                    descriptors.append(child["/FontDescriptor"].get_object())
            fonts.append({"resource": str(key), "base_font": str(font.get("/BaseFont", "")),
                          "embedded": any(any(k in d for k in ("/FontFile", "/FontFile2", "/FontFile3"))
                                          for d in descriptors)})
        reports.append({"page": name, "size_points": actual, "text_objects": operators["BT"],
                        "fonts": fonts, "text_sample": (page.extract_text() or "")[:240]})
    return {"pages": reports, "metadata": {str(k): str(v) for k, v in (reader.metadata or {}).items()}}


def inspect_probe(prefix: Path, with_pdf: bool) -> dict:
    reports = {}
    for name, size in SIZES.items():
        filename = Path(f"{prefix}.{name}.svg")
        report = inspect_svg(filename.read_bytes(), size)
        require(report["elements"].get("text", 0) == 0,
                f"{name}: auto-outline mode should not emit text nodes")
        require(report["elements"].get("path", 0) > 0, f"{name}: expected vector paths")
        expected_images = [(386, 284), (329, 284)] if name == "effects" else []
        require(report["embedded_png_sizes"] == expected_images,
                f"{name}: wrong raster-group pixel sizes: {report['embedded_png_sizes']}")
        if name == "units":
            require(report["elements"].get("linearGradient", 0) > 0, "missing native linear gradient")
        reports[name] = report
    result = {"svg": reports, "pdf": inspect_pdf(Path(f"{prefix}.pdf")) if with_pdf else "NOT CHECKED (use --pdf)",
              "visual_review": "NOT PERFORMED by this structural inspector"}
    return result


# Synthetic parser/unit tests. These are not Skia rendering tests.
def sample_svg(body: str = "", width: str = "72pt", height: str = "36pt") -> bytes:
    return (f'<svg xmlns="{SVG}" xmlns:xlink="{XLINK}" width="{width}" height="{height}" '
            f'viewBox="0 0 72 36">{body}</svg>').encode()


def sample_png(width: int = 2, height: int = 1) -> bytes:
    def chunk(tag: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xffffffff)
    raw = b"".join(b"\0" + bytes(width * 4) for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


class InspectorTests(unittest.TestCase):
    def test_physical_units(self):
        self.assertEqual(inspect_svg(sample_svg(), (72, 36))["size_points"], [72.0, 36.0])
    def test_unitless_size_is_not_equivalent(self):
        with self.assertRaises(ValueError):
            inspect_svg(sample_svg(width="72"))
    def test_wrong_page_size(self):
        with self.assertRaises(ValueError):
            inspect_svg(sample_svg(), (144, 36))
    def test_missing_reference(self):
        with self.assertRaises(ValueError):
            inspect_svg(sample_svg('<path fill="url(#missing)"/>'))
    def test_duplicate_id(self):
        with self.assertRaises(ValueError):
            inspect_svg(sample_svg('<path id="x"/><path id="x"/>'))
    def test_embedded_pixel_size(self):
        data = base64.b64encode(sample_png()).decode()
        report = inspect_svg(sample_svg(f'<image xlink:href="data:image/png;base64,{data}"/>'))
        self.assertEqual(report["embedded_png_sizes"], [(2, 1)])
    def test_bad_png_crc(self):
        damaged = bytearray(sample_png()); damaged[20] ^= 1
        with self.assertRaises(ValueError):
            png_size(bytes(damaged))
    def test_no_external_image(self):
        with self.assertRaises(ValueError):
            inspect_svg(sample_svg('<image href="https://example.invalid/image.png"/>'))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--probe-prefix", type=Path)
    parser.add_argument("--pdf", action="store_true", help="also inspect the actual PDF with pypdf")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(InspectorTests))
        if not result.wasSuccessful():
            return 1
    if args.probe_prefix:
        print(json.dumps(inspect_probe(args.probe_prefix, args.pdf), indent=2))
    elif args.pdf:
        parser.error("--pdf requires --probe-prefix")
    elif not args.self_test:
        parser.error("choose --self-test or --probe-prefix")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, ET.ParseError) as exc:
        raise SystemExit(f"vector-output inspection failed: {exc}") from exc
