#!/usr/bin/env python3
"""Check actual CPU color-filter probes and native samples. --pdf needs pypdf.

Structure and pixel invariants, not a visual-fidelity or color-management certificate.
SVG traversal counts executed uses; PDF traversal counts Image/Form draws, not masks.
"""
from __future__ import annotations
import argparse
import base64
import binascii
from collections import Counter
import copy
import importlib.util
import io
import json
import math
from pathlib import Path
import re
import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zlib

NS = "{http://www.w3.org/2000/svg}"
XLINK = "{http://www.w3.org/1999/xlink}href"
NAMES = ("matrices", "curves", "composition")
TITLES = ("Color filters transform channels, not geometry",
          "Transfer curves and lookup tables are different tools",
          "Luma, contrast, and composed color operations")
FILTERS = {"matrices": ("control", "hue", "desaturate", "lighting"),
           "curves": ("encode", "decode", "rgb-table", "threshold"),
           "composition": ("luma", "contrast", "lerp", "compose")}
EXPECTED = {name: [(600, 192)] * (3 if name == "matrices" else 4) for name in NAMES}

def require(condition, message):
    if not condition:
        raise ValueError(message)


def png_size(raw):
    require(raw[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG")
    pos, size, data_seen, ended = 8, None, False, False
    while pos < len(raw):
        require(pos + 12 <= len(raw), "truncated PNG chunk")
        n = struct.unpack_from(">I", raw, pos)[0]
        require(n <= len(raw) - pos - 12, "PNG chunk extends past file")
        kind, data = raw[pos + 4:pos + 8], raw[pos + 8:pos + 8 + n]
        crc = struct.unpack_from(">I", raw, pos + 8 + n)[0]
        require(binascii.crc32(kind + data) & 0xffffffff == crc, "PNG CRC mismatch")
        if pos == 8:
            require(kind == b"IHDR" and n == 13, "missing PNG header")
        if kind == b"IHDR":
            require(size is None and n == 13, "duplicate/malformed PNG header")
            size = struct.unpack(">II", data[:8])
            require(min(size) > 0, "empty PNG")
        if kind == b"IDAT":
            data_seen = True
        pos += n + 12
        if kind == b"IEND":
            require(n == 0 and data_seen and pos == len(raw), "invalid PNG end")
            ended = True
            break
    require(size is not None and ended, "incomplete PNG")
    return size


def point_length(value):
    m = re.fullmatch(r"([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)pt", value or "")
    require(m is not None, "SVG physical lengths must use pt")
    n = float(m.group(1))
    require(math.isfinite(n), "nonfinite SVG length")
    return n


def svg_info(raw, name):
    root = ET.fromstring(raw)
    require(root.tag == NS + "svg", "missing SVG root")
    require([float(x) for x in root.get("viewBox", "").split()] == [0, 0, 720, 500], "wrong SVG viewport")
    require(point_length(root.get("width")) == 720 and point_length(root.get("height")) == 500,
            "wrong SVG physical dimensions")
    ids, images = {}, {}
    for e in root.iter():
        key = e.get("id")
        if key:
            require(key not in ids, "duplicate SVG identifier")
            ids[key] = e
        require(e.tag not in (NS + "text", NS + "script", NS + "foreignObject"),
                "native text or unexpected active content in probe")
        require("matrix3d" not in e.get("transform", ""), "non-SVG matrix")
        for values in re.findall(r"matrix\(([^)]*)\)", e.get("transform", "")):
            numbers = [float(x) for x in re.split(r"[\s,]+", values.strip())]
            require(len(numbers) == 6 and all(math.isfinite(x) for x in numbers), "invalid affine matrix")
        href = e.get("href", e.get(XLINK, ""))
        if e.tag == NS + "image":
            require(href.startswith("data:image/png;base64,"), "external/non-PNG image")
            images[id(e)] = png_size(base64.b64decode(href.split(",", 1)[1], validate=True))
        elif href:
            require(href.startswith("#"), "unexpected external SVG reference")
    for e in root.iter():
        href = e.get("href", e.get(XLINK, ""))
        if href.startswith("#"):
            require(href[1:] in ids, "dangling SVG reference")
        for value in e.attrib.values():
            for key in re.findall(r"url\(#([^)]*)\)", value):
                require(key in ids, "dangling clip/paint reference")
    drawn = []
    used_images = set()

    def walk(e, active):
        tag = e.tag
        if tag in {NS + x for x in ("defs", "clipPath", "mask", "pattern", "linearGradient", "radialGradient")}:
            return
        if tag == NS + "image":
            drawn.append(images[id(e)])
            used_images.add(id(e))
        elif tag == NS + "use":
            key = e.get("href", e.get(XLINK, ""))[1:]
            require(key in ids and key not in active, "cyclic/dangling SVG use")
            walk(ids[key], active | {key})
        else:
            for child in e:
                walk(child, active)
    walk(root, set())
    require(Counter(drawn) == Counter(EXPECTED[name]),
            f"{name}: wrong drawn fallback sizes/count: {drawn}; expected {EXPECTED[name]}")
    require(used_images == set(images), "unused or hidden image resource in probe")
    paths = sum(e.tag == NS + "path" for e in root.iter())
    require(paths >= 4, "missing vector labels/artwork")
    return {"size_points": [720, 500], "drawn_image_sizes": [list(x) for x in drawn],
            "unique_image_resources": len(images), "vector_path_count": paths,
            "bounded_fallbacks": len(drawn)}


def pdf_info(raw):
    try:
        from pypdf import PdfReader
        from pypdf.generic import ContentStream
    except ImportError as exc:
        raise RuntimeError("--pdf requires pypdf; install it in the Python environment running this inspector") from exc
    reader = PdfReader(io.BytesIO(raw))
    require(len(reader.pages) == 3, "wrong PDF page count")
    result = []

    def obj(value):
        return value.get_object() if hasattr(value, "get_object") else value

    def identity(ref, value):
        return (getattr(ref, "idnum", id(value)), getattr(ref, "generation", 0))

    def walk(contents, resources, active, primary, masks):
        if contents is None:
            return
        resources = obj(resources or {})
        for operands, operator in ContentStream(contents, reader).operations:
            if operator == b"INLINE IMAGE":
                raise ValueError("unexpected inline image in PDF probe")
            if operator != b"Do":
                continue
            xobjects = obj(resources.get("/XObject", {}))
            require(operands and operands[0] in xobjects, "missing PDF XObject")
            ref = xobjects[operands[0]]
            image = obj(ref)
            key = identity(ref, image)
            require(key not in active, "cyclic PDF Form resource")
            if image.get("/Subtype") == "/Image":
                primary.append((int(image["/Width"]), int(image["/Height"])))
                mask_ref = image.get("/SMask")
                if mask_ref is not None:
                    mask = obj(mask_ref)
                    require(mask.get("/Subtype") == "/Image", "invalid PDF soft mask")
                    masks[identity(mask_ref, mask)] = (int(mask["/Width"]), int(mask["/Height"]))
            elif image.get("/Subtype") == "/Form":
                walk(image, image.get("/Resources", resources), active | {key}, primary, masks)
            else:
                raise ValueError("unexpected drawn PDF XObject")
    for page, name, title in zip(reader.pages, NAMES, TITLES):
        require([float(page.mediabox.width), float(page.mediabox.height)] == [720, 500], "wrong PDF media box")
        text = " ".join((page.extract_text() or "").split())
        require(title in text, "missing native PDF heading")
        primary, masks = [], {}
        walk(page.get_contents(), page.get("/Resources", {}), set(), primary, masks)
        require(Counter(primary) == Counter(EXPECTED[name]), f"{name}: wrong PDF drawn images: {primary}")
        result.append({"page": name, "drawn_image_sizes": [list(x) for x in primary],
                       "soft_mask_sizes": [list(x) for x in masks.values()], "bounded_fallbacks": len(primary)})
    return {"pages": result, "size_points": [720, 500], "headings": "extractable"}


def audit_info(report, name):
    pdf = name == "pdf"
    count = 11 if pdf else len(EXPECTED[name])
    require(report.get("backend") == ("pdf" if pdf else "svg"), "wrong audit backend")
    require(report.get("mode") == "export" and report.get("blocking") is False,
            "not a nonblocking export")
    require(report.get("pages") == (3 if pdf else 1), "wrong page count")
    require(report.get("vector_only") is False, "effect panels falsely certified vector-only")
    events = report.get("events", [])
    require(events and all(e.get("status") in ("vector", "rasterized", "embedded-raster")
                           for e in events), "unhandled output feature")
    decisions = [e for e in events if e.get("operation") == "draw-output-group"]
    require(len(decisions) == (12 if pdf else 4), "wrong group decision count")
    rasters = [e for e in events if e.get("operation") == "draw-rasterized"
               and e.get("feature") == "raster-group"]
    require(len(rasters) == count, "wrong actual raster-boundary count")
    for e in rasters:
        d = e.get("details", {})
        require([d.get("pixel_width"), d.get("pixel_height")] == [600, 192], "wrong raster dimensions")
    effects = [e for e in events if e.get("feature") == "color-filter"]
    require(len(effects) >= count, "missing color-filter provenance")
    require(all(e.get("status") == "rasterized" and
                any(str(s).startswith("raster-group-") for s in e.get("scope", [])) for e in effects),
            "color filtering escaped its raster scope")
    require(any(e.get("feature") == "geometry" and e.get("status") == "vector" for e in events),
            "missing surrounding vector content")
    for e in decisions:
        g = e.get("details", {})
        control = g.get("label") == "control"
        require(g.get("strategy") == ("native" if control else "raster"), "wrong group strategy")
    return {"decision_events": len(decisions), "actual_raster_events": count,
            "color_filter_events": len(effects), "blocking": False}


def decision_info(data):
    require(set(data) == {"pdf", "svg"}, "missing decision backend")
    result = {}
    for backend, rows in data.items():
        require([r.get("page") for r in rows] == list(NAMES), "wrong decision page order")
        result[backend] = []
        for row in rows:
            groups = row.get("groups", [])
            require([g.get("label") for g in groups] == list(FILTERS[row["page"]]), "wrong panel order")
            for g in groups:
                control = g["label"] == "control"
                require(g.get("backend") == backend and g.get("captured_children") == [], "wrong capture context")
                require(g.get("strategy") == ("native" if control else "raster"), "wrong filter decision")
                require(g.get("reason") == ("native-compatible" if control else "backend-fallback"), "wrong decision reason")
                require(g.get("pixel_size") is False if control else g.get("pixel_size") == [600, 192],
                        "wrong decision pixel dimensions")
                require(("color-filter" in g.get("features", [])) is (not control), "wrong filter provenance")
            result[backend].append({"page": row["page"], "strategies": [g["strategy"] for g in groups]})
    return result


SAMPLE_EXPECTED = {"encode": [188, 188, 188, 255], "decode": [55, 55, 55, 255],
                   "hue_red": [0, 255, 0, 255], "desaturated_red": [128, 128, 128, 255],
                   "luma_white_alpha128": [0, 0, 0, 128], "rgb_invert": [223, 191, 159, 255],
                   "all_channel_invert_white": [0, 0, 0, 0], "roundtrip": [72, 144, 216, 255]}


def samples_info(data):
    require(data.get("input_gray") == 128, "wrong gray sample input")
    require(set(data) == set(SAMPLE_EXPECTED) | {"input_gray"}, "incomplete sample data")
    for key, expected in SAMPLE_EXPECTED.items():
        actual = data[key]
        require(isinstance(actual, list) and len(actual) == 4 and
                all(type(x) is int and 0 <= x <= 255 for x in actual), "non-byte sample output")
        require(all(abs(a-b) <= 2 for a, b in zip(actual, expected)),
                f"native sample {key}: {actual}, expected approximately {expected}")
    return {"checks": len(SAMPLE_EXPECTED), "encode_gray": data["encode"][0],
            "decode_gray": data["decode"][0], "alpha_semantics": "checked"}


def inspect(prefix, pdf=False):
    def f(suffix): return Path(str(prefix)+suffix)
    result = {"svg": {}, "audit": {}}
    for name in NAMES:
        result["svg"][name] = svg_info(f(f".{name}.svg").read_bytes(), name)
        result["audit"][name] = audit_info(json.loads(f(f".{name}.audit.json").read_text()), name)
        require(png_size(f(f".{name}.reference.png").read_bytes()) == (1440, 1000), "wrong reference dimensions")
    result["audit"]["pdf"] = audit_info(json.loads(f(".pdf.audit.json").read_text()), "pdf")
    result["decisions"] = decision_info(json.loads(f(".decisions.json").read_text()))
    result["native_samples"] = samples_info(json.loads(f(".samples.json").read_text()))
    review = f(".review.html").read_text()
    require(review.count("<img ") == 6 and "not a PDF/SVG rasterization" in review, "incorrect review provenance")
    for name in NAMES:
        require(f".{name}.svg" in review and f".{name}.reference.png" in review, "missing comparison")
    result["pdf"] = pdf_info(f(".pdf").read_bytes()) if pdf else "NOT CHECKED (use --pdf; requires pypdf)"
    result["visual_review"] = "NOT PERFORMED by structural inspector"
    return result


# Synthetic fixtures validate the inspector, not Skia or the new Racket bindings.
def fixture_png(width, height):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + bytes(width * 4)) * height)) + chunk(b"IEND", b""))


