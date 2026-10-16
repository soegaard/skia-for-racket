# Skia Reference visual examples implementation plan

Prepared for **Documentation - Writer** on October 16, 2026.

Baseline: `d687d39e960e85996c11e22c70c6ccb92ca65674` and the working checkout at that revision. This is an editorial implementation plan; it does not change the Reference or regenerate its images.

Complete the illustrations of the examples already in the Reference first. Then add focused examples for public operations whose effects are difficult to understand without seeing them. A figure must depict the displayed program or an explicitly explained view of its result. The number of images is not the measure of completion.

## 1 Scope and current coverage

The include tree rooted at [reference.scrbl](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/reference.scrbl) contains 13 subject groups and 71 API chapters. Those chapters contain **288 `racketblock` blocks, 25 evaluated `examples` blocks, and 208 figure declarations**. The 208 committed PNGs pass the current image validator. These counts exclude the binding-link probe under `reference/tests/` and all tutorials.

Many unillustrated blocks intentionally return numbers, bytes, flags, metadata, or errors. Preserve that useful distinction: add images when they explain pixels, geometry, layout, or the transformation of a drawable object. Do not turn every query or resource-lifetime example into a drawing exercise.

Recent commits first added broad visual coverage and then consolidated it. In particular, `f7aabbb`, `f63e186`, and `d687d39` removed redundant stage-ten, stage-nine, and stage-eight scenes and moved retained examples beside relevant definitions. Preserve that direction. Do not restore the removed galleries merely to increase coverage.

The existing implementation consists of:

| File | Role in the work |
| --- | --- |
| [render-reference-images.rkt](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/render-reference-images.rkt) | Maintainer-only renderer; currently a sequence of scene definitions with a shared 2× canvas scale. |
| [figures.rkt](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/support/figures.rkt) | Loads committed PNGs and displays them at half their stored dimensions; supplies alternative text. |
| [validate-reference-images.py](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/validate-reference-images.py) | Checks declarations, descriptive alternatives, files, and registered dimensions. It does not verify the depicted result. |
| [images README](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/images/README.md) | Documents image regeneration and the density convention. |
| [reference-native-test.rkt](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/reference-native-test.rkt) | Reads the displayed native blocks and executes each twice in fresh namespaces. It checks execution, not correspondence with the PNG. |
| [check-reference.py](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/check-reference.py) | Source coverage, binding, rendering, and cross-reference checks. |
| [REFERENCE-DEVELOPMENT.md](/Users/soegaard/Dropbox/GitHub/skia-for-racket/docs/REFERENCE-DEVELOPMENT.md:639) | Distinguishes a Reference-only editing preview from integrated publication validation. |

Keep native rendering out of ordinary Scribble builds. Do not alter public APIs, tutorials, chapter order, or declaration tags just to add pictures. Preserve existing result expressions and ownership demonstrations when extending their examples.

## 2 Correct existing illustrations before expanding coverage

These are specific findings at the baseline, not hypothetical review questions. Line numbers are navigation aids; use the named API and filename when lines move.

### 2.1 Correct mismatched and misplaced figures

| Work item | Evidence and required correction | Acceptance |
| --- | --- | --- |
| F01 Mesh triangle | [structured-drawing.scrbl:58](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/structured-drawing.scrbl:58) creates a 24×24 surface, a default paint, and a right triangle at `(2 2)`, `(22 2)`, `(2 22)`. The renderer at line 324 creates a different 160×120 triangle and a white paint. Choose one useful example and make both sources agree. Prefer extending the existing block into a clearly colored, readable triangle while retaining its `vertices-count` result. Explain the white paint if required by modulation. | Same points, orientation, paint, vertex colors, and background in code and renderer. No claim that the old image was a magnification of the old triangle. |
| F02 Atlas placement | [portable-drawing.scrbl:53](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/portable-drawing.scrbl:53) puts `portable-atlas.png` inside `draw-markers`, before `portable-markers.png`. Move it to the existing `draw-atlas/portable` example near line 237. That block uses a 12×6 target and transforms `(1 1)` and `(7 1 #:scale 2)`; the current renderer changes these to a 120×60 target and different geometry. Capture the actual target and magnify it explicitly. | The marker entry shows only markers. The atlas entry shows its two copies with the correct positions, 1:2 size ratio, and transparency. No duplicate figure declaration: the validator rejects reuse of a filename. |
| F03 Filter placement | [image-operations.scrbl:166](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/image-operations.scrbl:166) uses a 6×4 red image, offset `(2 1)`, and a 12×10 destination. `image-filter-placement.png` instead uses 40×25, `(30 15)`, and 120×80. Render the actual subset and returned offset from the documented operation. Show a nearest-neighbor enlargement of the 12×10 result with a caption identifying its original size. | The result begins at the returned placement, and the documented probe at `(3,2)` is visibly inside it. Preserve transparent destination pixels; any checkerboard is a declared preview background. |
| F04 Codec result | [codecs.scrbl:98](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/codecs.scrbl:98) encodes and decodes a solid blue 3×2 image. `codec-image.png` depicts a rounded rectangle on white, and its generator does not decode a codec. Replace it with the actual decoded 3×2 pixels, enlarged and labeled. Keep the frame-count and dimension example. | The image is solid blue with the stated aspect ratio and is obtained through `codec->image`; the caption does not invent geometry. |
| F05 Raster buffer result | [raster-buffers.scrbl:455](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/raster-buffers.scrbl:455) writes one logical sample to a 2×1 BGRA buffer. The attached checkerboard is unrelated, and its generator draws rectangles instead of writing buffer samples. Replace it with a view of the actual two pixels, keeping the numerical logical-channel/storage-byte comparison. Rename the asset to a semantic name such as `raster-buffer-bgra-sample.png`. | One pixel represents `(20,40,60,255)` and the untouched pixel has its actual initialized value. Do not depict storage order as a different displayed color. Remove the replaced checkerboard from both the generator and registry. |
| F06 Output group | [output-groups.scrbl:69](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/output-groups.scrbl:69) draws a red 8×6 group at `(4,5)` on a transparent 20×20 surface with padding 1. `output-group.png` changes dimensions, placement, padding, and background. Render the actual operation and enlarge its result. Keep the callback-count, strategy, and pixel-size results. | The group occupies the documented bounds. Padding does not move the logical content or become visible colored geometry. |
| F07 Output page margins | [output-pages.scrbl:196](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/output-pages.scrbl:196) describes a 60×40 mm page with 5 mm margins and a circle at content coordinates `(10,10)`, radius 8. The 120×80 preview redraws a circle centered at `(20,20)` without using the page. Build the image through `output-page->image` or `draw-output-page` and normalize only the final presentation size. | On a 120×80 proportional preview, the center is `(30,30)` and radius 16, including the margins. State that the screen preview is scaled; it is not a physical-size proof. |
| F08 Specialized and document provenance | `nway-canvas.png` redraws one rectangle directly; `pdf-document.png` and `svg-document.png` redraw content on CPU surfaces. For n-way, run `call-with-nway-canvas` and capture one actual target. For document figures, either rasterize the actual exported document with an explicit maintainer dependency, or label them visibly as a raster preview of the same drawing commands. | An illustration of document content does not imply that the PDF/SVG was rendered and checked. The two-page example in A10 follows the same rule. Do not introduce a PDF/SVG renderer as an ordinary Scribble dependency. |

