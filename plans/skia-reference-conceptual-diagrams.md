# Skia Reference conceptual diagram plan

## Editorial recommendation

The Reference needs conceptual diagrams as well as rendered examples. A rendered example answers “what does this code draw?” A conceptual diagram answers “which coordinate, boundary, space, or lifetime does this argument describe?” The current pictures often show the result without making those relationships visible.

Start with the nine first-priority briefs below. The eleven second-priority briefs address narrower APIs or can follow the existing-example work. These are editorial work items, not a requirement to add twenty independent pictures: reuse and annotate an existing example when it can explain the relationship clearly, and cross-reference one canonical explanation from related entries.

This is a companion handoff for **Documentation - Writer** to the [visual examples plan](/Users/soegaard/Dropbox/GitHub/skia-for-racket/plans/skia-reference-visual-examples.md). It covers all 71 leaf chapters in the 13 Reference groups. Source locations refer to the working checkout at `d687d39e960e85996c11e22c70c6ccb92ca65674`; use the named section or API when concurrent documentation work moves a line. This plan does not change the Reference or implement figures.

The strongest initial text treatment is three separate explanations:

1. Font metrics are coordinates relative to a baseline.
2. An advance interval is not an ink bounding box.
3. A paragraph layout has its own origin, baseline step, and reported dimensions.

Putting all three into one typography chart would obscure the distinctions the reader needs.

## First priority

### D01 Baseline and font metrics

Place a new conceptual figure after the introduction to [Font Metrics](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/fonts.scrbl:157), before the metric accessors. Cross-reference it from `draw-simple-text` and Text Layout. Suggested asset: `concept-font-metrics.png`, approximately 460 by 230 logical units.

Draw a short specimen such as “Hgx” with a marked baseline origin, a downward-positive y arrow, the baseline, and the ascent and descent guides. Label the returned coordinates `ascent = a < 0` and `descent = d > 0` for the chosen ordinary font. Label the distances above and below the baseline as `-a` and `d`. With a drawing baseline at `b`, the guides are at `b+a`, `b`, and `b+d`.

Use actual `font-get-metrics` values for the illustrated font. Add a small secondary panel for cap height and x-height, treated as distances, only if the chosen font supplies useful values. Keep top/bottom and decoration metrics out of the primary panel; explain in the adjacent prose that top/bottom are separate native extents and that font metrics are not the bounds of this particular string. Do not equate font size with ascent plus descent, turn negative ascent into a positive returned value, or imply all glyph ink fits between the ascent/descent guides.

Caption: “The baseline is the origin for vertical font metrics. In the usual downward-positive canvas, ascent is above it and normally negative; descent is below it and normally positive.”

Acceptance: moving the drawing baseline translates every guide consistently; labels come from the same font used for the specimen; the graphic makes sense without knowing the colors. This develops B15 of the visual examples plan, rather than adding a second competing metrics example.

### D02 Advance versus ink bounds

Place beside [measure-simple-text and simple-text-bounds](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/fonts.scrbl:278). Cross-reference from shaped-run advances and text alignment. Suggested asset: `concept-text-advance.png`, about 460 by 190.

Extend the teaching idea of `font-bounds.png`, not its unexplained red rectangle. Compare “A” and “A ” on a common baseline. Mark each drawing origin, its advance endpoint, and its measured ink rectangle. Show the trailing space as a bracket below the baseline, explicitly labeled as an annotation, not as a drawn space glyph. An optional italic specimen can demonstrate overhang, but only if its measured bounds actually extend beyond the advance interval.

Translate bounds by the drawing origin: `(origin-x+bx, baseline-y+by, bw, bh)`. Do not use advance as `bw`, suggest a space has visible ink, or call simple-text bounds a guarantee about arbitrary filtered output. Keep shaped and unshaped measurements labeled if both appear.

Caption: “Advance determines where the next origin goes. Ink bounds describe the measured string geometry; a trailing space can increase advance without adding ink.”

Acceptance: the endpoint is computed with `measure-simple-text`; the rectangle uses `simple-text-bounds`; the trailing-space difference is visible at normal manual size. Coordinate this with B15 and the existing bounds example.

