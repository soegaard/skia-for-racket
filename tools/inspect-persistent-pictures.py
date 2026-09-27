#!/usr/bin/env python3
"""Inspect SKP cache probes and reports, not visual fidelity. --pdf needs pypdf."""
from __future__ import annotations
import argparse
import base64
import copy
import importlib.util
import json
import math
from pathlib import Path
import re
import struct
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

_spec = importlib.util.spec_from_file_location("matrix_probe_inspector", Path(__file__).with_name("inspect-projective-matrices.py"))
_base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_base)
require, png_size, point_length, NS, XLINK = _base.require, _base.png_size, _base.point_length, _base.NS, _base.XLINK
PANELS = {"roundtrip": 0, "indexed": 0, "shaders": 2}
HEADINGS = ["A drawing can outlive its recording session", "An index changes replay work, not the drawing",
            "A picture can become a sampled paint source"]

def svg_info(raw: bytes, name: str) -> dict:
    root = ET.fromstring(raw)
    require(root.tag == NS + "svg", "missing SVG root")
    require(list(map(float, root.get("viewBox", "").split())) == [0, 0, 720, 500], "wrong SVG viewBox")
    require(point_length(root.get("width")) == 720 and point_length(root.get("height")) == 500, "wrong physical SVG size")
    ids = [e.get("id") for e in root.iter() if e.get("id")]
    require(len(ids) == len(set(ids)), "duplicate SVG IDs")
    images = []
    for e in root.iter():
        require(e.tag != NS + "text", "native text in outlined probe")
        transform = e.get("transform", "")
        require("matrix3d" not in transform, "non-SVG transform")
        for match in re.findall(r"matrix\(([^)]*)\)", transform):
            values = [float(v) for v in re.split(r"[\s,]+", match.strip())]
            require(len(values) == 6 and all(math.isfinite(v) for v in values), "invalid SVG matrix")
        href = e.get("href", e.get(XLINK, ""))
        if e.tag == NS + "image":
            require(href.startswith("data:image/png;base64,"), "external or non-PNG image")
            images.append(list(png_size(base64.b64decode(href.split(",", 1)[1], validate=True))))
        elif href:
            require(href.startswith("#") and href[1:] in ids, "external or unresolved SVG reference")
        for v in e.attrib.values():
            for ref in re.findall(r"url\(#([^)]*)\)", v):
                require(ref in ids, "unresolved SVG paint/clip reference")
    require(images == [[600, 360]] * PANELS[name], "wrong bounded image count/size")
    require(sum(e.tag == NS + "path" for e in root.iter()) >= 4, "missing vector artwork/labels")
    return {"size_points": [720, 500], "embedded_png_sizes": images, "resource_count": len(ids)}

def audit_info(report: dict, name: str) -> dict:
    expected_opaque = name in ("roundtrip", "pdf")
    expected_groups = 2 if name in ("shaders", "pdf") else 0
    require(report.get("backend") == ("pdf" if name == "pdf" else "svg"), "wrong audit backend")
    require(report.get("mode") == "export" and report.get("pages") == (3 if name == "pdf" else 1), "wrong audit mode/pages")
    require(report.get("blocking") is expected_opaque, "incorrect opaque blocking flag")
    events = report.get("events", [])
    require(events, "empty report")
    opaque = [e for e in events if e.get("feature") == "deserialized-picture"]
    require(bool(opaque) is expected_opaque, "missing or unexpected imported-picture provenance")
    for e in events:
        if e.get("feature") == "deserialized-picture":
            require(e.get("status") == "unknown", "imported picture incorrectly certified")
        else:
            require(e.get("status") in ("vector", "rasterized", "embedded-raster"), "unexpected unhandled output feature")
    groups = [e for e in events if e.get("feature") == "raster-group"]
    require(len(groups) == expected_groups, "wrong audit raster-group count")
    for e in groups:
        d = e.get("details", {})
        require([d.get("pixel_width"), d.get("pixel_height")] == [600, 360], "wrong audit panel pixels")
        require([d.get("width"), d.get("height")] == [300, 180], "wrong audit panel local extent")
    sampled = [e for e in events if e.get("feature") == "picture-shader"]
    require(bool(sampled) is bool(expected_groups), "missing/unexpected picture-shader provenance")
    for e in sampled:
        require(e.get("status") == "rasterized" and any(str(s).startswith("raster-group-") for s in e.get("scope", [])),
                "picture shader not inside explicit fallback")
    require(report.get("vector_only") is (name == "indexed"), "wrong vector-only flag")
    require(any(e.get("feature") == "geometry" and e.get("status") == "vector" for e in events), "missing outer vector geometry")
    return {"blocking": expected_opaque, "opaque_events": len(opaque), "raster_groups": len(groups),
            "policy_note": "report-only import demonstration" if expected_opaque else "strict export"}

