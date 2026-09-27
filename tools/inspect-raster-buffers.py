#!/usr/bin/env python3
"""Check actual raster-buffer probes and native memory samples. --pdf needs pypdf.

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
NAMES = ("stride", "canvas", "snapshots")
TITLES = ("Rows have a stride; views have a lifetime",
          "One allocation, two ways to change pixels",
          "Snapshots are independent of mutable storage")
EXPECTED = {"stride": [(160, 96), (160, 96)],
            "canvas": [(160, 96), (160, 96)],
            "snapshots": [(160, 96), (320, 192)]}

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
            f"{name}: wrong drawn source-image sizes/count: {drawn}; expected {EXPECTED[name]}")
    require(used_images == set(images), "unused or hidden image resource in probe")
    paths = sum(e.tag == NS + "path" for e in root.iter())
    require(paths >= 4, "missing vector labels/artwork")
    return {"size_points": [720, 500], "drawn_image_sizes": [list(x) for x in drawn],
            "unique_image_resources": len(images), "vector_path_count": paths,
            "image_placements": len(drawn)}


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
                       "soft_mask_sizes": [list(x) for x in masks.values()], "image_placements": len(primary)})
    return {"pages": result, "size_points": [720, 500], "headings": "extractable"}


def audit_info(report, name):
    pdf = name == "pdf"
    require(report.get("backend") == ("pdf" if pdf else "svg"), "wrong backend")
    require(report.get("mode") == "export" and report.get("blocking") is False, "blocking/missing audit")
    require(report.get("pages") == (3 if pdf else 1), "wrong audit page count")
    require(report.get("vector_only") is False, "source images are not vector-only")
    events = report.get("events", [])
    require(events and all(e.get("status") in ("vector", "embedded-raster") for e in events),
            "unhandled feature or unintended rasterization")
    decisions = [e for e in events if e.get("operation") == "draw-output-group"]
    require(len(decisions) == (6 if pdf else 2), "wrong group count")
    require(all(e.get("details", {}).get("strategy") == "native" for e in decisions), "group was flattened")
    require(not any(e.get("operation") == "draw-rasterized" for e in events), "unexpected raster boundary")
    images = [e for e in events if e.get("feature") == "image" and e.get("status") == "embedded-raster"]
    require(len(images) >= (6 if pdf else 2), "missing image provenance")
    require(any(e.get("feature") == "geometry" and e.get("status") == "vector" for e in events), "missing page vectors")
    return {"native_groups": len(decisions), "raster_group_events": 0, "blocking": False}


def decision_info(data):
    require(set(data) == {"pdf", "svg"}, "missing decision backend")
    result = {}
    expected_labels = [f"{name}-{n}" for name in NAMES for n in range(2)]
    for backend, groups in data.items():
        require([g.get("label") for g in groups] == expected_labels, "wrong group labels/order")
        for group in groups:
            require(group.get("backend") == backend and group.get("strategy") == "native", "wrong strategy/backend")
            require(group.get("reason") == "native-compatible" and group.get("pixel_size") is False, "unexpected fallback")
            require("image" in group.get("features", []), "snapshot missing from provenance")
        result[backend] = {"native_groups": len(groups), "raster_groups": 0}
    return result


SAMPLES = {
    "layout": {"width": 160, "height": 96, "row_bytes": 704, "allocation_bytes": 67584,
               "subset_row_bytes": 704, "padding_zero": True, "read_only_rejected": True,
               "expired_view_rejected": True, "outside": [50, 100, 220, 255], "inside": [240, 160, 32, 255]},
    "canvas": {"direct_pixel": [50, 100, 220, 255], "edited_pixel": [14, 149, 142, 255],
               "padding_zero": True, "expired_canvas_rejected": True},
    "snapshots": {"sources_closed": True, "before": [50, 100, 220, 255], "after": [14, 149, 142, 255]},
    "premultiplied": [128, 64, 32, 128]}


def samples_info(data):
    # Exact equality includes both numeric values and boolean types; do not let
    # a JSON number 1 stand in for a successful lifetime rejection.
    require(json.dumps(data, sort_keys=True) == json.dumps(SAMPLES, sort_keys=True),
            "incorrect native stride, ownership, snapshot, or pixel samples")
    return {"row_bytes": 704, "allocation_bytes": 67584, "padding_preserved": True,
            "expired_access_rejected": True, "snapshot_independence": "checked"}


def inspect(prefix, pdf=False):
    def f(suffix): return Path(str(prefix) + suffix)
    result = {"svg": {}, "audit": {}}
    for name in NAMES:
        result["svg"][name] = svg_info(f(f".{name}.svg").read_bytes(), name)
        result["audit"][name] = audit_info(json.loads(f(f".{name}.audit.json").read_text()), name)
        require(png_size(f(f".{name}.reference.png").read_bytes()) == (1440, 1000), "wrong reference dimensions")
        for n, size in enumerate(EXPECTED[name]):
            require(png_size(f(f".{name}.source-{n}.png").read_bytes()) == size, "wrong saved source dimensions")
    result["audit"]["pdf"] = audit_info(json.loads(f(".pdf.audit.json").read_text()), "pdf")
    result["decisions"] = decision_info(json.loads(f(".decisions.json").read_text()))
    result["native_memory"] = samples_info(json.loads(f(".samples.json").read_text()))
    review = f(".review.html").read_text()
    require(review.count("<img ") == 6 and "not a PDF/SVG rasterization" in review, "missing review comparisons")
    require("same source snapshots" in review, "reference input sharing must be disclosed")
    for name in NAMES:
        require(f".{name}.svg" in review and f".{name}.reference.png" in review, "missing review page")
    result["pdf"] = pdf_info(f(".pdf").read_bytes()) if pdf else "NOT CHECKED (use --pdf; requires pypdf)"
    result["visual_review"] = "NOT PERFORMED by structural inspector"
    return result


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
    count = 6 if pdf else 2
    return {"backend": "pdf" if pdf else "svg", "mode": "export", "pages": 3 if pdf else 1,
            "blocking": False, "vector_only": False,
            "events": [{"feature": "geometry", "status": "vector"}] +
                      [{"operation": "draw-output-group", "status": "vector", "details": {"strategy": "native"}} for _ in range(count)] +
                      [{"feature": "image", "status": "embedded-raster"} for _ in range(count)]}


def fixture_decisions():
    return {backend: [{"label": f"{name}-{n}", "backend": backend, "strategy": "native", "reason": "native-compatible",
                       "pixel_size": False, "features": ["image", "picture"]} for name in NAMES for n in range(2)]
            for backend in ("pdf", "svg")}


def fixture_directory(prefix, pdf=False):
    def put(suffix, data): Path(str(prefix)+suffix).write_bytes(data if isinstance(data, bytes) else data.encode())
    for name in NAMES:
        put(f".{name}.svg", fixture_svg(name))
        put(f".{name}.audit.json", json.dumps(fixture_report(name)))
        put(f".{name}.reference.png", fixture_png(1440, 1000))
        for n, size in enumerate(EXPECTED[name]): put(f".{name}.source-{n}.png", fixture_png(*size))
    put(".pdf.audit.json", json.dumps(fixture_report("pdf")))
    put(".decisions.json", json.dumps(fixture_decisions()))
    put(".samples.json", json.dumps(SAMPLES))
    put(".review.html", "not a PDF/SVG rasterization; same source snapshots" + "".join(
        f'<img src="x.{n}.svg"><img src="x.{n}.reference.png">' for n in NAMES))
    if pdf: put(".pdf", fixture_pdf())


class Checks(unittest.TestCase):
    def test_svg_placements_not_definitions(self):
        result = svg_info(fixture_svg("stride"), "stride")
        self.assertEqual(len(result["drawn_image_sizes"]), 2)
        self.assertEqual(result["unique_image_resources"], 1)
    def test_all_svg_pages(self):
        for name in NAMES: svg_info(fixture_svg(name), name)
    def test_wrong_source_size(self):
        with self.assertRaises(ValueError): svg_info(fixture_svg("snapshots"), "stride")
    def test_missing_image_placement(self):
        root = ET.fromstring(fixture_svg("canvas")); root.remove(list(root)[-1])
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "canvas")
    def test_external_image(self):
        root = ET.fromstring(fixture_svg("canvas")); next(root.iter(NS+"image")).set("href", "https://invalid.example/image.png")
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "canvas")
    def test_dangling_reference(self):
        raw = fixture_svg("stride").replace(b"#im0", b"#missing")
        with self.assertRaises(ValueError): svg_info(raw, "stride")
    def test_svg_physical_units(self):
        with self.assertRaises(ValueError): svg_info(fixture_svg("stride").replace(b"720.0pt", b"720px"), "stride")
    def test_svg_outlined_text(self):
        root = ET.fromstring(fixture_svg("canvas")); ET.SubElement(root, NS+"text").text = "native"
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "canvas")
    def test_png_crc(self):
        raw = bytearray(fixture_png(16, 8)); raw[20] ^= 1
        with self.assertRaises(ValueError): png_size(raw)
    def test_audits(self):
        for name in (*NAMES, "pdf"): audit_info(fixture_report(name), name)
    def test_audit_rejects_raster_group(self):
        data = fixture_report("stride"); data["events"].append({"operation": "draw-rasterized", "status": "rasterized"})
        with self.assertRaises(ValueError): audit_info(data, "stride")
    def test_audit_does_not_certify_images_as_vector(self):
        data = fixture_report("stride"); data["vector_only"] = True
        with self.assertRaises(ValueError): audit_info(data, "stride")
    def test_decisions(self): decision_info(fixture_decisions())
    def test_wrong_decision(self):
        data = fixture_decisions(); data["pdf"][0]["strategy"] = "raster"
        with self.assertRaises(ValueError): decision_info(data)
    def test_samples(self): samples_info(copy.deepcopy(SAMPLES))
    def test_stride_is_checked(self):
        data = copy.deepcopy(SAMPLES); data["layout"]["subset_row_bytes"] = 320
        with self.assertRaises(ValueError): samples_info(data)
    def test_alpha_encoding_is_checked(self):
        data = copy.deepcopy(SAMPLES); data["premultiplied"] = [255, 128, 64, 128]
        with self.assertRaises(ValueError): samples_info(data)
    def test_expiration_is_checked(self):
        data = copy.deepcopy(SAMPLES); data["canvas"]["expired_canvas_rejected"] = False
        with self.assertRaises(ValueError): samples_info(data)
    def test_boolean_not_integer(self):
        data = copy.deepcopy(SAMPLES); data["snapshots"]["sources_closed"] = 1
        with self.assertRaises(ValueError): samples_info(data)
    def test_end_to_end(self):
        with tempfile.TemporaryDirectory() as root:
            p = Path(root)/"probe"; fixture_directory(p); inspect(p)
    @unittest.skipUnless(importlib.util.find_spec("pypdf"), "pypdf is optional")
    def test_pdf_reused_images_forms_and_masks(self):
        result = pdf_info(fixture_pdf())
        self.assertEqual([p["image_placements"] for p in result["pages"]], [2,2,2])
    @unittest.skipUnless(importlib.util.find_spec("pypdf"), "pypdf is optional")
    def test_end_to_end_pdf(self):
        with tempfile.TemporaryDirectory() as root:
            p = Path(root)/"probe"; fixture_directory(p, pdf=True); inspect(p, pdf=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--probe-prefix", default="output/raster-buffers-0.37")
    parser.add_argument("--pdf", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks))
        raise SystemExit(0 if result.wasSuccessful() else 1)
    print(json.dumps(inspect(args.probe_prefix, pdf=args.pdf), indent=2))
