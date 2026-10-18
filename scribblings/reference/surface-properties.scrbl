#lang scribble/manual

@(require scribble/eval
          (for-label racket/base racket/contract skia skia/surface-properties))

@(define properties-eval (make-base-eval))
@(properties-eval '(require skia/surface-properties))

@title[#:tag "skia-surface-properties"]{Surface Properties}

@defmodule[skia/surface-properties #:no-declare]
@(declare-exporting skia skia/surface-properties #:use-sources (skia/surface-properties))

A @deftech{surface-properties value} is an immutable description of a surface's
pixel geometry and rendering settings. @deftech{Pixel geometry} describes the
arrangement of red, green, and blue subpixels within a display pixel.

The rendering flags record requests. Whether Skia fulfills a request depends
on the drawing backend. Creating a properties value does not change an
existing surface.

@section{Creating and Inspecting Properties}

@defproc[(surface-properties? [v any/c])
          boolean?]{
Returns @racket[#t] for a @tech{surface-properties value} and @racket[#f] otherwise.
}

@defproc[(make-surface-properties [#:pixel-geometry geometry (or/c 'unknown 'rgb-h 'bgr-h 'rgb-v
          'bgr-v) 'unknown] [#:device-independent-fonts? fonts? boolean? #f] [#:dynamic-msaa?
          msaa? boolean? #f] [#:always-dither? dither? boolean? #f])
          surface-properties?]{
Creates a @tech{surface-properties value} with the given pixel geometry and
rendering flags.

The @racket['rgb-h] and @racket['bgr-h] geometries describe horizontal subpixel
arrangements in red-green-blue and blue-green-red order, respectively.
The @racket['rgb-v] and @racket['bgr-v] geometries describe the corresponding
vertical arrangements. The default, @racket['unknown], leaves the arrangement
unspecified.

The boolean arguments request the following rendering settings:

@itemlist[
 @item{@racket[fonts?] requests device-independent font rendering.}
 @item{@racket[msaa?] requests dynamic multisample antialiasing for GPU surfaces.
       @deftech{Multisample antialiasing} (MSAA) smooths edges by sampling
       coverage at several positions within each pixel. Dynamic MSAA allows
       Skia to use these samples internally even when the surface does not
       store multiple samples per pixel.}
 @item{@racket[dither?] requests dithering for all drawing. @deftech{Dithering}
       adds small color variations to reduce visible bands between colors.}]
}

@defproc[(surface-properties-pixel-geometry [properties surface-properties?])
          (or/c 'unknown 'rgb-h 'bgr-h 'rgb-v 'bgr-v)]{
Returns the recorded @tech{pixel geometry}.
}

@defproc[(surface-properties-device-independent-fonts? [properties surface-properties?])
          boolean?]{
Reports whether the device-independent-fonts request is set.
}

@defproc[(surface-properties-dynamic-msaa? [properties surface-properties?])
          boolean?]{
Reports whether the dynamic @tech{multisample antialiasing} request is set.
}

@defproc[(surface-properties-always-dither? [properties surface-properties?])
          boolean?]{
Reports whether the request to use @tech{dithering} for all drawing is set.
}

@defproc[(surface-properties-flags [properties surface-properties?])
          (integer-in 0 7)]{
Returns the rendering requests as a bit mask: @racket[1] for device-independent
fonts, @racket[2] for dynamic MSAA, and @racket[4] for dithering on all drawing.
The mask is the sum of the requested flags. Use the boolean accessors above
to test individual requests.
}

@defproc[(surface-properties->jsexpr [properties surface-properties?])
          (and/c hash? immutable?)]{
Returns an immutable JSON-compatible hash with keys @racket['pixel_geometry], @racket['flags],
@racket['device_independent_fonts], @racket['dynamic_msaa], and @racket['always_dither]. Pixel
geometry is represented by a string.
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
Returns a copy of @racket[surface]'s properties. Raises an exception if Skia
reports a flag or pixel geometry that the library does not recognize.

The surface must be open. See @secref["skia-resources"] for the general resource
rules and @secref["skia-gpu-surfaces"] for access to GPU surfaces.
}
