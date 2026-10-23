#lang scribble/manual

@(require scribble/eval
          (for-label racket/base racket/contract skia skia/surface-properties
                     skia/gpu skia/gpu-dc))

@(define properties-eval (make-base-eval))
@(properties-eval '(require skia/surface-properties))

@title[#:tag "skia-surface-properties"]{Surface Properties}

@defmodule[skia/surface-properties #:no-declare]
@(declare-exporting skia skia/surface-properties #:use-sources (skia/surface-properties))

Use surface properties when a drawing target needs a known display-subpixel
arrangement or a rendering request such as dithering. Otherwise, omit the
surface-properties argument to use unknown pixel geometry and unset flags.

A @deftech{surface-properties value} describes a drawing target's pixel
geometry and requests settings for font rendering, @tech{multisample antialiasing},
and @tech{dithering}. These rendering settings are separate from the surface's
dimensions, pixel format, and @tech{color space}.

@deftech{Pixel geometry} describes the arrangement of red, green, and blue
subpixels within a display pixel. For example, @racket['rgb-h] describes
subpixels arranged horizontally in red-green-blue order. It does not describe
the order in which color components are stored in the surface's memory. The
default, @racket['unknown], leaves the display's subpixel arrangement unspecified.

Use @racket[make-surface-properties] to create a value, then pass it as the
@racket[#:surface-properties] argument to @racket[make-gpu-surface]. The same
argument to @racket[call-with-gpu-frame-dc] configures the @tech{GPU surface} used for
drawing during its callback.

A properties value is immutable and can be reused for several surfaces.
Creating one does not allocate a surface or change an existing surface.
The flags record requests; whether Skia fulfills them depends on the drawing
backend. Inspecting a flag reports the request, not whether it took effect.

Pixel geometry and font-rendering properties are relevant to raster surfaces
as well as GPU surfaces. The current API only accepts custom properties when
creating GPU surfaces: neither @racket[make-surface] nor
@racket[make-surface-from-info] has a surface-properties argument.
@racket[surface-properties-of] can nevertheless inspect either kind of surface.
The dynamic-MSAA request is specific to GPU rendering.

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
       @deftech{Multisample antialiasing} (MSAA) is a form of @tech{antialiasing}
       that samples coverage at several positions within each pixel. Dynamic MSAA allows
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
Returns an immutable JSON-compatible hash table with keys @racket['pixel_geometry], @racket['flags],
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
Returns an immutable copy of @racket[surface]'s properties. Accepts both raster
surfaces and GPU surfaces. Raises an exception if Skia reports a flag or pixel
geometry that the library does not recognize.

The surface must be open. See @secref["skia-resources"] for the general resource
rules and @secref["skia-gpu-surfaces"] for access to GPU surfaces.
}
