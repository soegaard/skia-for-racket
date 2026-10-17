#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/specialized-canvases))

@title[#:tag "skia-specialized-canvases"]{Specialized Canvases}

@defmodule[skia/specialized-canvases #:no-declare]
@(declare-exporting skia skia/specialized-canvases #:use-sources (skia/specialized-canvases))

These scoped canvases discard drawing, forward it to several targets, or count
native overdraw. Each helper calls a function with one @tech{borrowed canvas} and
preserves its return values. Callbacks must not require keyword arguments.
The supplied canvas expires on return or escape and must not be retained.
Continuation reentry is prohibited.

Target-based helpers borrow the supplied surfaces, not their ownership. Each
surface must have a balanced root canvas: @tech{save count} 1, identity full matrix,
and a full rectangular device clip. Targets cannot already be borrowed by
another specialized-canvas scope. While borrowed, use the supplied wrapper,
not a target's ordinary canvas or operations that close or repurpose that target.

Cleanup destroys the wrapper before releasing the target borrows and restores
every target's original drawing state, including on exceptions. It does not undo
drawing already performed. Target surfaces remain caller-owned. Specialized
canvases do not provide document annotations and cannot be treated as PDF or SVG
canvases. No wrapper creates a GPU context or performs automatic readback.

@section{No-Draw Canvases}

@defproc[(call-with-nodraw-canvas [width (integer-in 1 32768)]
          [height (integer-in 1 32768)]
          [proc (-> canvas? any)])
          any]{
Calls the function with a native no-draw canvas of the given dimensions.
Drawing produces no pixels, but native canvas construction, graphics-state
changes, validation, and callback side effects still occur. The usual logical
four-bytes-per-pixel budget applies even though no output image is allocated.

This is not a sandbox or a static validator for arbitrary drawing programs.
The callback may still allocate other native resources. Both its execution and
cleanup must complete normally for the helper to return values.
}

@section{N-Way Canvases}

@defproc[(call-with-nway-canvas [surfaces (listof surface?)]
          [proc (-> canvas? any)])
          any]{
Calls the function with a canvas forwarding drawing to between 1 and 64
distinct surfaces. The list must be nonempty, with no duplicate surface wrappers.
All targets must have identical dimensions and execution backends. Each target
must also have save count 1, an identity full matrix, and a full rectangular
device clip. Resource validation rejects incompatible GPU contexts before
borrowing targets; matching backend names alone do not prove that contexts are
compatible.

The callback runs once, not once per target. A failure is not a transaction over
target pixels: earlier drawing may remain in some or all targets.

@racketblock[
(with-skia ([a (make-surface 16 16)]
            [b (make-surface 16 16)]
            [ink (make-paint #:color 'blue #:antialias? #f)])
  (call-with-nway-canvas
   (list a b)
   (lambda (canvas) (draw-rect canvas 2 2 8 8 ink)))
  (list (color->argb (surface-pixel a 4 4))
        (color->argb (surface-pixel b 4 4))))
]

Both targets contain the blue rectangle and have their root canvas state restored.

@reference-figure["nway-canvas.png"
                  "A nearest-neighbor enlargement of one actual 16 by 16 target from the n-way callback. Its blue square occupies x two through nine and y two through nine; the white surrounding area is the preview background."]

The renderer invokes @racket[call-with-nway-canvas] and captures target @racket[a] after the
callback; it does not redraw a similar rectangle on an ordinary canvas.
}

@section{Overdraw Canvases}

@defproc[(call-with-overdraw-canvas [surface surface?]
          [proc (-> canvas? any)])
          any]{
Calls the function with a native overdraw-counting wrapper over an Alpha8
surface. The target must satisfy the root-state rules and have Alpha8 storage;
initialize its samples to zero before collecting fresh counts. The wrapper does
not clear it automatically.

The alpha channel stores saturating eight-bit counts using Skia's overdraw
approximations. It is not a hardware fragment, occlusion, or performance counter,
and it does not promise an exact count for every high-level drawing primitive.
The surface is not released by this helper.
}
