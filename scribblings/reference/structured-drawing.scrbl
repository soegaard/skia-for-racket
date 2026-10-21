#lang scribble/manual

@(require "support/figures.rkt"
          scribble/eval
          (for-label racket/base racket/contract skia skia/geometry-primitives
                     skia/portable-drawing))

@(define grid-eval (make-base-eval))
@(grid-eval '(require skia/portable-drawing))

@title[#:tag "skia-structured-drawing"]{Meshes, Patches, Image Grids, and Atlases}

@defmodule[skia/geometry-primitives #:no-declare]
@(declare-exporting skia skia/geometry-primitives #:use-sources (skia/geometry-primitives))

These interfaces draw triangle meshes, @tech[#:key "cubic patch"]{cubic patches},
image grids, and transformed image batches. Drawing uses the canvas's current
@tech{canvas transform} and @tech{clip}, with the normal resource lifetime and
context restrictions. A successful native call does not promise vector
preservation in PDF or SVG.

Portable image-grid drawing and grid planning are described after the native
nine-patch and lattice operations. Those functions are also available from
@racketmodname[skia/portable-drawing]. Portable markers and atlas drawing are
described in @secref["skia-portable-drawing"].

Point collections are lists or vectors of two-coordinate lists or vectors.
Inputs are validated and copied before submission, and their counts and
byte sizes are bounded by
@racket[current-skia-byte-limit].

@local-table-of-contents[#:style 'immediate-only]

@section{Triangle Meshes}

Use a triangle mesh for artwork defined by vertices, especially when colors
should interpolate between vertices or a @tech{shader} should follow custom texture
coordinates. Construct it with @racket[make-vertices] and draw it with
@racket[draw-vertices]. For a flat-colored outline that needs filling or
stroking, a @tech{path} is usually simpler.

A @deftech{vertices resource} owns a native immutable mesh and Racket copies
of its input lists or vectors. Drawing requires its live native resource. Its metadata
queries read the Racket copies and remain usable after explicit closure,
without requiring its creating thread. The queries describe the saved inputs,
not the rounded coordinates used for drawing.

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
are @tech{color specification}s. The mesh's copies are independent of later
changes to the caller's collections.

Indices, when supplied, must be unsigned 16-bit exact integers less than the
number of positions. There must be at least three indices or, when
@racket[indices] is @racket[#f], three positions. Triangles mode requires that
count to be divisible by three. An explicitly empty list or vector of indices
is not treated as omitted.

@racketblock[
(with-skia ([surface (make-surface 24 24 #:background 'white)]
            [paint (make-paint #:color 'white #:antialias? #f)]
            [mesh (make-vertices 'triangles '((2 2) (22 2) (2 22))
                                 #:colors '(red green blue))])
  (draw-vertices (surface-canvas surface) mesh paint)
  (vertices-count mesh))
]

@reference-figure["mesh-triangle.png"
                  "A nearest-neighbor enlargement of the displayed 24 by 24 white surface. Its right triangle has red, green, and blue vertex colors blended across the interior."]

The figure is a magnification of the exact 24 by 24 drawing target. The white paint preserves
the mesh's vertex colors under color modulation; it is not an additional white triangle.

The mesh contains three vertices.
}

@defproc[(vertices-mode [mesh vertices?])
          (or/c 'triangles 'triangle-strip 'triangle-fan)]{
Returns the mode supplied to @racket[make-vertices], which determines how
vertices are grouped into triangles.
}

@defproc[(vertices-positions [mesh vertices?])
          (and/c vector? immutable?)]{
Returns the mesh's vertex positions.

The result is an immutable vector of immutable two-coordinate vectors.
The query remains available after the mesh is closed.
}

@defproc[(vertices-texture-coordinates [mesh vertices?])
          (or/c #f (and/c vector? immutable?))]{
Returns the copied immutable point vector, or @racket[#f] if texture
coordinates were omitted. These coordinates use the shader's coordinate
system; they are not required to lie between zero and one.
}

@defproc[(vertices-colors [mesh vertices?])
          (or/c #f (and/c vector? immutable?))]{
Returns the immutable packed-ARGB color vector, or @racket[#f] if omitted.
The entries are integers from 0 through 4294967295, not the original color syntax.
}

@defproc[(vertices-indices [mesh vertices?])
          (or/c #f (and/c vector? immutable?))]{
Returns the vertex indices, or @racket[#f] when positions are submitted directly in order.

The result is an immutable vector of unsigned 16-bit integers.
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
and texture-coordinate data are stored in the mesh, not the canvas wrapper.
}

@section{Cubic Patches}

Use a cubic patch to draw a four-sided curved region with interpolated corner
colors or to map a shader across it. Create the boundary and corner data with
@racket[make-cubic-patch], then draw it with @racket[draw-patch].

A @deftech{cubic patch} is an immutable Racket structure specifying a Coons patch. Its
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
than twelve entries. Colors are @tech{color specification}s.
}

@defproc[(cubic-patch-points [patch cubic-patch?])
          (and/c vector? immutable?)]{
Returns the patch's twelve boundary points.

The result is an immutable vector, and each point entry is also immutable.
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
selected by the paint.

@racketblock[
(define patch
  (make-cubic-patch
   '((20 20) (60 0) (120 0) (160 20)
     (180 50) (180 70) (160 100)
     (120 120) (60 120) (20 100)
     (0 70) (0 50))
   #:colors '(red blue green yellow)))
(with-skia ([surface (make-surface 180 120 #:background 'white)]
            [paint (make-paint #:color 'white)])
  (draw-patch (surface-canvas surface) patch paint))
]

@reference-figure["cubic-patch.png"
                  "A curved four-sided patch with colors interpolated from red, blue, green, and yellow corners."]
}

@section{Nine-Patch and Lattice Images}

Use nine-patch or lattice drawing to resize an image while preserving borders
when space permits, as with a resizable panel. @racket[draw-image-nine] accepts
a single center rectangle. For additional divisions or per-cell styles,
create a specification with @racket[make-image-lattice] and pass it to
@racket[draw-image-lattice].

An @deftech{image lattice} is an immutable Racket structure specifying integer image
divisions and optional cell styles. Image bounds use coordinates, width, and height.
Lattices alternate fixed and stretchable spans, starting with a fixed span.
When the destination is smaller than the fixed spans, those spans shrink and
stretchable spans can collapse. This is not equal-size tiling.

The lattice constructor can operate without an image. Drawing validates its
bounds and divisions against the actual source image. Divisions must lie strictly
inside the selected bounds; the native outer-edge special cases are not accepted.

@bold{Conceptual diagram.} Nine-patch drawing preserves correspondence between
source and destination cells. Corners remain fixed, edge spans stretch in one
axis, and the center span stretches in both. The center rectangle is
@tt{x, y, width, height}, not opposite corners. If the destination is smaller
than the fixed spans, fixed spans shrink and stretch spans can collapse.

@reference-figure["concept-nine-patch.png"
                  "Numbered three-by-three source and enlarged destination grids show matching cells. Blue corners remain fixed, light edge cells stretch along one axis, and the light center stretches along both; the source center rectangle is labeled by x, y, width, and height."]

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
cell types. Every color entry must be a valid @tech{color specification}, even
when its cell type does not use the color.


@racketblock[
(with-skia ([surface (make-surface 200 120 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 30 30 #:background "#E8EEF9")])
    (with-skia ([image (surface-snapshot source)])
      (define lattice
        (make-image-lattice
         '(10 20) '(10 20)
         #:cell-types '(default fixed-color default
                        fixed-color transparent fixed-color
                        default fixed-color default)
         #:colors '(white "#326DE6" white
                    "#10988E" transparent "#EFA02B"
                    white "#E94F37" white)))
      (draw-image-lattice canvas image lattice 15 10 170 100 #:sampling 'nearest))))
]
@reference-figure["lattice-fixed-color-stage10.png"
                  "A lattice combines sampled cells, four fixed-color cells, and a transparent center cell."]
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
optional paint modifies native image drawing. To draw the grid as separate
image rectangles, use @racket[draw-image-nine/portable].

@racketblock[
(with-skia ([source (make-surface 30 30 #:background "#F4D35E")]
            [blue (make-paint #:color "#326DE6")])
  (draw-rect (surface-canvas source) 0 0 30 8 blue)
  (draw-rect (surface-canvas source) 0 22 30 8 blue)
  (with-skia ([image (surface-snapshot source)]
              [target (make-surface 180 110 #:background 'white)])
    (draw-image-nine (surface-canvas target) image
                     '(8 8 14 14) 15 10 150 90)))
]

@reference-figure["nine-patch.png"
                  "A stretched nine-patch image whose blue top and bottom borders stay narrow while the yellow center expands."]
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
To draw the grid as separate image rectangles, use @racket[draw-image-lattice/portable].


@racketblock[
(with-skia ([surface (make-surface 200 120 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 30 30 #:background "#F4D35E")]
              [blue (make-paint #:color "#326DE6")])
    (draw-rect (surface-canvas source) 0 0 30 7 blue)
    (draw-rect (surface-canvas source) 0 23 30 7 blue)
    (draw-rect (surface-canvas source) 0 0 7 30 blue)
    (draw-rect (surface-canvas source) 23 0 7 30 blue)
    (with-skia ([image (surface-snapshot source)])
      (define lattice (make-image-lattice '(7 23) '(7 23)))
      (draw-image-lattice canvas image lattice 15 10 170 100 #:sampling 'nearest))))
]
@reference-figure["lattice-native-stage10.png"
                  "A native image lattice stretches a yellow center while preserving narrow blue border cells."]
}

@section[#:tag "skia-portable-image-grids"]{Portable Image-Grid Drawing}

@(declare-exporting skia skia/portable-drawing #:use-sources (skia/portable-drawing))

Use @racket[draw-image-nine/portable] or @racket[draw-image-lattice/portable] to
draw the grids described above as separate image rectangles. These functions
calculate the cell layout for you; you do not need to construct a @tech{grid plan}.
They use ordinary drawing commands before recording, without changing
@racket[draw-image-nine] or @racket[draw-image-lattice] or silently selecting a
backend. The images still contain raster pixels; drawing them this way does not
turn them into vector geometry or guarantee identical results in every viewer.

The image-grid functions below and @racket[draw-atlas/portable] accept
@tech[#:key "nearest sampling"]{nearest} or @tech{linear sampling} and a byte alpha
multiplier. They do not accept an arbitrary paint, per-sprite tint colors, or
blend mode. They draw source-over, in input or cell order. Repeated source
rectangles share temporary subset images during one call; those temporaries
are released before return, including on failure. The original image remains
caller-owned.

@defproc[(draw-image-nine/portable [canvas canvas?]
          [image image?]
          [center (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:alpha alpha byte? 255])
          void?]{
Draws a nine-patch image as ordinary image rectangles, using the layout
calculated by @racket[image-nine-plan]. Empty source or destination cells are
omitted. Source samples are sliced without resampling before destination drawing;
interpolation then follows the chosen sampling mode.
The alpha multiplier applies to each cell.


@racketblock[
(with-skia ([surface (make-surface 200 120 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 30 30 #:background "#326DE6")]
              [orange (make-paint #:color "#EFA02B")])
    (draw-circle (surface-canvas source) 15 15 8 orange)
    (with-skia ([image (surface-snapshot source)])
      (draw-image-nine/portable canvas image '(8 8 14 14) 15 10 170 100
                                #:sampling 'nearest #:alpha 128))))
]
@reference-figure["portable-nine-alpha-stage10.png"
                  "A portable nine-patch is drawn at half alpha, revealing the white background through the image."]
}

@defproc[(draw-image-lattice/portable [canvas canvas?]
          [image image?]
          [lattice image-lattice?]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:alpha alpha byte? 255])
          void?]{
Draws an image lattice as image rectangles and plain fixed-color rectangles,
using the layout calculated by @racket[image-lattice-plan]. Transparent or
zero-area cells are omitted. The alpha multiplier also scales fixed-color alpha,
using nearest byte rounding. The lattice's full-grid validation occurs before drawing.


@racketblock[
(with-skia ([surface (make-surface 200 120 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 30 30 #:background "#E8EEF9")]
              [blue (make-paint #:color "#326DE6")])
    (draw-rect (surface-canvas source) 0 0 10 30 blue)
    (draw-rect (surface-canvas source) 20 0 10 30 blue)
    (with-skia ([image (surface-snapshot source)])
      (define lattice (make-image-lattice '(10 20) '(10 20)))
      (draw-image-lattice/portable canvas image lattice 15 10 170 100 #:sampling 'nearest))))
]
@reference-figure["portable-lattice-stage10.png"
                  "A portable lattice stretches the center spans while drawing each cell as ordinary rectangles."]
}

@section[#:tag "skia-image-grid-plans"]{Grid Plans}

@(declare-exporting skia skia/portable-drawing #:use-sources (skia/portable-drawing))

A @deftech{grid plan} describes how an image is divided into rectangular cells
and where each cell goes in a destination rectangle. This is useful for resizing
an image of a framed panel or button: the corners and border thickness can stay
the same while the center stretches. If the destination is too small to fit the
fixed parts, those parts shrink instead.

Use @racket[image-nine-plan] for a three-by-three grid of corners, edges, and a
center. Use @racket[image-lattice-plan] for an @tech{image lattice} with other
divisions or cells that are skipped or filled with a fixed color. The lattice
specifies the source divisions; the plan calculates the resulting rectangles
for a particular destination position and size.

Call these planning functions when you need to inspect the cell layout, check
how it changes at different sizes, or export the rectangles with
@racket[image-grid-plan->jsexpr]. They calculate the layout from image dimensions
and division information, without needing an image or canvas. They do not draw
anything or load Skia.

If you only want to draw the resized image, use
@racket[draw-image-nine/portable] or @racket[draw-image-lattice/portable]; they
compute their plans for you. If all parts of the image should scale together,
use the simpler @racket[draw-image-rect] instead.

A plan is a list of cell structures, recognized by @racket[image-grid-cell?], in
row-major order: left to right within each row, from top to bottom. Each cell
has integer source-image geometry and finite destination geometry in
@tech{local coordinates}. Adjacent cells use the same coordinates for their
shared destination edges. A plan can
include cells with zero destination area, which the drawing functions omit.

@defproc[(image-grid-cell? [v any/c])
          boolean?]{
Returns @racket[#t] for a grid-plan cell and @racket[#f] otherwise.
}

@defproc[(image-nine-plan [image-width (integer-in 1 1073741823)]
          [image-height (integer-in 1 1073741823)]
          [center (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))])
          (listof image-grid-cell?)]{
Returns the nine row-major cells for an image and its nonempty center
rectangle. The center must lie within the supplied image dimensions. Fixed
outer spans retain their size when possible; if they do not fit, they shrink
proportionally and the corresponding center span collapses.

@examples[#:eval grid-eval
 (define cells (image-nine-plan 10 10 '(2 2 6 6) 0 0 20 20))
 (eval:check (image-grid-cell-source (list-ref cells 4)) #(2 2 6 6))
 (eval:check (image-grid-cell-destination (list-ref cells 4)) #(2.0 2.0 16.0 16.0))]

The two-pixel borders retain their widths while the center expands to sixteen pixels.
}

@defproc[(image-lattice-plan [image-width (integer-in 1 1073741823)]
          [image-height (integer-in 1 1073741823)]
          [lattice image-lattice?]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))])
          (listof image-grid-cell?)]{
Returns the row-major cells for the lattice after checking bounds and
interior divisions against the image dimensions. Cell kinds and fixed colors
are preserved. An undivided axis maps its whole source extent to the destination.
The plan does not contain sampled image pixels.
}

@defproc[(image-grid-cell-row [cell image-grid-cell?])
          exact-nonnegative-integer?]{
Returns the zero-based row index in the plan.
}

@defproc[(image-grid-cell-column [cell image-grid-cell?])
          exact-nonnegative-integer?]{
Returns the zero-based column index in the plan.
}

@defproc[(image-grid-cell-kind [cell image-grid-cell?])
          (or/c 'default 'transparent 'fixed-color)]{
Returns whether the cell samples the source image, is omitted, or uses a
fixed color.
}

@defproc[(image-grid-cell-source [cell image-grid-cell?])
          (and/c (vector/c exact-integer? exact-integer? exact-integer? exact-integer?) immutable?)]{
Returns the immutable source rectangle, using coordinates, width, and height.
Some grid edge cells can have zero extent.
}

@defproc[(image-grid-cell-destination [cell image-grid-cell?])
          (and/c (vector/c real? real? real? real?) immutable?)]{
Returns the immutable destination rectangle derived from the shared rounded
edges. A zero extent means the drawing function omits this cell.
}

@defproc[(image-grid-cell-color [cell image-grid-cell?])
          (or/c rgba? #f)]{
Returns an @racket[rgba] value for a fixed-color cell, or @racket[#f] for
other kinds. This is not the packed integer used by @racket[image-lattice-colors].
}

@defproc[(image-grid-plan->jsexpr [plan (listof image-grid-cell?)])
          (listof hash?)]{
Returns JSON-compatible cell descriptions with row, column, kind, source,
destination, and color keys. Kind symbols become strings, coordinate vectors
become lists, and fixed colors become packed ARGB integers. Missing colors use
@racket[#f]. An empty plan returns an empty list.
}

@close-eval[grid-eval]

@section{Transformed Image Batches}

Use @racket[draw-atlas] when many sprites come from rectangular areas of one
image, such as a sprite sheet. Supply one source rectangle and one
@tech{atlas transform} per sprite to place, rotate, and scale them in a single
batch. For one image or one source rectangle, the ordinary image-drawing
functions are simpler.

Each @tech{atlas transform} maps a sprite's local source origin, not its absolute
location in the atlas image.

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
Every transform must satisfy @racket[atlas-transform?]. Source rectangles are
nonempty rectangles contained in the image; fractional source coordinates are
allowed. Optional colors are @tech{color specification}s, one per sprite.
They combine with source samples using
@racket[blend-mode]; the optional paint controls the resulting destination draw.

A supplied cull rectangle is a local native rejection hint, not a clip. The
budget accounts for the native expansion to six vertices per sprite. An empty
batch draws nothing but still validates the canvas, image, paint, and options.
To draw the atlas as separate image rectangles, use @racket[draw-atlas/portable],
which accepts a more restricted set of inputs.

@racketblock[
(with-skia ([source (make-surface 32 16 #:background 'red)]
            [blue (make-paint #:color "#326DE6")])
  (draw-rect (surface-canvas source) 16 0 16 16 blue)
  (with-skia ([image (surface-snapshot source)]
              [target (make-surface 180 90 #:background 'white)])
    (draw-atlas
     (surface-canvas target) image
     (list (make-atlas-transform 20 20 #:scale 2)
           (make-atlas-transform 90 15 #:scale 3)
           (make-atlas-transform 145 55 #:scale 1.5 #:rotation 25))
     '((0 0 16 16) (16 0 16 16) (0 0 16 16))
     #:sampling 'nearest)))
]

@reference-figure["atlas-batch.png"
                  "Three atlas sprites drawn from red and blue source tiles at different scales, with the final red sprite rotated."]


@racketblock[
(with-skia ([surface (make-surface 220 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 20 20 #:background 'white)])
    (with-skia ([image (surface-snapshot source)])
      (draw-atlas canvas image
                  (list (make-atlas-transform 20 20 #:scale 2.5)
                        (make-atlas-transform 90 20 #:scale 2.5)
                        (make-atlas-transform 160 20 #:scale 2.5))
                  '((0 0 20 20) (0 0 20 20) (0 0 20 20))
                  #:colors '(red green blue)
                  #:blend-mode 'modulate
                  #:sampling 'nearest))))
]
@reference-figure["atlas-tints-stage10.png"
                  "Three white atlas sprites are modulated by red, green, and blue per-sprite colors."]
}
