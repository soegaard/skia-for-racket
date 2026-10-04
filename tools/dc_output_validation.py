#!/usr/bin/env python3
"""0.63 document acceptance. Native documents are evidence; declarations are not.

Structural checks use pypdf content streams (including Form XObjects), not raw
PDF regexes. Pixel checks use separately installed Poppler and librsvg. Neither
mode certifies PDF/A, color fidelity, accessibility or physical displays.
"""
from __future__ import annotations
import base64
import hashlib
import html
import io
import json
import math
from pathlib import Path
import re
from typing import Any
import xml.etree.ElementTree as ET

TEXT = "SkiaDC063"
URI = "https://example.org/skia-063"
DEST = "dest-7365636f6e64"


def specifications() -> dict[str, dict[str, Any]]:
    result = {}
    def add(name, kind, fmt, mode, w, h, pages=1):
        result[name] = dict(id=name, file=name+"."+fmt, kind=kind, format=fmt,
                            text_mode=mode, width_points=w, height_points=h, pages=pages)
    for fmt in ("pdf", "svg"):
        for mode in ("native", "outline"):
            add(f"vector-{fmt}-{mode}", "vector", fmt, mode, 160, 120)
        mode = "native" if fmt == "pdf" else "outline"
        add("mixed-"+fmt, "mixed", fmt, mode, 200, 160)
        add("styles-"+fmt, "styles", fmt, mode, 80, 64)
        add("units-"+fmt, "units", fmt, mode, 72, 36)
        add("links-"+fmt, "links", fmt, mode, 160, 120, 2 if fmt == "pdf" else 1)
        for scene in ("pict", "plot"):
            for execution in ("direct", "procedure", "datum"):
                add(f"{scene}-{execution}-{fmt}", scene, fmt, mode, 320, 240)
    return result


SPECS = specifications()


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def exact(value, minimum=0) -> bool:
    return type(value) is int and value >= minimum


def finite(value) -> bool:
    return type(value) in (int, float) and math.isfinite(value)


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key: "+key)
        result[key] = value
    return result


def read_json(path: Path):
    require(path.is_file() and not path.is_symlink(), "missing or symlinked receipt")
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique,
                      parse_constant=lambda s: (_ for _ in ()).throw(ValueError("nonfinite JSON: "+s)))


def safe_file(directory: Path, name: str) -> Path:
    require(isinstance(name, str) and re.fullmatch(r"[a-z0-9-]+\.(pdf|svg)", name) is not None,
            "invalid document filename")
    path = directory / name
    require(path.is_file() and not path.is_symlink(), "missing or symlinked document: "+name)
    require(0 < path.stat().st_size <= 128*1024*1024, "invalid document size: "+name)
    return path


