#!/usr/bin/env python3
"""Inspect portable-drawing SVG/PNG/plans/audits; --pdf additionally needs pypdf.

Counts drawn image occurrences, not every PDF image object or SVG definition.
This is structural validation, not rendering or an image-fidelity certificate.
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
NAMES = ("markers", "grids", "atlas")
TITLES = ("Markers stay ordinary vector geometry", "Image grids do not need a panel bitmap",
          "Atlas sprites stay individual image placements")
GROUP_COUNTS = {"markers": 4, "grids": 2, "atlas": 1, "pdf": 7}
NINE = [(x, y) for y in (5, 12, 7) for x in (6, 17, 7)]
GRID_IMAGES = NINE + [size for i, size in enumerate(NINE) if i not in (1, 4)]
ATLAS_IMAGES = [(24, 24), (20, 28), (20, 20), (24, 24), (20, 28)]
EXPECTED = {"markers": [], "grids": GRID_IMAGES, "atlas": ATLAS_IMAGES}


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
            f"{name}: wrong drawn crop sizes/count: {drawn}; expected {EXPECTED[name]}")
    require(used_images == set(images), "unused or hidden image resource in probe")
    paths = sum(e.tag == NS + "path" for e in root.iter())
    require(paths >= 4, "missing vector labels/artwork")
    return {"size_points": [720, 500], "drawn_image_sizes": [list(x) for x in drawn],
            "unique_image_resources": len(images), "vector_path_count": paths,
            "whole_panel_fallbacks": 0}


def audit_info(report, name):
    require(report.get("backend") == ("pdf" if name == "pdf" else "svg"), "wrong audit backend")
    require(report.get("mode") == "export" and report.get("blocking") is False, "not a nonblocking export")
    require(report.get("pages") == (3 if name == "pdf" else 1), "wrong audit page count")
    events = report.get("events", [])
    require(events, "empty audit")
    require(all(e.get("status") in ("vector", "embedded-raster") for e in events),
            "unexpected effect, raster fallback, or unknown content")
    require(not any(e.get("feature") in ("raster-group", "point-sprites", "image-grid", "image-atlas") for e in events),
            "native batch/fallback provenance leaked into portable drawing")
    decisions = [e for e in events if e.get("operation") == "draw-output-group"]
    require(len(decisions) == GROUP_COUNTS[name], "wrong group decision count")
    for e in decisions:
        require(e.get("feature") == "output-group" and e.get("details", {}).get("strategy") == "native",
                "portable group did not remain native")
    require(report.get("vector_only") is (name == "markers"), "images wrongly certified as vector-only")
    has_image = any(e.get("feature") == "image" and e.get("status") == "embedded-raster" for e in events)
    require(has_image is (name != "markers"), "wrong embedded-raster classification")
    return {"decision_events": len(decisions), "raster_events": 0, "vector_only": name == "markers"}


def decision_info(data):
    require(set(data) == {"pdf", "svg"}, "missing decision backend")
    result = {}
    for backend, rows in data.items():
        require([r.get("page") for r in rows] == list(NAMES), "wrong decision page order")
        result[backend] = []
        for row in rows:
            groups = row.get("groups", [])
            require(len(groups) == GROUP_COUNTS[row["page"]], "wrong top-level groups")
            for g in groups:
                require(g.get("backend") == backend and g.get("strategy") == "native", "unexpected raster decision")
                require(g.get("pixel_size") is False and g.get("captured_children") == [], "unexpected child/fallback")
                require(g.get("reason") == "native-compatible", "wrong native decision reason")
                require(not any(f in g.get("features", []) for f in ("point-sprites", "image-grid", "image-atlas")),
                        "unlowered native batch in group")
            result[backend].append({"page": row["page"], "native_groups": len(groups)})
    return result


def plan_info(data):
    require(set(data) == {"nine", "lattice", "atlas"}, "missing plan family")
    for key in ("nine", "lattice"):
        cells = data[key]
        require(isinstance(cells, list) and len(cells) == 9, "expected nine inspectable grid cells")
        for i, cell in enumerate(cells):
            require([cell.get("row"), cell.get("column")] == [i // 3, i % 3], "grid is not row-major")
            s, d = cell.get("source"), cell.get("destination")
            require(isinstance(s, list) and len(s) == 4 and all(type(x) is int for x in s), "noninteger source crop")
            require(s[0] >= 0 and s[1] >= 0 and s[2] > 0 and s[3] > 0 and s[0] + s[2] <= 30 and s[1] + s[3] <= 24,
                    "source crop outside master image")
            require(isinstance(d, list) and len(d) == 4 and all(type(x) in (float, int) and math.isfinite(x) for x in d),
                    "invalid destination rectangle")
            require(d[2] >= 0 and d[3] >= 0, "inverted destination cell")
            expected_kind = "default" if key == "nine" else {1: "fixed-color", 4: "transparent"}.get(i, "default")
            require(cell.get("kind") == expected_kind, "wrong cell kind")
            require(tuple(s[2:]) == NINE[i], "wrong source crop size")
            col, row = i % 3, i // 3
            require(s == [(0, 6, 23)[col], (0, 5, 17)[row], (6, 17, 7)[col], (5, 12, 7)[row]],
                    "wrong source crop location")
            expected_dst = [(0, 6, 293)[col], (0, 5, 163)[row], (6, 287, 7)[col], (5, 158, 7)[row]]
            require(all(math.isclose(a, b, rel_tol=0, abs_tol=1e-6) for a, b in zip(d, expected_dst)),
                    "fixed/stretch destination layout mismatch")
            require((type(cell.get("color")) is int and cell["color"] == 0xffefa125)
                    if expected_kind == "fixed-color" else cell.get("color") is False,
                    "wrong fixed-color or non-color cell value")
        for row in range(3):
            for column in range(2):
                a, b = cells[row * 3 + column]["destination"], cells[row * 3 + column + 1]["destination"]
                require(math.isclose(a[0] + a[2], b[0], abs_tol=1e-6), "gap in adjacent grid columns")
        for column in range(3):
            for row in range(2):
                a, b = cells[row * 3 + column]["destination"], cells[(row + 1) * 3 + column]["destination"]
                require(math.isclose(a[1] + a[3], b[1], abs_tol=1e-6), "gap in adjacent grid rows")
        first, last = cells[0]["destination"], cells[-1]["destination"]
        require(first[:2] == [0, 0] and last[0] + last[2] == 300 and last[1] + last[3] == 170,
                "grid does not cover the declared destination")
    require(len(data["atlas"]) == 5, "expected five atlas placements")
    for row, size in zip(data["atlas"], ATLAS_IMAGES):
        source, matrix = row.get("source"), row.get("matrix")
        require(isinstance(source, list) and len(source) == 4 and all(type(x) is int for x in source), "invalid atlas crop")
        require(tuple(source[2:]) == size, "wrong atlas source size")
        require(source[:2] == {(24, 24): [0, 0], (20, 28): [28, 0], (20, 20): [52, 0]}[size],
                "wrong atlas crop location")
        require(isinstance(matrix, list) and len(matrix) == 4 and all(type(x) in (float, int) and math.isfinite(x) for x in matrix),
                "bad RSXform snapshot")
    return {"nine_cells": 9, "lattice_cells": 9, "atlas_placements": 5}


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
                       "soft_mask_sizes": [list(x) for x in masks.values()], "whole_panel_fallbacks": 0})
    return {"pages": result, "size_points": [720, 500], "headings": "extractable"}


def inspect(prefix, pdf=False):
    f = lambda suffix: Path(str(prefix) + suffix)
    result = {"svg": {}, "audit": {}}
    result["plans"] = plan_info(json.loads(f(".plans.json").read_text()))
    result["decisions"] = decision_info(json.loads(f(".decisions.json").read_text()))
    for name in NAMES:
        result["svg"][name] = svg_info(f("." + name + ".svg").read_bytes(), name)
        result["audit"][name] = audit_info(json.loads(f("." + name + ".audit.json").read_text()), name)
        require(png_size(f("." + name + ".reference.png").read_bytes()) == (1440, 1000), "wrong raster reference dimensions")
    result["audit"]["pdf"] = audit_info(json.loads(f(".pdf.audit.json").read_text()), "pdf")
    require(png_size(f(".grid-source.png").read_bytes()) == (30, 24), "wrong grid master")
    require(png_size(f(".atlas-source.png").read_bytes()) == (72, 28), "wrong atlas master")
    pdf_bytes = f(".pdf").read_bytes()
    require(pdf_bytes.startswith(b"%PDF-"), "missing PDF output")
    result["pdf"] = pdf_info(pdf_bytes) if pdf else "NOT CHECKED (rerun with --pdf; requires pypdf)"
    review = f(".review.html").read_text()
    require("independent raster reference" in review and "not a PDF/SVG rasterization" in review, "missing review provenance")
    for name in NAMES:
        require("." + name + ".svg" in review and "." + name + ".reference.png" in review, "missing review pair")
    result["visual_review"] = "NOT PERFORMED by structural inspector"
    return result


# Synthetic fixtures test this inspector; they are never presented as Skia output.
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


def fixture_report(name):
    events = [{"feature": "geometry", "status": "vector", "operation": "draw-rect"}]
    events += [{"feature": "output-group", "status": "vector", "operation": "draw-output-group",
                "details": {"strategy": "native"}} for _ in range(GROUP_COUNTS[name])]
    if name != "markers":
        events.append({"feature": "image", "status": "embedded-raster", "operation": "draw-picture"})
    return {"backend": "pdf" if name == "pdf" else "svg", "mode": "export", "blocking": False,
            "pages": 3 if name == "pdf" else 1, "vector_only": name == "markers", "events": events}


def fixture_decisions():
    return {b: [{"page": name, "groups": [{"backend": b, "strategy": "native", "pixel_size": False,
                "captured_children": [], "reason": "native-compatible", "features": ["geometry"]}
                for _ in range(GROUP_COUNTS[name])]} for name in NAMES] for b in ("pdf", "svg")}



def fixture_plans():
    cells = []
    for row in range(3):
        for col in range(3):
            cells.append({"row": row, "column": col, "kind": "default", "color": False,
                          "source": [(0, 6, 23)[col], (0, 5, 17)[row], (6, 17, 7)[col], (5, 12, 7)[row]],
                          "destination": [(0, 6, 293)[col], (0, 5, 163)[row], (6, 287, 7)[col], (5, 158, 7)[row]]})
    mixed = copy.deepcopy(cells)
    mixed[1].update(kind="fixed-color", color=0xffefa125)
    mixed[4]["kind"] = "transparent"
    atlas = [{"source": {(24, 24): [0, 0, 24, 24], (20, 28): [28, 0, 20, 28], (20, 20): [52, 0, 20, 20]}[size],
              "matrix": [1, 0, 0, 0]} for size in ATLAS_IMAGES]
    return {"nine": cells, "lattice": mixed, "atlas": atlas}


def write_fixture_directory(prefix, pdf=False):
    def write(suffix, data):
        Path(str(prefix) + suffix).write_bytes(data)
    def write_json(suffix, data):
        write(suffix, json.dumps(data).encode())
    write_json(".plans.json", fixture_plans())
    write_json(".decisions.json", fixture_decisions())
    for name in NAMES:
        write("." + name + ".svg", fixture_svg(name))
        write_json("." + name + ".audit.json", fixture_report(name))
        write("." + name + ".reference.png", fixture_png(1440, 1000))
    write_json(".pdf.audit.json", fixture_report("pdf"))
    write(".grid-source.png", fixture_png(30, 24))
    write(".atlas-source.png", fixture_png(72, 28))
    write(".pdf", fixture_pdf() if pdf else b"%PDF-synthetic-no-pdf-check")
    write(".review.html", ("independent raster reference, not a PDF/SVG rasterization " +
          " ".join("." + name + suffix for name in NAMES for suffix in (".svg", ".reference.png"))).encode())


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


class Checks(unittest.TestCase):
    def test_svg_occurrences_not_definitions(self):
        for name in NAMES: svg_info(fixture_svg(name), name)
    def test_wrong_physical_units(self):
        with self.assertRaises(ValueError): svg_info(fixture_svg("markers").replace(b"720.0pt", b"720px"), "markers")
    def test_wrong_page_size(self):
        with self.assertRaises(ValueError): svg_info(fixture_svg("markers").replace(b"5e2pt", b"501pt"), "markers")
    def test_missing_drawn_image(self):
        root = ET.fromstring(fixture_svg("atlas")); root.remove(root.findall(NS + "use")[-1])
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "atlas")
    def test_whole_panel_fallback_rejected(self):
        root = ET.fromstring(fixture_svg("atlas")); image = next(root.iter(NS + "image"))
        image.set("href", "data:image/png;base64," + base64.b64encode(fixture_png(600, 340)).decode())
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "atlas")
    def test_external_image_rejected(self):
        root = ET.fromstring(fixture_svg("atlas")); next(root.iter(NS + "image")).set("href", "x.png")
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "atlas")
    def test_duplicate_ids(self):
        root = ET.fromstring(fixture_svg("atlas")); images = list(root.iter(NS + "image")); images[1].set("id", images[0].get("id"))
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "atlas")
    def test_dangling_use(self):
        root = ET.fromstring(fixture_svg("atlas")); root.find(NS + "use").set("href", "#missing")
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "atlas")
    def test_native_text_rejected(self):
        root = ET.fromstring(fixture_svg("markers")); ET.SubElement(root, NS + "text").text = "label"
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "markers")
    def test_bad_png_crc(self):
        data = bytearray(fixture_png(3, 4)); data[20] ^= 1
        with self.assertRaises(ValueError): png_size(data)
    def test_png_truncation(self):
        with self.assertRaises(ValueError): png_size(fixture_png(3, 4)[:-1])
    def test_audits(self):
        for name in (*NAMES, "pdf"): audit_info(fixture_report(name), name)
    def test_images_are_not_vector(self):
        r = fixture_report("grids"); r["vector_only"] = True
        with self.assertRaises(ValueError): audit_info(r, "grids")
    def test_hidden_fallback_rejected(self):
        r = fixture_report("grids"); r["events"].append({"feature": "raster-group", "status": "rasterized"})
        with self.assertRaises(ValueError): audit_info(r, "grids")
    def test_decisions(self): decision_info(fixture_decisions())
    def test_raster_decision_rejected(self):
        r = fixture_decisions(); r["svg"][2]["groups"][0]["strategy"] = "raster"
        with self.assertRaises(ValueError): decision_info(r)
    def test_plans(self):
        plan_info(fixture_plans())
    def test_plan_shared_edge_mismatch(self):
        data = fixture_plans(); data["nine"][1]["destination"][0] += 1
        with self.assertRaises(ValueError): plan_info(data)
    def test_plan_wrong_crop(self):
        data = fixture_plans(); data["atlas"][0]["source"][0] = 1
        with self.assertRaises(ValueError): plan_info(data)
    def test_fixed_color_value(self):
        data = fixture_plans(); data["lattice"][1]["color"] = False
        with self.assertRaises(ValueError): plan_info(data)
    def test_end_to_end_standard_library(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory) / "synthetic"
            write_fixture_directory(prefix)
            result = inspect(prefix)
            self.assertEqual(result["svg"]["atlas"]["whole_panel_fallbacks"], 0)
    @unittest.skipUnless(importlib.util.find_spec("pypdf"), "pypdf is optional")
    def test_end_to_end_pdf(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory) / "synthetic"
            write_fixture_directory(prefix, pdf=True)
            result = inspect(prefix, pdf=True)
            self.assertEqual(len(result["pdf"]["pages"]), 3)
    @unittest.skipUnless(importlib.util.find_spec("pypdf"), "pypdf is optional")
    def test_pdf_forms_reused_images_and_soft_masks(self):
        r = pdf_info(fixture_pdf())
        self.assertEqual(len(r["pages"][2]["drawn_image_sizes"]), 5)
        self.assertEqual(len(r["pages"][2]["soft_mask_sizes"]), 3)
    @unittest.skipUnless(importlib.util.find_spec("pypdf"), "pypdf is optional")
    def test_pdf_missing_placement(self):
        from pypdf import PdfReader, PdfWriter
        reader = PdfReader(io.BytesIO(fixture_pdf()))
        form = reader.pages[2]["/Resources"]["/XObject"]["/Group"].get_object()
        form.set_data(form.get_data().rsplit(b"\n", 1)[0])
        writer = PdfWriter(); writer.append_pages_from_reader(reader)
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
    if args.probe_prefix:
        print(json.dumps(inspect(args.probe_prefix, args.pdf), indent=2))
    if not args.self_test and not args.probe_prefix:
        parser.error("use --self-test and/or --probe-prefix")