def opaque_info(rows: list) -> dict:
    require(isinstance(rows, list) and len(rows) == 4, "expected four opaque preflights")
    seen = set()
    for row in rows:
        report = row.get("report", {})
        raster = row.get("raster_group")
        require(type(raster) is bool, "invalid raster_group marker")
        key = (report.get("backend"), raster)
        require(key not in seen and key[0] in ("pdf", "svg"), "duplicate/wrong opaque preflight")
        seen.add(key)
        require(report.get("mode") == "preflight" and report.get("blocking") is True
                and report.get("vector_only") is False and report.get("pages") == 1, "invalid opaque preflight flags")
        events = report.get("events", [])
        opaque = [e for e in events if e.get("feature") == "deserialized-picture"]
        require(opaque and all(e.get("status") == "unknown" for e in opaque), "rasterization hid unknown provenance")
        require(sum(e.get("feature") == "raster-group" for e in events) == int(raster), "wrong opaque group boundary")
        if raster:
            require(all(any(str(s).startswith("raster-group-") for s in e.get("scope", [])) for e in opaque), "unknown event escaped raster scope")
    return {"reports": 4, "unknown_inside_and_outside_groups": True}

def skp_info(raw: bytes) -> dict:
    # Header inspection only; full native decoding occurs in the fresh process.
    require(len(raw) > 29 and raw[:8] == b"skiapict", "truncated or wrong SKP magic")
    endian = ">" if sys.byteorder == "big" else "<"
    version, left, top, right, bottom = struct.unpack(endian + "Iffff", raw[8:28])
    require(version == 103 and raw[28] == 1, "wrong pinned SKP version/payload kind")
    require(all(math.isfinite(x) for x in (left, top, right, bottom)), "nonfinite SKP cull")
    require([left, top, right, bottom] == [0, 0, 240, 140], "wrong cache cull bounds")
    return {"stream_version": version, "encoded_bytes": len(raw), "cull_bounds": [left, top, right - left, bottom - top],
            "validation": "header only; not a native-payload safety validator"}

def metadata_info(row: dict) -> dict:
    for field in ("width", "height"):
        require(type(row.get(field)) in (float, int) and math.isfinite(row[field]) and row[field] >= 0, "bad nominal extent")
    b = row.get("cull_bounds")
    require(isinstance(b, list) and len(b) == 4 and all(type(x) in (float, int) and math.isfinite(x) for x in b)
            and b[2] >= 0 and b[3] >= 0, "invalid cull snapshot")
    for field in ("unique_id", "operations", "nested_operations", "approximate_bytes"):
        require(type(row.get(field)) is int and row[field] >= (1 if field in ("unique_id", "approximate_bytes") else 0), "bad picture counter/ID")
    require(row["unique_id"] <= 0xffffffff, "picture ID out of range")
    require(row["nested_operations"] >= row["operations"], "nested operation estimate smaller than shallow estimate")
    return row

def replay_info(expected: bytes, actual: bytes, row: dict) -> dict:
    metadata_info(row)
    require(row.get("native_package") == "3.119.1" and isinstance(row.get("racket"), str), "missing fresh-process runtime identity")
    require([row["width"], row["height"]] == [240, 140], "wrong replay nominal size")
    require(len(expected) == 240 * 140 * 4 and len(actual) == len(expected), "wrong raw RGBA extent")
    require(expected == actual, "fresh-process replay pixels differ from the original recording")
    return {"size_pixels": [240, 140], "raw_rgba_equal": True, "racket": row["racket"], "native_package": row["native_package"]}