### D03 Layout origin, line spacing, and wrapping width

Place after the metric paragraph in [Wrapping and Alignment](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/text-layout.scrbl:22), with a cross-reference from `draw-text-layout`. Suggested asset: `concept-layout-box.png`, about 480 by 300, using two panels.

The main panel shows a three-line layout, its upper-left origin, the first baseline, the baseline-to-baseline step, and the reported height. Label `first baseline = max(0,-ascent)` and `height = max(0,-ascent) + (n-1)*line-height + max(0,descent)`. Use line records for the actual baseline locations. Distinguish the baseline step from the blank gap between ink on neighboring lines. Native recommended spacing is not universally the font size; an explicit small line height can overlap ink.

The second panel shows the existing unbreakable-word case: a dashed requested-width guide, the larger reported layout box, and the complete word. Label both widths. Neither the requested width nor the layout box adds a drawing clip. Base-font metrics determine the reported height, not the union of fallback glyph ink.

Caption: “A layout is drawn from its box origin, not a text baseline. Line height measures baseline spacing; the wrapping width is not a clipping boundary.”

Acceptance: labels agree with layout queries; overflow remains visible. Reuse A13 and B15 rather than maintaining duplicate overflow and spacing specimens. Keep alignment galleries separate; they already illustrate different choices.

### D04 Local coordinates and transform order

Place in [Changing Coordinates](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/canvases.scrbl:117). Link from [Notation and Conventions](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/notation.scrbl:23) and [matrix-compose](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/matrices.scrbl:124). Suggested asset: `concept-transform-order.png`, about 480 by 240.

Replace or supplement the teaching role of `transform-order-stage9.png` with two labeled coordinate diagrams. Use translation `T=(10,20)`, uniform scale `S=2`, and point `p=(3,4)`. Show `T(S(p))=(16,28)` versus `S(T(p))=(26,48)`, with local axes, the original point, and the transformed point. Put the corresponding canvas call order beside each panel. Label initial x-right/y-down orientation and distinguish local units from target coordinates.

Explain that `(matrix-compose T S)` applies S first to a point, while canvas calls translate-then-scale accumulate `T*S`. Do not label argument order and point-application order identically. Existing pixels do not move when the transform changes. Do not introduce a six-coefficient row-major matrix diagram: this API's coefficient order is `xx, yx, xy, yy, x0, y0`.

Acceptance: pure matrix queries reproduce both endpoints; the same base target coordinates are used in both panels. This is the explanatory component of B13, not another unannotated rotated rectangle.

### D05 Established clips and saved state

Place at the introduction to [Clipping](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/canvases.scrbl:246), and link from reset-transform and state scopes. Suggested asset: `concept-clip-state.png`, about 480 by 240.

Use three frames on a fixed target grid: establish a clip under a translation; reset the transform and draw through the unchanged clip; restore the outer saved state and make another mark. Track the local origin separately from the clip. A simple numeric fixture is translate `(20,10)`, then clip local `(0,0,40,30)`: the established target rectangle is `(20,10,40,30)` even after reset.

Show prior marks remaining after restore. Label “transform and clip restored” and “pixels already drawn remain.” A small inset can reuse A02's intersection/difference example to show both operate within the existing clip and neither enlarges it. Conservative clip bounds are not exact coverage, especially with antialiasing.

Caption: “Clipping geometry is transformed when the clip is established. Later transform changes move drawing coordinates, not the established clip.”

Acceptance: drawing and reset occur on the actual subject canvas; presentation scaling must not accidentally change the semantics being illustrated. Do not imply state restoration rolls back paint mutations or drawing.

### D06 Per-draw opacity versus layer opacity

Place after the opening explanation in [Canvas Layers](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/layers.scrbl:12). Suggested asset: `concept-layer-compositing.png`, about 480 by 240.

Pair the existing overlap specimen with an explicit two-route diagram. Route one draws each translucent rectangle onto the parent, so their overlap accumulates opacity. Route two draws opaque rectangles into a transparent intermediate layer, then composites that completed group once with the group opacity. Show the intermediate target and the restore/composite arrow, not only the two final pictures.

