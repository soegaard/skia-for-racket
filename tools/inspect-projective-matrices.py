#!/usr/bin/env python3
"""Check exported matrix probes, not rendered appearance. --pdf needs pypdf."""
from __future__ import annotations
import argparse
import base64
import copy
import importlib.util
import json
import math
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

_spec = importlib.util.spec_from_file_location("canvas_probe_inspector", Path(__file__).with_name("inspect-canvas-primitives.py"))
_base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_base)
require, png_size, NS, XLINK = _base.require, _base.png_size, _base.NS, _base.XLINK
PANELS = {"homography": 1, "depth": 2, "scope": 2}
HEADINGS = ["Perspective is a homogeneous divide", "Keep depth until the final projection",
            "Matrix state is scoped; horizons are not finite"]
TRACE_NAMES = {"affine", "homography", "left-tilt", "right-tilt", "restored", "clipped"}

def point_length(value: str | None) -> float:
    match = re.fullmatch(r"([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)pt", value or "")
    require(match is not None, "physical SVG size is not in points")
    result = float(match.group(1))
    require(math.isfinite(result), "non-finite physical SVG size")
    return result

def svg_info(raw: bytes, name: str) -> dict:
    root = ET.fromstring(raw)
    require(root.tag == NS+"svg", "missing SVG root")
    require(list(map(float, root.get("viewBox", "").split())) == [0, 0, 720, 500], "wrong viewport")
    require(math.isclose(point_length(root.get("width")), 720.0, abs_tol=1e-9)
            and math.isclose(point_length(root.get("height")), 500.0, abs_tol=1e-9),
            "wrong physical size")
    ids = [e.get("id") for e in root.iter() if e.get("id")]
    require(len(ids) == len(set(ids)), "duplicate SVG IDs")
    images = []
    for e in root.iter():
        require(e.tag != NS+"text", "native text in an outlined SVG")
        transform = e.get("transform", "")
        require("matrix3d" not in transform, "unhandled 3D SVG transform")
        for match in re.findall(r"matrix\(([^)]*)\)", transform):
            values = [float(x) for x in re.split(r"[\s,]+", match.strip())]
            require(len(values) == 6 and all(math.isfinite(x) for x in values), "nonaffine/invalid SVG matrix")
        href = e.get("href", e.get(XLINK, ""))
        if e.tag == NS+"image":
            require(href.startswith("data:image/png;base64,"), "external or non-PNG image")
            data = base64.b64decode(href.split(",", 1)[1], validate=True)
            images.append(list(png_size(data)))
        elif href.startswith("#"):
            require(href[1:] in ids, "unresolved SVG reference")
    require(images == [[600, 360]]*PANELS[name], "wrong bounded image count/size")
    require(sum(e.tag == NS+"path" for e in root.iter()) >= 4, "missing vector artwork/labels")
    return {"size_points": [720, 500], "embedded_png_sizes": images, "resource_count": len(ids)}

def audit_info(report: dict, name: str) -> dict:
    require(report.get("backend") == ("pdf" if name == "pdf" else "svg"), "wrong audit backend")
    require(report.get("mode") == "export" and report.get("blocking") is False, "not a successful export")
    require(report.get("pages") == (3 if name == "pdf" else 1), "wrong audit page count")
    events = report.get("events", [])
    require(events and all(e.get("status") in ("vector", "rasterized", "embedded-raster") for e in events), "unhandled output feature")
    expected = sum(PANELS.values()) if name == "pdf" else PANELS[name]
    groups = [e for e in events if e.get("feature") == "raster-group"]
    require(len(groups) == expected, "wrong raster-group count")
    for e in groups:
        d = e.get("details", {})
        require([d.get("pixel_width"), d.get("pixel_height")] == [600, 360], "wrong raster-group pixels")
    general = [e for e in events if e.get("feature") == "projective-transform"]
    require(len(general) >= expected, "missing general-matrix provenance")
    for e in general:
        require(e.get("status") == "rasterized" and any(str(s).startswith("raster-group-") for s in e.get("scope", [])),
                "general matrix was not inside a raster group")
    require(report.get("vector_only") is False, "raster panels incorrectly reported as vector-only")
    require(any(e.get("feature") == "geometry" and e.get("status") == "vector" for e in events), "no outer vector geometry")
    return {"raster_groups": len(groups), "general_matrix_events": len(general), "blocking": False}

