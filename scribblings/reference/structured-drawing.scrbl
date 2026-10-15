#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/geometry-primitives))

@title[#:tag "skia-structured-drawing"]{Meshes, Patches, Image Grids, and Atlases}

@defmodule[skia/geometry-primitives #:no-declare]
@(declare-exporting skia skia/geometry-primitives #:use-sources (skia/geometry-primitives))

These interfaces draw triangle meshes, cubic patches, image grids, and transformed
image batches. They use the native Skia canvas, its current transform and clip,
and the normal resource lifetime and context restrictions. A successful native
call does not promise vector preservation in PDF or SVG. Portable alternatives
are described in @secref["skia-portable-drawing"].

Point collections are lists or vectors of two-coordinate lists or vectors.
Coordinates are @tech{drawing scalar}s. Input arrays are validated and copied before
submission, and their counts and byte sizes are bounded by
@racket[current-skia-byte-limit]. Detached specifications retain no canvas.

@local-table-of-contents[#:style 'immediate-only]

@section{Triangle Meshes}

A @deftech{vertices resource} owns a native immutable mesh and detached copies
of its submitted arrays. Drawing requires its live native resource. Its metadata
queries read the detached copies and remain usable after explicit closure,
without requiring its creating thread. The copies describe submitted values,
not a readback of the native binary32 arrays.

@defproc[(vertices? [v any/c])
          boolean?]{
Returns @racket[#t] for a vertices wrapper, including a closed one, and
@racket[#f] otherwise.
}

@defproc[(make-vertices [mode (or/c 'triangles 'triangle-strip 'triangle-fan)]
          [positions (or/c list? vector?)]
          [#:texture-coordinates texture-coordinates (or/c #f list? vector?) #f]
          [#:colors colors (or/c #f list? vector?) #f]
          [#:indices indices (or/c #f list? vector?) #f])
          vertices?]{
Returns an owned mesh with 3 through 65536 positions. Triangles mode groups
consecutive submitted vertices into independent triples. Strip and fan modes
use their corresponding connected triangle organizations.

Texture coordinates and colors, when supplied, must each have one entry per
position. Texture coordinates use the same point format as positions; colors
are color specifications copied as packed ARGB integers. They do not remain
linked to the caller's collections.

Indices, when supplied, must be unsigned 16-bit exact integers within the
position array. There must be at least three submitted indices or, without an
index array, three positions. Triangles mode requires that submitted count to
be divisible by three. An explicitly empty index array is not treated as omitted.

@racketblock[
(with-skia ([surface (make-surface 24 24)]
            [paint (make-paint)]
            [mesh (make-vertices 'triangles '((2 2) (22 2) (2 22))
                                 #:colors '(red green blue))])
  (draw-vertices (surface-canvas surface) mesh paint)
  (vertices-count mesh))
]

The mesh contains three vertices. Its native arrays do not borrow the input lists.
}

@defproc[(vertices-mode [mesh vertices?])
          (or/c 'triangles 'triangle-strip 'triangle-fan)]{
Returns the mesh's submitted topology.
}

@defproc[(vertices-positions [mesh vertices?])
          (and/c vector? immutable?)]{
Returns the immutable vector of immutable two-coordinate position vectors.
This is detached metadata, including after native closure.
}

@defproc[(vertices-texture-coordinates [mesh vertices?])
          (or/c #f (and/c vector? immutable?))]{
Returns the copied immutable point vector, or @racket[#f] if texture
coordinates were omitted. Values are shader coordinates, not normalized UVs
imposed by this interface.
}

@defproc[(vertices-colors [mesh vertices?])
          (or/c #f (and/c vector? immutable?))]{
Returns the immutable packed-ARGB color vector, or @racket[#f] if omitted.
The entries are integers from 0 through 4294967295, not the original color syntax.
}

@defproc[(vertices-indices [mesh vertices?])
          (or/c #f (and/c vector? immutable?))]{
Returns the immutable unsigned 16-bit index vector, or @racket[#f] when
positions are submitted directly in order.
}

@defproc[(vertices-count [mesh vertices?])
          (integer-in 3 65536)]{
Returns the number of positions, not the number of indices or triangles.
}

@defproc[(draw-vertices [canvas canvas?]
          [mesh vertices?]
          [paint paint?]
          [#:blend-mode blend-mode (or/c 'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in
                 'src-out 'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate
                 'screen 'overlay 'darken 'lighten 'color-dodge 'color-burn
                 'hard-light 'soft-light 'difference 'exclusion 'multiply
                 'hue 'saturation 'color 'luminosity) 'modulate])
          void?]{
Draws the live mesh with the supplied paint. The blend-mode argument combines
mesh colors with paint shading. The paint's own blend mode then controls
composition with the destination; these are distinct stages. Position, color,
and texture-coordinate arrays are retained by the mesh, not the canvas wrapper.
}

@section{Cubic Patches}

A @deftech{cubic patch} is a detached immutable Coons-patch specification. Its
boundary has four cubic curves, with corners at point indices 0, 3, 6, and 9.
Indices 1 and 2 are the first edge's control points, and the same pattern continues
around the other edges; points 10 and 11 return to corner 0. Twelve points are
supplied, without repeating corner 0 at the end. Drawing tessellates the patch;
it is not a single Bézier path fill.

@defproc[(cubic-patch? [v any/c])
          boolean?]{
Returns @racket[#t] for a cubic-patch specification and @racket[#f] otherwise.
}

@defproc[(make-cubic-patch [points (or/c list? vector?)]
          [#:colors colors (or/c #f list? vector?) #f]
          [#:texture-coordinates texture-coordinates (or/c #f list? vector?) #f])
          cubic-patch?]{
Copies exactly twelve two-coordinate boundary points. Optional colors and
texture coordinates each contain exactly four entries, in corner order, rather
than twelve entries. Colors are stored as packed ARGB values. This constructor
creates no native resource; submission storage is allocated only while drawing.
}

@defproc[(cubic-patch-points [patch cubic-patch?])
          (and/c vector? immutable?)]{
Returns the immutable twelve-point boundary vector with immutable point entries.
}

@defproc[(cubic-patch-colors [patch cubic-patch?])
          (or/c #f (and/c vector? immutable?))]{
Returns the immutable four-color packed-ARGB vector, or @racket[#f] when omitted.
}

@defproc[(cubic-patch-texture-coordinates [patch cubic-patch?])
          (or/c #f (and/c vector? immutable?))]{
Returns the immutable four-point shader-coordinate vector, or @racket[#f] when omitted.
}

@defproc[(draw-patch [canvas canvas?]
          [patch cubic-patch?]
          [paint paint?]
          [#:blend-mode blend-mode (or/c 'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in
                 'src-out 'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate
                 'screen 'overlay 'darken 'lighten 'color-dodge 'color-burn
                 'hard-light 'soft-light 'difference 'exclusion 'multiply
                 'hue 'saturation 'color 'luminosity) 'modulate])
          void?]{
Tessellates and draws the patch with native Skia. The blend-mode argument
combines patch colors with paint shading, independently of destination blending
selected by the paint. Temporary arrays are retained only for the synchronous
call; the detached patch remains reusable afterward.
}

@section{Nine-Patch and Lattice Images}

An @deftech{image lattice} is a detached specification of integer image divisions
and optional cell styles. Image bounds use coordinates, width, and height.
Lattices alternate fixed and stretchable spans, starting with a fixed span.
When the destination is smaller than the fixed spans, those spans shrink and
stretchable spans can collapse. This is not equal-size tiling.

The lattice constructor can operate without an image. Drawing validates its
bounds and divisions against the actual source image. Divisions must lie strictly
inside the selected bounds; the native outer-edge special cases are not accepted.

@defproc[(image-lattice? [v any/c])
          boolean?]{
Returns @racket[#t] for an image-lattice specification and @racket[#f] otherwise.
}

@defproc[(make-image-lattice [x-divisions (or/c list? vector?)]
          [y-divisions (or/c list? vector?)]
          [#:bounds bounds (or/c #f list? vector?) #f]
          [#:cell-types cell-types (or/c #f list? vector?) #f]
          [#:colors colors (or/c #f list? vector?) #f])
          image-lattice?]{
Copies strictly increasing integer division coordinates. At least one axis
must contain a division. Coordinates and supplied bounds use the region-safe
integer range from -1073741823 through 1073741823. Supplied bounds must be
nonempty, with every division strictly inside its corresponding extent.
An omitted bound selects the whole source image at drawing time.

Cell types, when supplied, cover the entire row-major grid: the count is one
more than the x-division count times one more than the y-division count. Each
entry is @racket['default], @racket['transparent], or @racket['fixed-color].
Colors require explicit cell types and must also cover the whole grid. Any
fixed-color cell requires the color vector, including entries for the other
cell types. Colors are copied as packed ARGB values; unused entries still
undergo normal validation.
}

@defproc[(image-lattice-x-divisions [lattice image-lattice?])
          (and/c vector? immutable?)]{
Returns the immutable strictly increasing x-division vector.
}

@defproc[(image-lattice-y-divisions [lattice image-lattice?])
          (and/c vector? immutable?)]{
Returns the immutable strictly increasing y-division vector.
}

@defproc[(image-lattice-bounds [lattice image-lattice?])
          (or/c #f (and/c (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)
          immutable?))]{
Returns copied source bounds, or @racket[#f] for image-dependent full bounds.
}

@defproc[(image-lattice-cell-types [lattice image-lattice?])
          (or/c #f (and/c vector? immutable?))]{
Returns the immutable row-major cell-type vector, or @racket[#f] when all
cells use source-image samples.
}

@defproc[(image-lattice-colors [lattice image-lattice?])
          (or/c #f (and/c vector? immutable?))]{
Returns the immutable packed-ARGB color vector, or @racket[#f] when omitted.
Its entries correspond to every grid cell, not only fixed-color cells.
}

@defproc[(draw-image-nine [canvas canvas?]
          [image image?]
          [center (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:paint paint (or/c paint? #f) #f])
          void?]{
Draws the image as a nine-patch grid. The nonempty integer center rectangle
must lie wholly inside the image. Its edges delimit the stretchable center
spans; destination coordinates use current local canvas coordinates. The
optional paint modifies native image drawing. For explicit rectangle-based
lowering, use @racket[draw-image-nine/portable].
}

@defproc[(draw-image-lattice [canvas canvas?]
          [image image?]
          [lattice image-lattice?]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:paint paint (or/c paint? #f) #f])
          void?]{
Draws the selected lattice inside the local destination rectangle. Source
bounds must be nonempty and inside the image, and all divisions must be strictly
interior to those bounds. The optional paint applies to native image drawing.
The detached lattice and image remain unchanged. For explicit rectangle-based
lowering, use @racket[draw-image-lattice/portable].
}

@section{Transformed Image Batches}

Atlas transforms are documented in @secref["skia-atlas-transforms"]. Each maps
a sprite's local source origin, not its absolute location in the atlas image.

@defproc[(draw-atlas [canvas canvas?]
          [image image?]
          [transforms (or/c list? vector?)]
          [sources (or/c list? vector?)]
          [#:colors colors (or/c #f list? vector?) #f]
          [#:blend-mode blend-mode (or/c 'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in
                 'src-out 'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate
                 'screen 'overlay 'darken 'lighten 'color-dodge 'color-burn
                 'hard-light 'soft-light 'difference 'exclusion 'multiply
                 'hue 'saturation 'color 'luminosity) 'modulate]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:cull cull (or/c #f list? vector?) #f]
          [#:paint paint (or/c paint? #f) #f])
          void?]{
Draws one image batch with matching transform and source-rectangle counts.
Every transform must be an @racket[atlas-transform?]. Source rectangles are
nonempty drawing-scalar rectangles contained in the image; fractional source
coordinates are allowed. Optional packed colors are supplied as color
specifications, one per sprite. They combine with source samples using
@racket[blend-mode]; the optional paint controls the resulting destination draw.

A supplied cull rectangle is a local native rejection hint, not a clip. The
budget accounts for the native expansion to six vertices per sprite. An empty
batch draws nothing but still validates the canvas, image, paint, and options.
For the more restricted portable lowering, use @racket[draw-atlas/portable].
}