Reuse `canvas-layer.png` as the group result or replace it with a clearly labeled comparison whose code includes both routes. State that an ordinary state save creates no intermediate group. Layer bounds can restrict the extent but are not an exact canvas clip; restoring a layer composites even during exception cleanup. Do not depict backdrop filtering as filtering only the later foreground drawing.

Acceptance: the two routes share geometry, background, and group color; labels identify when opacity is applied. Coordinate with B09. A separate backdrop-flow inset can follow once its existing-example task is complete.

### D07 Source rectangles and filtered-result placement

Place the main explanation at [Filtering and Result Placement](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/image-operations.scrbl:141). Cross-reference the rectangle convention from [draw-image-subrect](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/images.scrbl:178). Suggested asset: `concept-image-placement.png`, about 480 by 230.

Show three labeled spaces: the original filtering coordinates; the returned image with its returned `source=(sx,sy,sw,sh)` highlighted; and that source rectangle placed at the returned `offset=(ox,oy)`. Connect corresponding corners. A small ordinary subrectangle panel may show source pixels mapping to a differently sized destination rectangle; make clear that this optional scaling is not what the filter offset itself means.

The key rule is that the offset places the selected source rectangle's upper-left corner, not necessarily the full returned image's origin. The existing red rectangle in `image-filter-placement.png` does not communicate that distinction. Use actual result metadata for a native illustration. If the native implementation returns an uninteresting full-image source, add a separately labeled schematic with a nonzero source origin rather than inventing a native result.

Acceptance: drawing the selected source at the offset matches the source/offset recipe in the Reference. Rectangles are x/y/width/height, never opposite-corner tuples. Coordinate with B14 and the existing placement example.

### D08 Filter graphs and crop order

Place near [Coordinates, Inputs, and Crops](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/image-filters.scrbl:30), linking to `make-compose-image-filter`. Suggested asset: `concept-filter-graph.png`, about 480 by 300.

Use directed boxes for `source → crop → blur` and `source → blur → crop`, with matching small rendered results. Choose a crop cutting through the source so the two orders visibly differ. Label the input port `#f = dynamic drawing source`. For composition, show that `(make-compose-image-filter outer inner)` feeds the inner result into the outer graph's dynamic source slots. If a branching inset is needed, two false input slots receive the same source, not two transparent images.

Caption: “A graph connects inputs; constructing it does not process pixels. Cropping before a blur changes its input, while cropping afterward restricts its output.”

Do not use blur versus translation alone to prove order matters: such a fixture can commute and conceal the lesson. Distinguish node-output crop from the canvas clip. Avoid a purported universal paint/shader/filter pipeline that the current Reference does not specify.

Acceptance: each arrow corresponds to a real input relationship, both results come from those graphs, and the crop boundaries explain the visible difference. Existing individual-filter swatches remain useful and need not be duplicated.

### D09 Pixels, row stride, and padding

Place beside [image-info-storage-layout](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/pixel-descriptions.scrbl:119). Link from raster buffers, pixmaps, scanline batches, and typed transfers. Suggested asset: `concept-pixel-stride.png`, about 480 by 210.

Draw the existing 3 by 2 RGBA8888 case as two rows of byte cells. Each row contains three four-byte pixels and four padding bytes. Label tight row length 12, row stride 16, second-row start offset 16, minimum addressable length 28, and full allocation 32. Pixel bytes occupy offsets 0–11 and 16–27; padding occupies 12–15 and 28–31. Use brackets for the three returned values `(16,28,32)`.

Caption: “Row stride includes padding. The minimum addressable length stops at the last pixel; the full allocation also includes final-row padding.”

Acceptance: byte counts match the existing evaluated example; padding is visibly not a fourth pixel. Keep logical channel order versus physical BGRA byte order in a small accompanying table, not an ambiguous colored-pixel picture. A pixmap subset retains its parent storage layout; it is not necessarily a newly packed image.

## Second priority

### D10 Page origin, margins, and content clip