def fixture_svg(name):
    root = ET.Element(NS + "svg", {"width": "720.0pt", "height": "5e2pt", "viewBox": "0 0 720 500"})
    for _ in range(4):
        ET.SubElement(root, NS + "path", {"d": "M0 0L1 1"})
    defs = ET.SubElement(root, NS + "defs")
    keys = {}
    for size in EXPECTED[name]:
        if size not in keys:
            keys[size] = "im" + str(len(keys))
            ET.SubElement(defs, NS + "image", {"id": keys[size], "href": "data:image/png;base64," +
                          base64.b64encode(fixture_png(*size)).decode()})
        ET.SubElement(root, NS + "use", {"href": "#" + keys[size]})
    return ET.tostring(root)


def fixture_pdf():
    from pypdf import PdfWriter
    from pypdf.generic import DictionaryObject as D, NameObject as N, NumberObject as Num, DecodedStreamObject as Stream, ArrayObject as A
    writer = PdfWriter()
    font = writer._add_object(D({N("/Type"): N("/Font"), N("/Subtype"): N("/Type1"), N("/BaseFont"): N("/Helvetica")}))
    for name, title in zip(NAMES, TITLES):
        page = writer.add_blank_page(720, 500)
        xobjects = D()
        commands = []
        keys = {}
        for w, h in EXPECTED[name]:
            size = (w, h)
            if size not in keys:
                mask = Stream(); mask.set_data(bytes([255]) * (w * h))
                mask.update({N("/Type"): N("/XObject"), N("/Subtype"): N("/Image"), N("/Width"): Num(w), N("/Height"): Num(h),
                             N("/ColorSpace"): N("/DeviceGray"), N("/BitsPerComponent"): Num(8)})
                image = Stream(); image.set_data(bytes(w * h * 3))
                image.update({N("/Type"): N("/XObject"), N("/Subtype"): N("/Image"), N("/Width"): Num(w), N("/Height"): Num(h),
                              N("/ColorSpace"): N("/DeviceRGB"), N("/BitsPerComponent"): Num(8), N("/SMask"): writer._add_object(mask)})
                key = N("/Im" + str(len(keys))); keys[size] = key
                xobjects[key] = writer._add_object(image)
            commands.append(str(keys[size]) + " Do")
        form = Stream(); form.set_data("\n".join(commands).encode())
        form.update({N("/Type"): N("/XObject"), N("/Subtype"): N("/Form"), N("/BBox"): A([Num(0), Num(0), Num(720), Num(500)]),
                     N("/Resources"): D({N("/XObject"): xobjects})})
        page[N("/Resources")] = D({N("/Font"): D({N("/F0"): font}), N("/XObject"): D({N("/Group"): writer._add_object(form)})})
        contents = Stream(); contents.set_data(("BT /F0 12 Tf 20 470 Td (" + title + ") Tj ET\n/Group Do\n").encode())
        page[N("/Contents")] = writer._add_object(contents)
    out = io.BytesIO(); writer.write(out); return out.getvalue()


