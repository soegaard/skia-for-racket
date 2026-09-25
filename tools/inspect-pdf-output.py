#!/usr/bin/env python3
"""Optional structural inspection of generated PDFs (development dependency: pypdf).

This does not render the PDF or establish visual fidelity. In --probe mode it
checks the three-page example's media boxes and that page 1 remains vector/text.
"""
from __future__ import annotations
import argparse
from collections import Counter
import json
from pathlib import Path
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path)
    parser.add_argument("--probe", action="store_true", help="Check examples/pdf-documents.rkt output")
    args = parser.parse_args()
    try:
        from pypdf import PdfReader
        from pypdf.generic import ContentStream
    except ImportError:
        print("This optional inspector needs pypdf: python3 -m pip install pypdf", file=sys.stderr)
        return 2

    def obj(value):
        return value.get_object() if hasattr(value, "get_object") else value

    try:
        reader = PdfReader(str(args.pdf), strict=True)
        if reader.is_encrypted:
            raise ValueError("Expected an unencrypted generated PDF")
        report = {"file": str(args.pdf), "metadata": dict(reader.metadata or {}), "pages": []}
        for number, page in enumerate(reader.pages, 1):
            seen_streams: set[int] = set()
            seen_images: set[int] = set()
            seen_fonts: set[int] = set()
            fonts = []
            operators: Counter[str] = Counter()

            def visit(stream, resources):
                stream, resources = obj(stream), obj(resources) or {}
                if stream is None or id(stream) in seen_streams:
                    return
                seen_streams.add(id(stream))
                for _, operator in ContentStream(stream, reader).operations:
                    operators[operator.decode("ascii", errors="replace")] += 1
                for font_ref in (obj(resources.get("/Font")) or {}).values():
                    font = obj(font_ref)
                    if id(font) in seen_fonts:
                        continue
                    seen_fonts.add(id(font))
                    descendants = obj(font.get("/DescendantFonts")) or [font]
                    embedded = str(font.get("/Subtype")) == "/Type3"
                    for descendant in descendants:
                        desc = obj(obj(descendant).get("/FontDescriptor")) or {}
                        embedded |= any(k in desc for k in ("/FontFile", "/FontFile2", "/FontFile3"))
                    fonts.append({"name": str(font.get("/BaseFont", "")),
                                  "subtype": str(font.get("/Subtype", "")), "embedded": embedded})
                for xref in (obj(resources.get("/XObject")) or {}).values():
                    x = obj(xref)
                    if x.get("/Subtype") == "/Image":
                        seen_images.add(id(x))
                    elif x.get("/Subtype") == "/Form":
                        visit(x, x.get("/Resources") or resources)

            visit(page.get_contents(), page.get("/Resources"))
            report["pages"].append({
                "page": number,
                "width_points": float(page.mediabox.width),
                "height_points": float(page.mediabox.height),
                "fonts": fonts,
                "image_xobjects": len(seen_images),
                "path_operators": sum(operators[k] for k in ("m", "l", "c", "v", "y", "re", "h")),
                "text_operators": sum(operators[k] for k in ("Tj", "TJ", "'", '"')),
                "text_preview": (page.extract_text() or "")[:180],
            })
        if args.probe:
            expected = [(612, 792), (792, 612), (480, 480)]
            pages = report["pages"]
            if len(pages) != len(expected):
                raise ValueError(f"Expected three pages, found {len(pages)}")
            for page, (w, h) in zip(pages, expected):
                if abs(page["width_points"] - w) > .01 or abs(page["height_points"] - h) > .01:
                    raise ValueError(f"Unexpected media box on page {page['page']}")
            first = pages[0]
            if first["image_xobjects"] or not first["path_operators"] or not first["text_operators"]:
                raise ValueError("Page 1 must contain vector paths and text, not a flattened page image")
            if pages[1]["image_xobjects"] < 1:
                raise ValueError("Page 2 must contain the explicit embedded image")
            report["probe_structure"] = "passed"
        print(json.dumps(report, ensure_ascii=False, indent=2, default=str))
        return 0
    except Exception as exc:
        print(f"PDF inspection failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