F02 repairs an existing image association; it is not a request for another atlas scene. F05 replaces a misleading picture rather than turning a byte-order example into a checkerboard tutorial.

### 2.2 Correct renderer and font assumptions

**F09 Transform replacement.** [canvases.scrbl:197](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/canvases.scrbl:197) and line 224 describe `canvas-reset-transform!` and `canvas-set-transform!`. Their renderer entries near lines 2055 and 2067 discard the shared device scale. In the reset figure, two documented 70×45 rectangles consequently appear at different sizes. In the set-transform figure, both placement and size are halved when displayed.

Prefer a small renderer helper that captures a surface at the example's actual pixel size and then presents that image at 2× storage resolution, using nearest sampling when preserving individual pixels. Use it for transform-reset and device-pixel examples. This preserves the literal program's coordinate behavior without pretending an identity transform retains a hidden scale. Ordinary scale-independent geometry can keep the existing high-resolution rendering path. An alternative device-transform adapter must explicitly compose the device transform after every replacement operation and have a geometry check; do not patch only one reset call and leave the general assumption unexplained.

**F10 Antialiasing.** The two fractional rectangles in [canvases.scrbl:289](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/canvases.scrbl:289) use half-integer coordinates. Multiplying these by two makes the clip edges integral device coordinates, removing the distinction promised by `clip-antialias-stage9.png`. Capture the literal example at 1× and add a magnified edge view, or change both displayed and rendered coordinates so the intended edges remain fractional at the chosen density. Confirm intermediate edge coverage in the antialiased panel and its absence in the hard-edge panel. Review `paint-hairline-stage9.png`, `paint-antialias-stage9.png`, and coverage-mask examples with the same device-pixel distinction in mind.

**F11 Hebrew and shaping fixtures.** [rtl-shaping.png](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/images/rtl-shaping.png) contains missing-glyph boxes and is clipped at the right edge. [layout-rtl-stage8.png](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/images/layout-rtl-stage8.png) contains boxes in place of Hebrew letters. A native probe on this checkout selected Helvetica and returned glyph ID zero for the Hebrew letters. Choose a font with verified coverage, show the font selection or an explicit prerequisite in the example, and compute placement from the run's actual positions/bounds. RTL shaping does not by itself make the supplied drawing origin a right-edge anchor.

For a single-font example, keep a single shaper; do not substitute mixed-text layout to hide missing glyphs. Use the existing `SKIA_REFERENCE_TEST_FONT` convention where appropriate, but note that it currently affects the semantic test suite, not the generator or displayed examples. If the generator adopts a configurable font, document how the displayed example selects the same face. Do not silently download or bundle a font. Record the regeneration face and native version, check all required non-space glyphs, and fail regeneration of a required fixture when coverage is missing. Also inspect ligature and kerning comparisons: verify the chosen font actually changes glyphs or positioning when the demonstrated feature is toggled. Exact glyph IDs and raster hashes need not be portable across fonts or platforms.

**F12 Example hygiene.** Correct resource management in touched blocks. For example, [paths.scrbl:656](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/paths.scrbl:656) constructs the tangent paint inline instead of managing it with `with-skia`. Preserve the distinction between owned resources, borrowed canvases, and detached layout/geometry values. Add a short visible caption for comparison order, magnification, or preview provenance; alternative text alone is not visible explanatory prose.

## 3 First implementation pass for existing examples

Each row describes an existing example to extend or illustrate. Reuse its input data and keep its returned-value demonstration. Add only the drawing/capture scaffolding needed to show that result. Proposed preview sizes are logical display sizes, not silent replacements for source image dimensions.