def validate_receipt(value: dict, token: str, identity: dict) -> list[dict]:
    require(isinstance(value, dict) and type(value.get("schema")) is int and value["schema"] == 1,
            "invalid document receipt schema")
    require(value.get("stage") == "0.63" and value.get("status") == "passed", "incomplete document worker")
    require(value.get("run_token") == token and value.get("identity") == identity, "foreign/stale document evidence")
    for flag in ("physical_display_verified", "pdfa_certified", "color_fidelity_certified"):
        require(value.get(flag) is False, "unsupported certification: "+flag)
    rows = value.get("documents")
    require(type(rows) is list and len(rows) == len(SPECS), "incomplete document matrix")
    seen = set()
    for row in rows:
        require(type(row) is dict and row.get("id") in SPECS, "unknown document")
        name = row["id"]
        require(name not in seen, "duplicate document: "+name)
        seen.add(name)
        spec = SPECS[name]
        for key in ("file", "kind", "format", "text_mode"):
            require(row.get(key) == spec[key], name+": incorrect "+key)
        require(type(row.get("pages")) is int and row["pages"] == spec["pages"], name+": page count")
        require(type(row.get("authoring_calls")) is int and row["authoring_calls"] == spec["pages"],
                name+": authoring must run once per page")
        for key in ("width_points", "height_points"):
            require(finite(row.get(key)) and abs(row[key]-spec[key]) <= 1e-4, name+": incorrect physical size")
        require(type(row.get("raster_callback_calls")) is int and row["raster_callback_calls"] ==
                (1 if spec["kind"] == "mixed" else 0), name+": raster callback was skipped/retried")
        reports = row.get("dc_reports")
        require(type(reports) is list and len(reports) == spec["pages"], name+": missing DC reports")
        for r in reports:
            require(type(r) is dict and type(r.get("schema")) is int and r["schema"] == 1
                    and r.get("stage") == "0.63" and r.get("backend") == spec["format"]
                    and r.get("dc_expired") is True, name+": incomplete DC scope")
            require(exact(r.get("command_count"), 1) and r.get("text_mode") == spec["text_mode"],
                    name+": command/text-mode mismatch")
            groups = r.get("groups")
            require(type(groups) is list and groups, name+": missing output-group accounting")
            for g in groups:
                require(type(g) is dict and g.get("strategy") in ("native", "raster"), name+": rejected group")
                if g["strategy"] == "raster":
                    ps = g.get("pixel_size")
                    require(type(ps) is list and len(ps) == 2 and all(exact(n, 1) for n in ps),
                            name+": raster group lacks pixel bounds")
            for field, strategy in (("native_groups", "native"), ("raster_groups", "raster")):
                require(type(r.get(field)) is int and r[field] == sum(g["strategy"] == strategy for g in groups),
                        name+": incorrect group counts")
        require(row.get("audit_policy") == "error",
                name+": document worker did not request strict output audit")
        audit = row.get("audit")
        require(type(audit) is dict and audit.get("backend") == spec["format"]
                and audit.get("mode") == "export" and audit.get("blocking") is False
                and type(audit.get("pages")) is int and audit["pages"] == spec["pages"],
                name+": strict output audit did not pass")
        if spec["kind"] in ("vector", "units", "links"):
            require(all(r["raster_groups"] == 0 for r in reports), name+": unexpected fallback")
        if spec["kind"] == "mixed":
            groups = [g for r in reports for g in r["groups"]]
            require(any(g.get("label") == "copy-island-64x32" and g["strategy"] == "raster"
                        and g.get("pixel_size") == [128, 64] for g in groups), name+": missing bounded copy island")
        layout = row.get("layout")
        require(type(layout) is dict, name+": missing layout")
        if spec["kind"] == "plot":
            lo, hi = layout.get("lower_left"), layout.get("upper_right")
            require(type(lo) is list and type(hi) is list and len(lo) == len(hi) == 2
                    and all(finite(x) for x in lo+hi) and lo[0] < hi[0] and lo[1] > hi[1], name+": plot layout")
    return rows


def inspect_pdf(path: Path) -> dict:
    from pypdf import PdfReader
    from pypdf.generic import ContentStream
    reader = PdfReader(str(path), strict=True)
    require(not reader.is_encrypted, "unexpected encrypted PDF")
    images, uris, destinations, operators = [], [], [], []
    boxes, texts = [], []
    visited = set()
    def deref(value):
        return value.get_object() if hasattr(value, "get_object") else value
    def walk(stream, resources, depth=0):
        require(depth < 40, "recursive PDF Form depth")
        if stream is None:
            return
        resources = deref(resources)
        for operands, operator in ContentStream(stream, reader).operations:
            operators.append(operator.decode("ascii", errors="strict"))
            if operator != b"Do":
                continue
            reference = deref(resources.get("/XObject", {})).get(operands[0])
            require(reference is not None, "unresolved PDF XObject")
            key = (getattr(reference, "idnum", None), getattr(reference, "generation", None))
            obj = reference.get_object()
            if key[0] is not None:
                if key in visited:
                    continue
                visited.add(key)
            if obj.get("/Subtype") == "/Image":
                images.append([int(obj["/Width"]), int(obj["/Height"])])
            elif obj.get("/Subtype") == "/Form":
                walk(obj, obj.get("/Resources", resources), depth+1)
    for page in reader.pages:
        box = page.mediabox
        boxes.append([float(box.width), float(box.height)])
        texts.append(page.extract_text() or "")
        walk(page.get_contents(), page.get("/Resources", {}))
        for ref in page.get("/Annots", []):
            ann = ref.get_object()
            action = deref(ann.get("/A", {}))
            if action.get("/S") == "/URI":
                uris.append(str(action.get("/URI")))
            if "/Dest" in ann:
                destinations.append(str(ann["/Dest"]))
            if action.get("/S") == "/GoTo":
                destinations.append(str(action.get("/D")))
    return dict(pages=len(reader.pages), boxes=boxes, image_sizes=images,
                geometry=sum(op in ("m", "l", "c", "re") for op in operators),
                text_operations=sum(op in ("Tj", "TJ", "'", '"') for op in operators),
                text="\n".join(texts), uris=uris, destinations=destinations,
                named_destinations=list(reader.named_destinations),
                gradient_operations=operators.count("sh"),
                pdfa_certified=False)


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def dimension(value: str) -> float:
    match = re.fullmatch(r"\s*([0-9.+eE-]+)(?:pt|px)?\s*", value or "")
    require(match is not None, "SVG dimension is not in point-compatible units")
    n = float(match[1])
    require(math.isfinite(n) and n > 0, "invalid SVG dimension")
    return n


