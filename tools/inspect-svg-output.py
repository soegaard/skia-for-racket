#!/usr/bin/env python3
"""Inspect exported SVG structure without a browser or third-party packages.

This parses SVG; it does not render it or prove pixel equivalence to Skia.
Open the probe's .review.html for an actual browser rendering comparison.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter
import json
from pathlib import Path
import re
import struct
import sys
import tempfile
import xml.etree.ElementTree as ET
import zlib

SVG = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"
DEFAULT_LIMIT = 256 * 1024 * 1024
PROBES = {
    "vectors": (720, 520, 0),
    "text-images": (800, 540, 1),
    "effects": (720, 480, 2),
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def inspect(path: Path, *, probe: str | None = None,
            max_bytes: int = DEFAULT_LIMIT) -> dict:
    require(path.stat().st_size <= max_bytes, "input exceeds the inspector byte limit")
    data = path.read_bytes()
    require(b"<!DOCTYPE" not in data.upper(), "DOCTYPE is not expected in Skia output")
    root = ET.fromstring(data)
    require(root.tag == f"{{{SVG}}}svg", "root is not a namespaced SVG element")
    width = float(root.attrib["width"])
    height = float(root.attrib["height"])
    viewbox = [float(v) for v in root.attrib["viewBox"].replace(",", " ").split()]
    require(0 < width <= 32768 and 0 < height <= 32768, "invalid viewport dimensions")
    require(viewbox == [0.0, 0.0, width, height], "viewBox does not match the logical viewport")

    counts: Counter[str] = Counter()
    ids: set[str] = set()
    references: list[str] = []
    images: list[dict] = []
    families: set[str] = set()
    text_samples: list[str] = []
    for elem in root.iter():
        name = elem.tag.rsplit("}", 1)[-1]
        counts[name] += 1
        identifier = elem.attrib.get("id")
        if identifier is not None:
            require(identifier not in ids, f"duplicate ID: {identifier}")
            ids.add(identifier)
        for key, value in elem.attrib.items():
            references.extend(re.findall(r"url\(#([^)]*)\)", value))
            if key in ("href", f"{{{XLINK}}}href") and value.startswith("#"):
                references.append(value[1:])
        if "font-family" in elem.attrib:
            families.add(elem.attrib["font-family"])
        if name == "text":
            text_samples.append("".join(elem.itertext())[:160])
        if name == "image":
            uri = elem.attrib.get(f"{{{XLINK}}}href", elem.attrib.get("href", ""))
            match = re.fullmatch(r"data:image/(png|jpeg);base64,([A-Za-z0-9+/=\r\n]+)", uri)
            require(match is not None, "image is not an embedded PNG/JPEG data URI")
            assert match is not None
            encoded = re.sub(r"[\r\n]", "", match.group(2))
            image = base64.b64decode(encoded, validate=True)
            report = {"format": match.group(1), "encoded_bytes": len(image)}
            if match.group(1) == "png":
                require(image[:8] == b"\x89PNG\r\n\x1a\n" and len(image) >= 24,
                        "embedded PNG has an invalid signature/header")
                require(image[12:16] == b"IHDR", "PNG has no leading IHDR")
                w, h = struct.unpack(">II", image[16:24])
                require(w > 0 and h > 0, "invalid embedded PNG dimensions")
                report.update(width=w, height=h)
            else:
                require(image.startswith(b"\xff\xd8\xff"), "embedded JPEG has an invalid signature")
            images.append(report)
    missing = set(references) - ids
    require(not missing, f"unresolved references: {sorted(missing)}")
    title = root.findtext(f"{{{SVG}}}title", default="")
    description = root.findtext(f"{{{SVG}}}desc", default="")
    if probe:
        w, h, nimages = PROBES[probe]
        require((width, height) == (w, h), f"wrong dimensions for {probe}")
        require(len(images) == nimages, f"expected {nimages} embedded images, got {len(images)}")
        require(counts["path"] > 0, "expected outline/vector paths")
        require(bool(title) and bool(description), "expected title and description metadata")
        require(all(i.startswith(f"probe-{probe}-") for i in ids), "unexpected resource ID prefix")
        if probe == "vectors":
            require(counts["linearGradient"] > 0, "linear gradient was not kept as a paint server")
            require(counts["clipPath"] > 0, "intersect clipping was not serialized")
            require(counts["text"] == 0, "the vector-only probe should use outlined labels")
        elif probe == "text-images":
            require(counts["text"] > 0, "native text sample did not remain text")
            require(bool(families), "native text has no family declaration")
        elif probe == "effects":
            require(counts["text"] == 0, "effect-page labels should be outlines")
            require(all(i.get("width") == 610 and i.get("height") == 440 for i in images),
                    "2x rasterized groups have unexpected embedded pixel dimensions")
    return {
        "file": str(path), "bytes": len(data), "viewport": [width, height], "viewBox": viewbox,
        "title": title, "description": description, "elements": dict(sorted(counts.items())),
        "resource_ids": len(ids), "resolved_references": len(references),
        "embedded_images": images, "font_families_needed_by_text": sorted(families),
        "text_samples": text_samples[:8], "probe": probe,
        "structural_validation": "passed", "visual_rendering": "NOT PERFORMED",
    }


def self_test() -> None:
    """Exercise the inspector with synthetic fixtures, not native Skia output."""
    def png_chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

    png = (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
           + png_chunk(b"IDAT", zlib.compress(b"\0\xff\0\0\xff")) + png_chunk(b"IEND", b""))
    uri = "data:image/png;base64," + base64.b64encode(png).decode("ascii")
    good = (f'<svg xmlns="{SVG}" xmlns:xlink="{XLINK}" width="10.5" height="20" viewBox="0 0 10.5 20">'
            '<title>A &amp; B</title><desc>Synthetic inspector test</desc>'
            '<defs><clipPath id="c"><rect width="10" height="10"/></clipPath></defs>'
            f'<image id="i" xlink:href="{uri}"/><use xlink:href="#i" clip-path="url(#c)"/></svg>')
    with tempfile.TemporaryDirectory(prefix="skia-svg-inspector-") as directory:
        path = Path(directory) / "test.svg"
        path.write_text(good, encoding="utf-8")
        result = inspect(path)
        assert result["title"] == "A & B"
        assert result["embedded_images"][0]["width"] == 1
        checks = 1
        for bad in [good.replace('href="#i"', 'href="#missing"'),
                    good.replace('id="i"', 'id="c"'), good.replace('0 0 10.5 20', '0 0 10 20'),
                    good.replace(uri, "https://example.invalid/image.png"),
                    good.removesuffix("</svg>")]:
            path.write_text(bad, encoding="utf-8")
            try:
                inspect(path)
            except (ValueError, ET.ParseError):
                checks += 1
            else:
                raise AssertionError("malformed synthetic fixture was accepted")
    print(f"SVG inspector self-tests passed: {checks} synthetic fixtures; native output NOT tested.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", type=Path, nargs="*")
    parser.add_argument("--probe-prefix", type=Path,
                        help="inspect PREFIX.vectors.svg, PREFIX.text-images.svg, and PREFIX.effects.svg")
    parser.add_argument("--max-input-bytes", type=int, default=DEFAULT_LIMIT)
    parser.add_argument("--self-test", action="store_true", help="run synthetic inspector checks")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    if args.max_input_bytes <= 0:
        parser.error("--max-input-bytes must be positive")
    inputs = [(p, None) for p in args.files]
    if args.probe_prefix is not None:
        inputs.extend((Path(str(args.probe_prefix) + f".{name}.svg"), name) for name in PROBES)
    if not inputs and not args.self_test:
        parser.error("supply SVG files or --probe-prefix")
    try:
        reports = [inspect(path, probe=probe, max_bytes=args.max_input_bytes) for path, probe in inputs]
    except (OSError, ValueError, KeyError, ET.ParseError) as exc:
        print(f"SVG inspection FAILED: {exc}", file=sys.stderr)
        return 1
    if reports:
        print(json.dumps(reports, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