def fixture_report(name):
    pdf = name == "pdf"
    names = NAMES if pdf else (name,)
    events = [{"feature": "geometry", "status": "vector"}]
    for page_name in names:
        for label in FILTERS[page_name]:
            control = label == "control"
            events.append({"operation": "draw-output-group", "status": "vector" if control else "rasterized",
                           "details": {"label": label, "strategy": "native" if control else "raster"}})
            if not control:
                events += [{"operation": "draw-rasterized", "feature": "raster-group", "status": "rasterized",
                            "details": {"pixel_width": 600, "pixel_height": 192}},
                           {"feature": "color-filter", "status": "rasterized", "scope": ["raster-group-1"]}]
    return {"backend": "pdf" if pdf else "svg", "mode": "export", "blocking": False,
            "pages": 3 if pdf else 1, "vector_only": False, "events": events}


def fixture_decisions():
    return {backend: [{"page": name, "groups": [
        {"label": label, "backend": backend, "strategy": "native" if label == "control" else "raster",
         "reason": "native-compatible" if label == "control" else "backend-fallback",
         "captured_children": [], "features": [] if label == "control" else ["color-filter"],
         "pixel_size": False if label == "control" else [600, 192]}
        for label in FILTERS[name]]} for name in NAMES] for backend in ("pdf", "svg")}