| ID and location | Implementation and intended result | Suggested asset and acceptance |
| --- | --- | --- |
| A01 [surface snapshots, line 124](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/surfaces.scrbl:124) | Capture the red 2×1 snapshot and the surface after clearing it blue. Present the two actual results side by side, labeled snapshot and current surface. Preserve the snapshot byte list. | `surface-snapshot-independence.png`, about 180×60. Snapshot remains red; surface is blue. Capture both before their owners close. |
| A02 [nested clipping, line 269](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/canvases.scrbl:269) | Show the two actual 8×6 states from the loop, with identical magnification. Retain the sample results and identify sample positions in a separate legend or marked inset. | `clip-within-existing-clip.png`, about 220×100. Neither operation paints beyond the first 6×6 clip. Existing large `clip-intersect`/`clip-difference` examples cover the general operations; this picture teaches their restriction to the existing clip. |
| A03 [layer options, line 174](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/layers.scrbl:174) | Capture the existing 16×16 result of `call-with-canvas-layer-rec` with explicit `(2 2 12 12)` clipping. Show its transparent border against a declared checkerboard. | `layer-options-clip.png`, about 96×96. The visible square follows the explicit clip, not merely the layer bounds. |
| A04 [color-space interpretation, line 44](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/color-management.scrbl:44) | Magnify the actual two output samples made from identical byte values tagged as sRGB and linear sRGB. Keep the numeric result alongside the two swatches. | `color-space-interpretation.png`, about 200×70. In an sRGB output the samples are approximately 128 and 188, with opaque alpha. Do not replace the operation with manually selected gray paints. |
| A05 [explicit image conversion, line 385](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/color-management.scrbl:385) | Display the original untagged image under an explicitly stated sRGB preview interpretation beside the converted sRGB image. Keep both original byte lists. | `image-color-space-conversion.png`, about 200×70. The source bytes stay unchanged; conversion changes samples. Distinguish assumed interpretation from color tagging. Cross-reference A04 and the existing floating-color swatches. |
| A06 [stroke expansion, line 491](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/paints.scrbl:491) | Draw the original stroked line and the returned fill path in separate labeled rows. Keep `fillable?` and the containment result. Optionally outline the returned path to show its boundary. | `paint-fill-path.png`, about 180×100. Matching capsule geometry with round ends; paint color and filters are not claimed to be encoded in the path. |
| A07 [path extraction, line 677](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/paths.scrbl:677) | Plot the existing `moved` and `unmoved` results over a faint source guide. Keep the command lists. Show the two paths in separate coordinate panels to avoid obscuring their difference. | `path-segment-initial-move.png`, about 240×100. Default extraction runs from `(30,20)` to `(50,20)`; omitting the initial move produces a segment from `(0,0)` to `(50,20)`. |
| A08 [matrix scope, line 443](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/projective-matrices.scrbl:443) | Capture the translated red 4×3 rectangle on the actual 20×20 target. Add a small second mark after the scope, with its code shown, so restoration is visible as well as checked by the final matrix equality. | `canvas-matrix-scope.png`, about 120×120. The first mark is offset by `(5,6)` and the second uses restored coordinates. Use the native-scale capture helper. |
| A09 [raw RGBA image, line 44](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/images.scrbl:44) | Display the actual opaque red and half-alpha blue pixels over a declared checkerboard while retaining the byte round trip. This is distinct from the existing two opaque pixels in `image-pair.png`. | `image-rgba-alpha.png`, about 160×60. Blue retains alpha 128; the checkerboard belongs to the preview, not to the image bytes. |
| A10 [two PDF pages, line 187](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/pdf-documents.scrbl:187) | Show page 1 and page 2 in one paired figure, using the existing 120×80 pages and blue squares of size 20 and 40. Follow F08's actual-document versus content-preview rule. | `pdf-two-pages.png`, about 260×90. Page order, common page size, square size, and `(10,10)` origin agree with the code. Do not suggest the PNG proves publication or link behavior. |
| A11 [pixmap subset, line 208](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/raster-buffers.scrbl:208) | After the writable borrow ends, create an image from the 3×2 parent buffer and magnify it. Preserve the query demonstrating that the escaped pixmap has expired. | `pixmap-subset-write.png`, about 150×100. Only pixel `(2,1)` is red; the other initialized samples remain unchanged. Do not use the expired view for rendering. |
| A12 [bottom-up scanlines, line 235](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/scanline-codecs.scrbl:235) | Reuse the existing generated BMP. Convert each returned batch to an image and place it using `scanline-batch-first-row`. Show batch boundaries or a legend while preserving the returned row positions. | `scanline-bottom-up-placement.png`, about 160×150. Top is red/green, middle blue/white, bottom yellow/black. This teaches row placement; an arbitrary completed image does not. |
| A13 [unbreakable layout, line 109](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/text-layout.scrbl:109) | Draw the existing layout while its shaper is open, with a guide marking the requested width. Give the preview enough space for the whole word and retain the count/width results. | `layout-unbreakable-overflow.png`, about 280×90. The word stays on one line and extends beyond the requested width; the figure must not clip the overflow it is explaining. |
| A14 [retained on-path blob, line 599](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/text-blobs.scrbl:599) | Draw the returned blob after the source path and shaper close, preserving the transform-metadata result. Show a separately retained or reconstructed guide for the documented straight path. | `text-blob-path-snapshot.png`, about 330×90. Start offset 20 and normal offset 5 are visible, and the preview consumes the retained blob rather than calling the on-path drawing helper again. |
| A15 [Draw path conversions, lines 181 and 198](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/racket-draw.scrbl:181) | Extend both existing conversion blocks to draw their actual values. For the rectangle show Draw → Skia → Draw with the returned fill style. For the conic overlay or compare the native conic and the explicitly approximated Draw path. Preserve the type/fill-style results. | `draw-path-roundtrip.png` and `draw-path-conic-approximation.png`. Render the Draw result through a real Draw bitmap DC, not by redrawing the Skia input. The subdivision power is an expansion bound, not an error tolerance. |

The existing portable-atlas example is also part of this pass through F02. The mismatched codec, buffer, group, and output-page images are repaired through F03–F07, not counted again as new examples.

### 3.1 Existing blocks that should stay numerical or use a nearby figure

The chapter audit below accounts for the remaining blocks without an immediately associated result. In particular:

- Keep allocation, lifetime, identity, storage-layout, encoding-signature, metadata, and error examples numerical. A blank surface or a successful file save does not need a decorative blank image.
- Use the existing comparison after `make-paint/color4f` for the one-pixel query at line 138. Use existing offset-filter, clipped-color, tangent, rounded-normalization, glyph-bounds, text-builder, and mixed-layout figures where they already explain the same visual point. Add a short local reference when the connection is otherwise hard to find.
- [drawables.scrbl:89](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/drawables.scrbl:89) reproduces the two red rectangles already shown by `drawable.png`. Refer to the earlier result; do not generate another identical image. The figure belongs once in the chapter.
- [output-pages.scrbl:290](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/output-pages.scrbl:290) has a document-lifecycle example followed by a separate rasterization example and figure. Keep that distinction explicit. The latter is not the exact output of the former.
- Keep the return-value parts of positioned-blob ownership, builder snapshots, clusters, and font lifetime examples. Their nearby drawing examples already show the generic visual operation. New pictures are warranted only for an additional visible distinction, such as A14.

## 4 Second implementation pass for newly illustrated operations

