#!/usr/bin/env python3
"""Validate committed rendered results used by the Skia Reference."""

from __future__ import annotations

import re
import struct
import zlib
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
    "draw-path-roundtrip.png": (200, 150),
    "draw-path-conic-approximation.png": (280, 150),
    "image-rgba-alpha.png": (200, 100),
    "simple-text.png": (240, 80),
    "shaped-text.png": (240, 80),
    "surface-snapshot-independence.png": (220, 100),
    "canvas-state.png": (100, 80),
    "canvas-layer.png": (160, 100),
    "layer-options-clip.png": (96, 96),
    "layer-backdrop-initialization.png": (420, 155),
    "paint-styles.png": (180, 80),
    "paint-fill-path.png": (220, 120),
    "path-bounds-and-measure-matrix.png": (420, 235),
    "color-filter.png": (160, 70),
    "color-filter-channel-curves.png": (420, 180),
    "color-space-interpretation.png": (220, 100),
    "image-color-space-conversion.png": (220, 100),
    "image-filter-merge.png": (150, 60),
    "image-filter-displacement-magnifier.png": (420, 225),
    "image-filter-lighting-grid.png": (420, 280),
    "picture-image-filter-target-crop.png": (420, 175),
    "runtime-effect-bands.png": (180, 60),
    "runtime-blender-consumers.png": (420, 270),
    "path-hole.png": (160, 100),
    "rounded-rect.png": (160, 90),
    "region.png": (155, 80),
    "affine-transform.png": (180, 120),
    "matrix-composition-and-bounds.png": (420, 260),
    "projective-transform.png": (180, 110),
    "matrix4-projected-grid.png": (300, 190),
    "canvas-matrix-scope.png": (160, 150),
    "radial-gradient.png": (120, 80),
    "sweep-gradient.png": (120, 80),
    "corner-path-effect.png": (160, 90),
    "blur-mask-filter.png": (160, 90),
    "blur-image-filter.png": (160, 90),
    "drop-shadow-filter.png": (180, 100),
    "primitive-gallery.png": (220, 120),
    "bezier-path.png": (180, 100),
    "fill-rules.png": (190, 90),
    "mesh-triangle.png": (144, 144),
    "cubic-patch.png": (180, 120),
    "nine-patch.png": (180, 110),
    "atlas-batch.png": (180, 90),
    "portable-markers.png": (180, 90),
    "portable-atlas.png": (240, 120),
    "image-filter-placement.png": (240, 200),
    "image-pixmap-copy-scaling.png": (420, 240),
    "bitmap-mask-and-copies.png": (420, 180),
    "bitmap-resolution-density.png": (400, 185),
    "text-blob.png": (180, 80),
    "text-layout.png": (260, 150),
    "mixed-text-layout.png": (300, 90),
    "recording.png": (100, 40),
    "drawable.png": (120, 50),
    "output-group.png": (220, 220),
    "float-gradient.png": (64, 16),
    "nway-canvas.png": (160, 160),
    "pdf-document.png": (120, 80),
    "pdf-two-pages.png": (260, 115),
    "svg-document.png": (120, 80),
    "output-page-preview.png": (120, 80),
    "raster-buffer-bgra-sample.png": (280, 150),
    "raster-buffer-extracted-alpha.png": (300, 140),
    "pixmap-subset-write.png": (190, 150),
    "codec-image.png": (200, 130),
    "pict-bridge.png": (120, 70),
    "picture-pict-viewport-density.png": (420, 220),
    "skia-dc-headless-snapshot.png": (220, 150),
    "dc-output-capture-and-page-preview.png": (420, 170),
    "color-swatches.png": (210, 70),
    "conical-gradient.png": (160, 90),
    "image-shader-tiles.png": (160, 90),
    "blend-shader.png": (180, 90),
    "discrete-path-effect.png": (180, 90),
    "path-effect-2d-lattices.png": (300, 150),
    "mask-filter-coverage.png": (420, 125),
    "trim-path-effect.png": (160, 110),
    "stamp-path-effect.png": (190, 90),
    "lighting-color-filter.png": (180, 80),
    "dilate-image-filter.png": (180, 90),
    "erode-image-filter.png": (180, 90),
    "matrix-convolution.png": (180, 90),
    "points-modes.png": (220, 90),
    "arc-wedge.png": (190, 90),
    "double-rounded-rect.png": (180, 100),
    "draw-color-device-clip.png": (160, 160),
    "region-clip.png": (180, 90),
    "image-subrect.png": (220, 90),
    "font-bounds.png": (250, 90),
    "font-metrics-guides.png": (420, 205),
    "concept-font-metrics.png": (460, 230),
    "concept-text-advance.png": (460, 190),
    "simple-text-path-outlines.png": (360, 190),
    "font-manager-style-selection.png": (420, 180),
    "glyph-outline.png": (140, 100),
    "text-on-path.png": (330, 120),
    "text-blob-path-snapshot.png": (330, 100),
    "text-blob-multirun-outline.png": (420, 175),
    "multi-run-text-blob.png": (260, 100),
    "justified-text.png": (320, 125),
    "picture-shader.png": (180, 100),
    "draw-rasterized.png": (190, 105),
    "raster-buffer-canvas.png": (180, 100),
    "scanline-batches.png": (90, 60),
    "scanline-bottom-up-placement.png": (190, 190),
    "incremental-final.png": (100, 70),
    "paint-caps.png": (180, 100),
    "paint-joins.png": (210, 100),
    "paint-miter-and-translucent-blends.png": (420, 250),
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
    "rounded-rect-inset-outset.png": (260, 165),
    "region-intersection.png": (180, 100),
    "region-xor.png": (180, 100),
    "region-quantization-and-difference.png": (420, 170),
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
    "two-point-conical-offset.png": (180, 100),
    "dash-phase-stage8.png": (200, 90),
    "trim-inverted-stage8.png": (160, 110),
    "compose-path-effects-stage8.png": (210, 100),
    "sum-path-effects-stage8.png": (210, 100),
    "stamp-morph-stage8.png": (220, 110),
    "blur-mask-styles-stage8.png": (240, 110),
    "blur-anisotropic-stage8.png": (200, 100),
    "shadow-only-stage8.png": (200, 100),
    "compose-filter-stage8.png": (220, 110),
    "convolution-emboss-stage8.png": (200, 100),
    "image-source-filter-stage8.png": (220, 100),
    "point-caps-stage8.png": (220, 100),
    "arc-open-stage8.png": (200, 100),
    "draw-color-blends-stage8.png": (240, 100),
    "relative-path-stage8.png": (200, 110),
    "quad-cubic-stage8.png": (240, 120),
    "reverse-difference-stage8.png": (180, 110),
    "simplify-path-stage8.png": (200, 110),
    "as-winding-stage8.png": (200, 110),
    "measure-tangent-stage8.png": (240, 120),
    "svg-path-stage8.png": (220, 120),
    "blob-run-origins-stage8.png": (280, 120),
    "blob-positioned-wave-stage8.png": (280, 110),
    "blob-shaped-run-stage8.png": (280, 100),
    "glyphs-to-path-stage8.png": (240, 120),
    "text-path-offset-stage8.png": (330, 130),
    "layout-rtl-stage8.png": (300, 100),
    "layout-nowrap-stage8.png": (360, 90),
    "layout-unbreakable-overflow.png": (320, 90),
    "concept-layout-box.png": (480, 300),
    "layout-break-provider-insertion.png": (420, 175),
    "canvas-reset-transform-stage9.png": (200, 110),
    "canvas-set-transform-stage9.png": (200, 110),
    "canvas-nested-state-stage9.png": (200, 110),
    "clip-antialias-stage9.png": (220, 100),
    "clip-within-existing-clip.png": (240, 130),
    "clip-path-circle-stage9.png": (180, 100),
    "clip-rrect-stage9.png": (180, 100),
    "transform-order-stage9.png": (240, 110),
    "concept-transform-order.png": (480, 240),
    "concept-clip-state.png": (480, 240),
    "concept-layer-compositing.png": (480, 240),
    "concept-image-placement.png": (480, 230),
    "concept-filter-graph.png": (480, 300),
    "concept-pixel-stride.png": (480, 210),
    "rotate-around-point-stage9.png": (200, 120),
    "paint-hairline-stage9.png": (200, 90),
    "paint-alpha-stage9.png": (200, 100),
    "paint-antialias-stage9.png": (220, 100),
    "image-shader-decal-stage9.png": (180, 100),
    "empty-shader-stage9.png": (180, 100),
    "gamma-mask-stage9.png": (220, 100),
    "shader-source-filter-stage9.png": (200, 100),
    "arc-chord-stage9.png": (180, 100),
    "draw-color-clipped-stage9.png": (180, 100),
    "path-polygon-stage9.png": (180, 100),
    "path-extend-stage9.png": (220, 100),
    "float-source-space-stage10.png": (210, 80),
    "float-radial-stage10.png": (180, 100),
    "float-sweep-stage10.png": (180, 100),
    "float-conical-stage10.png": (190, 105),
    "lattice-native-stage10.png": (200, 120),
    "lattice-fixed-color-stage10.png": (200, 120),
    "atlas-tints-stage10.png": (220, 100),
    "portable-nine-alpha-stage10.png": (200, 120),
    "portable-lattice-stage10.png": (200, 120),
    "portable-atlas-alpha-stage10.png": (220, 100),
    "font-embolden-stage10.png": (280, 105),
    "font-break-prefix-stage10.png": (320, 100),
    "shaping-kern-stage10.png": (320, 110),
    "shaped-positions-stage10.png": (320, 110),
    "shaped-advance-stage10.png": (320, 100),
    "picture-shader-mirror-stage10.png": (220, 110),
    "picture-image-background-stage10.png": (220, 110),
    "picture-nested-stage10.png": (220, 110),
    "drawable-to-picture-stage10.png": (220, 110),
    "output-page-no-clip-stage10.png": (220, 120),
    "output-page-background-stage10.png": (220, 120),
    "draw-output-page-rotated-stage10.png": (240, 140),
    "concept-page-margins.png": (480, 240),
    "concept-raster-padding.png": (480, 230),
    "concept-path-bounds.png": (480, 250),
    "concept-fill-rules.png": (480, 255),
    "concept-nine-patch.png": (480, 245),
    "concept-text-clusters.png": (480, 245),
    "concept-text-path-frame.png": (480, 240),
    "concept-raster-density.png": (480, 225),
    "concept-resource-lifetimes.png": (480, 245),
    "concept-color-interpretation.png": (480, 220),
    "concept-gpu-boundaries.png": (480, 245),
}

