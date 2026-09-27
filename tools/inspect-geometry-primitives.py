#!/usr/bin/env python3
"""Inspect actual structured-geometry files. This does not render or certify fidelity."""
from __future__ import annotations
import argparse
import base64
import binascii
import copy
import importlib.util
import json
from pathlib import Path
import struct
import unittest
import xml.etree.ElementTree as ET
import zlib

spec = importlib.util.spec_from_file_location("canvas_inspector", Path(__file__).with_name("inspect-canvas-primitives.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
base.PANELS = {"regions": 0, "images": 4, "meshes": 4}
require = base.require
NS = base.NS
HEADINGS = ["Integer regions are geometry, not soft masks",
            "One image, several structured ways to draw it",
            "Meshes interpolate; patches are not just outlines"]

def audit_info(report: dict, name: str) -> dict:
    require(report.get("backend") in ("pdf", "svg"), "unexpected backend")
    require(report.get("mode") == "export" and report.get("blocking") is False, "unsuccessful export report")
    events = report.get("events", [])
    require(events, "no audit events")
    require(not any(e["status"] in ("unknown", "needs-raster", "unsupported", "discarded") for e in events),
            "unresolved audit risk")
    features = {(e["feature"], e["status"]) for e in events}
    groups = [e for e in events if e["feature"] == "raster-group"]
    expected = {"regions": 0, "images": 4, "meshes": 4, "pdf": 5}[name]
    require(len(groups) == expected, "wrong raster group count")
    for g in groups:
        d = g["details"]
        require((d.get("pixel_width"), d.get("pixel_height")) == (600, 224), "wrong raster dimensions")
    if name == "regions":
        require(report.get("vector_only") is True, "region page should stay vector")
        require(("clip-intersect", "vector") in features, "missing boundary path clip")
    elif name == "images":
        require(("image-grid", "rasterized") in features, "missing explicit grid fallback")
        require(("image-atlas", "rasterized") in features, "missing explicit atlas fallback")
    elif name == "meshes":
        require(("vertices", "rasterized") in features, "missing mesh fallback")
        require(("coons-patch", "rasterized") in features, "missing patch fallback")
    elif name == "pdf":
        require(report.get("pages") == 3, "PDF report page count")
        require(("image-grid", "embedded-raster") in features, "PDF should submit native image grids")
        require(("vertices", "rasterized") in features and ("coons-patch", "rasterized") in features,
                "PDF must contain explicit mesh and patch fallback")
    return {"raster_groups": len(groups), "blocking": False, "features": sorted([list(x) for x in features])}

def trace_info(trace: list) -> dict:
    require(isinstance(trace, list) and len(trace) == 3, "expected PDF/SVG/raster region snapshots")
    require({t.get("backend") for t in trace} == {"pdf", "svg", "raster"}, "missing region backend")
    for t in trace:
        bounds = t.get("region_bounds", [])
        require(len(bounds) == 4 and all(type(v) is int for v in bounds), "noninteger region bounds")
        require(bounds[2] > 0 and bounds[3] > 0, "empty region bounds")
        rectangles = t.get("rectangles", [])
        require(bool(rectangles), "no region rectangles")
        for box in rectangles:
            require(len(box) == 4 and all(type(v) is int for v in box), "noninteger rectangle")
            x, y, w, h = box
            require(w > 0 and h > 0, "empty rectangle")
            require(bounds[0] <= x and bounds[1] <= y and x+w <= bounds[0]+bounds[2]
                    and y+h <= bounds[1]+bounds[3], "rectangle outside region bounds")
    require(all(t["rectangles"] == trace[0]["rectangles"] for t in trace), "region snapshots differ by backend")
    return {"backends": [t["backend"] for t in trace], "rectangle_count": len(trace[0]["rectangles"])}

def pdf_info(path: Path) -> dict:
    try:
        from pypdf import PdfReader
    except ImportError as e:
        raise RuntimeError("--pdf requires pypdf") from e
    reader = PdfReader(str(path))
    require(len(reader.pages) == 3, "PDF page count")
    for p, heading in zip(reader.pages, HEADINGS):
        require(abs(float(p.mediabox.width)-720) < 0.01 and abs(float(p.mediabox.height)-500) < 0.01,
                "wrong PDF page size")
        require(heading in (p.extract_text() or ""), "missing extractable PDF heading")
    return {"pages": 3, "size_points": [720, 500], "headings": "present"}

def inspect(prefix: Path, check_pdf: bool = False) -> dict:
    result = {"svg": {}, "audit": {}}
    for name in base.PANELS:
        result["svg"][name] = base.svg_info(Path(str(prefix)+f".{name}.svg").read_bytes(), name)
        result["audit"][name] = audit_info(json.loads(Path(str(prefix)+f".{name}.audit.json").read_text()), name)
        require(base.png_size(Path(str(prefix)+f".{name}.reference.png").read_bytes()) == (1440, 1000),
                "reference image dimensions")
    result["audit"]["pdf"] = audit_info(json.loads(Path(str(prefix)+".pdf.audit.json").read_text()), "pdf")
    result["regions"] = trace_info(json.loads(Path(str(prefix)+".regions.json").read_text()))
    html = Path(str(prefix)+".review.html").read_text()
    for name in base.PANELS:
        require(f"{prefix.name}.{name}.svg" in html and f"{prefix.name}.{name}.reference.png" in html,
                "review does not compare actual SVG and reference")
    result["pdf"] = pdf_info(Path(str(prefix)+".pdf")) if check_pdf else "NOT CHECKED (use --pdf)"
    result["visual_review"] = "NOT PERFORMED by structural inspector"
    return result

def fixture_report(name: str) -> dict:
    features = {"regions": [("clip-intersect", "vector")],
                "images": [("image-grid", "rasterized"), ("image-atlas", "rasterized")],
                "meshes": [("vertices", "rasterized"), ("coons-patch", "rasterized")],
                "pdf": [("image-grid", "embedded-raster"), ("vertices", "rasterized"), ("coons-patch", "rasterized")]}
    events = [{"feature": f, "status": s, "details": {}} for f,s in features[name]]
    for _ in range({"regions": 0, "images": 4, "meshes": 4, "pdf": 5}[name]):
        events.append({"feature": "raster-group", "status": "rasterized",
                       "details": {"pixel_width": 600, "pixel_height": 224}})
    return {"backend": "pdf" if name == "pdf" else "svg", "mode": "export", "blocking": False,
            "pages": 3 if name == "pdf" else 1, "vector_only": name == "regions", "events": events}

def fixture_png(width: int = 600, height: int = 224) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I",len(data))+kind+data+struct.pack(">I",binascii.crc32(kind+data)&0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB",width,height,8,6,0,0,0))
            + chunk(b"IDAT",zlib.compress((b"\x00"+bytes(width*4))*height)) + chunk(b"IEND",b""))