Place beside [make-output-page](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/output-pages.scrbl:43). Suggested asset: `concept-page-margins.png`.

Draw the full page and inset content area using deliberately unequal margins. Label left, top, right, bottom in that order; mark the page origin and callback origin separately. Dimension the full page and content sizes in page units. A mark crossing the content boundary can compare `#:clip? #t` and `#f` without changing the origins. Explain that `draw-output-page` treats target units as points and establishes page units for the callback. Do not imply CSS margin order or a hardware-dependent meaning of `'px`.

Acceptance: content width/height equal page extents minus paired margins. Fold this into the output-page corrections and examples already planned, not another unrelated page screenshot.

### D11 Raster fallback padding and placement

Place beside [draw-rasterized](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/output-pages.scrbl:262). Suggested asset: `concept-raster-padding.png`.

Show the original logical content rectangle inside a larger transparent raster region, with four unequal padding values. Mark callback `(0,0)`, target `(x,y)`, and the snapshot placement `(x-left,y-top)`. Add a scale inset: allocated pixel width is `ceiling((width+left+right)*scale)`, with the analogous height formula. Show blur extending into padding, not content shrinking to make room.

Caption: “Padding enlarges the raster region without moving the logical content. The completed image is placed back with its original content origin unchanged.”

Acceptance: distinguish the callback canvas, which does not inherit the target transform/clip, from final image drawing, which does. Link D17 for density. Reuse the existing `draw-rasterized.png` subject; do not claim the resulting region remains vector geometry or searchable text.

### D12 Curve controls and different bounds

Place at [Geometry and Bounds](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/paths.scrbl:308), linking back to segment construction. Suggested asset: `concept-path-bounds.png`.

Draw a cubic with endpoints and off-curve control points, a dashed control polygon, its stored-point bounds, and tight geometric bounds. Label endpoints and controls; the curve normally does not pass through its controls. An inset can compare a quadratic's one control with a cubic's two. Use distinct line styles for the two rectangles, not color alone.

Acceptance: rectangles come from `path-bounds` and `path-tight-bounds`; the chosen curve makes their difference substantial. Neither includes stroke width, filters, transform, or clip. A small transformed-rectangle inset may show `matrix-map-rect` returning an axis-aligned envelope, not a rotated rectangle. Consolidate with B10 and B13.

### D13 Winding and even-odd fill rules

Place after the rules in [Construction and Fill Rules](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/paths.scrbl:27). Suggested asset: `concept-fill-rules.png`.

Upgrade the existing fill-rule comparison with direction arrows on nested contours and one labeled test ray. Use a two-by-two comparison: same versus opposite contour directions, winding versus even-odd. Label the center's signed winding total and crossing parity. Choose the sign convention explicitly or explain nonzero versus zero without claiming a universal positive direction.

Caption: “Winding uses a signed total; even-odd uses crossing parity. Reversing the inner contour can change a winding fill without changing an even-odd fill.”

Acceptance: actual filled paths match each label. Keep the separate rule that open contours are treated as closed for filling in prose; it does not mean `path-close!` is unnecessary for stroke joins. Do not add another unannotated donut.

### D14 Nine-patch and lattice stretching

Place at [Nine-Patch and Lattice Images](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/structured-drawing.scrbl:193); link from the portable variants. Suggested asset: `concept-nine-patch.png`.

Show a source grid and destination grid with matching numbered cells and dimension arrows. In the normal enlarged destination, corners remain fixed, edge cells stretch along one axis, and the center stretches along both. Mark the selected center rectangle by x/y/width/height, not opposite corners. A small inset shows a destination smaller than the fixed spans, where those spans shrink and stretchable spans can collapse.

Acceptance: source divisions lie inside the bounds; source and destination share an unmistakable cell correspondence. Explain that general lattices alternate fixed/stretchable spans starting with fixed. The existing blue-border image alone does not show which source spans produced the result.

### D15 Characters, UTF-8 bytes, and shaped glyphs

Place beside [shape-text](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/shaping.scrbl:51), and link from text-blob cluster metadata. Suggested asset: `concept-text-clusters.png`.

