#!/usr/bin/env python3
"""Inspect the 0.28 runtime-effect probes; this does not render or execute SkSL.
Only --pdf needs pypdf. All other checks use the Python standard library.
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
KINDS = ("uniforms", "children", "pipeline")
PANEL = (624, 224)
MAX_FILE_BYTES = 64 * 1024 * 1024
COMPONENTS = dict(zip(("float", "float2", "float3", "float4", "float2x2", "float3x3", "float4x4",
                       "int", "int2", "int3", "int4"), (1, 2, 3, 4, 4, 9, 16, 1, 2, 3, 4)))
EXPECTED = {"solid": ("shader", 16, 0), "wave": ("shader", 52, 0),
            "palette": ("shader", 40, 0), "pass": ("shader", 0, 1),
            "warp": ("shader", 4, 1), "mixed": ("shader", 0, 3),
            "invert": ("color-filter", 0, 0), "mix": ("blender", 4, 0)}

def read_bounded(path):
    with Path(path).open("rb") as stream:
        data = stream.read(MAX_FILE_BYTES + 1)
    if len(data) > MAX_FILE_BYTES:
        raise ValueError(f"probe is larger than {MAX_FILE_BYTES} bytes: {path}")
    return data

def png_size(data):
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("not a PNG")
    at, size, compressed, ended = 8, None, [], False
    channels = None
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
        if size is None and kind != b"IHDR":
            raise ValueError("missing initial IHDR")
        if kind == b"IHDR":
            if size is not None or length != 13:
                raise ValueError("invalid or repeated IHDR")
            w, h, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            if not (0 < w <= 4096 and 0 < h <= 4096 and depth == 8
                    and color in (0, 2, 4, 6) and compression == filtering == interlace == 0):
                raise ValueError("unsupported probe PNG layout")
            size, channels = (w, h), {0: 1, 2: 3, 4: 2, 6: 4}[color]
        elif kind == b"IDAT":
            compressed.append(payload)
        elif kind == b"IEND":
            if length or end != len(data) or not compressed:
                raise ValueError("invalid PNG ending")
            ended = True
            break
        at = end
    if not ended:
        raise ValueError("missing PNG IEND")
    stride = size[0] * channels + 1
    expected = stride * size[1]
    inflater = zlib.decompressobj()
    rows = inflater.decompress(b"".join(compressed), expected + 1)
    if len(rows) != expected or not inflater.eof or inflater.unused_data or inflater.unconsumed_tail:
        raise ValueError("invalid or oversized PNG scanlines")
    if any(rows[i] > 4 for i in range(0, len(rows), stride)):
        raise ValueError("invalid PNG row filter")
    return size

def inspect_svg(data):
    root = ET.fromstring(data)
    if root.tag != f"{{{SVG}}}svg":
        raise ValueError("not an SVG root")
    for name, expected in (("width", 720), ("height", 500)):
        value = root.get(name, "")
        if not value.endswith("pt") or abs(float(value[:-2]) - expected) > 0.001:
            raise ValueError("incorrect physical " + name)
    if [float(v) for v in root.get("viewBox", "").split()] != [0, 0, 720, 500]:
        raise ValueError("incorrect viewBox")
    counts = Counter(e.tag.split("}")[-1] for e in root.iter())
    if counts["text"] or counts["path"] < 1:
        raise ValueError("expected outlined text and vector geometry")
    ids = [e.attrib["id"] for e in root.iter() if "id" in e.attrib]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate SVG id")
    images = []
    for e in root.iter():
        for key, value in e.attrib.items():
            for ref in re.findall(r"url\(#([^)]*)\)", value):
                if ref not in ids:
                    raise ValueError("unresolved resource")
            if key.split("}")[-1] == "href" and value.startswith("#") and value[1:] not in ids:
                raise ValueError("unresolved href")
        if e.tag == f"{{{SVG}}}image":
            href = e.get(f"{{{XLINK}}}href", e.get("href", ""))
            prefix = "data:image/png;base64,"
            if not href.startswith(prefix):
                raise ValueError("external or non-PNG image")
            images.append(png_size(base64.b64decode(href[len(prefix):], validate=True)))
    if images != [PANEL] * 4:
        raise ValueError("expected four bounded 624x224 images; got " + repr(images))
    return {"size_points": [720, 500], "embedded_png_sizes": images,
            "elements": dict(counts), "resource_count": len(ids)}

def inspect_trace(data):
    trace = json.loads(data)
    if trace.get("version") != "0.28.0":
        raise ValueError("wrong trace version")
    effects = trace.get("effects", [])
    if sorted(e.get("name") for e in effects) != sorted(EXPECTED):
        raise ValueError("missing or duplicate reflected effects")
    result = []
    for effect in effects:
        kind, size, children = EXPECTED[effect["name"]]
        if (effect.get("kind"), effect.get("uniform_bytes"), len(effect.get("children", []))) != (kind, size, children):
            raise ValueError("unexpected effect reflection summary")
        end, seen = 0, set()
        for u in effect.get("uniforms", []):
            if u["name"] in seen or u["offset"] != end or u["type"] not in COMPONENTS:
                raise ValueError("duplicate or misplaced uniform")
            seen.add(u["name"])
            if type(u["count"]) is not int or u["count"] < 1 or (not u["array"] and u["count"] != 1):
                raise ValueError("invalid array count")
            if u["bytes"] != 4 * COMPONENTS[u["type"]] * u["count"]:
                raise ValueError("invalid uniform size")
            if u["color"] and u["type"] not in ("float3", "float4"):
                raise ValueError("invalid color uniform")
            end += u["bytes"]
        if end != size:
            raise ValueError("uniform buffer has a gap or an incomplete description")
        for index, c in enumerate(effect["children"]):
            if c["index"] != index or c["kind"] not in ("shader", "color-filter", "blender") or c["name"] in seen:
                raise ValueError("invalid child slot")
            seen.add(c["name"])
        result.append({"name": effect["name"], "kind": kind, "uniform_bytes": size, "child_count": children})
    return result

def inspect_pdf(path):
    try:
        from pypdf import PdfReader
    except ImportError as error:
        raise SystemExit("--pdf requires pypdf in your Python environment") from error
    reader = PdfReader(str(path))
    if len(reader.pages) != 3:
        raise ValueError("expected three PDF pages")
    headings = ("Programs are reusable; values are snapshots", "A child is a shader, not just a texture",
                "The ordinary paint API accepts runtime nodes")
    result = []
    for page, heading in zip(reader.pages, headings):
        size = (float(page.mediabox.width), float(page.mediabox.height))
        if any(abs(a - b) > 0.01 for a, b in zip(size, (720, 500))):
            raise ValueError("wrong PDF MediaBox")
        if heading not in (page.extract_text() or ""):
            raise ValueError("missing native PDF heading")
        images, fonts, seen = [], [], set()
        def walk(resources):
            if resources is None:
                return
            resources = resources.get_object()
            if "/Font" in resources:
                for ref in resources["/Font"].get_object().values():
                    fonts.append(str(ref.get_object().get("/BaseFont", "")))
            if "/XObject" not in resources:
                return
            for ref in resources["/XObject"].get_object().values():
                key = (getattr(ref, "idnum", None), getattr(ref, "generation", None))
                if key[0] is not None:
                    if key in seen:
                        continue
                    seen.add(key)
                obj = ref.get_object()
                if obj.get("/Subtype") == "/Image":
                    images.append((int(obj["/Width"]), int(obj["/Height"])))
                    # An alpha mask referenced by /SMask is not another authored panel.
                elif obj.get("/Subtype") == "/Form":
                    walk(obj.get("/Resources"))
        walk(page.get("/Resources"))
        if sorted(images) != [PANEL] * 4:
            raise ValueError("unexpected PDF panel images: " + repr(images))
        result.append({"size_points": size, "panel_images": images, "fonts": sorted(set(fonts))})
    return result

def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

def synthetic_png(size=PANEL):
    w, h = size
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    rows = (b"\0" + b"\0" * w * 4) * h
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")

def synthetic_svg(count=4, extra="", size=PANEL):
    uri = "data:image/png;base64," + base64.b64encode(synthetic_png(size)).decode()
    images = ''.join(f'<image href="{uri}"/>' for _ in range(count))
    return (f'<svg xmlns="{SVG}" width="720pt" height="500pt" viewBox="0 0 720 500">'
            + '<path d="M0 0L1 1"/>' + images + extra + '</svg>').encode()

class Checks(unittest.TestCase):
    def test_four_panels(self):
        self.assertEqual(inspect_svg(synthetic_svg())["embedded_png_sizes"], [PANEL] * 4)
    def test_crc(self):
        data = bytearray(synthetic_png()); data[30] ^= 1
        with self.assertRaisesRegex(ValueError, "CRC"):
            png_size(data)
    def test_truncated_png(self):
        with self.assertRaises(ValueError):
            png_size(synthetic_png()[:-1])
    def test_oversized_scanlines(self):
        data = synthetic_png()
        pos = data.find(b"IDAT") - 4
        head = data[:pos]
        with self.assertRaisesRegex(ValueError, "scanlines"):
            png_size(head + chunk(b"IDAT", zlib.compress(b"\0" * (624 * 224 * 4 + 225))) + chunk(b"IEND", b""))
    def test_missing_panel(self):
        with self.assertRaisesRegex(ValueError, "four bounded"):
            inspect_svg(synthetic_svg(3))
    def test_whole_page_raster(self):
        with self.assertRaisesRegex(ValueError, "four bounded"):
            inspect_svg(synthetic_svg(1, size=(1440, 1000)))
    def test_wrong_units(self):
        with self.assertRaisesRegex(ValueError, "physical"):
            inspect_svg(synthetic_svg().replace(b'720pt', b'720px'))
    def test_wrong_viewbox(self):
        with self.assertRaisesRegex(ValueError, "viewBox"):
            inspect_svg(synthetic_svg().replace(b'0 0 720 500', b'0 0 720 400'))
    def test_native_text(self):
        with self.assertRaisesRegex(ValueError, "outlined"):
            inspect_svg(synthetic_svg(extra='<text>unexpected</text>'))
    def test_duplicate_resource(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            inspect_svg(synthetic_svg(extra='<path id="x"/><path id="x"/>'))
    def test_missing_resource(self):
        with self.assertRaisesRegex(ValueError, "resource"):
            inspect_svg(synthetic_svg(extra='<path fill="url(#missing)"/>'))
    def test_external_image(self):
        with self.assertRaisesRegex(ValueError, "external"):
            inspect_svg(synthetic_svg(extra='<image href="external.png"/>'))
    def test_valid_reference(self):
        inspect_svg(synthetic_svg(extra='<path id="x"/><use href="#x"/>'))
    def test_missing_trace(self):
        with self.assertRaisesRegex(ValueError, "reflected effects"):
            inspect_trace('{"version":"0.28.0","effects":[]}')

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
        result = {"svg": {kind: inspect_svg(read_bounded(prefix + "." + kind + ".svg")) for kind in KINDS},
                  "reflection": inspect_trace(read_bounded(prefix + ".trace.json")),
                  "pdf": inspect_pdf(prefix + ".pdf") if args.pdf else "NOT CHECKED (use --pdf)",
                  "visual_review": "NOT PERFORMED by structural inspector",
                  "sksl_execution": "NOT PERFORMED by structural inspector"}
        print(json.dumps(result, indent=2))
    elif not args.self_test:
        parser.error("supply --self-test or --probe-prefix")

if __name__ == "__main__":
    main()