def fixture_svg(name: str) -> bytes:
    root = ET.Element(NS+"svg", {"width":"720pt","height":"500pt","viewBox":"0 0 720 500"})
    ET.SubElement(root, NS+"path", {"d":"M 0 0 L 1 1", "id":"p"})
    for _ in range(base.PANELS[name]):
        ET.SubElement(root, NS+"image", {"width":"300","height":"112", "href":"data:image/png;base64,"+base64.b64encode(fixture_png()).decode()})
    return ET.tostring(root)

def fixture_trace() -> list:
    return [{"backend": b,"region_bounds":[0,0,10,10],"rectangles":[[0,0,10,10]]} for b in ["pdf","svg","raster"]]

class Checks(unittest.TestCase):
    def test_valid_reports(self):
        for n in ["regions","images","meshes","pdf"]: audit_info(fixture_report(n),n)
    def test_unresolved(self):
        r=fixture_report("meshes");r["events"][0]["status"]="needs-raster"
        with self.assertRaises(ValueError): audit_info(r,"meshes")
    def test_group_count(self):
        r=fixture_report("images");r["events"].pop()
        with self.assertRaises(ValueError): audit_info(r,"images")
    def test_group_size(self):
        r=fixture_report("images");r["events"][-1]["details"]["pixel_width"]=599
        with self.assertRaises(ValueError): audit_info(r,"images")
    def test_pdf_native_grid(self):
        r=fixture_report("pdf");r["events"][0]["status"]="rasterized"
        with self.assertRaises(ValueError): audit_info(r,"pdf")
    def test_regions_vector_only(self):
        r=fixture_report("regions");r["vector_only"]=False
        with self.assertRaises(ValueError): audit_info(r,"regions")
    def test_svg_counts(self):
        for n in base.PANELS: base.svg_info(fixture_svg(n),n)
    def test_svg_external(self):
        s=fixture_svg("images");root=ET.fromstring(s);root.find(NS+"image").set("href","other.png")
        with self.assertRaises(ValueError): base.svg_info(ET.tostring(root),"images")
    def test_svg_unresolved_id(self):
        root=ET.fromstring(fixture_svg("regions"));ET.SubElement(root,NS+"use",{"href":"#missing"})
        with self.assertRaises(ValueError): base.svg_info(ET.tostring(root),"regions")
    def test_png_crc(self):
        b=bytearray(fixture_png());b[-1]^=1
        with self.assertRaises(ValueError): base.png_size(bytes(b))
    def test_trace(self): trace_info(fixture_trace())
    def test_trace_mismatch(self):
        t=fixture_trace();t[-1]["rectangles"]=[[0,0,5,5]]
        with self.assertRaises(ValueError): trace_info(t)
    def test_trace_noninteger(self):
        t=fixture_trace();t[-1]["rectangles"]=[[0.1,0,5,5]]
        with self.assertRaises(ValueError): trace_info(t)
    def test_trace_missing_backend(self):
        t=fixture_trace();t[-1]["backend"]="svg"
        with self.assertRaises(ValueError): trace_info(t)

if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test",action="store_true")
    parser.add_argument("--probe-prefix",type=Path)
    parser.add_argument("--pdf",action="store_true")
    args=parser.parse_args()
    if args.self_test:
        result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks))
        raise SystemExit(not result.wasSuccessful())
    if not args.probe_prefix: parser.error("use --self-test or --probe-prefix")
    print(json.dumps(inspect(args.probe_prefix,args.pdf),indent=2))