# A figure is part of its nearby example, not a reusable gallery asset.  Keep
# the high-risk repaired scenes tied to their owning chapter so a declaration
# cannot silently drift to an unrelated example.
FIGURE_CHAPTERS = {
    "surface-snapshot-independence.png": "scribblings/reference/surfaces.scrbl",
    "layer-options-clip.png": "scribblings/reference/layers.scrbl",
    "layer-backdrop-initialization.png": "scribblings/reference/layers.scrbl",
    "color-space-interpretation.png": "scribblings/reference/color-management.scrbl",
    "image-color-space-conversion.png": "scribblings/reference/color-management.scrbl",
    "mesh-triangle.png": "scribblings/reference/structured-drawing.scrbl",
    "portable-atlas.png": "scribblings/reference/portable-drawing.scrbl",
    "image-filter-placement.png": "scribblings/reference/image-operations.scrbl",
    "concept-image-placement.png": "scribblings/reference/image-operations.scrbl",
    "concept-filter-graph.png": "scribblings/reference/image-filters.scrbl",
    "concept-pixel-stride.png": "scribblings/reference/pixel-descriptions.scrbl",
    "image-pixmap-copy-scaling.png": "scribblings/reference/image-operations.scrbl",
    "codec-image.png": "scribblings/reference/codecs.scrbl",
    "raster-buffer-bgra-sample.png": "scribblings/reference/raster-buffers.scrbl",
    "raster-buffer-extracted-alpha.png": "scribblings/reference/raster-buffers.scrbl",
    "pixmap-subset-write.png": "scribblings/reference/raster-buffers.scrbl",
    "output-group.png": "scribblings/reference/output-groups.scrbl",
    "output-page-preview.png": "scribblings/reference/output-pages.scrbl",
    "nway-canvas.png": "scribblings/reference/specialized-canvases.scrbl",
    "rtl-shaping.png": "scribblings/reference/shaping.scrbl",
    "layout-rtl-stage8.png": "scribblings/reference/text-layout.scrbl",
    "canvas-reset-transform-stage9.png": "scribblings/reference/canvases.scrbl",
    "canvas-set-transform-stage9.png": "scribblings/reference/canvases.scrbl",
    "clip-antialias-stage9.png": "scribblings/reference/canvases.scrbl",
    "clip-within-existing-clip.png": "scribblings/reference/canvases.scrbl",
    "concept-transform-order.png": "scribblings/reference/canvases.scrbl",
    "concept-clip-state.png": "scribblings/reference/canvases.scrbl",
    "concept-layer-compositing.png": "scribblings/reference/layers.scrbl",
    "paint-fill-path.png": "scribblings/reference/paints.scrbl",
    "paint-miter-and-translucent-blends.png": "scribblings/reference/paints.scrbl",
    "path-bounds-and-measure-matrix.png": "scribblings/reference/paths.scrbl",
    "rounded-rect-inset-outset.png": "scribblings/reference/rounded-rectangles.scrbl",
    "region-quantization-and-difference.png": "scribblings/reference/regions.scrbl",
    "matrix-composition-and-bounds.png": "scribblings/reference/matrices.scrbl",
    "matrix4-projected-grid.png": "scribblings/reference/projective-matrices.scrbl",
    "canvas-matrix-scope.png": "scribblings/reference/projective-matrices.scrbl",
    "image-rgba-alpha.png": "scribblings/reference/images.scrbl",
    "pdf-two-pages.png": "scribblings/reference/pdf-documents.scrbl",
    "scanline-bottom-up-placement.png": "scribblings/reference/scanline-codecs.scrbl",
    "layout-unbreakable-overflow.png": "scribblings/reference/text-layout.scrbl",
    "concept-layout-box.png": "scribblings/reference/text-layout.scrbl",
    "text-blob-path-snapshot.png": "scribblings/reference/text-blobs.scrbl",
    "draw-path-roundtrip.png": "scribblings/reference/racket-draw.scrbl",
    "draw-path-conic-approximation.png": "scribblings/reference/racket-draw.scrbl",
    "path-effect-2d-lattices.png": "scribblings/reference/path-effects.scrbl",
    "mask-filter-coverage.png": "scribblings/reference/path-effects.scrbl",
    "color-filter-channel-curves.png": "scribblings/reference/color-filters.scrbl",
    "image-filter-displacement-magnifier.png": "scribblings/reference/image-filters.scrbl",
    "image-filter-lighting-grid.png": "scribblings/reference/image-filters.scrbl",
    "picture-image-filter-target-crop.png": "scribblings/reference/image-filters.scrbl",
    "runtime-blender-consumers.png": "scribblings/reference/runtime-effects.scrbl",
    "font-metrics-guides.png": "scribblings/reference/fonts.scrbl",
    "concept-font-metrics.png": "scribblings/reference/fonts.scrbl",
    "concept-text-advance.png": "scribblings/reference/fonts.scrbl",
    "font-manager-style-selection.png": "scribblings/reference/typefaces.scrbl",
    "simple-text-path-outlines.png": "scribblings/reference/fonts.scrbl",
    "text-blob-multirun-outline.png": "scribblings/reference/text-blobs.scrbl",
    "layout-break-provider-insertion.png": "scribblings/reference/text-layout.scrbl",
    "bitmap-mask-and-copies.png": "scribblings/reference/racket-draw.scrbl",
    "bitmap-resolution-density.png": "scribblings/reference/racket-draw.scrbl",
    "picture-pict-viewport-density.png": "scribblings/reference/pict-bridge.scrbl",
    "skia-dc-headless-snapshot.png": "scribblings/reference/racket-dc.scrbl",
    "dc-output-capture-and-page-preview.png": "scribblings/reference/dc-output.scrbl",
    "concept-page-margins.png": "scribblings/reference/output-pages.scrbl",
    "concept-raster-padding.png": "scribblings/reference/output-pages.scrbl",
    "concept-path-bounds.png": "scribblings/reference/paths.scrbl",
    "concept-fill-rules.png": "scribblings/reference/paths.scrbl",
    "concept-nine-patch.png": "scribblings/reference/structured-drawing.scrbl",
    "concept-text-clusters.png": "scribblings/reference/shaping.scrbl",
    "concept-text-path-frame.png": "scribblings/reference/text-blobs.scrbl",
    "concept-raster-density.png": "scribblings/reference/pict-bridge.scrbl",
    "concept-resource-lifetimes.png": "scribblings/reference/resources.scrbl",
    "concept-color-interpretation.png": "scribblings/reference/color-management.scrbl",
    "concept-gpu-boundaries.png": "scribblings/reference/gpu-synchronization.scrbl",
}


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"{path}: not a valid PNG header")
    return struct.unpack(">II", data[16:24])


