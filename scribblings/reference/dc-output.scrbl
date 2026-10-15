#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract
                     (prefix-in draw: racket/draw)
                     skia skia/dc skia/dc-output skia/output))

@title[#:tag "skia-dc-output"]{Drawing-Context Output}

@defmodule[skia/dc-output #:no-declare]
@(declare-exporting skia/dc-output #:use-sources (skia/dc-output))

The @racketmodname[skia/dc-output] library adapts the supported Racket
@racket[draw:dc<%>] drawing subset to Skia PDF, SVG, and CPU-raster canvases.
Authoring is captured once into a callback-scoped DC and replayed through the
existing output-policy machinery. The bridge does not render an entire document
to a bitmap and does not add an implicit GPU fallback.

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
Returns detached declarations for the output-DC compatibility surface. The
result describes deferred vector commands, callback-only lifetime, annotations,
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
Captures one drawing callback and replays its commands onto @racket[canvas]. The
receiver must be a live PDF, SVG, or CPU-raster canvas with an affine 2D
transform. A GPU surface and an unrelated picture recorder are rejected.

The @racket[draw] function must accept one positional DC argument with no
required keyword arguments. Its result values are ignored. The capture DC
expires and releases its selection locks before native replay begins. A callback
exception or escape therefore emits none of that capture's drawing commands,
although ordinary callback side effects remain.

The returned detached report records backend, command count, logical size,
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
Creates an ordinary detached output-page description whose drawing callback is
adapted through @racket[call-with-output-dc]. The page constructor retains the
usual physical-unit, background, and content-clipping rules from
@racket[make-output-page]. A margin is either one nonnegative drawing scalar
applied to all four sides or four nonnegative drawing scalars in left, top,
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
Runs @racket[draw] once on an isolated transparent CPU DC of the requested
logical size, then inserts the resulting pixels at @racket[x] and @racket[y].
The child closes on every exit and cannot be retained or resumed. Its callback
must accept one positional argument and no required keywords.

On an output DC, the operation becomes an explicitly audited bounded raster
group. The @racket['require-vector] policy rejects before the child callback runs. On an
ordinary raster or GPU DC, the helper inserts a bitmap through that DC's public
bitmap path. The group cannot inspect the already emitted document backdrop;
include every required source/backdrop pixel inside the child callback.
}

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
Adds a link rectangle to a named destination through an output DC. Forward
references retain the document-level rules of @racket[canvas-link-destination!].
On ordinary raster or GPU DCs, the operation validates its arguments and does
not register a link.
}
