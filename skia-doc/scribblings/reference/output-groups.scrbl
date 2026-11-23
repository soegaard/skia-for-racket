#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/output-groups))

@title[#:tag "skia-output-groups"]{Bounded Output Groups}

@defmodule[skia/output-groups #:no-declare]
@(declare-exporting skia skia/output-groups #:use-sources (skia/output-groups))

Use a bounded output group when one part of a PDF or SVG drawing may need
rasterization but the surrounding content should remain vector where
supported. Wrap that part in @racket[draw-output-group] and choose whether to
prefer vector output, require it, or force a raster image. This makes the
representation decision local to the selected region.

The group's @tech{output policy} chooses its representation. It is separate
from the audit policies in @secref["skia-output-audit"], which can reject
features used by an export, including a group's raster image.

A @deftech{bounded output group} calls the drawing callback once and records the
commands it produces. It then selects native replay or explicit @tech{raster fallback}
for a PDF, SVG, or CPU-raster destination and returns an immutable report describing
that decision. Later replay uses the recorded commands without calling the callback again.

A @deftech{raster executor} determines how a group's recorded drawing commands
are rendered into a temporary image. The default uses the CPU; a GPU executor
uses a @tech{GPU context}. The group's policy determines whether the group is
rasterized. Using a GPU executor does not turn a rasterized group into vector
content. See @secref["skia-gpu-output"] for GPU executors.

Groups do not establish output compatibility for resources
whose compatibility is unknown or recover annotations that were already flattened.

@section{Drawing Bounded Groups}

@defproc[(draw-output-group [canvas canvas?] [x real?] [y real?] [width (and/c real? (>/c 0))]
          [height (and/c real? (>/c 0))] [draw (-> canvas? any)] [#:policy policy (or/c
          'prefer-vector 'require-vector 'raster) 'prefer-vector] [#:padding padding (or/c real?
          list?) 0] [#:scale scale (real-in 1/1024 1024) (current-raster-output-scale)]
          [#:color-space space (or/c #f color-space?) #f] [#:label label (or/c #f string?) #f]
          [#:raster-executor executor (or/c #f 'cpu output-raster-executor?) #f])
          output-group-report?]{
Records the drawing produced by @racket[draw] and replays it as a group on
@racket[canvas], using the requested representation policy.

The callback receives a borrowed recording canvas. Its local origin is placed
at @racket[x] and @racket[y] on the destination. Logical dimensions must be positive.
Padding accepts a nonnegative real number or the left/top/right/bottom
list forms used by @racket[draw-rasterized]. It enlarges the captured region without shrinking
the original content. Both replay strategies use the same padded local clip.

The destination is a supported document or CPU-raster canvas. An ordinary @tech{picture recorder} has
no output backend and is rejected. A recording canvas created by an enclosing output-group
capture can inherit that capture's backend; an unrelated recorder cannot. An outer document
matrix must be affine. Put perspective inside the group callback when raster fallback is needed.

The @racket['prefer-vector] policy chooses native replay only when the captured features permit
it; native replay can still embed existing images or depend on viewer behavior. The
@racket['require-vector] policy requires every captured feature to be vector-compatible and is
not valid for a raster destination. The @racket['raster] policy requests isolated rasterization,
but still rejects resources whose output compatibility is unknown and operations
known to discard document features such as annotations.

For @tech{blend modes} that depend on background pixels, the group starts with a transparent
background rather than the content already drawn on the destination canvas. Include
any needed background drawing in the callback. Groups reject device-coordinate
region clips, whose replay would ignore the intended local placement. Rasterization that would
lose annotations or document-native text is rejected rather than silently accepted.

For raster output, pixel extents are the ceilings of padded dimensions times the scale. The
ordinary dimension and RGBA byte limits are checked when rasterization is selected, not imposed
as an RGBA allocation requirement on a native vector group. A supplied color space is validated
before the callback and used by raster fallback; it does not convert existing document content.

When @racket[#:raster-executor] is @racket[#f], a group drawn on its enclosing group's
recording canvas uses that group's executor; a group drawn on any other supported
canvas uses the CPU.
Passing @racket['cpu] explicitly always selects the CPU.

Before running the drawing callback, the function checks that the
@tech{raster executor} is still usable and is being used from the correct thread.

If the executor creates a GPU context on demand, it does so only after the
group's policy and any enclosing @tech{output audit} allow rasterization.

If a later step fails, the exception propagates without calling the drawing
callback again.

Callback values are ignored, and its canvas expires on exit. Failure before replay draws no
group to the destination, but ordinary callback side effects persist. Failures during actual
replay or drawing the raster image can leave the destination pixels partially changed.
A policy rejection raises @racket[exn:fail:output-group?] with its report.

The optional label identifies the group in its report. A supplied string must
contain 1 through 200 characters and is copied as an immutable string, just as
with @racket[call-with-output-label]. The default @racket[#f] supplies no label.
}

@racketblock[
(define calls 0)
(with-skia ([surface (make-surface 20 20)]
            [ink (make-paint #:color 'red)])
  (define report
    (draw-output-group (surface-canvas surface) 4 5 8 6
      (lambda (canvas)
        (set! calls (add1 calls))
        (draw-rect canvas 0 0 8 6 ink))
      #:policy 'raster #:scale 2 #:padding 1))
  (list calls (output-group-report-strategy report)
        (output-group-report-pixel-size report)))
]

@reference-figure["output-group.png"
                  "A nearest-neighbor enlargement of the transparent 20 by 20 output surface. The red raster output group occupies x four through eleven and y five through ten; the checkerboard is only a preview background."]

The result contains 1, @racket['raster], and @racket[#(20 16)]. Padding is included before
scaling, but does not move the group's logical red content or become visible colored geometry.

@section{Reports and Failures}

@defproc[(output-raster-executor? [v any/c])
          boolean?]{
Identifies an output @tech{raster executor} value supplied by the output integration
interface. The @racket['cpu] symbol is accepted by @racket[draw-output-group],
but is not an executor value. The predicate does not certify that an executor's
scope is still live or that its backend is available.
}

@defproc[(output-group-report? [v any/c])
          boolean?]{
Returns @racket[#t] for an immutable group report and @racket[#f] otherwise.
}

@defproc[(output-group-report-backend [report output-group-report?])
          (or/c 'pdf 'svg 'raster)]{
Returns the receiving output representation backend, not the GPU backend used to create an
intermediate image.
}

@defproc[(output-group-report-policy [report output-group-report?])
          (or/c 'prefer-vector 'require-vector 'raster)]{
Returns the requested representation policy.
}

@defproc[(output-group-report-strategy [report output-group-report?])
          (or/c 'native 'raster 'reject)]{
Returns the selected replay strategy. A rejected report is obtained through the group exception,
not a successful draw.
}

@defproc[(output-group-report-reason [report output-group-report?])
          (or/c 'native-compatible 'raster-target 'explicit-raster 'isolated-compositing
                  'backend-fallback 'unknown-provenance 'discarded-semantics 'vector-required
                  'annotation-would-be-lost 'native-text-would-be-lost 'device-space-clip)]{
Returns a symbol identifying the reason for the decision, separate from diagnostic exception text.
}

@defproc[(output-group-report-bounds [report output-group-report?])
          (and/c (vector/c real? real? real? real?) immutable?)]{
Returns the original x, y, width, and height in destination-local coordinates.
}

@defproc[(output-group-report-padded-bounds [report output-group-report?])
          (and/c (vector/c real? real? real? real?) immutable?)]{
Returns the padded destination-local rectangle, beginning at the original position minus
left/top padding.
}

@defproc[(output-group-report-pixel-size [report output-group-report?])
          (or/c #f (and/c (vector/c exact-positive-integer?
                                         exact-positive-integer?) immutable?))]{
Returns raster width and height, or @racket[#f] when no raster intermediate was selected.
}

@defproc[(output-group-report-scale [report output-group-report?])
          (real-in 1/1024 1024)]{
Returns the requested pixels-per-logical-unit scale, including when no raster intermediate was
used.
}

@defproc[(output-group-report-features [report output-group-report?])
          (listof symbol?)]{
Returns a sorted, duplicate-free list of captured feature summaries. It is not a full display
list or a pixel-equivalence proof.
}

@defproc[(output-group-report-label [report output-group-report?])
          (or/c #f (and/c string? immutable?))]{
Returns the copied label or @racket[#f].
}

@defproc[(output-group-report-children [report output-group-report?])
          (listof output-group-report?)]{
Returns nested capture reports in capture order. They describe decisions made during capture,
not separate callbacks rerun during outer replay.
}

@defproc[(output-group-report-execution [report output-group-report?])
          (and/c hash? immutable?)]{
Returns JSON-compatible execution details. These distinguish the requested executor,
representation phase, actual backend, context generation, fallback reason, and explicit readback
count. A native strategy does not initialize a GPU merely because one was requested. Planned or
rejected work is not reported as completed.
}

@defproc[(output-group-report->jsexpr [report output-group-report?])
          (and/c hash? immutable?)]{
Returns a JSON-compatible hash table of the report. Rectangles become lists,
classification symbols become strings, and nested reports appear under
@racket['captured_children]. A false pixel size remains false.
}

@defproc[(exn:fail:output-group? [v any/c])
          boolean?]{
Returns @racket[#t] for a group-policy rejection. Other argument, callback, native, or executor
errors are not converted to this type.
}

@defproc[(exn:fail:output-group-report [exception exn:fail:output-group?])
          output-group-report?]{
Returns the rejected group's report. No group was drawn to the destination before this policy
rejection, but callback side effects may already have occurred.
}
