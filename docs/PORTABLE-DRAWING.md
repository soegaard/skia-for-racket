# Portable drawing

`portable-drawing.rkt`, also re-exported by `main.rkt`, offers explicit geometry and image decomposition for document output. It does not replace or change `draw-point`, `draw-points`, `draw-image-nine`, `draw-image-lattice`, or `draw-atlas`.

The portable calls emit ordinary geometry, image, and affine-transform operations **before recording**. Consequently a live picture and a bounded output group retain the lowered operations. The exporter does not need to recognize a native batch operation or parse custom annotations out of generated SVG.

Portable does **not** mean vector-only or pixel-identical. Marker shapes are vector geometry. Cropped source images are still raster images, with independent document placements. Browser interpolation, crop-edge antialiasing, color management, and small native rounding differences can affect appearance. The existing output auditor continues to reject embedded images under `vector-only`.

## Marker geometry

```racket
(draw-markers canvas points size paint #:shape 'circle)
```

`points` is a list or vector of two-coordinate lists/vectors. `size` is a positive finite diameter (circle) or side length (square), in local canvas units. `#:shape` is `'circle` (default) or `'square`.

The entire coordinate batch is checked and copied before painting. Each marker is centered on its point. Markers are drawn in input order; overlapping semitransparent markers accumulate normally, rather than being merged into one path. No marker changes the canvas transform, so a shader attached to the paint keeps a shared coordinate system across the set.

`paint` is an ordinary live `paint?`. Its fill/stroke style is honored. Stroke width is independent of marker size. Path effects, shaders and other paint attachments remain visible to the normal audit and may still require an output-group fallback. This API is deliberately **not** a claim to reproduce every native `drawPoints` hairline, cap, style-ignoring or batch-rasterization rule.

```racket
(with-skia ([fill (make-paint #:color 'blue)]
            [outline (make-paint #:color 'orange
                                 #:style 'stroke #:stroke-width 2)])
  (draw-markers canvas '((20 20) (50 20) (80 20)) 12 fill)
  (draw-markers canvas '((20 50) (50 50) (80 50)) 16 outline
                #:shape 'square))
```

Even an empty marker batch validates the paint and canvas lifetime/thread. Invalid input raises before painting; an unexpected native failure during a multi-operation draw is not a rollback transaction.

## Inspectable image-grid plans

```racket
(image-nine-plan image-width image-height center x y width height)
(image-lattice-plan image-width image-height lattice x y width height)
(image-grid-plan->jsexpr plan)
```

These are pure planning operations: they use numeric image dimensions rather than a native image resource. The dimensions are positive exact integers. A nine-patch `center` is an integer `(x y width height)` list/vector, nonempty and inside the image. `lattice` is the existing immutable `image-lattice?` value.

The result is a row-major list of immutable **`image-grid-cell?`** values with these accessors:

| Accessor | Result |
|---|---|
| `image-grid-cell-row`, `image-grid-cell-column` | Zero-based grid indices. |
| `image-grid-cell-kind` | `'default`, `'transparent`, or `'fixed-color`. |
| `image-grid-cell-source` | Immutable integer `#(x y width height)` crop. |
| `image-grid-cell-destination` | Immutable local `#(x y width height)` placement. |
| `image-grid-cell-color` | An immutable `rgba?` value for a fixed-color cell, otherwise `#f`. |

There is no public unchecked cell constructor. Source arrays, centers, and coordinate vectors are not borrowed. A plan remains usable after any native image is closed. `image-grid-plan->jsexpr` returns a JSON-ready list; colors are unsigned ARGB integers or `#f`.

The nine-patch has nine cells even when an edge touches the source boundary. Such cells can have zero source width/height. A small destination first collapses the stretch spans and proportionally shrinks the fixed spans; zero-width/height destination cells remain present in the plan but are not drawn. A zero destination is valid and paints nothing. Negative extents, invalid divisions, nonfinite coordinates, and out-of-image source boxes raise.

A lattice uses the existing strict-interior division rule. Spans alternate fixed/stretch, beginning with a fixed span. An undivided axis maps its entire source extent onto its entire destination extent. Nonzero source bounds retain their original source coordinates. Adjacent cells share computed, single-precision edges rather than independently rounded widths.

```racket
(define layout
  (image-nine-plan 30 24 '(6 5 17 12) 0 0 300 170))
(for ([cell (in-list layout)])
  (displayln (list (image-grid-cell-source cell)
                   (image-grid-cell-destination cell))))
```