Draw aligned rows for characters, UTF-8 byte positions, and glyph records. The existing “éA” example gives an exact first panel: character indices 0 and 1, byte starts 0 and 2, two characters but three bytes. A second, font-verified ligature example can map several characters to a glyph and mark its cluster start. Label stored origins separately from glyph outlines.

Acceptance: glyph IDs, counts, and clusters come from the actual shaper. Never promise a particular font forms a ligature. State that RTL cluster offsets can descend and that clusters are not a complete caret map. Break-provider indices are Racket character indices, not these UTF-8 offsets. The simple byte relationship could be a native table; use a figure only when the glyph associations add explanatory value.

### D16 Tangent and normal for text on a path

Place in [Placing Shaped Text on a Path](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/text-blobs.scrbl:552). Link from path measurement. Suggested asset: `concept-text-path-frame.png`.

Show the contour direction, an arc-length bracket from the contour start to sample distance `s=start+gx`, the unit tangent `(tx,ty)`, and the normal `(-ty,tx)`. Mark the final glyph origin at `P(s)+(normal+gy)*(-ty,tx)`. Use a straight rightward segment first to make positive normal visibly downward, with a curved inset showing rigid glyph rotation.

Acceptance: label start offset and normal offset independently; do not bend glyph outlines or show automatic fitting/wraparound. The accepted range applies to glyph origins, not all ink; a glyph can overhang an endpoint. Coordinate with A14 and B10 so the retained-blob example and the geometry explanation share one fixture where practical.

### D17 Logical dimensions and physical pixels

Place in [Racket Pict Bridge](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/pict-bridge.scrbl:33), with links from Racket Draw interoperability and raster fallback. Suggested asset: `concept-raster-density.png`.

Use two explicitly different routes. A 120 by 80 pixel image passed to `image->pict` with backing scale 2 remains 120 by 80 pixels but becomes a 60 by 40 logical pict. A picture viewport of 120 by 80 logical units passed to `picture->pict` with raster scale 2 produces 240 by 160 physical pixels while remaining a 120 by 80 logical pict. Label every dimension with “pixels” or “logical units.”

Acceptance: do not imply changing backing scale resamples an image, or that raster scale changes the picture's logical size. An optional viewport inset shows bounds translated to the raster origin and clipped. Explain ceiling for fractional dimensions in prose. This develops B18; it must not conflate Racket bitmap backing scale, page DPI, and the documentation renderer's 2× asset scale.

### D18 Owners, borrowed views, and independent results

Place after [Resource Kinds and Validity](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/resources.scrbl:13), with a specific pixmap inset linked from [Scoped Pixel Views](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/raster-buffers.scrbl:151). Suggested asset: `concept-resource-lifetimes.png`.

Use a time axis, not a misleading universal ownership tree. Show a CPU surface open until close, its borrowed canvas usable while the owner is valid, and an independently owned snapshot still open after the surface closes. In a separate row, show a buffer's pixmap and subset valid only inside their callback, even if their wrappers are retained. Label the snapshot as independent lifetime, not necessarily a deep copy of native storage.

Acceptance: no arrow implies that keeping a borrowed wrapper reachable extends validity. A detached metrics snapshot can survive its font, but do not generalize to “all detached values can draw without resources”: layouts retain shapers that must remain open. Keep GPU lease/thread rules separate and link D20. The existing lifetime code remains the executable evidence.

### D19 Color interpretation versus conversion

Place beside the two-image example in [Color Management](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/color-management.scrbl:35). Suggested asset: `concept-color-interpretation.png`.

Use a two-branch data-flow diagram: identical opaque RGB bytes `(128,128,128)` are declared as sRGB or linear sRGB, then drawn into the same sRGB destination. Label the resulting values 128 and approximately 188, respectively, alongside the swatches. The constructor's tag declares meaning; drawing into the tagged destination performs conversion. Color-space construction alone converts no samples. An untagged source must not be relabeled as implicit sRGB.