def paeth(left: int, above: int, upper_left: int) -> int:
    prediction = left + above - upper_left
    left_distance = abs(prediction - left)
    above_distance = abs(prediction - above)
    upper_left_distance = abs(prediction - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    if above_distance <= upper_left_distance:
        return above
    return upper_left


def decode_rgba(path: Path) -> tuple[int, int, bytes]:
    """Decode the committed noninterlaced 8-bit RGBA PNGs without Skia."""
    data = path.read_bytes()
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    offset = 8
    header = None
    payload = bytearray()
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError(f"{path}: truncated PNG chunk")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        start = offset + 8
        end = start + length
        if end + 4 > len(data):
            raise ValueError(f"{path}: truncated {kind.decode('ascii', 'replace')} chunk")
        chunk = data[start:end]
        if kind == b"IHDR":
            header = chunk
        elif kind == b"IDAT":
            payload.extend(chunk)
        elif kind == b"IEND":
            break
        offset = end + 4
    if header is None or len(header) != 13:
        raise ValueError(f"{path}: missing PNG header")
    width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", header
    )
    if (bit_depth, color_type, compression, filtering, interlace) != (8, 6, 0, 0, 0):
        raise ValueError(f"{path}: expected noninterlaced 8-bit RGBA PNG")
    try:
        raw = zlib.decompress(payload)
    except zlib.error as exc:
        raise ValueError(f"{path}: invalid PNG image data: {exc}") from exc
    stride = width * 4
    if len(raw) != height * (stride + 1):
        raise ValueError(f"{path}: unexpected PNG image-data length")
    rows: list[bytes] = []
    previous = bytes(stride)
    for row_index in range(height):
        begin = row_index * (stride + 1)
        filter_type = raw[begin]
        encoded = raw[begin + 1 : begin + 1 + stride]
        row = bytearray(stride)
        for index, value in enumerate(encoded):
            left = row[index - 4] if index >= 4 else 0
            above = previous[index]
            upper_left = previous[index - 4] if index >= 4 else 0
            if filter_type == 0:
                row[index] = value
            elif filter_type == 1:
                row[index] = (value + left) & 0xFF
            elif filter_type == 2:
                row[index] = (value + above) & 0xFF
            elif filter_type == 3:
                row[index] = (value + ((left + above) // 2)) & 0xFF
            elif filter_type == 4:
                row[index] = (value + paeth(left, above, upper_left)) & 0xFF
            else:
                raise ValueError(f"{path}: unsupported PNG filter {filter_type}")
        previous = bytes(row)
        rows.append(previous)
    return width, height, b"".join(rows)


def color_bounds(pixels: bytes, width: int, height: int, color: tuple[int, int, int, int]):
    matches = []
    for y in range(height):
        for x in range(width):
            offset = (y * width + x) * 4
            if tuple(pixels[offset : offset + 4]) == color:
                matches.append((x, y))
    if not matches:
        return None
    xs, ys = zip(*matches)
    return min(xs), min(ys), max(xs), max(ys)


def has_intermediate_blue_coverage(pixels: bytes, width: int, x_start: int, x_end: int) -> bool:
    blue = (50, 109, 230)
    white = (255, 255, 255)
    for y in range(0, len(pixels) // (width * 4)):
        for x in range(x_start, x_end):
            offset = (y * width + x) * 4
            red, green, blue_channel, alpha = pixels[offset : offset + 4]
            if alpha == 255 and all(
                min(component, backdrop) < value < max(component, backdrop)
                for value, component, backdrop in zip(
                    (red, green, blue_channel), blue, white
                )
            ):
                return True
    return False


def validate_semantics(path: Path, filename: str) -> list[str]:
    """Cheap pixel probes for figures whose meaning depends on device pixels."""
    if filename not in {
        "canvas-reset-transform-stage9.png",
        "canvas-set-transform-stage9.png",
        "clip-antialias-stage9.png",
    }:
        return []
    width, height, pixels = decode_rgba(path)
    problems = []
    if filename == "canvas-reset-transform-stage9.png":
        expected = {
            (50, 109, 230, 255): (190, 40, 329, 129),
            (239, 160, 43, 255): (40, 90, 179, 179),
        }
        for color, bounds in expected.items():
            if color_bounds(pixels, width, height, color) != bounds:
                problems.append(f"{path.relative_to(ROOT)}: reset-transform rectangle bounds are wrong")
    elif filename == "canvas-set-transform-stage9.png":
        bounds = color_bounds(pixels, width, height, (50, 109, 230, 255))
        if bounds != (110, 50, 333, 145):
            problems.append(f"{path.relative_to(ROOT)}: set-transform rectangle bounds are wrong")
    else:
        hard_has_coverage = has_intermediate_blue_coverage(pixels, width, 0, 210)
        smooth_has_coverage = has_intermediate_blue_coverage(pixels, width, 240, width)
        if hard_has_coverage or not smooth_has_coverage:
            problems.append(
                f"{path.relative_to(ROOT)}: fractional clip comparison lacks hard/antialiased edge coverage"
            )
    return problems


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

    for filename, chapter in FIGURE_CHAPTERS.items():
        if declared.get(filename) != chapter:
            problems.append(f"{filename}: expected declaration in {chapter}")

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
        try:
            problems.extend(validate_semantics(path, filename))
        except ValueError as exc:
            problems.append(str(exc))

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