def trace_info(trace: list) -> dict:
    require(isinstance(trace, list) and len(trace) == 18, "expected six matrix traces for each backend")
    seen = set()
    for row in trace:
        key = (row.get("backend"), row.get("name"))
        require(key not in seen, "duplicate matrix trace")
        seen.add(key)
        for k in ("before", "local", "after"):
            v = row.get(k)
            require(isinstance(v, list) and len(v) == 16, "missing full matrix snapshot")
            require(all(type(x) in (float, int) and math.isfinite(x) for x in v), "nonfinite matrix trace")
        a, b, actual = row["before"], row["local"], row["after"]
        expected = [sum(a[r*4+k]*b[k*4+c] for k in range(4)) for r in range(4) for c in range(4)]
        require(all(math.isclose(x, y, rel_tol=2e-6, abs_tol=2e-4) for x, y in zip(actual, expected)),
                "native matrix does not match current * local (row-major)")
    require(seen == {(b, n) for b in ("pdf", "svg", "raster") for n in TRACE_NAMES}, "incomplete matrix traces")
    return {"snapshots": len(trace), "composition": "current * local", "finite": True}

def unsafe_info(reports: list) -> dict:
    require(isinstance(reports, list) and len(reports) == 2, "expected two unsafe preflight reports")
    require({r.get("backend") for r in reports} == {"pdf", "svg"}, "missing preflight backend")
    for report in reports:
        require(report.get("mode") == "preflight" and report.get("blocking") is True, "unsafe preflight not blocking")
        require(any(e.get("feature") == "projective-transform" and e.get("status") == "needs-raster"
                    for e in report.get("events", [])), "unsafe perspective was not identified")
    return {"pdf": "blocking", "svg": "blocking", "unsafe_files_generated": False}

def pdf_info(path: Path) -> dict:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise RuntimeError("--pdf requires pypdf") from exc
    reader = PdfReader(str(path))
    require(len(reader.pages) == 3, "wrong PDF page count")
    results = []
    def image_sizes(resources, seen):
        output = []
        for reference in resources.get("/XObject", {}).get_object().values() if "/XObject" in resources else []:
            obj = reference.get_object()
            # Do not count an image's SMask as a separately drawn image.
            ident = id(obj)
            if ident in seen:
                continue
            seen.add(ident)
            if obj.get("/Subtype") == "/Image":
                output.append([int(obj["/Width"]), int(obj["/Height"])])
            elif obj.get("/Subtype") == "/Form":
                output += image_sizes(obj.get("/Resources", {}).get_object() if "/Resources" in obj else {}, seen)
        return output
    for page, name, heading in zip(reader.pages, PANELS, HEADINGS):
        require(abs(float(page.mediabox.width)-720) < .01 and abs(float(page.mediabox.height)-500) < .01,
                "wrong PDF media box")
        require(heading in (page.extract_text() or ""), "missing native PDF heading")
        sizes = image_sizes(page["/Resources"].get_object(), set())
        require(sizes == [[600, 360]]*PANELS[name], "unexpected PDF raster content")
        results.append({"name": name, "images": sizes})
    return {"pages": results, "headings": "extractable", "size_points": [720, 500]}

def inspect(prefix: Path, pdf: bool = False) -> dict:
    def f(suffix): return Path(str(prefix)+suffix)
    result = {"svg": {}, "audit": {}}
    for name in PANELS:
        result["svg"][name] = svg_info(f(f".{name}.svg").read_bytes(), name)
        result["audit"][name] = audit_info(json.loads(f(f".{name}.audit.json").read_text()), name)
        require(png_size(f(f".{name}.reference.png").read_bytes()) == (1440, 1000), "wrong reference size")
    result["audit"]["pdf"] = audit_info(json.loads(f(".pdf.audit.json").read_text()), "pdf")
    result["matrices"] = trace_info(json.loads(f(".matrices.json").read_text()))
    result["unsafe_preflight"] = unsafe_info(json.loads(f(".unsafe.audit.json").read_text()))
    require(not f(".unsafe.svg").exists() and not f(".unsafe.pdf").exists(), "unsafe document file exists")
    review = f(".review.html").read_text()
    require(review.count("<img ") == 6 and "not a PDF/SVG rasterization" in review, "incorrect review provenance")
    for name in PANELS:
        require(f".{name}.svg" in review and f".{name}.reference.png" in review, "missing review comparison")
    result["pdf"] = pdf_info(f(".pdf")) if pdf else "NOT CHECKED (use --pdf)"
    result["visual_review"] = "NOT PERFORMED by structural inspector"
    return result