Acceptance: the numerical labels, not a reader's display, carry the claim. Keep alpha premultiplication and RGBA/BGRA layout in separate compact numeric tables; they are different concepts from color-space encoding. Merge with A04/A05. Do not add speculative gamut diagrams or use ordinary PNG swatches to promise HDR appearance.

### D20 GPU submission, readback, and presentation

Place at [GPU Synchronization and Resource Caches](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/gpu-synchronization.scrbl:9), with cross-references from transfers, output, and presenters. Suggested asset: `concept-gpu-boundaries.png`.

Show pending drawing, flush, submission, and requested CPU completion as distinct boundaries. Add separately labeled readback and presentation routes, not a single compulsory chain. `gpu-submit!` submits previously flushed work; `gpu-wait!` includes flush and submission. Readback copies pixels into an independent CPU result and may include synchronization internally. Presentation is requested through the presentation API; a completed wait alone neither copies nor presents pixels.

Acceptance: this is an API responsibility diagram, not a GPU scheduling trace or performance claim. Note owning-thread/active-context requirements. Presentation success denotes a request, not proof of physical display. Reuse D18's scope vocabulary for borrowed frames, but do not promise a CPU lifetime rule covers GPU leases or external fences. No live GPU screenshot is required to explain these distinctions.

## Optional annotations rather than new diagram projects

| Topic | Editorial action |
| --- | --- |
| Stroke caps, joins, and miter limits | Add endpoint/centerline marks and cap/join labels to the existing comparisons; include the planned miter-limit comparison from B08. A full stroke-construction tutorial is unnecessary here. |
| Dash phase and shader tile modes | Label the repeat interval, phase origin, or tile boundary on existing comparisons. For shader local matrices, a small inverse-coordinate inset can reuse D04; do not create another matrix primer. |
| Atlas anchors | If B06/B13's examples remain unclear, add a source-crop/local-origin/anchor inset: `make-atlas-transform` maps its local anchor to `(x,y)`. Do not locate the anchor in full-atlas coordinates by accident. |
| Integer regions | Annotate B12's path-to-region example with an integer pixel grid and one scanline span. This explains quantization better than another smooth region silhouette. |
| Scanline order and codec orientation | Add row indices and destination arrows to A12's bottom-up example. For encoded orientation, a labeled asymmetric corner pattern is enough if an actual orientation example is added. No decorative codec pipeline is needed. |
| Projective matrices | B13's transformed-grid example can mark the original grid and projected bounds. A separate homogeneous-division/horizon diagram is a later Guide topic unless users need help with `#f` results near a zero divisor. Keep matrix storage order in a table. |
| Meshes and cubic patches | Label vertices, triangle indices, and patch control points on existing figures if their argument ordering is difficult to follow. Do not add a general tessellation tutorial. |
| Document and presenter lifecycles | A compact state/operation table is initially preferable. Add a state-transition diagram only when every normal, error, and cancellation edge is checked against the specific API; do not invent one generic state machine. |

## Coverage of the whole Reference

The group names link to their chapter lists. The following dispositions account for all leaf chapters, including those that need no additional conceptual figure.

