#!/usr/bin/env python3
"""Inspect 0.34 bounded-output-group documents and decision reports."""
from __future__ import annotations
import argparse
import base64
import binascii
import json
import math
from pathlib import Path
import re
import struct
import unittest
import xml.etree.ElementTree as ET

NS = "{http://www.w3.org/2000/svg}"
XLINK = "{http://www.w3.org/1999/xlink}href"

def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)

def png_size(raw: bytes) -> tuple[int, int]:
    require(raw[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG")
    pos, dimensions, ended, saw_data = 8, None, False, False
    while pos < len(raw):
        require(pos + 12 <= len(raw), "truncated PNG chunk")
        n = struct.unpack_from(">I", raw, pos)[0]
        require(n <= len(raw) - pos - 12, "PNG chunk past end")
        kind = raw[pos+4:pos+8]
        data = raw[pos+8:pos+8+n]
        crc = struct.unpack_from(">I", raw, pos+8+n)[0]
        require(binascii.crc32(kind + data) & 0xffffffff == crc, "bad PNG CRC")
        if pos == 8:
            require(kind == b"IHDR" and n == 13, "missing PNG header")
        if kind == b"IHDR":
            require(dimensions is None and n == 13, "duplicate/bad IHDR")
            dimensions = struct.unpack(">II", data[:8])
            require(min(dimensions) > 0, "zero PNG extent")
        if kind == b"IDAT":
            saw_data = True
        pos += n + 12
        if kind == b"IEND":
            require(n == 0 and pos == len(raw) and saw_data, "invalid PNG end")
            ended = True
            break
    require(ended and dimensions is not None, "incomplete PNG")
    return dimensions

def point_length(value: str | None) -> float:
    match = re.fullmatch(r"([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)pt", value or "")
    require(match is not None, "physical SVG size is not in points")
    result = float(match.group(1))
    require(math.isfinite(result), "non-finite physical SVG size")
    return result

EXPECTED_IMAGES = {
    "choice": [[624, 364]],
    "isolation": [[600, 340]],
    "nested": [[480, 280]],
}
PAGES = tuple(EXPECTED_IMAGES)


def svg_info(raw: bytes, name: str) -> dict:
    root = ET.fromstring(raw)
    require(root.tag == NS + "svg", "missing SVG root")
    require(list(map(float, root.get("viewBox", "").split())) == [0, 0, 720, 500],
            "wrong SVG viewBox")
    require(point_length(root.get("width")) == 720 and point_length(root.get("height")) == 500,
            "wrong physical SVG size")
    ids = [e.get("id") for e in root.iter() if e.get("id")]
    require(len(ids) == len(set(ids)), "duplicate SVG IDs")
    images = []
    path_count = 0
    for e in root.iter():
        require(e.tag != NS + "text", "native text in outlined SVG probe")
        path_count += int(e.tag == NS + "path")
        transform = e.get("transform", "")
        require("matrix3d" not in transform, "non-SVG transform")
        for match in re.findall(r"matrix\(([^)]*)\)", transform):
            values = [float(v) for v in re.split(r"[\s,]+", match.strip())]
            require(len(values) == 6 and all(math.isfinite(v) for v in values),
                    "invalid SVG matrix")
        href = e.get("href", e.get(XLINK, ""))
        if e.tag == NS + "image":
            require(href.startswith("data:image/png;base64,"), "external or non-PNG SVG image")
            images.append(list(png_size(base64.b64decode(href.split(",", 1)[1], validate=True))))
        elif href:
            require(href.startswith("#") and href[1:] in ids, "external or unresolved SVG reference")
        for value in e.attrib.values():
            for ref in re.findall(r"url\(#([^)]*)\)", value):
                require(ref in ids, "unresolved SVG paint/clip reference")
    require(images == EXPECTED_IMAGES[name], "wrong bounded SVG image count/size")
    require(path_count >= 8, "too little vector artwork remained outside fallback")
    return {"size_points": [720, 500], "embedded_png_sizes": images,
            "vector_path_count": path_count, "resource_count": len(ids)}


def pdf_info(raw: bytes) -> dict:
    require(raw.startswith(b"%PDF-"), "missing PDF header")
    page_count = len(re.findall(rb"/Type\s*/Page(?!s)\b", raw))
    require(page_count == 3, "wrong PDF page count")
    boxes = re.findall(rb"/MediaBox\s*\[([^\]]+)\]", raw)
    require(len(boxes) >= 3, "missing PDF MediaBox entries")
    for box in boxes[:3]:
        values = [float(x) for x in re.findall(rb"[-+0-9.eE]+", box)]
        require(values == [0, 0, 720, 500], "wrong PDF page size")

    # Skia can encode an RGBA fallback as a color image plus a separate /SMask
    # image.  The mask has the same dimensions but is not another painted
    # fallback.  Count only primary image XObjects here.
    objects = {}
    for match in re.finditer(rb"(?ms)(\d+)\s+(\d+)\s+obj\b(.*?)endobj", raw):
        objects[int(match.group(1))] = match.group(3)
    smasks = {int(m.group(1)) for m in re.finditer(rb"/SMask\s+(\d+)\s+\d+\s+R", raw)}
    images = []
    mask_images = []
    for number, obj in objects.items():
        if not re.search(rb"/Subtype\s*/Image\b", obj):
            continue
        width = re.search(rb"/Width\s+(\d+)", obj)
        height = re.search(rb"/Height\s+(\d+)", obj)
        require(width and height, "PDF image missing dimensions")
        size = [int(width.group(1)), int(height.group(1))]
        if number in smasks or re.search(rb"/ImageMask\s+true\b", obj):
            mask_images.append(size)
        else:
            images.append(size)

    expected = sum((EXPECTED_IMAGES[name] for name in PAGES), [])
    # Object count is not a stable proxy for draw count: a backend may reuse or
    # duplicate an image object.  The audit/decision checks establish the draw
    # count; this binary check establishes that every expected fallback size is
    # present and that no unrelated primary image size appeared.
    from collections import Counter
    actual_counts = Counter(map(tuple, images))
    expected_counts = Counter(map(tuple, expected))
    require(all(actual_counts[size] >= count for size, count in expected_counts.items()),
            "missing expected PDF fallback image size")
    require(all(tuple(size) in expected_counts for size in images),
            "unexpected primary PDF image size")
    return {"pages": page_count, "size_points": [720, 500],
            "embedded_image_sizes": images, "soft_mask_sizes": mask_images}


def check_group(group: dict, *, label: str, strategy: str, reason: str,
                pixels=None, child=None) -> None:
    require(group.get("label") == label, "wrong output-group label")
    require(group.get("strategy") == strategy, "wrong output-group strategy")
    require(group.get("reason") == reason, "wrong output-group reason")
    if pixels is None:
        require(group.get("pixel_size") in (False, None), "native group unexpectedly has pixel size")
    else:
        require(group.get("pixel_size") == pixels, "wrong output-group pixel size")
    children = group.get("captured_children", [])
    if child is None:
        require(children == [], "unexpected nested output-group decision")
    else:
        require(len(children) == 1, "missing nested output-group decision")
        check_group(children[0], **child)


def decision_page(row: dict, name: str) -> dict:
    require(row.get("page") == name, "wrong decision page name/order")
    groups = row.get("groups")
    require(isinstance(groups, list), "decision groups must be a list")
    if name == "choice":
        require(len(groups) == 2, "choice page should have two top-level groups")
        check_group(groups[0], label="vector-card", strategy="native", reason="native-compatible")
        check_group(groups[1], label="runtime-card", strategy="raster", reason="backend-fallback",
                    pixels=[624, 364])
    elif name == "isolation":
        require(len(groups) == 2, "isolation page should have two top-level groups")
        check_group(groups[0], label="source-over", strategy="native", reason="native-compatible")
        check_group(groups[1], label="multiply", strategy="raster", reason="isolated-compositing",
                    pixels=[600, 340])
        require("blend-mode" in groups[1].get("features", []), "multiply provenance was lost")
    else:
        require(len(groups) == 1, "nested page should have one top-level group")
        check_group(groups[0], label="outer-group", strategy="native", reason="native-compatible",
                    child={"label": "inner-runtime", "strategy": "raster",
                           "reason": "backend-fallback", "pixels": [480, 280]})
    return {"top_level_groups": len(groups), "strategies": [g.get("strategy") for g in groups]}


def decisions_info(data: dict) -> dict:
    result = {}
    for backend in ("pdf", "svg"):
        rows = data.get(backend)
        require(isinstance(rows, list) and len(rows) == 3, "wrong decision page count")
        result[backend] = [decision_page(row, name) for row, name in zip(rows, PAGES)]
    return result


def actual_raster_events(events: list) -> list:
    return [e for e in events
            if e.get("operation") == "draw-rasterized" and e.get("feature") == "raster-group"]


def decision_events(events: list) -> list:
    return [e for e in events if e.get("operation") == "draw-output-group"]


def audit_info(report: dict, backend: str, name: str | None = None) -> dict:
    require(report.get("backend") == backend, "wrong audit backend")
    expected_pages = 3 if name is None else 1
    require(report.get("mode") == "export" and report.get("pages") == expected_pages,
            "wrong audit mode/pages")
    require(report.get("blocking") is False, "handled output-group probe unexpectedly blocks")
    events = report.get("events", [])
    require(events, "empty output audit")
    require(not any(e.get("status") in ("needs-raster", "unknown", "discarded", "unsupported")
                    for e in events), "unhandled feature remained in output audit")
    rasters = actual_raster_events(events)
    if name is None:
        # The choice and isolation fallbacks execute on the document canvas and
        # therefore emit draw-rasterized events. The nested fallback executes
        # while the outer group is being captured with collection disabled; on
        # document replay it is observed as an embedded image instead.
        expected = [EXPECTED_IMAGES["choice"][0], EXPECTED_IMAGES["isolation"][0]]
        require(len(rasters) == 2, "wrong PDF top-level actual-raster count")
        sizes = sorted([[e.get("details", {}).get("pixel_width"),
                         e.get("details", {}).get("pixel_height")] for e in rasters])
        require(sizes == sorted(expected), "wrong PDF top-level audit raster dimensions")
        require(any(e.get("feature") == "image" and e.get("status") == "embedded-raster"
                    for e in events), "nested PDF fallback was not observed as an embedded image")
        require(len(decision_events(events)) == 5, "wrong PDF output-group decision count")
    else:
        if name == "nested":
            require(len(rasters) == 0,
                    "nested SVG fallback should occur during capture, not as a document draw-rasterized event")
            require(any(e.get("feature") == "image" and e.get("status") == "embedded-raster"
                        for e in events), "nested SVG fallback was not observed as an embedded image")
        else:
            require(len(rasters) == 1,
                    "choice/isolation SVG page should contain exactly one document raster fallback")
            details = rasters[0].get("details", {})
            require([details.get("pixel_width"), details.get("pixel_height")] == EXPECTED_IMAGES[name][0],
                    "wrong SVG audit raster dimensions")
        expected_decisions = 1 if name == "nested" else 2
        require(len(decision_events(events)) == expected_decisions,
                "wrong SVG output-group decision count")
    require(any(e.get("status") == "vector" for e in events), "no vector/native document content observed")
    return {"events": len(events), "decision_events": len(decision_events(events)),
            "actual_raster_events": len(rasters)}


def inspect(prefix: str) -> dict:
    f = lambda suffix: Path(prefix + suffix)
    result = {"svg": {}, "audit": {}}
    for name in PAGES:
        result["svg"][name] = svg_info(f("." + name + ".svg").read_bytes(), name)
        result["audit"][name] = audit_info(
            json.loads(f("." + name + ".audit.json").read_text()), "svg", name)
        require(png_size(f("." + name + ".reference.png").read_bytes()) == (1440, 1000),
                "wrong independent reference size")
    result["pdf"] = pdf_info(f(".pdf").read_bytes())
    result["audit"]["pdf"] = audit_info(json.loads(f(".pdf.audit.json").read_text()), "pdf")
    result["decisions"] = decisions_info(json.loads(f(".decisions.json").read_text()))
    html = f(".review.html").read_text()
    require("independent raster reference" in html.lower(), "missing review provenance label")
    require(".inspection.json" in html and ".decisions.json" in html, "review omits structural artifacts")
    result["review"] = "actual SVGs paired with independent raster references; PDF linked"
    result["visual_review"] = "NOT PERFORMED by structural inspector"
    return result


# Synthetic fixtures validate the inspector itself; they are not Skia output.
def fixture_png(width: int, height: int) -> bytes:
    import zlib
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + bytes(width * 4)) * height))
            + chunk(b"IEND", b""))