def pdf_info(path: Path) -> dict:
    from pypdf import PdfReader
    reader = PdfReader(path)
    require(len(reader.pages) == 3, "wrong PDF page count")
    pages = []
    def images(resources, visited):
        out = []
        resources = resources.get_object() if hasattr(resources, "get_object") else resources
        for ref in (resources or {}).get("/XObject", {}).get_object().values() if "/XObject" in (resources or {}) else []:
            obj = ref.get_object()
            key = (getattr(ref, "idnum", id(obj)), getattr(ref, "generation", 0))
            if key in visited:
                continue
            visited.add(key)
            if obj.get("/Subtype") == "/Image":
                out.append([int(obj["/Width"]), int(obj["/Height"])])
            elif obj.get("/Subtype") == "/Form":
                out.extend(images(obj.get("/Resources", {}), visited))
        return out
    for page, name, heading in zip(reader.pages, PANELS, HEADINGS):
        require([float(page.mediabox.width), float(page.mediabox.height)] == [720, 500], "wrong PDF page size")
        require(heading in (page.extract_text() or ""), "missing PDF heading text")
        sizes = images(page.get("/Resources", {}), set())
        require(sizes == [[600, 360]] * PANELS[name], "wrong PDF image count/extent")
        pages.append({"name": name, "size_points": [720, 500], "image_sizes": sizes})
    return {"pages": pages}

def inspect(prefix: str, pdf: bool = False) -> dict:
    f = lambda suffix: Path(prefix + suffix)
    result = {"svg": {}, "audit": {}}
    for name in PANELS:
        result["svg"][name] = svg_info(f("." + name + ".svg").read_bytes(), name)
        result["audit"][name] = audit_info(json.loads(f("." + name + ".audit.json").read_text()), name)
        require(png_size(f("." + name + ".reference.png").read_bytes()) == (1440, 1000), "wrong independent reference size")
    result["audit"]["pdf"] = audit_info(json.loads(f(".pdf.audit.json").read_text()), "pdf")
    result["opaque"] = opaque_info(json.loads(f(".opaque.audit.json").read_text()))
    result["skp"] = skp_info(f(".cache.skp").read_bytes())
    metadata = json.loads(f(".pictures.json").read_text())
    require(isinstance(metadata, list) and len(metadata) == 4, "wrong metadata trace count")
    require([row.get("name") for row in metadata] == ["original", "loaded", "indexed", "tile"], "wrong metadata trace names/order")
    for row in metadata:
        metadata_info(row)
    require(metadata[0]["cull_bounds"] == metadata[1]["cull_bounds"], "roundtrip cull mismatch")
    require([metadata[2]["width"], metadata[2]["height"]] == [640, 360], "R-tree changed nominal extent")
    result["metadata"] = metadata
    result["fresh_process"] = replay_info(f(".expected.rgba").read_bytes(), f(".fresh.rgba").read_bytes(), json.loads(f(".fresh.json").read_text()))
    require(png_size(f(".fresh.png").read_bytes()) == (240, 140), "wrong fresh replay PNG size")
    html = f(".review.html").read_text()
    require("independent raster" in html and ".fresh.png" in html and "report policy" in html, "missing review provenance labels")
    result["pdf"] = pdf_info(f(".pdf")) if pdf else "NOT CHECKED (use --pdf)"
    result["visual_review"] = "NOT PERFORMED by structural inspector"
    return result

# Synthetic fixtures test the inspector, never stand in for native Skia output.
def fixture_png(width, height):
    import zlib
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + bytes(width * 4)) * height)) + chunk(b"IEND", b""))
def fixture_svg(name):
    paths = '<path d="M0 0L1 1"/>' * 4
    images = ''.join('<image id="p%d" width="600" height="360" href="data:image/png;base64,%s"/>' %
                     (i, base64.b64encode(fixture_png(600, 360)).decode()) for i in range(PANELS[name]))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="720.0pt" height="500pt" viewBox="0 0 720 500">' + paths + images + '</svg>').encode()
def fixture_audit(name):
    groups = 2 if name in ("pdf", "shaders") else 0
    events = [{"feature": "geometry", "status": "vector"}]
    if name in ("pdf", "roundtrip"):
        events.append({"feature": "deserialized-picture", "status": "unknown", "scope": ["loaded-stream"]})
    for i in range(groups):
        events.extend([{"feature": "raster-group", "status": "rasterized", "details": {"pixel_width": 600, "pixel_height": 360, "width": 300, "height": 180}},
                       {"feature": "picture-shader", "status": "rasterized", "scope": ["raster-group-%d" % i]}])
    return {"backend": "pdf" if name == "pdf" else "svg", "mode": "export", "pages": 3 if name == "pdf" else 1,
            "blocking": name in ("pdf", "roundtrip"), "vector_only": name == "indexed", "events": events}
def fixture_metadata():
    return {"width": 240, "height": 140, "cull_bounds": [0, 0, 240, 140], "unique_id": 1,
            "operations": 4, "nested_operations": 4, "approximate_bytes": 1000, "racket": "fixture", "native_package": "3.119.1"}