def inspect_svg(path: Path) -> dict:
    from PIL import Image
    content = path.read_bytes()
    require(b"<!ENTITY" not in content.upper(), "SVG entities are not accepted")
    root = ET.fromstring(content)
    require(local(root.tag) == "svg", "not an SVG document")
    shapes, texts, links, views, gradients, images = 0, [], [], [], 0, []
    for elem in root.iter():
        tag = local(elem.tag)
        shapes += tag in ("path", "rect", "circle", "ellipse", "line", "polyline", "polygon")
        if tag == "text":
            texts.append("".join(elem.itertext()))
        if tag == "a":
            links.append(elem.get("href", elem.get("{http://www.w3.org/1999/xlink}href", "")))
        if tag == "view":
            views.append(elem.get("id", ""))
        gradients += tag == "linearGradient"
        if tag == "image":
            data = elem.get("href", elem.get("{http://www.w3.org/1999/xlink}href", ""))
            require(data.startswith("data:image/png;base64,"), "external/non-PNG SVG image")
            pixels = base64.b64decode(data.split(",", 1)[1], validate=True)
            with Image.open(io.BytesIO(pixels)) as image:
                require(image.format == "PNG", "embedded image is not PNG")
                image.verify()
                images.append(list(image.size))
    return dict(pages=1, boxes=[[dimension(root.get("width")), dimension(root.get("height"))]],
                geometry=shapes, text_operations=len(texts), text="\n".join(texts),
                image_sizes=images, uris=[s for s in links if not s.startswith("#")],
                destinations=[s for s in links if s.startswith("#")], named_destinations=views,
                gradient_operations=gradients, pdfa_certified=False)


