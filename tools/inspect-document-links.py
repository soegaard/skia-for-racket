#!/usr/bin/env python3
"""Inspect generated links without following them. PDF checks need pypdf.

Synthetic self-tests validate this inspector, not the Racket/native backend.
The inspector does not certify PDF/A, accessibility, or viewer interoperability.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import struct
import unittest
from html.parser import HTMLParser
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET

SVG = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"
LIMIT = 256 * 1024 * 1024
STEMS = ("links", "transforms", "destinations")
COUNTS = (4, 5, 4)
VIEW_COUNTS = (2, 1, 2)
HEADINGS = ("A drawing can also be a document", "Links follow canvas coordinates", "Names, not page-number guesses")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def bounded_bytes(path: Path) -> bytes:
    require(path.stat().st_size <= LIMIT, f"file exceeds inspector limit: {path}")
    return path.read_bytes()


def dest_id(name: str) -> str:
    return "dest-" + name.encode("utf-8").hex()


def floats(s: str) -> list[float]:
    result = [float(n) for n in s.replace(",", " ").split()]
    require(all(math.isfinite(n) for n in result), "nonfinite SVG number")
    return result


def near(actual: list[float], expected: list[float], label: str) -> None:
    require(len(actual) == len(expected) and all(abs(a-b) <= .02 for a, b in zip(actual, expected)),
            f"{label}: expected {expected}, got {actual}")


def rect_values(element: ET.Element) -> list[float]:
    values = [float(element.get(k, "0")) for k in ("x", "y", "width", "height")]
    require(all(math.isfinite(n) for n in values), "nonfinite link rectangle")
    require(values[2] > 0 and values[3] > 0, "empty or negative link rectangle")
    return values


def inspect_svg(data: bytes, count: int | None = None, views: int | None = None) -> dict:
    require(len(data) <= LIMIT, "SVG exceeds inspector limit")
    require(b"<!DOCTYPE" not in data and b"<!ENTITY" not in data, "unexpected XML DTD/entity")
    root = ET.fromstring(data)
    require(root.tag == f"{{{SVG}}}svg", "missing SVG root namespace")
    require(floats(root.get("viewBox", "")) == [0, 0, 720, 500], "wrong root viewBox")
    for key, expected in (("width", 720), ("height", 500)):
        require(root.get(key, "").endswith("pt"), "shared SVG dimensions must have pt units")
        require(float(root.attrib[key][:-2]) == expected, "wrong physical page size")
    parents = {child: parent for parent in root.iter() for child in parent}
    ids: dict[str, ET.Element] = {}
    for element in root.iter():
        tag = element.tag.rsplit("}", 1)[-1]
        require(tag not in {"script", "foreignObject", "image"}, f"unexpected {tag} in vector-link probe")
        require(not any(k.lower().startswith("on") for k in element.attrib), "unexpected SVG event handler")
        if "id" in element.attrib:
            name = element.attrib["id"]
            require(name not in ids, f"duplicate SVG ID: {name}")
            ids[name] = element
    for element in root.iter():
        for key, value in element.attrib.items():
            if key in {"href", f"{{{XLINK}}}href"}:
                continue
            for target in re.findall(r"url\(#([^)]*)\)", value):
                require(target in ids, f"unresolved graphics reference: {target}")
    found = []
    for a in root.iter(f"{{{SVG}}}a"):
        require(parents.get(a) is root, "annotation is still nested in a graphics group")
        require("transform" not in a.attrib and "clip-path" not in a.attrib, "annotation transformed/clipped twice")
        href = a.get("href")
        require(bool(href), "missing SVG 2 href")
        require(a.get(f"{{{XLINK}}}href") == href, "href and xlink:href disagree")
        require(not href.startswith("urn:racket-skia:"), "unresolved internal placeholder")
        rects = list(a.findall(f"{{{SVG}}}rect"))
        require(len(rects) == 1 and len(list(a)) == 1, "annotation must have one rectangle")
        rectangle = rects[0]
        require("transform" not in rectangle.attrib, "link rectangle transformed twice")
        require(float(rectangle.get("fill-opacity", "1")) == 0, "annotation changes visible artwork")
        box = rect_values(rectangle)
        if href.startswith("#"):
            require(href[1:] in ids and ids[href[1:]].tag == f"{{{SVG}}}view", "unresolved SVG destination view")
        else:
            scheme = urlsplit(href).scheme.lower()
            require(scheme in {"", "http", "https", "mailto"}, f"unexpected URI scheme: {scheme}")
        found.append({"href": href, "rect": box})
    named = {e.attrib["id"]: floats(e.get("viewBox", "")) for e in root.findall(f"{{{SVG}}}view")}
    for name, values in named.items():
        require(len(values) == 4 and values[2:] == [720, 500], f"wrong destination extent: {name}")
    if count is not None:
        require(len(found) == count, f"expected {count} links, got {len(found)}")
    if views is not None:
        require(len(named) == views, f"expected {views} destination views, got {len(named)}")
    require(len(list(root.iter(f"{{{SVG}}}text"))) == 0, "probe SVG labels should be outlines")
    return {"links": found, "views": named, "embedded_images": 0}


class ReviewHTML(HTMLParser):
    def __init__(self):
        super().__init__()
        self.objects = []
        self.image_svgs = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "object" and attrs.get("type") == "image/svg+xml":
            self.objects.append(attrs.get("data"))
        if tag == "img" and attrs.get("src", "").endswith(".svg"):
            self.image_svgs.append(attrs["src"])


def inspect_probe(prefix: Path) -> dict:
    svg = {}
    for stem, count, views in zip(STEMS, COUNTS, VIEW_COUNTS):
        svg[stem] = inspect_svg(bounded_bytes(Path(f"{prefix}.{stem}.svg")), count, views)
        png = bounded_bytes(Path(f"{prefix}.{stem}.reference.png"))
        require(png.startswith(b"\x89PNG\r\n\x1a\n") and len(png) >= 24, "missing raster reference")
        require(struct.unpack(">II", png[16:24]) == (1440, 1000), "wrong reference raster dimensions")
    near(svg["links"]["links"][0]["rect"], [24, 102, 302, 44], "first URL rectangle")
    near(svg["links"]["links"][1]["rect"], [360, 102, 312, 44], "same-page link rectangle")
    near(svg["transforms"]["links"][1]["rect"], [378, 140, 190, 54], "clipped link")
    near(svg["transforms"]["links"][2]["rect"], [34, 296, 150, 52], "recorded URL")
    near(svg["transforms"]["links"][3]["rect"], [234, 284, 225, 78], "scaled recorded URL")
    angle = math.radians(20)
    w = 140 * math.cos(angle) + 44 * math.sin(angle)
    h = 140 * math.sin(angle) + 44 * math.cos(angle)
    near(svg["transforms"]["links"][0]["rect"], [154-w/2, 164-h/2, w, h], "rotated URL bounds")
    near(svg["links"]["views"]["links-" + dest_id("overview-note")], [24, 309, 720, 500], "note view")
    near(svg["destinations"]["views"]["destinations-" + dest_id("α-section")], [24, 266, 720, 500], "Unicode view")
    for result in svg.values():
        for link in result["links"]:
            uri = urlsplit(link["href"])
            if not uri.scheme and uri.path:
                filename = unquote(uri.path)
                require(Path(filename).name == filename, "probe should link only to sibling files")
                target = prefix.parent / filename
                require(target.is_file(), f"missing companion link target: {target}")
                if target.suffix == ".svg":
                    root = ET.fromstring(bounded_bytes(target))
                    require(uri.fragment in {e.get("id") for e in root.iter()}, "cross-SVG fragment not found")
                elif target.suffix == ".html":
                    require(uri.fragment == "note" and b'id="note"' in bounded_bytes(target), "HTML target missing")
    review = ReviewHTML()
    review.feed(bounded_bytes(Path(f"{prefix}.review.html")).decode("utf-8"))
    require(len(review.objects) == 3 and not review.image_svgs, "review must embed interactive SVG documents with object")
    require("&two=2" in svg["destinations"]["links"][2]["href"], "URI ampersand was not preserved")
    return {"svg": svg, "review": "3 interactive object elements; all relative targets resolve"}


def inspect_pdf(path: Path) -> dict:
    try:
        from pypdf import PdfReader
        from pypdf.generic import NameObject
    except ImportError as exc:
        raise SystemExit("--pdf requires pypdf; no PDF check was performed") from exc
    reader = PdfReader(path)
    require(len(reader.pages) == 3, "expected a three-page PDF")
    # Skia m119 writes the catalog /Dests dictionary and /Dest name objects,
    # not a /Names tree of text-string keys. pypdf exposes the leading slash
    # for NameObject values. Accept both representations without changing IDs.
    def destination_name(value):
        return str(value)[1:] if isinstance(value, NameObject) else str(value)
    raw_names = reader.named_destinations
    names = {destination_name(k): v for k, v in raw_names.items()}
    require(len(names) == len(raw_names), "ambiguous normalized PDF destination names")
    expected_names = {dest_id(n): page for n, page in
                      (("overview", 0), ("overview-note", 0), ("transformed", 1), ("details", 2), ("α-section", 2))}
    require(set(names) == set(expected_names), f"wrong PDF destination names: {list(names)}")
    for name, page in expected_names.items():
        require(reader.get_destination_page_number(names[name]) == page, f"wrong destination page: {name}")
    pages = []
    for i, (p, count) in enumerate(zip(reader.pages, COUNTS)):
        near([float(p.mediabox.width), float(p.mediabox.height)], [720, 500], "PDF media box")
        require(HEADINGS[i] in (p.extract_text() or ""), "missing extractable PDF heading")
        annots = [a.get_object() for a in p.get("/Annots", [])]
        require(len(annots) == count, f"wrong PDF link count on page {i+1}")
        links = []
        for a in annots:
            require(a.get("/Subtype") == "/Link", "unexpected PDF annotation subtype")
            r = [float(n) for n in a["/Rect"]]
            require(len(r) == 4 and all(math.isfinite(n) for n in r), "bad PDF annotation rectangle")
            box = [r[0], 500-r[3], r[2]-r[0], r[3]-r[1]]
            require(box[2] > 0 and box[3] > 0, "empty PDF link")
            if "/A" in a:
                action = a["/A"].get_object()
                require(action.get("/S") == "/URI", "unexpected PDF action")
                target = str(action["/URI"])
                require(urlsplit(target).scheme.lower() in {"", "http", "https", "mailto"}, "unexpected PDF URI scheme")
                kind = "URI"
            else:
                target = destination_name(a.get("/Dest", ""))
                require(target in names, f"unresolved PDF named link: {target}")
                kind = "destination"
            links.append({"kind": kind, "target": target, "rect_top_left": box})
        pages.append(links)
    near(pages[0][0]["rect_top_left"], [24, 102, 302, 44], "PDF first URL")
    near(pages[1][1]["rect_top_left"], [378, 140, 190, 54], "PDF clipped link")
    near(pages[1][3]["rect_top_left"], [234, 284, 225, 78], "PDF scaled recorded URL")
    require([sum(x["kind"] == "URI" for x in p) for p in pages] == [2, 4, 1], "unexpected PDF link kinds")
    require(pages[0][2]["target"] == dest_id("details"), "forward page link is wrong")
    require("&two=2" in pages[2][2]["target"], "PDF URI ampersand was not preserved")
    return {"pages": pages, "destination_pages": {k: v+1 for k, v in expected_names.items()},
            "viewer_clicks": "NOT PERFORMED by structural inspector"}


def synthetic_svg(href: str = "https://example.invalid/?a=1&amp;b=2") -> bytes:
    return (f'<svg xmlns="{SVG}" xmlns:xlink="{XLINK}" width="720pt" height="500pt" viewBox="0 0 720 500">'
            f'<view id="x" viewBox="2 3 720 500"/><a href="{href}" xlink:href="{href}">'
            '<rect x="24" y="102" width="302" height="44" fill-opacity="0"/></a></svg>').encode()


class Checks(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(inspect_svg(synthetic_svg(), 1, 1)["links"][0]["rect"], [24, 102, 302, 44])
    def test_ampersand(self):
        self.assertIn("&b=2", inspect_svg(synthetic_svg())["links"][0]["href"])
    def test_local_view(self):
        self.assertEqual(inspect_svg(synthetic_svg("#x"))["links"][0]["href"], "#x")
    def test_dangling_view(self):
        with self.assertRaises(ValueError): inspect_svg(synthetic_svg("#missing"))
    def test_duplicate_id(self):
        with self.assertRaises(ValueError): inspect_svg(synthetic_svg().replace(b"</svg>", b'<g id="x"/></svg>'))
    def test_stale_clip_group(self):
        with self.assertRaises(ValueError): inspect_svg(synthetic_svg().replace(b"<a ", b"<g><a ").replace(b"</a>", b"</a></g>"))
    def test_href_mismatch(self):
        with self.assertRaises(ValueError): inspect_svg(synthetic_svg("#x").replace(b'xlink:href="#x"', b'xlink:href="#other"'))
    def test_opaque_annotation(self):
        with self.assertRaises(ValueError): inspect_svg(synthetic_svg().replace(b'fill-opacity="0"', b'fill-opacity="1"'))
    def test_negative_width(self):
        with self.assertRaises(ValueError): inspect_svg(synthetic_svg().replace(b'width="302"', b'width="-2"'))
    def test_repeated_transform(self):
        with self.assertRaises(ValueError): inspect_svg(synthetic_svg().replace(b"<a ", b'<a transform="translate(5 5)" '))
    def test_active_scheme(self):
        with self.assertRaises(ValueError): inspect_svg(synthetic_svg("javascript:alert(1)"))
    def test_rasterized_page(self):
        with self.assertRaises(ValueError): inspect_svg(synthetic_svg().replace(b"</svg>", b'<image href="x.png"/></svg>'))
    def test_ids(self):
        self.assertEqual(dest_id("intro"), "dest-696e74726f")
        self.assertEqual(dest_id("α"), "dest-ceb1")
    def test_interactive_review(self):
        p = ReviewHTML(); p.feed('<object type="image/svg+xml" data="x.svg"></object><img src="x.png">')
        self.assertEqual(p.objects, ["x.svg"]); self.assertEqual(p.image_svgs, [])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--probe-prefix", type=Path)
    parser.add_argument("--pdf", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Checks))
        if not result.wasSuccessful(): raise SystemExit(1)
    if args.probe_prefix:
        result = inspect_probe(args.probe_prefix)
        result["pdf"] = inspect_pdf(Path(f"{args.probe_prefix}.pdf")) if args.pdf else "NOT CHECKED (use --pdf)"
        result["visual_review"] = "NOT PERFORMED by structural inspector"
        print(json.dumps(result, indent=2, ensure_ascii=False))
    elif args.pdf:
        parser.error("--pdf requires --probe-prefix")
    elif not args.self_test:
        parser.error("select --self-test or --probe-prefix")


if __name__ == "__main__":
    main()
