# Skia Reference conceptual diagram progress

Companion implementation record for `skia-reference-conceptual-diagrams.md`.

## Implemented diagrams

- [x] D01 baseline and font metrics (`concept-font-metrics.png`)
- [x] D02 advance versus ink bounds (`concept-text-advance.png`)
- [x] D03 layout origin, line spacing, and wrapping width (`concept-layout-box.png`)
- [x] D04 local coordinates and transform order (`concept-transform-order.png`)
- [x] D05 established clips and saved state (`concept-clip-state.png`)
- [x] D06 per-draw opacity versus layer opacity (`concept-layer-compositing.png`)
- [x] D07 source rectangles and filtered-result placement (`concept-image-placement.png`)
- [x] D08 filter graphs and crop order (`concept-filter-graph.png`)
- [x] D09 pixels, row stride, and padding (`concept-pixel-stride.png`)
- [x] D10 page origin, margins, and content clip (`concept-page-margins.png`)
- [x] D11 raster fallback padding and placement (`concept-raster-padding.png`)
- [x] D12 curve controls and different bounds (`concept-path-bounds.png`)
- [x] D13 winding and even-odd fill rules (`concept-fill-rules.png`)
- [x] D14 nine-patch and lattice stretching (`concept-nine-patch.png`)
- [x] D15 characters, UTF-8 bytes, and shaped glyphs (`concept-text-clusters.png`)
- [x] D16 tangent and normal for text on a path (`concept-text-path-frame.png`)
- [x] D17 logical dimensions and physical pixels (`concept-raster-density.png`)
- [x] D18 owners, borrowed views, and independent results (`concept-resource-lifetimes.png`)
- [x] D19 color interpretation versus conversion (`concept-color-interpretation.png`)
- [x] D20 GPU submission, readback, and presentation (`concept-gpu-boundaries.png`)

## Integration and verification

- [x] Added canonical prose, visible conceptual-diagram introductions, and
      descriptive alternative text at each named Reference location.
- [x] Used deterministic Racket drawing code and registered all 20 assets with
      the reference image validator.
- [x] Added executable assertions for D04 mapped endpoints and D09 storage
      layout values.
- [x] Ran the generator with `/Applications/Racket v9.3.0.2/bin/racket` and
      `python3 -B tools/validate-reference-images.py` (270 declared PNGs).
- [x] Ran the complete `--render --native --require-complete` Reference gate;
      825 native tests passed and the rendered Reference passed its link and
      completeness checks.