## Portable nine-patch and lattice drawing

```racket
(draw-image-nine/portable canvas image center x y width height
                         #:sampling 'linear #:alpha 255)
(draw-image-lattice/portable canvas image lattice x y width height
                            #:sampling 'linear #:alpha 255)
```

Both return `void`. `#:sampling` is `'linear` (default) or `'nearest`. `#:alpha` is a byte, 0 through 255; it multiplies the source alpha **per cell**, not once on an isolated completed group.

Default cells use `image-subset` to retain an exact integer source crop, followed by the normal image-rectangle drawing API. Creating a crop does not resample or enlarge its pixels. Fixed-color cells are ordinary filled rectangles, with their color alpha multiplied by `#:alpha`. Transparent and zero-area cells are omitted.

Crops are created before drawing and closed deterministically after the operation. A recorder/paint backend retains what it needs for later replay. Repeated equal crops within a call share their native subset resource. The byte-limit parameter bounds the logical planning/batch payload, not all Skia allocations or the final document size.

These functions intentionally have **no arbitrary `#:paint` argument**: applying an image filter, custom blender, or mask to each separate cell can differ from applying it to a native grid or completed group. Use the unchanged native image-grid operation with explicit/automatic bounded fallback when those effects are required. Use a containing compositing layer when group opacity, rather than per-cell alpha, is intended.

The SVG contains crop-sized raster images with document-space placement, not one newly rendered bitmap at the destination panel size. This can improve editability and scaling when the underlying source pixels are adequate, but may increase resource and operation counts. Separate crop boundaries can expose viewer-dependent sampling seams under fractional placement or transforms. There is no blanket antialiasing or renderer-equivalence guarantee; retain bounded raster fallback when a seamless flattened result is required.

## Portable untinted atlas drawing

```racket
(draw-atlas/portable canvas image transforms source-rectangles
                     #:sampling 'linear #:alpha 255)
```

`transforms` uses the existing `atlas-transform?` values from `make-atlas-transform`. `source-rectangles` is a matching list/vector of integer crop boxes. Fractional source rectangles are rejected, not rounded. Source rectangles must be nonempty and inside the image. Empty batches still validate the source and receiver. Zero-scale sprites paint nothing.

Each sprite uses its own affine transform and an integer source crop. An anchor is relative to the crop's top-left corner, not the source atlas origin. Translation, rotation, scale and alpha are preserved as separate placement/drawing operations. The canvas matrix and clip are restored after each sprite. Repeated crops share their resource within the call.

```racket
(draw-atlas/portable
 canvas atlas
 (list (make-atlas-transform 40 50 #:scale 2 #:anchor '(12 12))
       (make-atlas-transform 120 50 #:scale 2 #:rotation 25
                             #:anchor '(12 12)))
 '((0 0 24 24) (0 0 24 24))
 #:alpha 220)
```

There is no `#:colors`, custom blend mode, arbitrary paint, or cull hint. The unchanged native `draw-atlas` remains the option for tinted batches, native batch-performance behavior, fractional source regions, or attached effects. Portable per-sprite edges need not match native triangle rasterization byte-for-byte.

## Output groups, pictures, and audit results

The portable calls are useful directly or inside `draw-output-group`:

```racket
(draw-output-group canvas 20 30 300 170
  (lambda (local)
    (draw-image-nine/portable local image '(6 5 17 12) 0 0 300 170)))
```

A plain marker group can remain `vector-only`. A portable image group can stay **native-compatible**, but its audit still contains `image / embedded-raster`, so it is not vector-only. No `point-sprites`, `image-grid`, or `image-atlas` capability is silently upgraded. The existing native APIs and conservative classifications are untouched.

Projective outer transforms, unsupported paints, opaque imported SKP, annotations inside rasterization, and other pre-existing audit restrictions are not relaxed. Serialization still discards trusted Racket-side provenance: loading an SKP made from portable operations is still an unknown imported picture.

## Reference and scope

The fixed/stretch partitioning follows the pinned `SkLatticeIter` implementation, particularly its small-destination rule and special nine-patch constructor:

https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/core/SkLatticeIter.cpp

This is the first vector-output refinement pass. Simple SVG layer opacity, SVG patterns for picture shaders, arbitrary tint/effect lowering, and a Racket-owned SVG backend are not introduced here. The portable module adds no native symbols or ABI layouts.