Implement the following after the existing-example pass. These are new displayed examples, not missing PNGs for old code. Put each beside the relevant definition or a named subsection shared by the family. Prefer one comparison with a useful common input over many nearly identical single images.

### 4.1 Highest priority new examples

| ID | APIs and chapter | Scene to implement and what it must establish |
| --- | --- | --- |
| B01 | `make-2d-line-path-effect`, `make-2d-path-effect` in path effects | Fill the same bounded region with parallel strokes and with a small asymmetric stamp on a lattice. Show enough repetitions to reveal both axes and the spacing. Explain that the lattice matrix is not the canvas transform. Two small results, or one paired result. |
| B02 | `make-table-mask-filter`, `make-clip-mask-filter`, `make-shader-mask-filter` | Use an antialiased/soft-edged shape with intermediate coverage, not a solid integer-aligned rectangle. Compare original coverage with threshold/table remapping; show an alpha-gradient shader modulating a colored shape. Keep gamma coverage distinct from RGB gamma. Native-scale edge insets must make the change visible. |
| B03 | `make-hsla-matrix-filter`, the two gamma color filters, channel-specific `make-table-argb-color-filter` | Reuse a compact multicolor strip and grayscale ramp. Show hue rotation/desaturation, encode/decode channel curves, and one selective-channel table. State that these change channels and do not retag an image or perform full gamut conversion. The existing identity-table query does not cover this behavior. |
| B04 | `make-displacement-map-image-filter`, `make-magnifier-image-filter` | Use an asymmetric grid/image so deformation is unmistakable. For displacement show both the displacement source and displaced image with named channel selections. For the magnifier show the lens rectangle and a transition controlled by inset. Avoid a flat source that conceals the effect. |
| B05 | Six diffuse/specular lighting factories in image filters | Use one smooth alpha height field and one common view. Make a 2×3 comparison: diffuse/specular by distant/point/spot light. Include a small view of the source alpha. Captions identify direction/location/target and explain that the output is computed from alpha, not original RGB relighting. Reject all-black/all-white results that fail to demonstrate lighting. |
| B06 | `runtime-effect->color-filter`, `runtime-effect->blender`; `paint-set-blender!`; `make-blender-shader`, `make-blender-image-filter`; `make-arithmetic-blender` | Use a short color-filter program and a short blender program with visibly asymmetric source and destination inputs. Provide one child-binding example for a runtime shader and one common blender setup reused conceptually across the three consumers. Each displayed block remains independently runnable. Preserve premultiplied-alpha requirements and clearly identify source versus destination. Do not create six unrelated gallery pages. |
| B07 | `make-picture-image-filter` | Record a small asymmetric picture, then use it as a filter source. Show a target/crop window against the original bounds. Demonstrate that the target selects a rasterization rectangle rather than fitting/rescaling recorded geometry. Close the original wrapper after construction if illustrating retention. |
| B08 | `paint-set-miter-limit!`; compositing modes in paints | Add an acute join at two miter limits. Add one translucent-overlap comparison for `src-over`, `modulate`, and `multiply`, with a declared backdrop; opacity must make the difference between the latter two visible. Cross-reference existing caps, joins, alpha, multiply, and screen examples. Do not restore one image per blend mode. |
| B09 | `call-with-canvas-layer-rec` backdrop and layer initialization | Place patterned background content behind a bounded region. Show a backdrop blur or a carefully chosen initialized-versus-empty layer comparison. Ensure the difference comes from the selected option, not from changing source geometry. Keep explicit clipping distinct from conservative layer bounds. |
| B10 | `path-bounds`, `path-tight-bounds`, `path-measure-matrix`, contour traversal | Draw a quadratic with its control polygon and both bounds; use the existing native test's `(0,0)–(50,100)–(100,0)` distinction as a starting point. Separately place an asymmetric arrow using `path-measure-matrix`, with a small two-contour example if needed to explain advancing the measure. Do not duplicate the existing tangent picture. |
| B11 | `rounded-rect-inset`, `rounded-rect-outset`, `rounded-rect-transform` | Compare an original rounded rectangle with inset/outset results using distinguishable outlines. Add a supported transform only if it reveals something beyond ordinary canvas scaling. Keep the `#f` result for an unrepresentable transformed rounded rectangle as a numerical example. |
| B12 | `path->region`, `region->path`, `region-spans`, `region-difference` | Show a curved source rasterized to an integer region, with a pixel-grid enlargement and one highlighted scanline. The geometry should reveal integer quantization. Add set difference in the same family if a clear two-input comparison is still missing. Do not render accessor tables as pictures. |
| B13 | `matrix-compose`, `matrix-map-rect`, `matrix4` projection and canvas application | Add a labeled comparison of composition order adjacent to the pure matrix example, linking to the existing canvas transform-order result. For mapped bounds, outline a rotated rectangle and its axis-aligned bounding box. For 4×4 projection use one tilted asymmetric grid, avoiding a singular horizon; do not suggest there is a 3D camera or visibility pipeline. |
| B14 | `image-read-pixmap!`, `image-scale-pixmap!`, `pixmap-scale!`, `raster-buffer-extract-alpha` | Use an asymmetric small pixel source to show a source-offset copy and nearest/linear scaling into actual writable destinations. In a second result, display extracted alpha as grayscale with that mapping explicitly shown. Capture the returned buffers instead of drawing an imitation. |
| B15 | Font metrics and typeface selection | Add a word with baseline, ascent, descent, and advance guides, including a descender. Select faces/styles through the public typeface/font-manager APIs for a small regular/bold/italic comparison; label the actual selected family and avoid promising a particular installed family everywhere. The font-coverage work in F11 is a prerequisite. |
| B16 | `simple-text-path`, `text-blob->path` | Show filled and stroked monochrome outlines of the same short text, with the conversion actually exercised. Use a retained multi-run blob where it adds useful distinction. Cross-reference existing glyph-outline, positioned-glyphs, and shaped-outline figures. State limits for color/bitmap glyphs rather than replacing them with unrelated text. |
| B17 | `make-layout-break-opportunity` with `#:break-provider` | Use the existing opportunity value in an actual layout. Compare a wide line where no insertion occurs with a narrow line using the displayed hyphen. Preserve original logical text and distinguish character indices from shaping clusters. Cross-reference A13 for unbreakable overflow. |
| B18 | `bitmap->image`, `image->bitmap`, `surface->bitmap`; pict conversion | Add a nonblank asymmetric bitmap with a partly transparent mask; show imported pixels with and without that mask. Add a small density comparison for `#:resolution`. For `picture->pict`, use nonzero `#:bounds` to show viewport translation and compare raster scales without changing logical size. Keep the existing `surface->pict` example. Use actual Racket bitmap/pict consumers. |
| B19 | `skia-dc%`, `make-dc-output-page`, `call-with-output-dc`, `draw-dc-raster-group` | Add a minimal complete headless DC example drawing a few shapes and text and obtaining a snapshot. Add a page authored through a real DC callback and a bounded raster group with surrounding vector content. For PDF/SVG, label a content preview honestly and use the report/inspection tools for representation claims. Close the persistent DC with its method; do not give callback DCs a persistent lifetime. |