# Synthetic fixtures test the inspector; they are not Skia output.
def fixture_svg(name):
    # Skia emits decimal point lengths (for example, 720.0pt).
    root = ET.Element(NS+"svg", {"width": "720.0pt", "height": "500.0pt", "viewBox": "0 0 720 500"})
    for _ in range(4): ET.SubElement(root, NS+"path", {"d": "M0 0L10 10"})
    for _ in range(PANELS[name]):
        ET.SubElement(root, NS+"image", {"href": "data:image/png;base64,"+base64.b64encode(_base.png(600, 360)).decode()})
    return ET.tostring(root)

def fixture_report(name):
    count = sum(PANELS.values()) if name == "pdf" else PANELS[name]
    events = [{"feature": "geometry", "status": "vector"}]
    for i in range(count):
        events += [{"feature": "raster-group", "status": "rasterized", "details": {"pixel_width": 600, "pixel_height": 360}},
                   {"feature": "projective-transform", "status": "rasterized", "scope": [f"raster-group-{i+1}"]}]
    return {"backend": "pdf" if name == "pdf" else "svg", "mode": "export", "blocking": False,
            "pages": 3 if name == "pdf" else 1, "vector_only": False, "events": events}

def fixture_trace():
    identity = [1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1.]
    return [{"backend": b, "name": n, "before": identity[:], "local": identity[:], "after": identity[:]}
            for b in ("pdf", "svg", "raster") for n in sorted(TRACE_NAMES)]

def fixture_unsafe():
    return [{"backend": b, "mode": "preflight", "blocking": True,
             "events": [{"feature": "projective-transform", "status": "needs-raster"}]} for b in ("pdf", "svg")]

class Checks(unittest.TestCase):
    def test_svg(self):
        for n in PANELS: svg_info(fixture_svg(n), n)
    def test_audits(self):
        for n in list(PANELS)+["pdf"]: audit_info(fixture_report(n), n)
    def test_trace(self): trace_info(fixture_trace())
    def test_unsafe(self): unsafe_info(fixture_unsafe())
    def test_dimensions(self):
        raw = fixture_svg("depth")
        with self.assertRaises(ValueError): svg_info(raw.replace(b"720.0pt", b"700.0pt"), "depth")
        with self.assertRaises(ValueError): svg_info(raw.replace(b"720.0pt", b"720px"), "depth")
    def test_native_text(self):
        raw = fixture_svg("depth").replace(b"</ns0:svg>", b"<ns0:text>x</ns0:text></ns0:svg>")
        with self.assertRaises(ValueError): svg_info(raw, "depth")
    def test_external(self):
        root = ET.fromstring(fixture_svg("homography")); root.find(NS+"image").set("href", "external.png")
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "homography")
    def test_duplicate_id(self):
        root = ET.fromstring(fixture_svg("homography"))
        for e in root.findall(NS+"path"): e.set("id", "same")
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "homography")
    def test_png_crc(self):
        data = bytearray(_base.png(600, 360)); data[-1] ^= 1
        with self.assertRaises(ValueError): png_size(data)
    def test_panel_count(self):
        with self.assertRaises(ValueError): svg_info(fixture_svg("depth"), "homography")
    def test_matrix3d(self):
        root = ET.fromstring(fixture_svg("homography")); root[0].set("transform", "matrix3d(1)")
        with self.assertRaises(ValueError): svg_info(ET.tostring(root), "homography")
    def test_unhandled_audit(self):
        r = fixture_report("depth"); r["events"][-1]["status"] = "needs-raster"
        with self.assertRaises(ValueError): audit_info(r, "depth")
    def test_audit_scope(self):
        r = fixture_report("depth"); r["events"][-1]["scope"] = []
        with self.assertRaises(ValueError): audit_info(r, "depth")
    def test_audit_group_size(self):
        r = fixture_report("depth"); r["events"][1]["details"]["pixel_height"] = 224
        with self.assertRaises(ValueError): audit_info(r, "depth")
    def test_trace_product(self):
        t = fixture_trace(); t[0]["after"][3] = 10
        with self.assertRaises(ValueError): trace_info(t)
    def test_trace_nonfinite(self):
        t = fixture_trace(); t[0]["after"][0] = float("nan")
        with self.assertRaises(ValueError): trace_info(t)
    def test_trace_duplicate(self):
        t = fixture_trace(); t[0] = copy.deepcopy(t[1])
        with self.assertRaises(ValueError): trace_info(t)
    def test_preflight_mode(self):
        r = fixture_unsafe(); r[0]["mode"] = "export"
        with self.assertRaises(ValueError): unsafe_info(r)

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
