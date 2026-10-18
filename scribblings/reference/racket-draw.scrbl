#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/class racket/contract
                     (prefix-in draw: racket/draw)
                     skia skia/bitmap skia/dc skia/pict skia/racket-draw))

@title[#:tag "skia-racket-draw"]{Racket Draw Interoperability}

@defmodule[skia/racket-draw #:no-declare]
@(declare-exporting skia/racket-draw #:use-sources (skia/racket-draw))

The @racketmodname[skia/racket-draw] library provides explicit conversions
between selected Racket Draw and Skia values. Each conversion eagerly copies
the relevant data and returns an independent result. The library is not
re-exported by @racketmodname[skia]; require it explicitly when bitmap, color,
or path interoperability is needed. Requiring it does not by itself load the
Skia or HarfBuzz native libraries, create a GPU context, or initialize a GUI.

The bridge converts standalone values rather than drawing contexts. Use
@racketmodname[skia/pict] when a consumer needs a Racket pict, and use
@racketmodname[skia/dc] when a consumer needs an implementation of Racket's
@racket[draw:dc<%>] interface. These functions do not create a live view,
share native handles, or provide zero-copy storage.

The @racket[bitmap->image] and @racket[dc-path->skia-path] functions return owned
Skia resources, which should be managed with @racket[with-skia],
@racket[call-with-skia-resource], or
@racket[skia-close!]. Conversions in the other direction return ordinary
Racket Draw objects, and @racket[color%->rgba] returns an immutable @racket[rgba] value.
Later mutation of a mutable source, or
closing a Skia source, does not change an already converted result. The bridge
does not make concurrent mutation of a Racket Draw source safe while a
conversion is in progress.

@local-table-of-contents[#:style 'immediate-only]

@section{Bitmaps}

@defproc[(bitmap->image
          [bitmap (is-a?/c draw:bitmap%)]
          [#:resolution resolution (or/c 'physical 'logical) 'physical]
          [#:mask mask (or/c 'loaded #f (is-a?/c draw:bitmap%)) 'loaded])
         image?]{
Creates a Skia image by copying the pixels of @racket[bitmap]. Later changes to
the bitmap do not affect the image.

The image is stored in CPU memory and has no color-space tag.

The @racket[resolution] argument determines the copied pixel dimensions. With
@racket['physical], the default, each dimension is the ceiling of the bitmap's
logical dimension multiplied by its backing scale, and the bridge requests
unscaled pixel readback. With @racket['logical], the output dimensions are the
bitmap's logical width and height and the bridge requests Racket Draw's
logical-size readback. The returned image records only the resulting pixel
dimensions. It stores no backing scale, DPI, encoded format, palette,
loaded-mask identity, color profile, or floating-point/HDR representation.

The @racket[mask] argument controls additional alpha coverage. The default
@racket['loaded] uses @method[draw:bitmap% get-loaded-mask] when one is present.
When @racket[mask] is @racket[#f], the loaded mask is ignored; a supplied bitmap
replaces it. A resolved mask must be usable and must have the same logical
dimensions as the source bitmap. Its own loaded mask is not applied
recursively. In physical mode, the bridge chooses the nearest mask pixel for each
source-pixel center, accounting for differing backing scales.

The bridge multiplies each premultiplied RGB component and alpha by the
resolved mask coverage. Invalid premultiplied source samples, where an RGB component
exceeds alpha, raise an exception. Fully transparent output has zero RGB.
Monochrome black and white samples remain literal black and white; this is a
pixel copy, not the foreground/background stencil behavior of a bitmap draw.

No PNG encoding, color-space conversion, or profile inference occurs. The
result is created with no Skia color-space tag. The selected source and mask
dimensions must satisfy the ordinary Skia image limits. Before allocating the
conversion buffers, the function checks a conservative size estimate: 12 bytes
per output pixel plus 4 bytes per mask pixel, when a mask is used. This estimate
must fit @racket[current-skia-byte-limit]. The check does not bound all memory
used internally by Racket Draw or Skia.
Readback or native image-construction failure raises without returning a
partial image.
}

The @racket[image->bitmap] and @racket[surface->bitmap] functions are
re-exported unchanged from @racketmodname[skia/bitmap]. They copy CPU Skia
pixels into independent Racket Draw bitmaps and retain the contracts documented
in @secref["skia-image-operations"]. They are reverse-direction pixel copies,
not metadata-preserving inverses of @racket[bitmap->image].

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/racket-draw)

(define source (draw:make-bitmap 20 10 #t))
(with-skia ([image (bitmap->image source #:mask #f)])
  (list (image-width image) (image-height image)))
]

For a bitmap with backing scale 1, the result is @racket['(20 10)].

@subsection{Masks, Reverse Copies, and Pixel Density}

This example starts with one asymmetric Racket bitmap and a partly transparent
loaded mask. The first panel uses that loaded mask; the second explicitly
ignores it, then goes through @racket[image->bitmap] before returning to a
Skia image. The third snapshots a Skia surface through @racket[surface->bitmap].
The checkerboard is only a presentation background for the copied alpha.

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/racket-draw)

(define source (draw:make-bitmap 3 2 #t))
(send source set-argb-pixels 0 0 3 2
      (bytes 255 230 75 50   255 35 155 85   255 45 105 230
             255 240 185 45  255 150 70 190   255 35 180 185)
      #f #t)
(define coverage (draw:make-bitmap 3 2 #t))
(send coverage set-argb-pixels 0 0 3 2
      (bytes 102 0 0 0  178 0 0 0  255 0 0 0
             102 0 0 0  178 0 0 0  255 0 0 0)
      #f #t)
(send source set-loaded-mask coverage)

(with-skia ([masked (bitmap->image source)]
            [unmasked (bitmap->image source #:mask #f)]
            [surface (make-surface 3 2)])
  (draw-image (surface-canvas surface) unmasked 0 0)
  (define returned-bitmap (image->bitmap unmasked))
  (define surface-bitmap (surface->bitmap surface))
  (with-skia ([returned (bitmap->image returned-bitmap #:mask #f)]
              [surface-copy (bitmap->image surface-bitmap #:mask #f)])
    (list (image-width masked) (image-height masked)
          (image-width returned) (image-height surface-copy))))
]
@reference-figure["bitmap-mask-and-copies.png"
                  "An asymmetric three-by-two Racket bitmap is imported with its partly transparent loaded mask, without the mask through image-to-bitmap, and from a Skia surface copied with surface-to-bitmap; checkerboards show only the alpha preview."]

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/racket-draw)

(define high-density (draw:make-bitmap 3 2 #t #:backing-scale 2))
(define bitmap-dc (new draw:bitmap-dc% [bitmap high-density]))
(send bitmap-dc set-pen "black" 1 'transparent)
(send bitmap-dc set-brush "orange" 'solid)
(send bitmap-dc draw-ellipse 1/4 1/4 5/2 3/2)
(send bitmap-dc set-bitmap #f)
(with-skia ([physical (bitmap->image high-density #:resolution 'physical #:mask #f)]
            [logical (bitmap->image high-density #:resolution 'logical #:mask #f)])
  (list (list (image-width physical) (image-height physical))
        (list (image-width logical) (image-height logical))))
]
@reference-figure["bitmap-resolution-density.png"
                  "One logical three-by-two Racket bitmap with backing scale two is imported as a six-by-four physical image and as a three-by-two logical image; nearest-neighbor previews expose the different copied sample grids."]

@section{Colors}

The color conversions copy channel values only. They do not use the Racket
color database, premultiply RGB, or perform color-space conversion.

@defproc[(color%->rgba [color (is-a?/c draw:color%)]) rgba?]{
Returns an immutable @racket[rgba] value with the red, green, and blue bytes
reported by @racket[color]. The Draw alpha value must be finite and in the
inclusive range from 0 through 1. The returned alpha byte is
@racket[(inexact->exact (round (* 255 alpha)))].

An exception is raised if the object reports a non-byte RGB component or an
invalid alpha value.
}

@defproc[(rgba->color% [color rgba?]) (is-a?/c draw:color%)]{
Returns a fresh Racket Draw @racket[draw:color%] with the same RGB bytes and
alpha @racket[(/ (rgba-alpha color) 255.0)].
}

@section{Paths}

Path conversion copies geometry. It does not copy a drawing-context transform,
clip, pen, brush, text state, or pixel-alignment policy. Racket Draw stores the
fill interpretation separately from @racket[draw:dc-path%], so the bridge makes
that distinction explicit in both directions.

@defproc[(dc-path->skia-path
          [path (is-a?/c draw:dc-path%)]
          [#:fill-style fill-style (or/c 'odd-even 'winding) 'odd-even])
         skia-path?]{
Creates a Skia path by copying the geometry of @racket[path].

The bridge copies moves, lines, cubic Bézier segments, closed
subpaths, and a possible final open subpath. Later mutation of the Draw path
does not change the result.

The @racket[fill-style] argument supplies the interpretation that a Draw
drawing operation would otherwise receive separately. The @racket['odd-even] fill style maps
to Skia's @racket['even-odd] fill rule, and @racket['winding] maps to
@racket['winding]. The default is @racket['odd-even]; callers that intend to
draw the source with winding fill should pass @racket['winding] explicitly.

The function raises an exception if public path data are invalid or if
allocation or native construction fails; it does not return a partial path.
}

@defproc[(skia-path->dc-path
          [path skia-path?]
          [#:conic-subdivisions power (or/c #f (integer-in 0 5)) #f])
         (values (is-a?/c draw:dc-path%) (or/c 'odd-even 'winding))]{
Returns two values: a fresh Racket Draw @racket[draw:dc-path%] and the
Draw fill style required to preserve the Skia path's fill rule. The source path
must be live and used on its owning Racket thread.

Moves, lines, cubic Bézier segments, and close operations map directly.
Quadratic Bézier segments are degree-elevated to cubics without geometric
approximation, although ordinary numeric roundoff can change coordinates. A
conic with weight 1 is handled as a quadratic. Other rational conics have no
direct @racket[draw:dc-path%] representation and therefore raise by default.

The @racket[power] argument requests an explicit vector approximation for
non-unit conics. Its value ranges from zero through five. A conic is subdivided
into at most @racket[(expt 2 power)] quadratic segments, and each resulting
quadratic is then degree-elevated to a cubic. The subdivision power is a bound
on expansion, not a geometric-error tolerance and not a raster fallback.

Racket Draw permits any number of closed subpaths followed by at most one final
open subpath. A Skia path containing an open contour followed by another
contour cannot be represented without closing or reordering geometry, so the
function raises instead. Empty paths are accepted.

Both conversion functions use a conservative estimate of 64 bytes per copied or
expected output command when checking @racket[current-skia-byte-limit]. For Skia
conics, the prediction includes the requested subdivision expansion. If
validation or conversion fails, neither function returns a partially converted
path.
}

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/racket-draw)

(define source-path (new draw:dc-path%))
(send source-path rectangle 2 2 20 14)

(with-skia ([path (dc-path->skia-path source-path #:fill-style 'winding)])
  (define-values (copy fill-style)
    (skia-path->dc-path path))
  (define bitmap (draw:make-bitmap 24 18 #t))
  (define bitmap-dc (new draw:bitmap-dc% [bitmap bitmap]))
  (send bitmap-dc set-pen "black" 1 'transparent)
  (send bitmap-dc set-brush "blue" 'solid)
  (send bitmap-dc draw-path copy 0 0 fill-style)
  (send bitmap-dc set-bitmap #f)
  (with-skia ([image (bitmap->image bitmap #:mask #f)]
              [surface (make-surface 200 150 #:background 'white)]
              [font (make-font #:size 13)]
              [label (make-paint #:color "#20344E")]
              [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
    (draw-simple-text (surface-canvas surface) "Draw -> Skia -> Draw (winding)" 20 20 font label)
    (draw-image-rect (surface-canvas surface) image 20 30 160 120 #:sampling 'nearest)
    (draw-rect (surface-canvas surface) 20 30 160 120 outline))
  (list (is-a? copy draw:dc-path%) fill-style))
]

@reference-figure["draw-path-roundtrip.png"
                  "The winding rectangle after Draw to Skia to Draw conversion, rendered by a real Racket Draw bitmap DC and enlarged with nearest-neighbor sampling."]

The displayed pixels come from the returned @racket[draw:dc-path%] and its returned fill style;
they are not a redraw of the original Skia path.

The result is @racket['(#t winding)]. Rational conics require an explicit
approximation policy:

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/racket-draw)

(with-skia ([path (make-path '((move 0 0) (conic 10 20 20 0 0.5)))]
            [native-surface (make-surface 24 24 #:background 'white)]
            [native-paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 1.5)])
  (define-values (copy fill-style)
    (skia-path->dc-path path #:conic-subdivisions 4))
  (draw-path (surface-canvas native-surface) path native-paint)
  (define bitmap (draw:make-bitmap 24 24 #t))
  (define bitmap-dc (new draw:bitmap-dc% [bitmap bitmap]))
  (send bitmap-dc set-pen "blue" 2 'solid)
  (send bitmap-dc set-brush "black" 'transparent)
  (send bitmap-dc draw-path copy 1 1 fill-style)
  (send bitmap-dc set-bitmap #f)
  (with-skia ([native-image (surface-snapshot native-surface)]
              [draw-image (bitmap->image bitmap #:mask #f)]
              [surface (make-surface 280 150 #:background 'white)]
              [font (make-font #:size 12)]
              [label (make-paint #:color "#20344E")]
              [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
    (draw-simple-text (surface-canvas surface) "native Skia conic" 20 20 font label)
    (draw-simple-text (surface-canvas surface) "Draw approx., power 4" 150 20 font label)
    (draw-image-rect (surface-canvas surface) native-image 20 32 110 110 #:sampling 'nearest)
    (draw-image-rect (surface-canvas surface) draw-image 150 32 110 110 #:sampling 'nearest)
    (draw-rect (surface-canvas surface) 20 32 110 110 outline)
    (draw-rect (surface-canvas surface) 150 32 110 110 outline))
  (list (is-a? copy draw:dc-path%) fill-style))
]

@reference-figure["draw-path-conic-approximation.png"
                  "The native Skia rational conic at left and the result of rendering the returned Racket Draw path at right. The Draw result uses the explicit subdivision power 4 and is rendered through a Racket Draw bitmap DC."]

The subdivision power bounds the number of generated quadratic segments; it is not an error
tolerance. The two panels use independent rendering consumers.

The second example returns @racket['(#t winding)] after converting the conic to
a bounded sequence of cubic Bézier segments.