| Reference group and chapters | Disposition |
| --- | --- |
| [Foundations](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/foundations.scrbl): Notation and Conventions; Resources and Lifetimes; Native Libraries and Capabilities; Global Caches and Memory Statistics | D04 and D18. Capabilities, installation, caches, and memory statistics need prose/tables, not drawings of imagined allocation behavior. |
| [Surfaces and Canvases](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/surfaces-and-canvases.scrbl): Surfaces and Canvas Access; Surface Properties; Canvas State; Canvas Layers; Specialized Canvases | D04–D06 and D18. Surface properties need no physical subpixel diagram without a supported display-specific example. Specialized canvases can reuse the existing multi-target example. |
| [Color and Effects](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/color-paint-effects.scrbl): Color Specifications; Color Management; Floating-Point Colors; Paints; Shaders and Gradients; Path Effects and Mask Filters; Color Filters; Image Filters; Runtime Effects and Blenders | D08 and D19, with the optional stroke/shader annotations. Swatches and existing effect comparisons suffice for appearance; storage/alpha tables serve numeric formats. Runtime uniform layouts need an offset table, not another shader image. |
| [Geometry and Drawing](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/geometry-and-drawing.scrbl): Drawing Primitives; Paths; Rounded Rectangles; Integer Regions; Meshes, Patches, Image Grids, and Atlases; Portable Markers and Image Grids; Affine Matrices; Projective Matrices | D04, D12–D14, and D16. Use optional region/mesh/atlas/projective annotations as needed. Primitive and rounded-rectangle examples already show their geometry; share the rectangle-coordinate convention. |
| [Images](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/image-api.scrbl): Images; CPU Image Operations; Image Encoding | D07, D17, and D18. File formats, quality ranges, and encoding ownership are better explained by tables/prose. Encoding does not need a decorative arrow from pixels to a file icon. |
| [Text and Fonts](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/text-and-fonts.scrbl): Font Managers and Typefaces; Fonts and Text Measurement; Shaped Text; Text Blobs; Text Layout | D01–D03, D15, and D16. Typeface discovery and fallback policy should stay textual, supplemented by the planned real fallback examples. Glyph-run variants can label their existing origin markers. |
| [Recording](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/recording.scrbl): Pictures; Recorded Drawables | Cross-reference D18 for retained ownership and D17 for rasterized viewport semantics. Existing playback examples suffice; nominal/cull bounds must not be depicted as guaranteed output clips. |
| [Documents and Output](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/documents-and-output.scrbl): PDF Documents; SVG Documents; Output Pages and Raster Fallback; Links and Named Destinations; Output Policies and Auditing; Bounded Output Groups; GPU Raster Output Execution | D10, D11, D18, and D20. Use lifecycle/policy tables. Link rectangles may get a labeled overlay on an existing page, but screenshots do not prove hyperlink, searchable-text, or vector semantics. |
| [Streams and Pixels](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/streams-pixels-codecs.scrbl): Native Streams and Buffered Ports; Live Port Input and Output; Pixel Descriptions and Formats; Raster Buffers and Pixmaps; Image Codecs and Frames; Scanline Decoding; Incremental Image Decoding | D09 and D18, plus the optional scanline annotation. Cursor positions, duplicate/fork behavior, callback restrictions, and incremental states can use concise examples and tables. |
| [GPU Rendering](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/gpu-rendering.scrbl): GPU Backends and Providers; GPU Context Options; GPU Contexts and Lifetimes; OpenGL Hosts; GPU Surfaces; GPU Images and Filtering; GPU Readback and One-Shot Rendering; GPU Synchronization and Resource Caches; GPU Diagnostics | D20 and carefully scoped links to D18. Provider support, options, host requirements, and diagnostics are tables/prose; generic hardware architecture drawings would add unsupported detail. |
| [GPU Interoperability](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/gpu-interoperability-output.scrbl): OpenGL Interoperation; External GPU Resources; Metal and Direct3D Native Handoffs | Link D20. Keep backend-specific ownership, fence, queue, and handoff requirements explicit in prose. Defer bespoke lifecycle diagrams until their state edges are independently checked. |
| [Presentation and GUI](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/presentation-and-gui.scrbl): GPU Presenters and Frames; GPU GUI Widgets; GUI Drawing Canvases; Unified Render Canvases | D20 and a borrowed-frame adaptation of D18 if needed. Distinguish persistent targets from callback-scoped frame canvases in text; use tables for scheduling/state differences. |
| [Racket Integration](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/racket-integration.scrbl): Racket Pict Bridge; Racket Draw Interoperability; Racket Drawing Contexts; Drawing-Context Output; GPU Drawing Contexts | D17, with D10/D11 for output and D18/D20 for scope. Existing-example tasks cover masks and path conversion. A single box labeled “Racket ↔ Skia” would hide the actual copy and lifetime differences. |

## Implementation rules for Writer

Use the current pipeline: [figure helper](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/support/figures.rkt), [image generator](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/render-reference-images.rkt), [PNG assets](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/images), and [image validator](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/validate-reference-images.py). The helper currently accepts PNG and displays at half the asset dimensions. Generate exact engineering geometry with code; this does not call for AI-painted illustrations or a new external drawing dependency.

