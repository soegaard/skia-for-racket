#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract racket/sequence
                     skia skia/geometry-primitives skia/geometry))

@title[#:tag "skia-regions"]{Integer Regions}

@(declare-exporting skia skia/geometry-primitives skia/geometry
                    #:use-sources (skia/geometry-primitives skia/geometry))

An @deftech{integer region} represents a set of integer-coordinate pixels using
rectangular bands. It is an owned native resource, not an antialiased path or a
list that retains its original rectangle decomposition. Native operations require
a live region on its owning thread. A predicate recognizes even a closed wrapper.

Rectangle inputs are four-element lists or vectors of coordinates, width, and
height. Coordinates and computed right and bottom edges must be exact integers
from -1073741823 through 1073741823. Dimensions are exact nonnegative integers.
Right and bottom edges are excluded. Empty rectangles are allowed unless an
entry says otherwise. Region drawing follows the canvas transform; region
clipping instead uses @tech{device coordinates}.

@local-table-of-contents[#:style 'immediate-only]

@section{Construction and Queries}

@defproc[(region? [v any/c])
          boolean?]{
Returns @racket[#t] for a region wrapper, including a closed one, and
@racket[#f] otherwise.
}

@defproc[(make-region [rectangles (or/c list? vector?) '()])
          region?]{
Returns an independently owned region containing the union of the supplied
rectangles. The outer collection can be a list or vector. Inputs are validated
before native construction and are not retained as mutable data. Empty input
returns an empty region. The submitted rectangle payload is bounded by
@racket[current-skia-byte-limit].
}

@defproc[(region-copy [region region?])
          region?]{
Returns an independently owned copy. Later mutation or closure of either
wrapper does not invalidate the other.
}

@defproc[(region-empty? [region region?])
          boolean?]{
Reports whether the region contains no pixels.
}

@defproc[(region-rect? [region region?])
          boolean?]{
Reports whether the nonempty region is one rectangle.
}

@defproc[(region-complex? [region region?])
          boolean?]{
Reports whether the nonempty region requires more than one rectangle.
}

@defproc[(region-bounds [region region?])
          (and/c (vector/c exact-integer? exact-integer? exact-integer? exact-integer?) immutable?)]{
Returns an immutable enclosing rectangle. An empty region returns zero bounds.
The bounds alone do not describe holes or prove containment of another shape.
}

@defproc[(region-contains-point? [region region?]
          [x (integer-in -1073741823 1073741823)]
          [y (integer-in -1073741823 1073741823)])
          boolean?]{
Reports whether the integer-coordinate pixel is in the region. Right and
bottom boundary coordinates are excluded.
}

@defproc[(region-contains-rect? [region region?]
          [rectangle (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))])
          boolean?]{
Reports whether the region contains the nonempty rectangle in full.
An empty rectangle does not count as contained by this native predicate.
}

@defproc[(region-contains-region? [region region?]
          [other region?])
          boolean?]{
Reports whether the first region contains the nonempty second region in full.
An empty second region does not count as contained by this native predicate.
}

@defproc[(region-intersects? [a region?]
          [b region?])
          boolean?]{
Reports whether the two regions share any pixels. This is an exact region
query, unlike @racket[region-quick-reject-rect?] and @racket[region-quick-reject?],
which provide sufficient quick-rejection tests.
}

@defproc[(region-intersects-rect? [region region?]
          [rectangle (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))])
          boolean?]{
Reports whether the region shares any pixels with the rectangle.
}

@defproc[(region-quick-contains-rect? [region region?]
          [rectangle (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))])
          boolean?]{
Returns @racket[#t] only when containment is established by the inexpensive
native test. A false result is inconclusive; use @racket[region-contains-rect?]
when an exact answer is needed.
}

@defproc[(region-quick-reject-rect? [region region?]
          [rectangle (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))])
          boolean?]{
Returns @racket[#t] when disjointness is established cheaply. A false result
means not proven disjoint, not definitely intersecting.
}

@defproc[(region-quick-reject? [a region?]
          [b region?])
          boolean?]{
Returns @racket[#t] when the regions are cheaply proved disjoint. A false
result is inconclusive; use @racket[region-intersects?] for exact intersection.
}

@section{Set Operations and Conversion}

Set operations return new owned regions. They do not change their inputs, even
when an operation has an empty result. The explicit clear and set functions are
the exceptions: they mutate an existing region and return @racket[(void)].

@defproc[(region-op [a region?]
          [b region?]
          [operation (or/c 'difference 'intersect 'union 'xor 'reverse-difference 'replace)])
          region?]{
Returns the selected set operation. Difference is the first region minus the
second; reverse-difference reverses those operands; xor keeps pixels in exactly
one operand; replace copies the second region. Union and intersection have their
ordinary set meanings. Empty results are valid resources, not allocation failures.
}

@defproc[(region-union [a region?]
          [b region?])
          region?]{
Returns @racket[(region-op a b 'union)].
}

@defproc[(region-intersect [a region?]
          [b region?])
          region?]{
Returns @racket[(region-op a b 'intersect)].
}

@defproc[(region-difference [a region?]
          [b region?])
          region?]{
Returns @racket[(region-op a b 'difference)].
}

@defproc[(region-xor [a region?]
          [b region?])
          region?]{
Returns @racket[(region-op a b 'xor)].
}

@defproc[(region-op-rect [region region?]
          [rectangle (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))]
          [operation (or/c 'difference 'intersect 'union 'xor 'reverse-difference 'replace)])
          region?]{
Returns the selected operation between the region and rectangle, using the
operand order and operations of @racket[region-op]. The original region is unchanged.
}

@defproc[(region-clear! [region region?])
          void?]{
Mutates the region to the empty set. Earlier detached snapshots remain valid.
}

@defproc[(region-set-rect! [region region?]
          [rectangle (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))])
          void?]{
Replaces the region with the supplied rectangle. An empty rectangle clears it.
Validation precedes mutation; earlier detached snapshots are unaffected.
}

@defproc[(region-translate [region region?]
          [dx (integer-in -1073741823 1073741823)]
          [dy (integer-in -1073741823 1073741823)])
          region?]{
Returns a translated, independently owned region. The translated nonempty
bounds must remain within the region-coordinate range. Coordinates are not wrapped.
}

@defproc[(path->region [path path?]
          [clip region?])
          region?]{
Rasterizes the path's fill into a new integer region, constrained by the clip
region. This is a binary pixel-region conversion, not antialiased coverage.
The clip is required, including for inverse-filled paths. Neither input changes.
}

@defproc[(region->path [region region?])
          path?]{
Returns a new owned boundary path. An empty region yields an empty path.
The path has no dependency on the region's later mutation or lifetime.
}

@section{Detached Rectangles and Spans}

The following operations snapshot their results synchronously. No borrowed native
iterator escapes. Sequence variants create the snapshot when called, not when
iteration begins, and can be traversed after the source closes. Snapshot counts
and payloads are bounded by @racket[current-skia-byte-limit]; this is not a bound
on all internal region storage.

@defproc[(region-rectangles [region region?])
          (listof (and/c (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)
          immutable?))]{
Returns the native band decomposition as immutable rectangles, in native
iteration order. It need not reproduce the rectangle list used for construction.
}

@defproc[(in-region-rectangles [region region?])
          sequence?]{
Returns a sequence over a newly created @racket[region-rectangles] snapshot.
}

@defproc[(region-clipped-rectangles [region region?]
          [clip (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))])
          (listof (and/c (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)
          immutable?))]{
Returns immutable rectangles describing the intersection with the clipping
rectangle, without mutating the region.
}

@defproc[(in-region-clipped-rectangles [region region?]
          [clip (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))])
          sequence?]{
Returns a sequence over a newly created @racket[region-clipped-rectangles] snapshot.
}

@defproc[(region-spans [region region?]
          [y (integer-in -1073741823 1073741823)]
          [left (integer-in -1073741823 1073741823)]
          [right (integer-in -1073741823 1073741823)])
          (listof (and/c (vector/c exact-integer? exact-integer?) immutable?))]{
Returns horizontal intervals at row @racket[y], clipped to the half-open
interval from @racket[left] to @racket[right]. Each immutable vector stores its
inclusive left and exclusive right endpoint. Left must not exceed right; equal
endpoints return an empty list.

@racketblock[
(define spans
  (with-skia ([region (make-region '((0 0 4 3) (6 0 2 3)))])
    (region-spans region 1 0 8)))
spans
]

The snapshot contains @racket[#(0 4)] and @racket[#(6 8)] and remains usable
after the region is closed.
}

@racketblock[
(with-skia ([surface (make-surface 420 170 #:background 'white)]
            [source (make-path '((move 2 12) (quad 2 1 10 1)
                                (quad 18 1 18 8) (quad 18 13 10 13)
                                (quad 3 13 2 12) (close)))]
            [clip (make-region '((0 0 20 14)))]
            [region (path->region source clip)]
            [boundary (region->path region)]
            [cutter (make-region '((9 0 5 14)))]
            [difference (region-difference region cutter)]
            [fill (make-paint #:color "#326DE6" #:antialias? #f)]
            [boundary-paint (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 0.8)]
            [scanline (make-paint #:color (rgba 239 79 55 135))]
            [grid (make-paint #:color "#CAD1DA" #:style 'stroke #:stroke-width 0.5)]
            [font (make-font #:size 10)]
            [label (make-paint #:color "#20344E")])
  (define scale 7)
  (define row 7)
  (define spans (region-spans region row 0 20))
  (define (image-of value)
    (with-skia ([page (make-surface 20 14)])
      (draw-region (surface-canvas page) value fill)
      (surface-snapshot page)))
  (with-skia ([region-image (image-of region)]
              [difference-image (image-of difference)])
    (define canvas (surface-canvas surface))
    (draw-simple-text canvas "path -> region: integer pixels" 18 17 font label)
    (draw-simple-text canvas "region-difference: remove center band" 208 17 font label)
    (draw-image-rect canvas region-image 18 30 (* 20 scale) (* 14 scale) #:sampling 'nearest)
    (draw-image-rect canvas difference-image 208 30 (* 20 scale) (* 14 scale) #:sampling 'nearest)
    (for ([x (in-range 21)])
      (draw-line canvas (+ 18 (* x scale)) 30 (+ 18 (* x scale)) (+ 30 (* 14 scale)) grid)
      (draw-line canvas (+ 208 (* x scale)) 30 (+ 208 (* x scale)) (+ 30 (* 14 scale)) grid))
    (for ([y (in-range 15)])
      (draw-line canvas 18 (+ 30 (* y scale)) (+ 18 (* 20 scale)) (+ 30 (* y scale)) grid)
      (draw-line canvas 208 (+ 30 (* y scale)) (+ 208 (* 20 scale)) (+ 30 (* y scale)) grid))
    (for ([span spans])
      (draw-rect canvas (+ 18 (* scale (vector-ref span 0))) (+ 30 (* scale row))
                 (* scale (- (vector-ref span 1) (vector-ref span 0))) scale scanline))
    (with-canvas-state canvas
      (canvas-translate! canvas 18 30)
      (canvas-scale! canvas scale scale)
      (draw-path canvas boundary boundary-paint))
    (draw-simple-text canvas "orange=boundary; red=spans y=7" 18 145 font label)
    (draw-simple-text canvas "binary cells, not coverage" 260 145 font label)
    surface))
]
@reference-figure["region-quantization-and-difference.png"
                  "A curved blue path has been rasterized to a 20 by 14 integer region and enlarged with a visible pixel grid. Orange traces the boundary path returned from that region and a red band highlights the actual horizontal spans at row seven. A second enlarged panel removes a central rectangular band with region-difference, splitting the same quantized region."]

The left result is deliberately not a smooth antialiased rendering of the source
curve.  It displays the binary scan conversion used by @racket[path->region].
The span endpoints are inclusive on the left and exclusive on the right, so the
red row is an actual visualization of the values returned by @racket[region-spans].

@defproc[(in-region-spans [region region?]
          [y (integer-in -1073741823 1073741823)]
          [left (integer-in -1073741823 1073741823)]
          [right (integer-in -1073741823 1073741823)])
          sequence?]{
Returns a sequence over a newly created @racket[region-spans] snapshot,
with the same half-open interval and validation rules.
}

@section{Drawing and Device Clipping}

@defproc[(draw-region [canvas canvas?]
          [region region?]
          [paint paint?])
          void?]{
Draws the region under the current canvas transform and clip. A fill paint
draws the boundary as one path, avoiding seams between touching bands in SVG.
Stroke and stroke-and-fill paints retain native region drawing, which can stroke
the rectangular decomposition. The region and paint must remain valid during the call.

@racketblock[
(with-skia ([region (make-region '((15 15 55 50) (90 15 50 50)))]
            [paint (make-paint #:color "#326DE6")]
            [surface (make-surface 155 80 #:background 'white)])
  (draw-region (surface-canvas surface) region paint))
]

@reference-figure["region.png"
                  "Two disjoint blue rectangular bands drawn from one integer region on a white background."]
}

@defproc[(canvas-clip-region! [canvas canvas?]
          [region region?]
          [#:operation operation (or/c 'intersect 'difference) 'intersect])
          void?]{
Combines the current clip with the integer region in device coordinates.
The current canvas transform does not transform the region. No antialiasing
option is provided. For a local-coordinate boundary clip, convert the region
with @racket[region->path] and use @racket[canvas-clip-path!] instead.

@racketblock[
(with-skia ([region (make-region '((15 15 65 60) (105 15 60 60)))]
            [shader (make-linear-gradient-shader 0 0 180 0 '("#326DE6" "#EFA02B"))]
            [paint (make-paint #:shader shader)]
            [surface (make-surface 180 90 #:background 'white)])
  (canvas-clip-region! (surface-canvas surface) region)
  (draw-paint (surface-canvas surface) paint))
]

@reference-figure["region-clip.png"
                  "A blue-to-orange gradient visible only inside two disjoint rectangular region components."]
}

@section{Additional Visual Examples}

@racketblock[
(with-skia ([a (make-region '((20 15 90 55)))]
            [b (make-region '((70 30 80 50)))]
            [surface (make-surface 180 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (with-skia ([result (region-intersect a b)])
    (draw-region (surface-canvas surface) result paint)))
]
@reference-figure["region-intersection.png"
                  "The blue rectangular overlap retained by intersecting two integer regions."]

@racketblock[
(with-skia ([a (make-region '((20 15 90 55)))]
            [b (make-region '((70 30 80 50)))]
            [surface (make-surface 180 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (with-skia ([result (region-xor a b)])
    (draw-region (surface-canvas surface) result paint)))
]
@reference-figure["region-xor.png"
                  "Two blue rectangular lobes remain after integer-region exclusive-or removes their overlap."]