def fixture_svg(name: str) -> bytes:
    images = "".join(
        '<image id="i%d" href="data:image/png;base64,%s"/>' %
        (i, base64.b64encode(fixture_png(w, h)).decode())
        for i, (w, h) in enumerate(EXPECTED_IMAGES[name]))
    paths = '<path d="M0 0L1 1"/>' * 8
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="720.0pt" height="500pt" '
            'viewBox="0 0 720 500">' + paths + images + '</svg>').encode()


def fixture_group(label, strategy, reason, pixels=False, children=None, features=None):
    return {"label": label, "strategy": strategy, "reason": reason,
            "pixel_size": pixels, "captured_children": children or [],
            "features": features or ["geometry"]}


def fixture_decisions():
    child = fixture_group("inner-runtime", "raster", "backend-fallback", [480, 280],
                          features=["geometry", "runtime-shader"])
    rows = [
        {"page": "choice", "groups": [fixture_group("vector-card", "native", "native-compatible"),
                                         fixture_group("runtime-card", "raster", "backend-fallback", [624, 364])]},
        {"page": "isolation", "groups": [fixture_group("source-over", "native", "native-compatible"),
                                            fixture_group("multiply", "raster", "isolated-compositing",
                                                          [600, 340], features=["blend-mode", "geometry"])]},
        {"page": "nested", "groups": [fixture_group("outer-group", "native", "native-compatible",
                                                       children=[child])]},
    ]
    return {"pdf": rows, "svg": json.loads(json.dumps(rows))}