1. Label each conceptual figure as an explanation, not silently as the literal output of the adjacent code block. If the printed example includes the guides, execute that complete example. Otherwise keep annotation generation separate and say what the guides mean.
2. Use one canonical home for each concept and section links from related entries. The validator currently expects unique figure declarations; cross-reference the section instead of repeating the same asset declaration throughout the Reference.
3. Keep labels readable at the actual half-size display. Start around 13–15 logical units for label text, use short labels and numbered panels, and split an overloaded figure. Budget roughly 420–480 logical units in width, then check the real manual column before finalizing.
4. Use solid/dashed boundaries, arrows, brackets, and direct labels as well as color. Distinguish content, measured bounds, requested bounds, and explanatory guides. Checkerboards and byte-grid padding are annotations, not source pixels.
5. Derive geometry and labels from one fixture. Font-dependent diagrams must measure their chosen font, check needed glyph coverage, and avoid hard-coded cross-platform metrics or ligature counts. If stable redistribution of a font is needed, resolve its license and repository policy before adding one.
6. Keep the subject's coordinates independent of presentation scaling. Especially for transform reset/set and device clips, render the subject at its intended scale first and annotate it afterward, or explicitly preserve the renderer's scale without changing the example's semantics. Do not reset away the 2× output scale unnoticed.
7. Add a concise visible caption and meaningful alternative text. Put essential equations, units, and conclusions in surrounding Scribble prose too; readers must not have to extract numbers from pixels. The figure helper's alternative-text argument is not a visible caption.
8. Prefer a table when it explains the concept completely: byte-order mappings, units, enum choices, callback requirements, and state/operation permissions generally do not need a PNG.

## Suggested work batches and acceptance checks

| Batch | Scope | Completion condition |
| --- | --- | --- |
| 1 Text fundamentals | D01–D03; consolidate B15 and A13 | Font metrics, advance, ink, layout origin, and line spacing are visibly distinct. No missing glyphs or clipped overflow. |
| 2 Canvas state | D04–D06; coordinate with A02/B09/B13 | Annotated transform order, fixed clips, and group opacity match actual operations. |
| 3 Image and storage contracts | D07–D09; coordinate with B14 and existing filter examples | Returned source/offset, graph order, and `(16,28,32)` storage layout are unambiguous. |
| 4 Geometry and text internals | D12–D16 | Controls, bounds, winding, grid stretching, byte clusters, and tangent/normal signs are verified. |
| 5 Output and integration | D10/D11/D17–D20 | Page/raster origins, density, lifetime boundaries, color interpretation, and GPU responsibilities are not conflated. |

For each batch, commit the Scribble explanation, deterministic generator changes, generated assets, and validator size entries together. Do not mix unrelated API fixes or backend changes into a diagram commit. Reconcile the earlier plan's overlapping tasks before starting; a single annotated example can satisfy both plans.

Run the image generator with the configured Racket that resolves this checkout, then `python3 -B tools/validate-reference-images.py`. Use a normal source check and execute any new or changed runnable examples. Render a fresh Reference-only HTML preview using the procedure in [Reference Development](/Users/soegaard/Dropbox/GitHub/skia-for-racket/docs/REFERENCE-DEVELOPMENT.md:639); use an output directory outside the checkout. The available Racket for this checkout at review time is `/Applications/Racket v9.3.0.2/bin/racket`.

Inspect every changed page at normal display size, not just the full-resolution PNG. Check text legibility, line styles, correspondence between caption and diagram, and cross-reference destinations. Add exact assertions for pure facts such as D04's mapped points and D09's byte lengths; check native geometry and metadata for the font/filter examples rather than asserting portable pixel identity. If an existing validation failure remains, identify it separately from the new diagram work rather than silently treating the batch as fully green.

The first useful stopping point is completion of batches 1–3. Evaluate the second-priority diagrams after those are integrated: keep each one only if it explains a relationship the nearby prose, tables, and literal examples still leave difficult to see.
