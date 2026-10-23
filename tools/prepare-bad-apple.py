#!/usr/bin/env python3
"""Prepare the pinned bad-console SVG-frame source for examples/bad-apple.

The player deliberately consumes only the small, validated JSON schema emitted here. This tool is
the only component that downloads media or parses SVG/XML; neither operation appears in playback.
"""

from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as element_tree
from pathlib import Path
from typing import Any


SOURCE_COMMIT = "829e8ebb90b2bc5c3cd4a1e1437528da248b1e63"
FRAMES_URL = (
    "https://raw.githubusercontent.com/jhancock532/bad-console/"
    f"{SOURCE_COMMIT}/frames.js"
)
MEDIA_URL = (
    "https://raw.githubusercontent.com/jhancock532/bad-console/"
    f"{SOURCE_COMMIT}/BadApple.mp4"
)
FRAMES_SHA256 = "0d7fad37dff9a9517c6a9f86de6365c40f97b2c99fe305011a6c0b324876b82c"
MEDIA_SHA256 = "0b5e74f6607ad1562bdabd8c95317685fa83b811716d1dba0dce3bf6719752d3"
EXPECTED_FRAME_COUNT = 6568
EXPECTED_PATH_COUNT = 19110
SVG_PREFIX = "data:image/svg+xml;base64,"
EXPECTED_VIEW_BOX = (0.0, 0.0, 480.0, 360.0)
EXPECTED_TRANSFORM = (0.0, 360.0, 0.1, -0.1)
TRANSFORM = re.compile(
    r"^\s*translate\(\s*([^,\s]+)\s*,\s*([^\s)]+)\s*\)\s*"
    r"scale\(\s*([^,\s]+)\s*,\s*([^\s)]+)\s*\)\s*$"
)
WRAPPER = re.compile(r"^\s*let\s+loadedFrames\s*=\s*(\[.*\])\s*;?\s*$", re.DOTALL)


class PreparationError(RuntimeError):
    """Input does not match the pinned, intentionally narrow source format."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_replace(path: Path, writer: Any) -> None:
    """Write path through a same-directory temporary, preserving an old valid target on failure."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            writer(output)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def fetch_verified(url: str, target: Path, expected_hash: str) -> Path:
    """Download a source into target only after it has the requested SHA-256 digest."""
    def write(output: Any) -> None:
        digest = hashlib.sha256()
        with urllib.request.urlopen(url) as response:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
                output.write(chunk)
        actual = digest.hexdigest()
        if actual != expected_hash:
            raise PreparationError(
                f"downloaded {url} has SHA-256 {actual}, expected {expected_hash}"
            )

    atomic_replace(target, write)
    return target


def verified_input(path: Path, expected_hash: str, label: str) -> Path:
    if not path.is_file():
        raise PreparationError(f"{label} does not exist: {path}")
    actual = sha256_file(path)
    if actual != expected_hash:
        raise PreparationError(f"{label} has SHA-256 {actual}, expected {expected_hash}")
    return path