def fixture_skp():
    return b"skiapict" + struct.pack((">" if sys.byteorder == "big" else "<") + "Iffff", 103, 0, 0, 240, 140) + b"\1fixture"
def fixture_opaque():
    return [{"raster_group": r, "report": {"backend": b, "mode": "preflight", "blocking": True, "vector_only": False, "pages": 1,
             "events": [{"feature": "deserialized-picture", "status": "unknown", "scope": ["raster-group-1"] if r else []}]
                       + ([{"feature": "raster-group"}] if r else [])}} for b in ("pdf", "svg") for r in (False, True)]

class Checks(unittest.TestCase):
    def test_svg(self):
        for name in PANELS: svg_info(fixture_svg(name), name)
    def test_point_spelling(self):
        svg_info(fixture_svg("indexed").replace(b"720.0pt", b"7.2e2pt"), "indexed")
    def test_wrong_units(self):
        with self.assertRaises(ValueError): svg_info(fixture_svg("indexed").replace(b"720.0pt", b"720px"), "indexed")
    def test_dimensions(self):
        with self.assertRaises(ValueError): svg_info(fixture_svg("indexed").replace(b"500pt", b"501pt"), "indexed")
    def test_duplicate_ids(self):
        with self.assertRaises(ValueError): svg_info(fixture_svg("shaders").replace(b'id="p1"', b'id="p0"'), "shaders")
    def test_external_image(self):
        root = ET.fromstring(fixture_svg("shaders")); root.find(NS + "image").set("href", "external.png")
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "shaders")
    def test_panel_count(self):
        with self.assertRaises(ValueError): svg_info(fixture_svg("indexed"), "shaders")
    def test_png_crc(self):
        p = bytearray(fixture_png(20, 10)); p[20] ^= 1
        with self.assertRaises(ValueError): png_size(bytes(p))
    def test_audits(self):
        for name in (*PANELS, "pdf"): audit_info(fixture_audit(name), name)
    def test_unknown_not_certified(self):
        r = fixture_audit("roundtrip"); r["events"][1]["status"] = "vector"
        with self.assertRaises(ValueError): audit_info(r, "roundtrip")
    def test_unknown_blocking(self):
        r = fixture_audit("roundtrip"); r["blocking"] = False
        with self.assertRaises(ValueError): audit_info(r, "roundtrip")
    def test_raster_boundary(self):
        r = fixture_audit("shaders"); r["events"][2]["scope"] = []
        with self.assertRaises(ValueError): audit_info(r, "shaders")
    def test_opaque_preflights(self): opaque_info(fixture_opaque())
    def test_opaque_raster_stays_unknown(self):
        r = fixture_opaque(); r[1]["report"]["events"][0]["status"] = "rasterized"
        with self.assertRaises(ValueError): opaque_info(r)
    def test_skp_header(self): skp_info(fixture_skp())
    def test_skp_version_is_not_milestone(self):
        s = bytearray(fixture_skp()); s[8:12] = (119).to_bytes(4, sys.byteorder)
        with self.assertRaises(ValueError): skp_info(s)
    def test_skp_truncated(self):
        with self.assertRaises(ValueError): skp_info(fixture_skp()[:29])
    def test_metadata_nonfinite(self):
        r = fixture_metadata(); r["cull_bounds"][0] = float("nan")
        with self.assertRaises(ValueError): metadata_info(r)
    def test_replay(self):
        data = bytes(240 * 140 * 4); replay_info(data, data, fixture_metadata())
    def test_replay_mismatch(self):
        data = bytes(240 * 140 * 4)
        with self.assertRaises(ValueError): replay_info(data, b"\1" + data[1:], fixture_metadata())
    def test_replay_truncated(self):
        with self.assertRaises(ValueError): replay_info(b"", b"", fixture_metadata())
    def test_fresh_id_is_not_a_cross_process_key(self):
        r = fixture_metadata(); r["unique_id"] = 31415
        replay_info(bytes(240 * 140 * 4), bytes(240 * 140 * 4), r)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--probe-prefix")
    parser.add_argument("--pdf", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks))
        if not result.wasSuccessful(): raise SystemExit(1)
    if args.probe_prefix: print(json.dumps(inspect(args.probe_prefix, args.pdf), indent=2))
    if not args.self_test and not args.probe_prefix: parser.error("supply --self-test or --probe-prefix")