B01–B07 are the largest gaps in visibly productive API families. B14–B19 substantially improve the newer interoperability and text areas. B08–B13 should be compact comparisons that explain distinctions absent from the existing figures.

### 4.2 Selective follow-up examples

These are useful after the preceding work, but should not delay completion of existing examples.

| ID | Candidate | Condition for inclusion |
| --- | --- | --- |
| C01 | `make-vertices`/`draw-vertices` texture coordinates and indices; `draw-patch` texture coordinates | Use one textured quadrilateral or curved patch that exposes how coordinates work. Basic topology modes alone were recently consolidated; do not reinstate three interchangeable triangle images. |
| C02 | `call-with-overdraw-canvas` | Show actual Alpha8 counts mapped to a documented display palette. Explain that counts are approximate and not a GPU/performance measurement. Keep palette conversion in the shown preparation or caption. |
| C03 | Codec orientation and animated frame selection | Reuse an existing repository fixture if suitable; otherwise create a small deterministic encoded fixture with clear orientation/corner markers and attribution where applicable. Show normalized versus encoded coordinates, then a labeled frame strip. Do not claim a still PNG demonstrates disposal/compositing. |
| C04 | JPEG/WebP quality and JPEG alpha handling | Compare the same high-frequency/color-edge source after actual encoding and decoding. Include a magnified crop and the chosen alpha policy. Do not spend a picture on PNG compression levels, which are not a lossy-quality comparison. |
| C05 | Custom line breaking, justification, and fallback beyond B17 | A single comparison can explain `justify` versus `justify-all`, hard breaks, or nonbreaking spaces. Arabic/CJK expansion and fallback need verified fonts and semantic checks. Avoid restaging all left/center/right layout examples already consolidated. |
| C06 | Color conversions between `rgba` and `color%` | Keep numerical alpha/channel examples as the primary explanation. Add a swatch only if it shows transparency in context; identical swatches do not establish preservation of metadata. |

### 4.3 GPU and GUI work stays explicitly separate

Existing helpers in [gpu-surfaces.scrbl:71](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/gpu-surfaces.scrbl:71), [gpu-images.scrbl:127](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/gpu-images.scrbl:127), and [gpu-transfers.scrbl:135](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/gpu-transfers.scrbl:135) and line 182 create, filter, or transfer visible results. Add an opt-in maintainer capture path if these are illustrated. It must invoke the real helper in an active context, perform explicit readback, and close children before the context. Record the backend used. A CPU reconstruction is not a GPU result, and a readback image is not proof of screen presentation or hardware acceleration.

Use one small scene and one backend capture for the surface/filter/transfer family, with links from related entries, rather than a duplicate square for each transfer function. Keep helper definitions safe to read during ordinary documentation builds. A missing backend may leave a documented optional capture unrun, but must not silently replace it with CPU rendering or report success.

For new GUI examples, start with `make-skia-render-canvas` using an explicit raster renderer, or `skia-canvas%`. Show a complete short runnable window program and its drawing area. A screenshot, if included, must be captured from the actual program and labeled with its platform. Keep GUI execution out of the generic native-block runner, which currently evaluates every `racketblock`. Add a deliberate displayed-only/opt-in execution classification before introducing a top-level window-creating block; do not rely on a comment to prevent execution. A shared callback can also be rendered headlessly, but that image must be labeled as the callback's drawing, not a window screenshot.

The presenter, GPU widget, GPU DC, and GPU-output chapters can link to that common scene and to a real opt-in GPU example. Their synchronization, external-resource tokens, native handles, diagnostics, and lifecycle procedures do not each need a PNG.

## 5 Complete chapter audit

`B/F` means displayed code blocks, including evaluated examples, followed by figure declarations. This is an inventory, not a completion score. Paths in this table are relative to the Reference directory linked above. Source line numbers listed under “Disposition” identify existing blocks to keep numerical or connect to a relevant figure; they are not instructions to remove those blocks.