def fixture_audit(name: str | None, backend: str):
    names = PAGES if name is None else (name,)
    events = [{"operation": "draw-rect", "feature": "geometry", "status": "vector", "details": {}}]
    decision_count = 0
    for n in names:
        top = 1 if n == "nested" else 2
        decision_count += top
        for i in range(top):
            is_raster = (n in ("choice", "isolation") and i == 1)
            events.append({"operation": "draw-output-group",
                           "feature": "raster-group" if is_raster else "output-group",
                           "status": "rasterized" if is_raster else "vector", "details": {}})
        if n == "nested":
            events.append({"operation": "draw-picture", "feature": "image",
                           "status": "embedded-raster", "details": {}})
        else:
            w, h = EXPECTED_IMAGES[n][0]
            events.append({"operation": "draw-rasterized", "feature": "raster-group",
                           "status": "rasterized", "details": {"pixel_width": w, "pixel_height": h}})
    return {"backend": backend, "mode": "export", "pages": 3 if name is None else 1,
            "blocking": False, "vector_only": False, "events": events}


def fixture_pdf(with_masks=False) -> bytes:
    parts = [b"%PDF-1.4\n"]
    obj = 1
    for _ in PAGES:
        parts.append((f"{obj} 0 obj\n<</Type /Page /MediaBox [0 0 720 500]>>\nendobj\n").encode())
        obj += 1
    for name in PAGES:
        w, h = EXPECTED_IMAGES[name][0]
        image_obj = obj
        mask_obj = obj + 1 if with_masks else None
        smask = f" /SMask {mask_obj} 0 R" if with_masks else ""
        parts.append((f"{image_obj} 0 obj\n<</Type /XObject /Subtype /Image /Width {w} /Height {h}{smask}>>\nendobj\n").encode())
        obj += 1
        if with_masks:
            parts.append((f"{obj} 0 obj\n<</Type /XObject /Subtype /Image /ColorSpace /DeviceGray /Width {w} /Height {h}>>\nendobj\n").encode())
            obj += 1
    return b"".join(parts)


