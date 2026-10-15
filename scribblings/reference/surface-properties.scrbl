#lang scribble/manual

@(require scribble/eval
          (for-label racket/base racket/contract skia skia/surface-properties))

@(define properties-eval (make-base-eval))
@(properties-eval '(require skia/surface-properties))

@title[#:tag "skia-surface-properties"]{Surface Properties}

@defmodule[skia/surface-properties #:no-declare]
@(declare-exporting skia skia/surface-properties #:use-sources (skia/surface-properties))

A @deftech{surface-properties value} is an immutable description of pixel geometry and native
rendering requests. It owns no surface, context, or other native resource. Creating a value does
not change an existing surface. A flag records a request, not proof that a device supports or
fulfills it.

@section{Detached Surface Properties}

@defproc[(surface-properties? [v any/c])
          boolean?]{
Returns @racket[#t] for a detached surface-properties value and @racket[#f] otherwise.
}

@defproc[(make-surface-properties [#:pixel-geometry geometry (or/c 'unknown 'rgb-h 'bgr-h 'rgb-v
          'bgr-v) 'unknown] [#:device-independent-fonts? fonts? boolean? #f] [#:dynamic-msaa?
          msaa? boolean? #f] [#:always-dither? dither? boolean? #f])
          surface-properties?]{
Creates a detached value. The horizontal and vertical geometry symbols describe RGB or BGR
subpixel order; @racket['unknown] makes no such assertion. The font flag requests
device-independent font behavior, the MSAA flag requests dynamic multisample antialiasing, and
the dither flag requests dithering. All flags default to false. These settings do not certify
display hardware, font appearance, or GPU availability.
}

@defproc[(surface-properties-pixel-geometry [properties surface-properties?])
          (or/c 'unknown 'rgb-h 'bgr-h 'rgb-v 'bgr-v)]{
Returns the recorded pixel geometry, not a measurement of the physical display.
}

@defproc[(surface-properties-flags [properties surface-properties?])
          (integer-in 0 7)]{
Returns the bit mask: 1 for device-independent fonts, 2 for dynamic MSAA, and 4 for
always-dither. The mask combines requests; it does not describe which requests were fulfilled.
}

@defproc[(surface-properties-device-independent-fonts? [properties surface-properties?])
          boolean?]{
Reports whether the device-independent-fonts request is set.
}

@defproc[(surface-properties-dynamic-msaa? [properties surface-properties?])
          boolean?]{
Reports whether the dynamic-MSAA request is set.
}

@defproc[(surface-properties-always-dither? [properties surface-properties?])
          boolean?]{
Reports whether the always-dither request is set.
}

@defproc[(surface-properties->jsexpr [properties surface-properties?])
          (and/c hash? immutable?)]{
Returns an immutable JSON-compatible hash with keys @racket['pixel_geometry], @racket['flags],
@racket['device_independent_fonts], @racket['dynamic_msaa], and @racket['always_dither]. Pixel
geometry is represented by a string. The conversion does not query or modify a native surface.
}

@examples[#:eval properties-eval
  (define properties
    (make-surface-properties #:pixel-geometry 'rgb-h
                             #:device-independent-fonts? #t
                             #:always-dither? #t))
  (eval:check (surface-properties-flags properties) 5)
  (eval:check (surface-properties-dynamic-msaa? properties) #f)]

@close-eval[properties-eval]

@section{Inspecting a Surface}

@(declare-exporting skia)

@defproc[(surface-properties-of [surface surface?])
          surface-properties?]{
Returns a detached copy of a live surface's native properties. The query obeys the surface's
lifetime, thread, and GPU-context rules where applicable. The native property object is borrowed
only during the query; the returned Racket value survives surface closure. It does not read back
pixels. Unrecognized native flag or geometry values raise instead of being silently discarded.
}