def inspect_document(path: Path, row: dict) -> dict:
    summary = inspect_pdf(path) if row["format"] == "pdf" else inspect_svg(path)
    name, kind = row["id"], row["kind"]
    require(summary["pages"] == row["pages"], name+": serialized page count mismatch")
    for box in summary["boxes"]:
        require(all(abs(a-b) <= .01 for a, b in zip(box, (row["width_points"], row["height_points"]))),
                name+": serialized physical size mismatch")
    require(summary["geometry"] > 0, name+": no serialized vector geometry")
    images = summary["image_sizes"]
    if kind in ("vector", "units", "links"):
        require(not images, name+": unexpected raster flattening")
    if kind == "vector":
        if row["format"] == "svg":
            require(summary["gradient_operations"] > 0, name+": linear gradient lost")
    if kind == "mixed":
        require(len(images) >= 2 and [128, 64] in images, name+": bounded raster copy/alpha absent")
    if kind in ("styles", "pict"):
        require(bool(images), name+": expected embedded bitmap/fallback absent")
    if row["text_mode"] == "outline":
        require(summary["text_operations"] == 0, name+": outline mode emitted text")
    elif kind in ("vector", "mixed", "links"):
        require(summary["text_operations"] > 0 and TEXT in re.sub(r"\s+", "", summary["text"]),
                name+": native text was lost or cannot be extracted")
    elif row["text_mode"] == "native" and kind in ("pict", "plot"):
        require(summary["text_operations"] > 0 and "Skia" in summary["text"], name+": native consumer text missing")
    if kind == "links":
        require(URI in summary["uris"], name+": URL link missing")
        require(any(DEST in s for s in summary["named_destinations"]), name+": named destination missing")
        require(any(DEST in s for s in summary["destinations"]), name+": destination reference missing")
    summary["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    summary["file"] = path.name
    return summary


def inspect_pixels(path: Path, row: dict) -> dict:
    from PIL import Image
    with Image.open(path) as original:
        image = original.convert("RGBA")
    expected = (math.ceil(row["width_points"]*2), math.ceil(row["height_points"]*2))
    require(image.size == expected, row["id"]+": renderer returned wrong dimensions")
    sx, sy = image.width/row["width_points"], image.height/row["height_points"]
    def at(x, y):
        return image.getpixel((min(image.width-1, int(x*sx)), min(image.height-1, int(y*sy))))
    def near(x, y, rgba, tolerance=4):
        value = at(x, y)
        require(all(abs(a-b) <= tolerance for a, b in zip(value, rgba)),
                f'{row["id"]}: expected {rgba} at logical {x},{y}; got {value}')
    def ink(box, pred, minimum=8):
        x0, y0, x1, y1 = box
        count = sum(pred(image.getpixel((x, y))) for y in range(int(y0*sy), min(image.height, int(y1*sy)))
                    for x in range(int(x0*sx), min(image.width, int(x1*sx))))
        require(count >= minimum, row["id"]+": expected ink missing in "+str(box))
    blue = lambda p: p[2] > 160 and p[0] < 100 and p[1] < 100 and p[3] > 240
    red = lambda p: p[0] > 160 and p[1] < 100 and p[2] < 100 and p[3] > 240
    black = lambda p: max(p[:3]) < 150 and p[3] > 240
    kind = row["kind"]
    if kind in ("vector", "mixed", "links"):
        near(12, 12, (255, 0, 0, 255))
        ink((8, 40, 96, 68), black)
    if kind == "vector":
        near(70, 17, (0, 0, 255, 255)); near(110, 14, (0, 255, 0, 255))
        near(130, 14, (255, 255, 255, 255))
        require(red(at(12, 88)) and blue(at(52, 88)), row["id"]+": gradient endpoints wrong")
    elif kind == "mixed":
        near(16, 80, (255, 128, 128, 255)); near(36, 80, (128, 128, 255, 255))
        near(115, 80, (255, 0, 0, 255)); near(130, 80, (0, 0, 255, 255))
        near(173, 80, (255, 255, 255, 255))
    elif kind == "units":
        near(4, 4, (255, 0, 0, 255)); near(30, 15, (255, 255, 255, 255))
    elif kind == "styles":
        require(red(at(2, 8)) and blue(at(14, 8)), row["id"]+": style gradient wrong")
        ink((16, 0, 32, 16), red); ink((16, 0, 32, 16), blue)
    elif kind == "pict":
        near(24, 24, (255, 0, 0, 255)); near(18, 72, (255, 128, 128, 255))
        near(36, 72, (128, 128, 255, 255)); near(164, 16, (20, 180, 60, 255))
        ink((12, 126, 165, 172), lambda p: p[0] < 160 and p[1] < 160 and p[2] > p[0]+20)
    elif kind == "plot":
        lo, hi = row["layout"]["lower_left"], row["layout"]["upper_right"]
        for x, y, predicate in ((-1.5, -.75, blue), (-.5, -.25, blue), (.5, .25, blue),
                                 (1.5, .75, blue), (-1, 1, red), (1, -1, red)):
            px, py = lo[0]+(x+2)/4*(hi[0]-lo[0]), lo[1]+(y+1.5)/3*(hi[1]-lo[1])
            ink((max(0, px-3), max(0, py-3), px+3, py+3), predicate, 1)
        ink((0, 0, 320, 50), black)
    return dict(file=path.name, size=list(image.size), semantic_pixels_passed=True,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def write_review(directory: Path, rows: list[dict], results: list[dict]) -> None:
    body = ["<!doctype html><meta charset=utf-8><title>DC output 0.63 review</title>",
            "<h1>DC output 0.63</h1><p>Native documents and independent renderer captures. "
            "No PDF/A, color-fidelity or physical-display certification.</p>"]
    for row, result in zip(rows, results):
        name = html.escape(row["file"], quote=True)
        body.append(f'<section><h2>{html.escape(row["id"])}</h2><a href="{name}">Native document</a>')
        if "render" in result:
            body.append(f'<p><img style="max-width:100%" src="{html.escape(result["render"]["file"], quote=True)}"></p>')
        body.append("<pre>"+html.escape(json.dumps(result, indent=2))+"</pre></section>")
    (directory/"review.html").write_text("\n".join(body), encoding="utf-8")
