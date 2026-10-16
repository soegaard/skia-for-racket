# Skia Reference visual examples progress

This checklist records implementation status for
[the visual-examples roadmap](skia-reference-visual-examples.md). An item is complete only when
its source example, renderer scene, committed asset, visible explanation, alternative text, and
relevant verification agree.

## Batch 0 — trustworthy validation

- [x] Reconciled the canonical chapters for `raster-buffer?`, `raster-buffer-image-info`, and
  `raster-buffer->image`.
- [x] Isolated displayed live-stream examples in fresh processes and verified all 590 displayed
  examples.
- [x] Selected and verified a Hebrew-capable single face for the shaping fixtures; regeneration
  logs the face and Skia/HarfBuzz versions.

## Batch 1 — repaired existing figures

- [x] F01 Mesh triangle
- [x] F02 Atlas placement
- [x] F03 Filter placement
- [x] F04 Codec result
- [x] F05 Raster-buffer BGRA result
- [x] F06 Output group
- [x] F07 Output-page margins
- [x] F08 N-way and document-preview provenance
- [x] F09 Transform replacement
- [x] F10 Antialiasing and device-pixel capture
- [x] F11 Hebrew and shaping fixtures
- [x] F12 Touched-example resource hygiene

## Batch 2 — first existing-result illustrations

- [x] A01 Surface snapshot independence
- [x] A02 Nested clipping within an existing clip
- [x] A03 Layer-options explicit clipping
- [x] A04 Color-space interpretation
- [x] A05 Explicit image color-space conversion
- [x] A06 Stroke expansion to a fill path
- [x] A07 Path-segment initial-move behavior
- [x] A08 Scoped projective canvas matrix restoration
- [x] A09 Raw RGBA image alpha preview

## Batch 3 — remaining existing-result illustrations

- [x] A10 Two PDF pages, labeled as raster content previews
- [x] A11 Pixmap subset write after borrow closure
- [x] A12 Bottom-up scanline batch placement
- [x] A13 Unbreakable text-layout overflow
- [x] A14 Retained text blob on a closed-path snapshot
- [x] A15 Racket Draw path roundtrip and conic approximation

## Batch 4 — newly illustrated high-priority operations

- [x] B01 Two-dimensional line and stamp path-effect lattices
- [x] B02 Table, clip, and shader mask coverage
- [x] B03 HSLA, gamma, and channel-specific color filters
- [x] B04 Displacement-map and magnifier filters
- [x] B05 Diffuse/specular lighting from alpha
- [x] B06 Runtime color-filter/blender consumers and arithmetic blending
- [x] B07 Picture image-filter target/crop and retained recording

## Batch 5 — remaining CPU visual coverage

- [x] B08 Miter-limit fallback and translucent source/destination blend modes
- [x] B09 Advanced layer initialization and backdrop blur
- [x] B10 Path bounds, tight bounds, and path-measure contour traversal
- [x] B11 Rounded-rectangle inset, outset, and unsupported transform result
- [x] B12 Path-to-region quantization, spans, and difference
- [x] B13 Matrix composition/bounds and matrix4 projection
- [x] B14 Image/pixmap copies, scaling, and extracted Alpha8
- [x] B15 Font metrics guides and manager-selected regular/bold/italic faces
- [x] B16 Simple-text and retained multi-run blob outline conversions
- [x] B17 Custom layout break opportunity with selected display insertion
- [x] B18 Bitmap/image mask and density conversions; picture/pict viewport density
- [x] B19 Headless DC snapshot and DC-output page/raster-group capture

## Selective follow-up dispositions

- [x] C01 Textured vertices/patches: not added. Existing topology, lattice, and atlas figures already
  cover the useful visible distinctions; a new texture fixture would be additional gallery coverage.
- [x] C02 Overdraw canvas: not added. It remains a narrowly scoped diagnostic opportunity requiring
  an explicit Alpha8 count palette, rather than a general rendering-performance illustration.
- [x] C03 Codec orientation/animation: not added. No existing deterministic orientation or animation
  fixture was reused, and this pass does not invent an encoded media fixture.
- [x] C04 JPEG/WebP quality: not added. A lossy comparison needs an intentionally chosen source and
  quality policy; PNG compression levels would not teach the requested distinction.
- [x] C05 Further custom line breaking/justification/fallback: not added. B17 covers the selected
  insertion mechanism; script-specific expansion and fallback remain conditional on verified fonts.
- [x] C06 RGBA/color% swatches: not added. The existing numerical conversions are the more accurate
  explanation; identical swatches would not establish metadata preservation.

## Optional GPU and GUI disposition

- [x] No GPU or GUI screenshot has been fabricated. The optional phase requires a real active backend
  or window capture with backend/platform evidence; the CPU examples above do not claim either.

## Final CPU-roadmap validation

- [x] Regenerated and visually inspected the added figures; the image registry reports 250 PNGs and
  declarations valid.
- [x] Executed all displayed native blocks in fresh processes: 644 tests passed.
- [x] Ran the roadmap's integrated `--render --native --require-complete` Reference checker
  successfully; its temporary evidence directory is
  `/private/tmp/skia-reference-visual-integrated-check-pass9`.

## Next

- [x] Completed the mandatory CPU visual-example roadmap and its verification receipt
