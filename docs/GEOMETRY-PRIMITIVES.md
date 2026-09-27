# Structured geometry and advanced image drawing

Available from `(require skia)` or `(require skia/geometry-primitives)`.
The existing `rounded-rect?` specification from `canvas-primitives.rkt` is reused;
this module does not introduce a competing rounded-rectangle representation.

## Integer regions

A `region?` is an owned native set of integer cells. Rectangles use
`(x y width height)` and are half-open: the right and bottom edges are excluded.
The public operations return new regions rather than mutating their inputs.

```racket
(with-skia ([outer (make-region '((10 10 140 90)))]
            [hole (make-region '((40 30 60 40)))]
            [frame (region-difference outer hole)]
            [paint (make-paint #:color 'blue)])
  (draw-region canvas frame paint)
  (for ([rectangle (in-region-rectangles frame)])
    (displayln rectangle)))
```

`make-region` takes a list/vector of integer rectangle lists/vectors, defaulting
to the empty region. Zero-sized rectangles are allowed. Coordinates and computed
right/bottom edges must lie in **[-1073741823, 1073741823]**. This deliberately
leaves room for native differences and avoids SkRegion's sentinel values.
Negative sizes, inexact integers, and out-of-range edges are rejected.

`region-op` accepts `difference`, `intersect`, `union`, `xor`,
`reverse-difference`, or `replace`. The convenience functions `region-union`,
`region-intersect`, `region-difference`, and `region-xor` call that operation.
An empty Boolean result is a valid resource, not an allocation failure.
`region-copy` and `region-translate` return independent resources.

`region-bounds` returns an immutable integer vector, including `#(0 0 0 0)` for
an empty region. `region-rectangles` returns a list of detached immutable vectors.
`in-region-rectangles` takes its snapshot **when called**: the sequence can be
traversed repeatedly after the source is closed. The rectangles describe the
native region decomposition, not the original authoring rectangles. Do not
use their ordering as a persistent serialization format.

Queries are `region-empty?`, `region-rect?`, `region-complex?`,
`region-contains-point?`, `region-contains-rect?`, `region-contains-region?`, and
`region-intersects?`. Native queries and drawing enforce thread/lifetime rules.

### Path conversion and clipping

`path->region` requires an explicit finite clipping **region**. It scan-converts
the path to integer cells; it does not preserve smooth curve geometry or
antialiased coverage. `region->path` returns an independent ordinary path for
the region boundary, including holes. Empty regions produce empty paths.

`draw-region` follows the canvas transform and paint. For a **fill-style**
paint it submits the region as one boundary path instead of Skia's internal
rectangle decomposition. This is fill-equivalent and prevents browser SVG
renderers from exposing hairline seams between touching region rectangles.
Stroke and stroke-and-fill paints retain the native rectangle semantics.

In contrast,
**`canvas-clip-region!` matches Skia's native device-coordinate operation and
ignores the current local transform.** It accepts `#:operation 'intersect` or
`'difference` and does not add antialiasing. Device units are backend-specific
(the PDF device includes its raster scale).

For a local-coordinate clip that moves with your drawing and can be exported
portably, convert to a boundary path instead:

```racket
(with-skia ([boundary (region->path region)])
  (with-canvas-state canvas
    (canvas-translate! canvas 20 30)
    (canvas-clip-path! canvas boundary)
    (draw-color canvas 'blue)))
```

## Triangle meshes

A `vertices?` owns a copied SkVertices triangle mesh. This is not the separate,
programmable SkMesh API and does not introduce a GPU context.

```racket
(with-skia ([mesh
             (make-vertices
              'triangles
              '((10 10) (250 10) (130 100))
              #:colors '(red green blue))]
            [paint (make-paint #:color 'white)])
  (draw-vertices canvas mesh paint))
```

Modes are `triangles`, `triangle-strip`, and `triangle-fan`. The API accepts
**3 through 65536 positions**. Optional indices are exact uint16 values within
the position array. There must be at least three submitted vertices/indices;
triangle-list counts must be divisible by three. Partial trailing triangles
are rejected rather than silently ignored.

`#:texture-coordinates` supplies one coordinate pair per vertex. These are in
**shader coordinates**, usually image pixels for an image shader, not implicitly
normalized 0–1 UVs. Without texture coordinates, Skia uses vertex positions.
`#:colors` supplies one ordinary Racket Skia color per vertex.

All lists/vectors are copied. Introspection functions expose detached immutable
values: `vertices-mode`, `vertices-positions`, `vertices-texture-coordinates`,
`vertices-colors` (packed ARGB integers), `vertices-indices`, and `vertices-count`.
These stored values remain readable after the native resource is closed;
drawing does not. Colors, texture coordinates, and indices return `#f` if absent.

### Two separate blend operations

`draw-vertices` accepts `#:blend-mode`, defaulting to `modulate`. It combines
**the paint shader (or opaque paint color) as source** with **interpolated vertex
colors as destination**. It is ignored when vertex colors are absent. The
paint's own blend mode then controls compositing with the canvas backdrop.
Use a white paint for unmodified vertex colors with `modulate`, or explicitly
use `dst` to select vertex colors. Paint alpha still applies.

Skia ignores mask filters, path effects, and the paint's antialiasing flag for
vertices and patches. Geometry edges are not promised to look like antialiased
`draw-path` strokes. Other paint effects are conservatively included in audits,
even when a particular native primitive may ignore them.

## Nine-patch and image lattices