| Group and chapter | B/F | Disposition |
| --- | ---: | --- |
| Foundations — `notation.scrbl` | 0/0 | No image needed for signatures, scalar limits, or error notation. |
| `resources.scrbl` | 2/0 | Keep lines 97 and 108 as lifetime examples. |
| `native-libraries.scrbl` | 1/0 | Keep line 129 as native-free ABI metadata. |
| `graphics.scrbl` | 0/0 | Cache limits and memory reports do not warrant visual output. |
| Surfaces and canvases — `surfaces.scrbl` | 3/0 | A01; keep allocation/access snippets at 51 and 67 without blank pictures. |
| `surface-properties.scrbl` | 1/0 | Keep line 70 numerical. Pixel-geometry declarations are not evidence of LCD output. |
| `canvases.scrbl` | 16/15 | F09–F10 and A02; other transforms and clips already have examples. |
| `layers.scrbl` | 2/1 | A03, then B09. Existing group-opacity image remains useful. |
| `specialized-canvases.scrbl` | 1/1 | F08 n-way provenance; C02 overdraw. No blank no-draw picture. |
| Color and effects — `colors.scrbl` | 6/1 | Existing swatches cover appearance. Keep pure conversions at 55, 76, 86, 99, 113 numerical. |
| `color-management.scrbl` | 6/0 | A04–A05. Keep space equality, transfer evaluation, gamut properties, and ICC serialization at 84, 158, 246, 329 numerical. |
| `float-colors.scrbl` | 9/5 | Cross-reference existing source-space comparison from line 138; pure value checks at 50, 81, 98 stay numerical. No duplicated float gradient gallery. |
| `paints.scrbl` | 13/10 | A06, B08; copying and resetting checks at 399 and 460 remain numerical. Review hairline density under F10. |
| `shaders.scrbl` | 15/15 | Core gradients, tiling, noise, empty shader, and local matrix already covered. B06 adds the missing custom-blender consumer. |
| `path-effects.scrbl` | 13/13 | B01–B02. Retain existing dash phase, compose/sum, trim, and stamp examples. |
| `color-filters.scrbl` | 9/8 | B03; identity-table check at 150 stays numerical. |
| `image-filters.scrbl` | 21/20 | B04–B07. Offset sample query at 203 connects to its existing offset figure. |
| `runtime-effects.scrbl` | 3/1 | B06. Solid-color compilation probe at 53 can refer to the existing shader example; closed-effect uniform packing at 133 remains numerical. |
| Geometry — `drawing.scrbl` | 12/11 | Primitive coverage is already broad. Clipped-color query at 308 can refer to the following result. |
| `paths.scrbl` | 25/20 | A07, B10, F12. Keep constructor containment at 62 and command/segment introspection at 404, 430; connect tangent query at 636 to the existing tangent figure. |
| `rounded-rectangles.scrbl` | 4/3 | B11; normalization values at 79 connect to the existing normalized-shape figure. |
| `regions.scrbl` | 5/4 | B12; keep the exact span values at 262 alongside any new diagram of their geometry. |
| `structured-drawing.scrbl` | 7/7 | F01, optionally C01. Nine-patch, lattice cell types, atlas tints, and patches already have useful results. |
| `portable-drawing.scrbl` | 6/5 | F02 repairs misplaced atlas coverage. Keep detached grid-plan query at 86 numerical. Existing portable nine/lattice/alpha examples remain. |
| `matrices.scrbl` | 8/1 | B13; retain numerical examples at 45, 110, 131, 160, 177, 193, 239. Add visual comparisons selectively, not one image per matrix constructor. |
| `projective-matrices.scrbl` | 3/1 | A08 and B13; singular-horizon examples at 109 remain numerical. |
| Images — `images.scrbl` | 8/6 | A09; `file/convertible` bytes at 219 remain numerical. Existing subset, subrect, alpha, sampling, and mirror images remain. |
| `image-operations.scrbl` | 2/1 | F03, B14, B18. Materialization flags at 85 remain numerical. |
| `encoding.scrbl` | 3/0 | Keep blank-file save at 28, PNG round trip at 98, and format-dispatch signature at 176 focused on their results. C04 is genuinely new content. |
| Text — `typefaces.scrbl` | 3/0 | B15; family count, style fields, and table tags at 55, 193, 334 remain numerical. |
| `fonts.scrbl` | 14/8 | B15–B16. Extend metrics at 170 with a separate actual drawing example. Keep ownership checks at 59, 398; link bounds/path/break queries at 293, 457, 496 to related figures. |
| `shaping.scrbl` | 9/7 | F11. Keep shaper snapshot and UTF-8 cluster queries at 40, 78 numerical. Existing positions, advances, kerning, and outlines cover the main visible family. |
| `text-blobs.scrbl` | 18/11 | A14 and B16. Keep snapshot/builder/metadata results at 44, 125, 199, 279, 357; intercept query at 507 already has a related figure. |
| `text-layout.scrbl` | 11/8 | F11, A13, B17; line 266 is the value-construction part of B17. Connect run-direction query at 323 to the mixed-text result. C05 is selective follow-up. |
| Recording — `pictures.scrbl` | 8/7 | Keep serialization-size example at 243 numerical. Existing recording, playback, background, nesting, and picture-shader examples cover the main outputs. Nonzero viewport example belongs in B18. |
| `drawables.scrbl` | 4/3 | Refer from the duplicate playback block at 89 to `drawable.png`. Keep the three distinct existing results. |
| Documents — `pdf-documents.scrbl` | 2/1 | F08 and A10. Metadata/lifecycle procedures need no separate thumbnails. |
| `svg-documents.scrbl` | 1/1 | F08 preview provenance. No generic SVG screenshot for every save/finish helper. |
| `output-pages.scrbl` | 8/6 | F07. Unit arithmetic at 31 stays numerical; distinguish the SVG example at 290 from its following raster example. |
| `annotations.scrbl` | 2/0 | Keep lines 91 and 120 as link/lifecycle and identifier examples. An annotation is invisible; a screenshot cannot show that a link works. |
| `output-audit.scrbl` | 2/0 | Keep capability/report results at 90 and 153. A blue-circle thumbnail would not explain audit policy. |
| `output-groups.scrbl` | 1/1 | F06. The callback/report semantics stay in text and returned data. |
| `gpu-output.scrbl` | 0/0 | Opt-in real GPU executor example only; cross-reference output groups. |
| Streams and codecs — `streams.scrbl` | 2/0 | Keep cursor, duplication, and detach examples at 123, 201 numerical. |
| `live-streams.scrbl` | 1/0 | Keep port-copy example at 104 numerical; separately record the runner failure in section 7. |
| `pixel-descriptions.scrbl` | 1/0 | Keep stride/allocation calculation at 134 numerical. |
| `raster-buffers.scrbl` | 4/2 | F05, A11, B14. Padding/storage-length result at 355 remains numerical. |
| `codecs.scrbl` | 1/1 | F04, optionally C03. Do not substitute an invented source image for a decoder result. |
| `scanline-codecs.scrbl` | 3/1 | A12. Read-count/state query at 159 connects to the existing batch example; no duplicate blue thumbnail. |
| `incremental-codecs.scrbl` | 3/1 | State transition at 102 and snapshot-lifetime/dimensions at 248 stay numerical; existing completed-result figure remains. Do not fabricate partial frames before pixels are initialized. |
| GPU rendering — `gpu-providers.scrbl` | 1/0 | Keep declaration query at 54 numerical. No image proves availability. |
| `gpu-context-options.scrbl` | 1/0 | Keep options comparison at 61 numerical. |
| `gpu-contexts.scrbl` | 1/0 | Keep scoped context helper at 114; link to a real drawing example when added. |
| `gpu-opengl-hosts.scrbl` | 0/0 | Host lifecycle, not a distinct drawing result. |
| `gpu-surfaces.scrbl` | 1/0 | Optional actual capture of the existing helper at 71; section 4.3. |
| `gpu-images.scrbl` | 1/0 | Optional actual filtered/subset result of helper at 127; section 4.3. |
| `gpu-transfers.scrbl` | 2/0 | Optional actual readbacks from helpers at 135, 182; section 4.3. |
| `gpu-synchronization.scrbl` | 0/0 | Synchronization/cache operations do not warrant PNGs. |
| `gpu-diagnostics.scrbl` | 0/0 | Reports and declarations remain textual/data examples. |
| GPU interoperability — `gpu-gl-interop.scrbl` | 0/0 | Host-specific handoff recipes belong with existing backend examples; no fabricated generic result. |
| `gpu-external-resources.scrbl` | 0/0 | Tokens and retirement are lifecycle concepts, not separate visual outputs. |
| `gpu-native-handoffs.scrbl` | 0/0 | Native pointer construction needs platform-specific code, not a stock screenshot. |
| Presentation — `gpu-presentation.scrbl` | 0/0 | Share an opt-in actual presenter example; snapshots do not establish presentation. |
| `gpu-widgets.scrbl` | 0/0 | Complete runnable GPU window example only with the opt-in classification from section 4.3. |
| `gui-canvases.scrbl` | 0/0 | Good first GUI example: explicit raster canvas and actual callback. |
| `render-canvases.scrbl` | 0/0 | Good shared window example: explicit renderer and documented callback lifetime. |
| Racket integration — `pict-bridge.scrbl` | 1/1 | Existing surface conversion correctly uses the bridge and the backing-scale convention. B18 adds picture bounds/density. |
| `racket-draw.scrbl` | 3/0 | A15 for the two existing path examples. Blank bitmap-dimension query at 88 remains numerical; B18 supplies a new nonblank bitmap/mask example. |
| `racket-dc.scrbl` | 0/0 | B19 adds a complete headless drawing/snapshot example. |
| `dc-output.scrbl` | 0/0 | B19 adds real capture, output-page, and bounded-raster examples. Annotation methods remain invisible. |
| `gpu-dc.scrbl` | 0/0 | Share an optional actual GPU scene through the scoped DC adapter; no ordinary-build GPU execution. |

