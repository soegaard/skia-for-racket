#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/class racket/contract
                     (prefix-in draw: racket/draw)
                     skia skia/dc skia/dc-output skia/output))

@title[#:tag "skia-dc-output"]{Drawing-Context Output}

@defmodule[skia/dc-output #:no-declare]
@(declare-exporting skia/dc-output #:use-sources (skia/dc-output))

Use @racketmodname[skia/dc-output] to export code written for Racket's
@racket[draw:dc<%>] interface to PDF or SVG, or to draw it onto a CPU-raster
canvas. For a reusable CPU drawing context instead, use @racket[skia-dc%].

The drawing callback runs once with a temporary DC. Its drawing commands are
recorded and then replayed according to the selected @tech{output policy}.
Only the supported Racket Draw methods are available, and the DC can be used
only during the callback. The adapter closes it automatically. See
@secref["skia-reference-racket-integration"] for lifetime and smoothing
differences between the adapters.

The bridge does not turn the entire document into a bitmap or use the GPU
implicitly. Use @racket[draw-dc-raster-group] for a specific part of the drawing
that should become an image in the output.

@local-table-of-contents[#:style 'immediate-only]

@section{Capture and Page Construction}

@defparam[current-output-dc-command-limit limit exact-positive-integer?]{
Bounds the number of captured DC commands in one output-DC invocation. The
initial value is 100000. Commands inside groups count toward the limit even when
a later policy rejects or replaces their representation. This is a capture
budget, not a measurement of total Racket or native memory.
}

@defproc[(skia-output-dc? [v any/c]) boolean?]{
Returns whether @racket[v] is one of the callback-scoped output DC values. The
predicate remains true after the callback has expired; later operations on the
expired DC are rejected.
}

@defproc[(output-dc-capabilities) (and/c hash? immutable?)]{
Describes the output drawing context's declared support for drawing features and
its lifetime rules. The result covers deferred vector commands, callback-only lifetime, annotations,
and explicit raster groups; it does not run a document exporter or native probe.
}

@defproc[(call-with-output-dc
          [canvas canvas?]
          [width (and/c real? (>/c 0) (<=/c 32768))]
          [height (and/c real? (>/c 0) (<=/c 32768))]
          [draw (-> (is-a?/c draw:dc<%>) any)]
          [#:policy policy (or/c 'prefer-vector 'require-vector) 'prefer-vector]
          [#:background background (or/c string? (is-a?/c draw:color%)) "white"]
          [#:smoothing smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed]
          [#:text-mode text-mode (or/c 'native 'outline) (current-text-output-mode)]
          [#:raster-scale raster-scale (real-in 1/1024 1024)
           (current-raster-output-scale)])
         (and/c hash? immutable?)]{
Calls @racket[draw] once, records its drawing commands, and replays them onto @racket[canvas]. The
receiver must be a live PDF, SVG, or CPU-raster canvas with an affine 2D
transform. A @tech{GPU surface} and an unrelated @tech{picture recorder} are rejected.

The @racket[draw] function must accept one positional DC argument with no
required keyword arguments. Its result values are ignored. The capture DC
expires and releases its selection locks before native replay begins. A callback
exception or escape therefore emits none of that capture's drawing commands,
although ordinary callback side effects remain.

The returned report records backend, command count, logical size,
selected policies, group reports, and the fact that the capture DC has expired.
The @racket['require-vector] policy is valid only for document receivers and rejects any
operation that would require raster representation.
}

@defproc[(make-dc-output-page
          [width (and/c real? (>/c 0) (<=/c 32768))]
          [height (and/c real? (>/c 0) (<=/c 32768))]
          [draw (-> (is-a?/c draw:dc<%>) any)]
          [#:unit unit (or/c 'pt 'in 'mm 'cm 'px) 'pt]
          [#:margins margins
           (or/c (and/c real? (>=/c 0))
                 (list/c (and/c real? (>=/c 0))
                         (and/c real? (>=/c 0))
                         (and/c real? (>=/c 0))
                         (and/c real? (>=/c 0))))
           0]
          [#:background background (or/c color? #f) #f]
          [#:smoothing smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed]
          [#:policy policy (or/c 'prefer-vector 'require-vector) 'prefer-vector]
          [#:on-report on-report (-> (and/c hash? immutable?) any) void])
         output-page?]{
Creates an output-page description whose drawing callback is
adapted through @racket[call-with-output-dc]. The page constructor follows the
usual physical-unit, background, and content-clipping rules from
@racket[make-output-page]. A margin is either one nonnegative real number
applied to all four sides or four nonnegative real numbers in left, top,
right, bottom order. The horizontal and vertical margin pairs must leave a
positive content width and height.

Both @racket[draw] and @racket[on-report] must accept their one positional
argument without required keywords. The report callback runs after successful
replay, when the output DC has already expired. Exporting the same page more
than once runs the page's authoring callback once per export.
}

@section{Explicit Raster Groups}

@defproc[(draw-dc-raster-group
          [dc (is-a?/c draw:dc<%>)] [x real?] [y real?]
          [width (and/c real? (>/c 0))] [height (and/c real? (>/c 0))]
          [draw (-> (is-a?/c draw:dc<%>) any)]
          [#:scale scale (real-in 1/1024 1024) (current-raster-output-scale)]
          [#:label label string? "dc-explicit-raster"])
         void?]{
Draws the content produced by @racket[draw] as an image at @racket[x] and @racket[y].

The callback runs once on a separate CPU drawing context of the requested logical
size, starting with transparent pixels. The child DC closes on every exit and
cannot be used afterward or resumed. Its callback must accept one positional
argument and no required keywords.

On an output DC, the operation becomes an explicitly audited bounded raster
group. The @racket['require-vector] policy rejects before the child callback runs. On an
ordinary raster or GPU DC, the helper inserts a bitmap through that DC's public
bitmap path. The group cannot inspect the already emitted document backdrop;
include every required source/backdrop pixel inside the child callback.
}

@subsection{A Drawing Callback for Raster and SVG Output}

The callback below draws a frame and text around one bounded raster group.
It is used both with @racket[call-with-output-dc] on a CPU canvas and with
@racket[make-dc-output-page] to create a page. In SVG output, the raster group
becomes an embedded image while the surrounding geometry remains vector
drawing.

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/dc-output skia/output)

(define white (make-object draw:color% 255 255 255))
(define navy (make-object draw:color% 32 52 78))
(define panel (make-object draw:color% 232 238 249))
(define orange (make-object draw:color% 239 160 43))
(define blue (make-object draw:color% 50 109 230))
(define black (make-object draw:color% 0 0 0))
(define (draw-scene dc)
  (send dc set-pen navy 2 'solid)
  (send dc set-brush panel 'solid)
  (send dc draw-rectangle 4 4 172 92)
  (send dc set-text-foreground navy)
  (send dc draw-text "vector frame" 12 14)
  (draw-dc-raster-group
   dc 100 30 52 45
   (lambda (group)
     (send group set-pen black 1 'transparent)
     (send group set-brush orange 'solid)
     (send group draw-ellipse 2 2 44 35)
     (send group set-pen blue 3 'solid)
     (send group draw-line 4 39 48 5))
   #:scale 2 #:label "orange-badge")
  (send dc set-pen blue 3 'solid)
  (send dc draw-line 15 80 80 42))

(define page (make-dc-output-page 180 100 draw-scene #:background "#FFFFFF"))
(with-skia ([surface (make-surface 180 100 #:background "#FFFFFF")])
  (define report (call-with-output-dc (surface-canvas surface) 180 100 draw-scene))
  (with-skia ([direct (surface-snapshot surface)]
              [preview (output-page->image page #:dpi 72)])
    (define svg (output->bytes page 'svg))
    (list (hash-ref report 'raster_groups)
          (list (image-width direct) (image-height preview))
          (regexp-match? #rx#"<image" svg))))
]
@reference-figure["dc-output-capture-and-page-preview.png"
                  "Side-by-side results from call-with-output-dc and an output-page preview show the same pale frame, blue line, and orange raster badge."]

The first result is one explicit raster group, and the final boolean is true
for the inspected SVG @tt{<image} element. Callback DCs expire after each
capture; unlike @racket[skia-dc%], they cannot be reused afterward and are not closed by the caller.

@section{Document Annotations}

@defproc[(dc-annotate-url! [dc (is-a?/c draw:dc<%>)] [x real?] [y real?]
                           [width (and/c real? (>=/c 0))]
                           [height (and/c real? (>=/c 0))]
                           [uri string?]) void?]{
Adds a URI rectangle when @racket[dc] is an output DC. The coordinates use the
current logical DC transform and clip. On ordinary raster or GPU DCs, the
operation validates its arguments and is otherwise an invisible no-op.
Annotations inside an explicit raster group are rejected rather than silently
flattened.
}

@defproc[(dc-define-destination! [dc (is-a?/c draw:dc<%>)] [name string?]
                                 [x real?] [y real?]) void?]{
Defines a named PDF/SVG destination through an output DC. Names and coordinates
obey the same validation rules as @racket[canvas-define-destination!]. On
ordinary raster or GPU DCs, the operation performs no registration after
validation.
}

@defproc[(dc-link-destination! [dc (is-a?/c draw:dc<%>)] [x real?] [y real?]
                               [width (and/c real? (>=/c 0))]
                               [height (and/c real? (>=/c 0))]
                               [name string?]) void?]{
Adds a link rectangle to a @tech{named destination} through an output DC. Forward
references retain the document-level rules of @racket[canvas-link-destination!].
On ordinary raster or GPU DCs, the operation validates its arguments and does
not register a link.
}