class Checks(unittest.TestCase):
    def test_svgs(self):
        for name in PAGES:
            svg_info(fixture_svg(name), name)

    def test_svg_wrong_image_size(self):
        raw = fixture_svg("choice").replace(b"624", b"625", 1)
        # Replacing XML attributes is insufficient because size comes from PNG bytes;
        # instead build a fixture with another page's image.
        wrong = fixture_svg("isolation")
        with self.assertRaises(ValueError):
            svg_info(wrong, "choice")

    def test_svg_native_text_rejected(self):
        raw = fixture_svg("nested").replace(b"</svg>", b"<text>x</text></svg>")
        with self.assertRaises(ValueError):
            svg_info(raw, "nested")

    def test_pdf(self):
        pdf_info(fixture_pdf())

    def test_pdf_soft_masks_are_not_extra_fallbacks(self):
        info = pdf_info(fixture_pdf(with_masks=True))
        require(len(info["embedded_image_sizes"]) == 3, "soft masks counted as primary images")
        require(len(info["soft_mask_sizes"]) == 3, "soft masks were not identified")

    def test_pdf_wrong_image_count(self):
        raw = fixture_pdf().replace(b"/Subtype /Image", b"/Subtype /Form", 1)
        with self.assertRaises(ValueError):
            pdf_info(raw)

    def test_decisions(self):
        decisions_info(fixture_decisions())

    def test_decision_wrong_nested_strategy(self):
        data = fixture_decisions()
        data["svg"][2]["groups"][0]["captured_children"][0]["strategy"] = "native"
        with self.assertRaises(ValueError):
            decisions_info(data)

    def test_audits(self):
        for name in PAGES:
            audit_info(fixture_audit(name, "svg"), "svg", name)
        audit_info(fixture_audit(None, "pdf"), "pdf")

    def test_audit_missing_raster(self):
        data = fixture_audit("choice", "svg")
        data["events"] = [e for e in data["events"] if e["operation"] != "draw-rasterized"]
        with self.assertRaises(ValueError):
            audit_info(data, "svg", "choice")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--probe-prefix")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(
            unittest.defaultTestLoader.loadTestsFromTestCase(Checks))
        if not result.wasSuccessful():
            raise SystemExit(1)
    if args.probe_prefix:
        print(json.dumps(inspect(args.probe_prefix), indent=2))
    if not args.self_test and not args.probe_prefix:
        parser.error("supply --self-test or --probe-prefix")
