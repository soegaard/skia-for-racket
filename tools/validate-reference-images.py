#!/usr/bin/env python3
"""Validate committed rendered results used by the Skia Reference."""

from __future__ import annotations

import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "scribblings" / "reference"
IMAGES = REFERENCE / "images"

FIGURE_RE = re.compile(
    r'@reference-figure\["(?P<filename>[A-Za-z0-9][A-Za-z0-9._-]*\.png)"\s+'
    r'"(?P<alternative>[^"\\]*(?:\\.[^"\\]*)*)"\]'
)

LOGICAL_SIZES = {
    "rectangle.png": (160, 100),
    "polyline.png": (120, 80),
    "gradient.png": (120, 40),
    "dashed-line.png": (100, 30),
    "image-pair.png": (80, 40),
    "simple-text.png": (240, 80),
    "shaped-text.png": (240, 80),
}


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"{path}: not a valid PNG header")
    return struct.unpack(">II", data[16:24])


def main() -> None:
    problems: list[str] = []
    declared: dict[str, str] = {}

    for path in sorted(REFERENCE.glob("*.scrbl")):
        text = path.read_text(encoding="utf-8")
        for match in FIGURE_RE.finditer(text):
            filename = match.group("filename")
            alternative = bytes(match.group("alternative"), "utf-8").decode("unicode_escape")
            if filename in declared:
                problems.append(
                    f"{path}: {filename} is also declared by {declared[filename]}"
                )
            declared[filename] = str(path.relative_to(ROOT))
            if not alternative.strip() or alternative.strip().lower() in {"image", "picture"}:
                problems.append(f"{path}: {filename} has inadequate alternative text")

    expected = set(LOGICAL_SIZES)
    if set(declared) != expected:
        missing_declarations = expected - set(declared)
        extra_declarations = set(declared) - expected
        if missing_declarations:
            problems.append(
                "missing figure declarations: " + ", ".join(sorted(missing_declarations))
            )
        if extra_declarations:
            problems.append(
                "unexpected figure declarations: " + ", ".join(sorted(extra_declarations))
            )

    for filename, logical_size in LOGICAL_SIZES.items():
        path = IMAGES / filename
        if not path.is_file():
            problems.append(f"missing generated image: {path.relative_to(ROOT)}")
            continue
        try:
            actual = png_size(path)
        except ValueError as exc:
            problems.append(str(exc))
            continue
        expected_size = (logical_size[0] * 2, logical_size[1] * 2)
        if actual != expected_size:
            problems.append(
                f"{path.relative_to(ROOT)}: expected {expected_size[0]}x{expected_size[1]}, "
                f"got {actual[0]}x{actual[1]}"
            )

    committed = {
        path.name for path in IMAGES.glob("*.png") if path.is_file()
    }
    undeclared = committed - expected
    if undeclared:
        problems.append("undeclared generated images: " + ", ".join(sorted(undeclared)))

    if problems:
        raise SystemExit("reference-image validation failed:\n  " + "\n  ".join(problems))

    print(f"reference images: {len(expected)} generated PNGs and figure declarations OK")


if __name__ == "__main__":
    main()