```racket
(draw-image-nine canvas image '(8 8 48 24) 20 30 280 90
                 #:sampling 'linear)

(define grid
  (make-image-lattice '(8 56) '(8 32)
    #:cell-types '(default default fixed-color
                   default transparent default
                   fixed-color default default)
    #:colors '(white white orange white white white blue white white)))
(draw-image-lattice canvas image grid 20 150 280 90)
```

The nine-patch center is an integer `(x y width height)` inside the image.
Native fixed corner/edge strips retain their size when space permits. Small
destinations proportionately shrink the fixed strips; they do not produce
negative stretch lengths.

A lattice is an immutable specification. Its division coordinates are absolute
source-image pixel positions, in strictly increasing order. At least one axis
must be divided; the other may have an empty division vector. Optional
`#:bounds` selects a nonempty integer image subset. Without it, the whole image
is used. This wrapper requires divisions **strictly inside** those bounds; it
deliberately excludes native special cases with a division on an outer edge.

The grid has `(x-count + 1) * (y-count + 1)` cells. Cell arrays are row-major,
with x varying fastest. Types are `default`, `transparent`, and `fixed-color`.
`fixed-color` requires a full color array; colors without cell types are rejected.
Unused colors for other cell kinds are allowed. Bounds/divisions are checked
against the actual image again at draw time.

Both drawing procedures accept `#:sampling 'nearest` or `'linear` and optional
`#:paint`. Alpha and supported paint filters/blending use the native image API.
The whole group is **not** automatically isolated or rasterized by the wrapper.

**ABI detail:** the C header's `sk_lattice_recttype_t` is an int-sized enum,
but the shim reinterprets `sk_lattice_t` as `SkCanvas::Lattice` without converting
its pointed-to arrays. Actual C++ `RectType` entries are uint8. This wrapper
therefore submits **one byte per cell**. Native regression/doctor checks mix all
three cell kinds at different array offsets. When no fixed colors are supplied,
a private zero-filled color array accompanies the cell types; the native
iterator still advances both arrays.

## Atlas sprites

```racket
(draw-atlas canvas atlas
  (list (make-atlas-transform 50 60 #:rotation 20 #:scale 1.5 #:anchor '(16 16))
        (make-atlas-transform 130 60 #:rotation -10 #:anchor '(16 16)))
  '((0 0 32 32) (32 0 32 32))
  #:sampling 'linear)
```

Each source rectangle is a nonempty finite `(x y width height)` inside the
image. An `atlas-transform?` contains the copied coefficients
`#(scos ssin tx ty)` for

```
x' = scos*x - ssin*y + tx
y' = ssin*x + scos*y + ty
```

Coordinates are relative to the selected sprite's upper-left corner, not its
position in the atlas. `#:rotation` is in degrees (positive clockwise in the
usual y-down canvas); `#:scale` is nonnegative. The local `#:anchor` is mapped
to the supplied x,y. Zero scale is allowed and yields degenerate geometry.
`atlas-transform-coefficients` returns the immutable coefficient vector.

The transform/source/color counts must agree. Optional `#:colors` tints each
sprite using `#:blend-mode 'modulate` by default, with the image as source and
the tint as destination. The optional paint controls canvas compositing.
`#:cull` is an optional conservative local-coordinate rectangle; an undersized
one can cause native rejection of visible sprites. It is not a clip.

An empty batch is a validated no-op, not permission to use a closed image.
Input payloads and the native six-vertices-per-sprite expansion count are checked.

## Cubic (Coons) patches

`make-cubic-patch` takes exactly twelve boundary points, plus optional four
corner colors and four texture coordinates. In clockwise order the four cubics
use point indices:

```
0,1,2,3     3,4,5,6     6,7,8,9     9,10,11,0
```

Corners are top-left, top-right, bottom-right, bottom-left by convention.
`draw-patch` tessellates the interpolated surface through Skia; it does not draw
only the boundary. Its `#:blend-mode` has the same source/destination meaning
as `draw-vertices`. Inputs are snapshotted and the value has no native lifetime.
Self-intersecting boundaries are not rejected or repaired by this API.

## PDF/SVG audit policy

| Feature | PDF | SVG |
|---|---|---|
| Region drawing / local boundary path | Ordinary geometry | Ordinary geometry |
| Direct device-region clip | Vector clip, with native device units | Needs explicit handling/fallback |
| Nine-patch/lattice | Embedded raster samples | Explicit raster fallback in this conservative policy |
| Vertices, cubic patches, atlas batches | Explicit raster fallback | Explicit raster fallback |

These are conservative policies, not an exhaustive declaration of which
individual primitives a given serializer can happen to emit. In particular,
mesh/patch output is not claimed to be editable path geometry. Use
`draw-rasterized` for bounded groups and include the required backdrop inside
that group. All calls contribute to recorded-picture provenance before audits.
No automatic fallback, pixel-perfect equivalence, or GPU behavior is promised.

Resources use `with-skia`/`skia-close!` and ordinary thread confinement. The byte
limit bounds submitted arrays and detached rectangle payloads; it does **not**
bound every native internal allocation, tessellation cost, or total process
memory. Serialization, general perspective matrices, and editable SVG meshes
remain separate work.

## Sources and validation

Audited against SkiaSharp's pinned `mono/skia` source commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`: `include/c/sk_region.h`,
`include/c/sk_vertices.h`, `include/c/sk_canvas.h`, `include/c/sk_types.h`,
`include/core/SkCanvas.h`, `src/c/sk_canvas.cpp`, `src/c/sk_types_priv.h`, and
`src/core/SkDevice.cpp`, and `src/core/SkLatticeIter.cpp`. See [testing](GEOMETRY-TESTING.md) for host validation.