## 6 Authoring and rendering rules

1. **Write the explanatory unit together.** Add or revise the introduction, complete displayed code, figure, visible caption, and alternative text in one edit. Explain the important distinction in one or two sentences. Keep code readable at normal manual width.
2. **Keep one result associated with its program.** Place it directly after the corresponding block or the short result explanation. Move useful older examples out of undifferentiated “Additional Visual Examples” sections when they otherwise leave their procedure entry disconnected; do not reorganize the entire manual as a prerequisite.
3. **Use real results.** Returned images, raster buffers, converted paths, recorded pictures, and text blobs must go through their documented operation. A scene that merely resembles the expected result is insufficient. Document-only content previews are the explicitly labeled exception described in F08.
4. **Separate source pixels from presentation.** For 1×1, 2×1, 3×2, and other pixel examples, capture the actual result and enlarge it with nearest sampling. Label original dimensions and any checkerboard or guides. For ordinary vector-like scenes, continue rendering at 2× and displaying at half scale. The native-scale capture helper can produce a 2× presentation PNG without changing the existing `reference-figure` interface.
5. **Make comparisons visible.** Keep source geometry, background, and scale constant when comparing one parameter. Use letters, row/column descriptions, or visible captions as well as color. Show unfiltered input when a filter's output otherwise has no reference point. Do not expect readers to detect a one-pixel edge change in a downscaled thumbnail.
6. **Choose compact scenes.** Most results should fit approximately 160–320 logical pixels wide; text or small multi-panel comparisons may need more. Keep padding for blur, shadows, caps, descenders, and overhang. Do not normalize away overflow when it is the subject of the example.
7. **Preserve runnable imports and lifetimes.** Native examples remain displayed code. Include opt-in modules where necessary. The existing runner provides only `skia` by default, so add `racket/class`, prefixed `racket/draw`, `skia/pict`, or other dependencies explicitly in examples that need them. Handle `#f` results before treating them as resources. Retain meaningful existing outputs.
8. **Register every asset.** Update the renderer, the chapter's figure declaration, and `LOGICAL_SIZES` together. Add the figure-helper import to previously unillustrated chapters. Use semantic new filenames without `stage11`/`stage12` suffixes. Preserve existing filenames unless an image's subject is being replaced, as in F05.
9. **Avoid a framework rewrite.** A native-scale capture helper and a small scene/source association record are sufficient initially. For touched scenes record the owner file, API/example label, input size, presentation size, and any font/backend requirement. Shared helpers may reduce duplication, but should not hide the public calls from readers. Migrating all 208 examples into a new authoring system is separate work.
10. **Verify at reading size.** Inspect the PNG and the rendered chapter. Check placement, clipping, comparison order, transparency, and whether alternative text describes the actual image. Accessibility text should convey the visible relationship rather than say only “output of function X.”

## 7 Validation and known baseline failures

### 7.1 Results from this editorial pass