def fixture_samples(): return dict(copy.deepcopy(SAMPLE_EXPECTED), input_gray=128)


def fixture_directory(prefix, pdf=False):
    def put(suffix, data): Path(str(prefix)+suffix).write_bytes(data if isinstance(data, bytes) else data.encode())
    for name in NAMES:
        put(f".{name}.svg", fixture_svg(name))
        put(f".{name}.audit.json", json.dumps(fixture_report(name)))
        put(f".{name}.reference.png", fixture_png(1440, 1000))
    put(".pdf.audit.json", json.dumps(fixture_report("pdf")))
    put(".decisions.json", json.dumps(fixture_decisions()))
    put(".samples.json", json.dumps(fixture_samples()))
    put(".review.html", "not a PDF/SVG rasterization"+"".join(
        f'<img src="x.{n}.svg"><img src="x.{n}.reference.png">' for n in NAMES))
    if pdf: put(".pdf", fixture_pdf())


class Checks(unittest.TestCase):
    def test_svg_draws_not_definitions(self):
        for name in NAMES: svg_info(fixture_svg(name), name)
    def test_svg_count(self):
        with self.assertRaises(ValueError): svg_info(fixture_svg("curves"), "matrices")
    def test_svg_dimensions(self):
        with self.assertRaises(ValueError): svg_info(fixture_svg("curves").replace(b"720.0pt", b"720px"), "curves")
    def test_svg_dangling_use(self):
        root = ET.fromstring(fixture_svg("curves")); root.find(NS+"use").set("href", "#missing")
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "curves")
    def test_svg_native_text(self):
        root = ET.fromstring(fixture_svg("curves")); ET.SubElement(root, NS+"text")
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "curves")
    def test_svg_external_image(self):
        root = ET.fromstring(fixture_svg("curves")); next(root.iter(NS+"image")).set("href", "image.png")
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "curves")
    def test_png_crc(self):
        b = bytearray(fixture_png(2, 3)); b[-1] ^= 1
        with self.assertRaises(ValueError): png_size(b)
    def test_audits(self):
        for name in (*NAMES, "pdf"): audit_info(fixture_report(name), name)
    def test_missing_raster_boundary(self):
        r = fixture_report("curves"); r["events"] = [e for e in r["events"] if e.get("operation") != "draw-rasterized"]
        with self.assertRaises(ValueError): audit_info(r, "curves")
    def test_filter_scope(self):
        r = fixture_report("curves")
        next(e for e in r["events"] if e.get("feature") == "color-filter")["scope"] = []
        with self.assertRaises(ValueError): audit_info(r, "curves")
    def test_vector_only_is_false(self):
        r = fixture_report("curves"); r["vector_only"] = True
        with self.assertRaises(ValueError): audit_info(r, "curves")
    def test_unknown_feature(self):
        r = fixture_report("curves"); r["events"].append({"status": "unknown"})
        with self.assertRaises(ValueError): audit_info(r, "curves")
    def test_decisions(self): decision_info(fixture_decisions())
    def test_control_stays_native(self):
        d = fixture_decisions(); d["pdf"][0]["groups"][0]["strategy"] = "raster"
        with self.assertRaises(ValueError): decision_info(d)
    def test_bad_filter_pixel_size(self):
        d = fixture_decisions(); d["svg"][1]["groups"][0]["pixel_size"] = [600, 190]
        with self.assertRaises(ValueError): decision_info(d)
    def test_samples(self): samples_info(fixture_samples())
    def test_gamma_not_identity(self):
        s = fixture_samples(); s["encode"] = [128, 128, 128, 255]
        with self.assertRaises(ValueError): samples_info(s)
    def test_table_alpha_is_checked(self):
        s = fixture_samples(); s["all_channel_invert_white"][3] = 255
        with self.assertRaises(ValueError): samples_info(s)
    def test_nonbyte_sample_rejected(self):
        s = fixture_samples(); s["encode"][0] = float("nan")
        with self.assertRaises(ValueError): samples_info(s)
    def test_end_to_end_standard_library(self):
        with tempfile.TemporaryDirectory() as d:
            prefix = Path(d)/"filters"; fixture_directory(prefix); inspect(prefix)
    @unittest.skipUnless(importlib.util.find_spec("pypdf"), "pypdf is optional")
    def test_pdf_forms_reused_images_and_masks(self): pdf_info(fixture_pdf())
    @unittest.skipUnless(importlib.util.find_spec("pypdf"), "pypdf is optional")
    def test_end_to_end_pdf(self):
        with tempfile.TemporaryDirectory() as d:
            prefix = Path(d)/"filters"; fixture_directory(prefix, True); inspect(prefix, True)
    @unittest.skipUnless(importlib.util.find_spec("pypdf"), "pypdf is optional")
    def test_pdf_missing_placement(self):
        from pypdf import PdfReader, PdfWriter
        from pypdf.generic import NameObject, DecodedStreamObject
        reader = PdfReader(io.BytesIO(fixture_pdf())); writer = PdfWriter()
        for page in reader.pages: writer.add_page(page)
        stream = DecodedStreamObject(); stream.set_data(b"BT /F0 12 Tf (Color filters transform channels, not geometry) Tj ET")
        writer.pages[0][NameObject("/Contents")] = writer._add_object(stream)
        out = io.BytesIO(); writer.write(out)
        with self.assertRaises(ValueError): pdf_info(out.getvalue())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--probe-prefix", type=Path)
    parser.add_argument("--pdf", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks))
        if not result.wasSuccessful(): raise SystemExit(1)
    if args.probe_prefix: print(json.dumps(inspect(args.probe_prefix, args.pdf), indent=2))
    if not args.self_test and not args.probe_prefix: parser.error("use --self-test and/or --probe-prefix")
