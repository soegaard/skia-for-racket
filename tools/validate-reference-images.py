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
    "canvas-state.png": (100, 80),
    "canvas-layer.png": (160, 100),
    "paint-styles.png": (180, 80),
    "color-filter.png": (160, 70),
    "image-filter-merge.png": (150, 60),
    "runtime-effect-bands.png": (180, 60),
    "path-hole.png": (160, 100),
    "rounded-rect.png": (160, 90),
    "region.png": (155, 80),
    "affine-transform.png": (180, 120),
    "projective-transform.png": (180, 110),
    "radial-gradient.png": (120, 80),
    "sweep-gradient.png": (120, 80),
    "corner-path-effect.png": (160, 90),
    "blur-mask-filter.png": (160, 90),
    "blur-image-filter.png": (160, 90),
    "drop-shadow-filter.png": (180, 100),
    "primitive-gallery.png": (220, 120),
    "bezier-path.png": (180, 100),
    "fill-rules.png": (190, 90),
    "mesh-triangle.png": (160, 120),
    "cubic-patch.png": (180, 120),
    "nine-patch.png": (180, 110),
    "atlas-batch.png": (180, 90),
    "portable-markers.png": (180, 90),
    "portable-atlas.png": (120, 60),
    "image-filter-placement.png": (120, 80),
    "text-blob.png": (180, 80),
    "text-layout.png": (260, 150),
    "mixed-text-layout.png": (300, 90),
    "recording.png": (100, 40),
    "drawable.png": (120, 50),
    "output-group.png": (120, 80),
    "float-gradient.png": (64, 16),
    "nway-canvas.png": (16, 16),
    "pdf-document.png": (120, 80),
    "svg-document.png": (120, 80),
    "output-page-preview.png": (120, 80),
    "raster-buffer-checker.png": (64, 48),
    "codec-image.png": (48, 32),
    "pict-bridge.png": (120, 70),
    "blur-mask-filter.png": (160, 90),
    "blur-image-filter.png": (160, 90),
    "drop-shadow-filter.png": (180, 100),
    "primitive-gallery.png": (220, 120),
    "mixed-text-layout.png": (300, 90),
    "drawable.png": (120, 50),
    "color-swatches.png": (210, 70),
    "conical-gradient.png": (160, 90),
    "image-shader-tiles.png": (160, 90),
    "blend-shader.png": (180, 90),
    "discrete-path-effect.png": (180, 90),
    "trim-path-effect.png": (160, 110),
    "stamp-path-effect.png": (190, 90),
    "lighting-color-filter.png": (180, 80),
    "dilate-image-filter.png": (180, 90),
    "erode-image-filter.png": (180, 90),
    "matrix-convolution.png": (180, 90),
    "points-modes.png": (220, 90),
    "arc-wedge.png": (190, 90),
    "double-rounded-rect.png": (180, 100),
    "region-clip.png": (180, 90),
    "image-subrect.png": (220, 90),
    "font-bounds.png": (250, 90),
    "glyph-outline.png": (140, 100),
    "text-on-path.png": (330, 120),
    "multi-run-text-blob.png": (260, 100),
    "justified-text.png": (320, 125),
    "picture-shader.png": (180, 100),
    "draw-rasterized.png": (190, 105),
    "raster-buffer-canvas.png": (180, 100),
    "scanline-batches.png": (90, 60),
    "incremental-final.png": (100, 70),
    "paint-caps.png": (180, 100),
    "paint-joins.png": (210, 100),
    "paint-stroke-widths.png": (180, 100),
    "blend-multiply.png": (180, 100),
    "blend-screen.png": (180, 100),
    "paint-stroke-and-fill.png": (180, 100),
    "canvas-translate.png": (180, 100),
    "canvas-scale.png": (180, 110),
    "canvas-rotate.png": (180, 120),
    "canvas-skew.png": (180, 110),
    "clip-intersect.png": (180, 100),
    "clip-difference.png": (180, 100),
    "shader-local-matrix.png": (180, 100),
    "fractal-noise.png": (180, 100),
    "turbulence.png": (180, 100),
    "shader-color-filter.png": (180, 90),
    "raw-image-shader.png": (180, 100),
    "gradient-tile-modes.png": (200, 120),
    "blend-color-filter.png": (180, 80),
    "compose-color-filter.png": (180, 80),
    "lerp-color-filter.png": (180, 80),
    "luma-color-filter.png": (180, 90),
    "high-contrast-color-filter.png": (180, 80),
    "table-color-filter.png": (180, 80),
    "offset-image-filter.png": (180, 90),
    "blend-image-filter.png": (180, 90),
    "arithmetic-image-filter.png": (180, 90),
    "crop-image-filter.png": (180, 90),
    "color-filter-image-filter.png": (180, 90),
    "matrix-transform-image-filter.png": (190, 110),
    "shader-image-filter.png": (180, 90),
    "tile-image-filter.png": (180, 90),
    "quadratic-path.png": (180, 100),
    "conic-path.png": (180, 100),
    "path-arc.png": (180, 100),
    "path-transform.png": (190, 120),
    "path-measure-segment.png": (190, 80),
    "path-union.png": (170, 100),
    "path-intersection.png": (170, 100),
    "path-xor.png": (170, 100),
    "rounded-rect-normalized.png": (180, 100),
    "rounded-rect-nine-patch.png": (180, 100),
    "region-intersection.png": (180, 100),
    "region-xor.png": (180, 100),
    "sampling-comparison.png": (210, 100),
    "image-subset.png": (220, 100),
    "image-alpha-paint.png": (200, 90),
    "image-mirror.png": (220, 90),
    "font-sizes.png": (250, 130),
    "font-scale-x.png": (260, 100),
    "font-skew-x.png": (260, 100),
    "ligature-shaping.png": (300, 110),
    "rtl-shaping.png": (260, 90),
    "shaped-outline.png": (240, 110),
    "horizontal-text-run.png": (240, 90),
    "transformed-text-run.png": (260, 110),
    "text-blob-intercepts.png": (240, 100),
    "layout-center.png": (300, 120),
    "layout-end.png": (300, 100),
    "layout-line-height.png": (320, 160),
    "picture-scaled.png": (180, 120),
    "picture-rasterized.png": (180, 120),
    "drawable-transformed.png": (200, 120),
    "output-page-margins.png": (180, 100),
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