def local_name(element: element_tree.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def fail_svg(source_index: int, message: str) -> None:
    raise PreparationError(f"source array index {source_index}: {message}")


def parse_view_box(value: str | None, source_index: int) -> tuple[float, float, float, float]:
    if value is None:
        fail_svg(source_index, "SVG has no viewBox")
    try:
        numbers = tuple(float(part) for part in value.replace(",", " ").split())
    except ValueError as error:
        fail_svg(source_index, f"invalid viewBox {value!r}: {error}")
    if len(numbers) != 4:
        fail_svg(source_index, f"viewBox has {len(numbers)} components, expected 4")
    return numbers  # type: ignore[return-value]


def parse_transform(value: str | None, source_index: int) -> tuple[float, float, float, float]:
    if value is None:
        fail_svg(source_index, "group has no transform")
    match = TRANSFORM.match(value)
    if not match:
        fail_svg(source_index, f"unexpected group transform {value!r}")
    try:
        return tuple(float(component) for component in match.groups())  # type: ignore[return-value]
    except ValueError as error:
        fail_svg(source_index, f"invalid group transform {value!r}: {error}")


def extract_paths(svg_data_url: str, source_index: int) -> list[str]:
    if not svg_data_url.startswith(SVG_PREFIX):
        fail_svg(source_index, "entry is not an SVG base64 data URL")
    try:
        encoded = svg_data_url[len(SVG_PREFIX):]
        svg_bytes = base64.b64decode(encoded, validate=True)
        if b"<!DOCTYPE" in svg_bytes.upper() or b"<!ENTITY" in svg_bytes.upper():
            fail_svg(source_index, "external XML declarations are not supported")
        root = element_tree.fromstring(svg_bytes)
    except (ValueError, element_tree.ParseError) as error:
        fail_svg(source_index, f"invalid base64 SVG: {error}")
    if local_name(root) != "svg":
        fail_svg(source_index, f"unexpected root element {root.tag!r}")
    if parse_view_box(root.attrib.get("viewBox"), source_index) != EXPECTED_VIEW_BOX:
        fail_svg(source_index, f"unexpected viewBox {root.attrib.get('viewBox')!r}")
    children = list(root)
    if len(children) != 1 or local_name(children[0]) != "g":
        fail_svg(source_index, "SVG must contain exactly one top-level group")
    group = children[0]
    if parse_transform(group.attrib.get("transform"), source_index) != EXPECTED_TRANSFORM:
        fail_svg(source_index, f"unexpected group transform {group.attrib.get('transform')!r}")
    if group.attrib.get("fill") not in {"#000000", "#000", "black"}:
        fail_svg(source_index, f"unexpected group fill {group.attrib.get('fill')!r}")
    if group.attrib.get("stroke") not in {"none", None}:
        fail_svg(source_index, f"unexpected group stroke {group.attrib.get('stroke')!r}")
    paths: list[str] = []
    for child in group:
        if local_name(child) != "path":
            fail_svg(source_index, f"unexpected group child {child.tag!r}")
        if set(child.attrib) != {"d"}:
            fail_svg(source_index, f"path has unexpected attributes {sorted(child.attrib)}")
        path_data = child.attrib["d"]
        if not path_data:
            fail_svg(source_index, "path has an empty d attribute")
        paths.append(path_data)
    return paths


def parse_frames(source_bytes: bytes) -> list[list[str]]:
    try:
        source = source_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PreparationError(f"frames.js is not UTF-8: {error}") from error
    wrapper = WRAPPER.match(source)
    if not wrapper:
        raise PreparationError("frames.js does not match the known let loadedFrames = [...] wrapper")
    try:
        entries = json.loads(wrapper.group(1))
    except json.JSONDecodeError as error:
        raise PreparationError(f"frames.js array is not JSON: {error}") from error
    if not isinstance(entries, list) or not entries or entries[0] is not None:
        raise PreparationError("frames.js must have exactly one initial null entry")
    if any(not isinstance(item, str) for item in entries[1:]):
        bad_index = next(index for index, item in enumerate(entries[1:], 1) if not isinstance(item, str))
        raise PreparationError(f"source array index {bad_index}: expected SVG data URL string")
    frames = [extract_paths(item, index) for index, item in enumerate(entries[1:], 1)]
    if len(frames) != EXPECTED_FRAME_COUNT:
        raise PreparationError(f"expected {EXPECTED_FRAME_COUNT} animation frames, found {len(frames)}")
    path_count = sum(map(len, frames))
    if path_count != EXPECTED_PATH_COUNT:
        raise PreparationError(f"expected {EXPECTED_PATH_COUNT} SVG paths, found {path_count}")
    return frames


def prepared_asset(frames: list[list[str]]) -> dict[str, Any]:
    return {
        "schema": "skia-bad-apple-paths",
        "version": 1,
        "source": {
            "repository": "jhancock532/bad-console",
            "commit": SOURCE_COMMIT,
            "path": "frames.js",
            "sha256": FRAMES_SHA256,
            "first_source_index": 1,
        },
        "fps_numerator": 30,
        "fps_denominator": 1,
        "frame_count": len(frames),
        "view_box": [0, 0, 480, 360],
        "source_to_view_box": [0.1, 0, 0, -0.1, 0, 360],
        "fill_rule": "winding",
        "frames": frames,
    }


def write_prepared_asset(path: Path, asset: dict[str, Any], compression_level: int) -> None:
    encoded = json.dumps(asset, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")

    def write(output: Any) -> None:
        # The prepared asset is local, generated data. Level 1 completes dramatically sooner than
        # level 9 while retaining gzip's dependency-free, streamable format and a compact file.
        with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0,
                           compresslevel=compression_level) as zipped:
            zipped.write(encoded)

    atomic_replace(path, write)


def write_provenance(path: Path, frames_path: Path, media_path: Path | None) -> None:
    report: dict[str, Any] = {
        "frames_js": {"path": frames_path.name, "sha256": FRAMES_SHA256},
        "frame_count": EXPECTED_FRAME_COUNT,
        "path_count": EXPECTED_PATH_COUNT,
    }
    if media_path:
        report["media"] = {"path": media_path.name, "sha256": MEDIA_SHA256}

    def write(output: Any) -> None:
        output.write(json.dumps(report, sort_keys=True, indent=2).encode("utf-8"))
        output.write(b"\n")

    atomic_replace(path, write)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument("--download", action="store_true", help="download the pinned frames.js")
    source_group.add_argument("--frames-js", type=Path, help="verified local frames.js input")
    parser.add_argument("--with-audio", action="store_true", help="also download the matching MP4")
    parser.add_argument("--output", type=Path, default=Path("output/bad-apple/frames.json.gz"))
    parser.add_argument("--downloads", type=Path, default=Path("downloads/bad-apple"))
    parser.add_argument("--compression-level", type=int, choices=range(10), default=1,
                        help="gzip compression level (0-9, default: 1 for quick preparation)")
    arguments = parser.parse_args(argv)

    try:
        if arguments.download:
            frames_path = fetch_verified(FRAMES_URL, arguments.downloads / "frames.js", FRAMES_SHA256)
        else:
            frames_path = verified_input(arguments.frames_js, FRAMES_SHA256, "frames.js")
        media_path: Path | None = None
        if arguments.with_audio:
            media_path = fetch_verified(MEDIA_URL, arguments.downloads / "BadApple.mp4", MEDIA_SHA256)
        frames = parse_frames(frames_path.read_bytes())
        write_prepared_asset(arguments.output, prepared_asset(frames), arguments.compression_level)
        write_provenance(arguments.output.with_name("provenance.json"), frames_path, media_path)
    except (OSError, PreparationError, urllib.error.URLError) as error:
        print(f"prepare-bad-apple.py: {error}", file=sys.stderr)
        return 1

    print(
        f"wrote {arguments.output}: {len(frames)} frames, "
        f"{sum(map(len, frames))} SVG paths, {arguments.output.stat().st_size} compressed bytes"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