- `python3 tools/validate-reference-images.py` passes: 208 PNGs and figure declarations.
- The source checker fails before runtime execution with `wrong canonical chapter: raster-buffer?`. There are exactly three observed chapter-map mismatches in [api/reference-coverage.json](/Users/soegaard/Dropbox/GitHub/skia-for-racket/api/reference-coverage.json): `raster-buffer?`, `raster-buffer-image-info`, and `raster-buffer->image` still name `pixel-descriptions.scrbl`; their definitions are in `raster-buffers.scrbl`. Reconcile these mappings against the existing chapter organization before using the checker as an acceptance gate. Do not weaken the canonical-definition check.
- The existing displayed-example suite, run through Racket 9.3.0.2, finishes with **7/590 test failures**. Five occur in `incremental-codecs.scrbl` and two in `live-streams.scrbl`, with `live-ffi: managed callbacks already claimed by another module or place`. The runner creates a fresh namespace for every block and retry; this is consistent with repeated module initialization conflicting with native callback ownership, but the failure does not by itself prove the remedy. Reproduce the affected blocks in fresh processes, then fix runner isolation if confirmed. Do not change live-stream ownership semantics or suppress exceptions to make an illustration check pass.
- Native font probing confirms that the default face on this machine is Helvetica and lacks the Hebrew glyphs used in F11. The existing PNGs independently show those missing glyphs.
- No Reference source, generator, PNG, API file, or source checksum was edited during this planning pass. The pre-existing untracked pict and Racket Draw plans remain untouched.

The source-check receipt is under `/private/tmp/skia-reference-editor-source-20261016/`. These failures are pre-existing validation work, not evidence that all drawing examples are invalid. Resolve them in a small validation commit or report their independently reproduced status while continuing editorial work that does not depend on them.

### 7.2 Commands for the Writer

Use the interpreter that resolves `skia` to this checkout. The shell's default `racket` here is 8.12 and does not find the collection; the configured 9.3.0.2 interpreter does. From the repository root:

```sh
SKIA_DOC_RACKET="/Applications/Racket v9.3.0.2/bin/racket"

# Source coverage, after reconciling the three stale mappings.
# --output must be a fresh directory outside the checkout.
python3 -B tools/check-reference.py --require-complete \
  --output /private/tmp/skia-reference-visual-source-check

# Regenerate only in the intended working checkout; this writes committed PNGs.
"$SKIA_DOC_RACKET" tools/render-reference-images.rkt
python3 -B tools/validate-reference-images.py

# Execute the actual displayed native code after resolving runner isolation.
"$SKIA_DOC_RACKET" -l raco -- test tools/reference-native-test.rkt

# Reference-only editing preview, not publication acceptance.
"$SKIA_DOC_RACKET" tools/reference-render.rkt +m --htmls \
  --dest /private/tmp/skia-reference-visual-preview \
  --dest-name skia-reference --redirect-main https://docs.racket-lang.org/ \
  --lib skia/scribblings/reference/reference.scrbl
```

Run the relevant existing semantic suites when changing their examples: `reference-core-test.rkt` for snapshots/clip/stroke geometry, `reference-effects-test.rkt` for effects, `reference-color-management-test.rkt` for sample conversion, `reference-geometry-test.rkt` for paths/regions, `reference-text-test.rkt` and `reference-blobs-test.rkt` for text, and the existing Racket Draw/pict tests for bridges. Add narrow semantic checks only for a new visual claim not already covered. Do not rely on whole-image byte hashes across platforms.

The image validator needs modest strengthening where the existing mistakes exposed gaps: source/example association, actual PNG decoding, and semantic probes for the problematic comparisons. Geometry positions, a known sample, nonzero glyph coverage, and a changed feature result are more useful than simply counting nonwhite pixels. At minimum, F09 must check both rectangle bounds and F10 must check intermediate edge coverage. Keep the cheap source/asset check usable without loading Skia.

After the relevant checks pass, inspect every changed figure at actual manual size and review the surrounding code/caption pair. Use an optional contact sheet as a review aid, never as a substitute for the rendered chapter. Regenerating on a different font/platform may alter unrelated text images: review that diff and avoid including unrelated churn.

For publication, use the integrated route from `REFERENCE-DEVELOPMENT.md`, including companion cross-references, rather than presenting the editing preview as a release-ready manual. An integrated command is:

```sh
python3 -B tools/check-reference.py --racket "$SKIA_DOC_RACKET" \
  --render --native --require-complete \
  --output /private/tmp/skia-reference-visual-integrated-check
```

Publication is not part of the current planning request. Before a future implementation commit, follow the repository's checksum workflow using `tools/update-source-sums.py` and its `--check` mode. Its inventory includes nonignored untracked files, including unrelated plans, so inspect that scope before updating; do not blindly stage or publish all untracked files. Keep source/asset changes and their checksum update coherent.

## 8 Work batches and completion criteria

| Batch | Deliverable | Completion condition |
| --- | --- | --- |
| 0 | Establish trustworthy validation | Reconcile the three canonical mappings; isolate/reproduce callback-ownership failures; record the usable native/font configuration. Keep any runtime-library issue separate from documentation edits. |
| 1 | Repair existing figures | F01–F12, including moved/replaced assets, correct native-scale rendering, and readable Hebrew. Every repaired figure matches its displayed example and caption. |
| 2 | Finish existing geometry and pixel examples | A01–A09 and F02's atlas result. Numerical conclusions are retained and actual intermediate resources are captured. |
| 3 | Finish existing text, document, scanline, and bridge examples | A10–A15, plus local references for the intentionally numerical/duplicate blocks in section 3.1. |
| 4 | Fill effects coverage | B01–B07 with shared comparison inputs and appropriate font-independent semantic checks. |
| 5 | Fill remaining CPU visual coverage | B08–B19, grouped by chapter into reviewable commits. C01–C06 are selective follow-ups, not an automatic gallery expansion. |
| 6 | Optional GPU and GUI illustrations | Real execution evidence, explicit backend/platform, and opt-in runner classification. Keep unavailable captures visible as outstanding work rather than fabricated results. |

For each batch, update a checklist of the IDs completed and any deliberately retained numerical examples. A completed item consists of accurate displayed code, the corresponding generated result, visible explanation, alternative text, registry entry, and successful relevant verification. Finishing the first pass means that every existing example with a useful visible result is either illustrated accurately, points clearly to an equivalent existing result, or has a specific nonvisual/optional-runtime disposition in the audit. Only then use the new-example list to expand coverage.

The immediate Writer assignment is batches 0–3. The plan's later batches provide the next queue; they do not justify postponing corrections to figures already in the manual.
