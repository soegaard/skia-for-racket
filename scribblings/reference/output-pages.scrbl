#lang scribble/manual

@(require "support/figures.rkt"
          scribble/eval
          (for-label racket/base racket/contract file/convertible skia skia/output))

@(define unit-eval (make-base-eval))
@(unit-eval '(require skia/output))

@title[#:tag "skia-output-pages"]{Output Pages and Raster Fallback}

@defmodule[skia/output #:no-declare]
@(declare-exporting skia skia/output #:use-sources (skia/output))

An @deftech{output page} is a detached description containing dimensions, units,
margins, a background, and a drawing callback. It owns no native resource.
Exporting it invokes the callback again; it is not a recorded picture. Resources
captured by the callback must remain open whenever the page is drawn.

@local-table-of-contents[#:style 'immediate-only]

@section{Dimensions and Page Descriptions}

@defproc[(unit->points [value real?] [unit (or/c 'pt 'in 'mm 'cm 'px) 'pt]) real?]{
Converts a length to points. The factors are exactly 1 for points, 72 for inches,
@racket[360/127] for millimeters, @racket[3600/127] for centimeters, and
@racket[3/4] for CSS pixels at 96 pixels per inch. The input and result must lie
within the drawing-scalar range. Exact inputs retain exact arithmetic; the
conversion does not query a display's DPI.

@examples[#:eval unit-eval
(eval:check (unit->points 1 'in) 72)
(eval:check (unit->points 127/5 'mm) 72)
(eval:check (unit->points 96 'px) 72)
]
@close-eval[unit-eval]
}

@defproc[(output-page? [v any/c]) boolean?]{
Returns @racket[#t] for an output-page description and @racket[#f] otherwise.
}

@defproc[(make-output-page [width (and/c real? (>/c 0))]
                           [height (and/c real? (>/c 0))] [draw (-> canvas? any)]
                           [#:unit unit (or/c 'pt 'in 'mm 'cm 'px) 'pt]
                           [#:margins margins (or/c real? list?) 0]
                           [#:background background (or/c color? #f) #f]
                           [#:clip? clip? boolean? #t]) output-page?]{
Returns a page description without invoking @racket[draw] or allocating native
storage. Width and height are positive drawing scalars in @racket[unit]. Their
point equivalents must each be from 0.001 through 14400.

Margins are a nonnegative drawing scalar applied to all four sides, or a list
of four such values in left, top, right, bottom order. This is not CSS order.
The paired horizontal and vertical margins must leave a positive content area.
The background is @racket[#f] for no background drawing or a color specification
normalized to an RGBA value. The clip flag controls clipping to the content area.

The callback must accept one canvas argument and have no required keyword
arguments. It draws in page units with its origin at the content area's upper-left.
Its results are discarded. Capturing a closed paint or image does not become
safe merely because the page itself is a detached value.


@racketblock[
(with-skia ([surface (make-surface 220 120 #:background 'white)])
  (define canvas (surface-canvas surface))
  (define page
    (make-output-page 220 120
      (lambda (pc)
        (with-skia ([blue (make-paint #:color "#326DE6")])
          (draw-circle pc 0 0 45 blue)))
      #:margins 25 #:clip? #f #:background "#EEF1F4"))
  (with-skia ([image (output-page->image page #:dpi 72)])
    (draw-image canvas image 0 0)))
]
@reference-figure["output-page-no-clip-stage10.png"
                  "With content clipping disabled, a blue circle centered at the content origin spills into the page margins."]

@racketblock[
(with-skia ([surface (make-surface 220 120 #:background 'white)])
  (define canvas (surface-canvas surface))
  (define page
    (make-output-page 220 120
      (lambda (pc)
        (with-skia ([orange (make-paint #:color "#EFA02B")])
          (draw-circle pc 90 45 32 orange)))
      #:margins 20 #:background "#326DE6"))
  (with-skia ([image (output-page->image page #:dpi 72)])
    (draw-image canvas image 0 0)))
]
@reference-figure["output-page-background-stage10.png"
                  "An orange content circle sits on a blue output-page background inside equal margins."]
}

@defproc[(output-page-width [page output-page?]) real?]{Returns the width in the page's units.}
@defproc[(output-page-height [page output-page?]) real?]{Returns the height in the page's units.}
@defproc[(output-page-unit [page output-page?]) (or/c 'pt 'in 'mm 'cm 'px)]{
Returns the page's length unit.
}
@defproc[(output-page-margins [page output-page?]) (list/c real? real? real? real?)]{
Returns the normalized left, top, right, bottom margins in page units.
}
@defproc[(output-page-background [page output-page?]) (or/c rgba? #f)]{
Returns the normalized background color or @racket[#f] for no background drawing.
}
@defproc[(output-page-clip? [page output-page?]) boolean?]{
Returns whether drawing is clipped to the content rectangle.
}
@defproc[(output-page-size-in-points [page output-page?]) (values real? real?)]{
Returns the full page width and height converted to points, without subtracting margins.
}
@defproc[(output-page-content-size [page output-page?]) (values real? real?)]{
Returns width and height after subtracting margins, in the page's own units, not points.
}

@section{Drawing and Exporting Pages}

@defproc[(draw-output-page [canvas canvas?] [page output-page?]
                           [#:text-mode text-mode (or/c 'native 'outline) 'native]
                           [#:raster-dpi raster-dpi (real-in 1 9600) 144]) void?]{
Draws the page on a canvas whose current coordinate unit is treated as a point.
Within a protected canvas-state scope, it scales to page units, paints any
background over the full page rectangle, translates by the left and top margins,
and optionally clips to the content rectangle before calling the callback.
The caller's existing transform and clip still apply. A background is ordinary
rectangle drawing, not @racket[canvas-clear!], and does not clear surrounding content.

The operation parameterizes text output and the explicit raster-fallback scale
only during the callback, then restores them and the canvas state. Drawing is
not rolled back on escape. The effective fallback scale is
@math{raster-dpi / 72} times the unit-to-point factor; it must lie from
@racket[1/1024] through 1024 even when no fallback is ultimately drawn.


@racketblock[
(with-skia ([surface (make-surface 240 140 #:background 'white)])
  (define canvas (surface-canvas surface))
  (define page
    (make-output-page 100 60
      (lambda (pc)
        (with-skia ([blue (make-paint #:color "#326DE6")])
          (draw-rounded-rect pc 0 0 100 60 10 10 blue)))
      #:background "#EEF1F4"))
  (with-canvas-state canvas
    (canvas-translate! canvas 70 35)
    (canvas-rotate! canvas 12)
    (draw-output-page canvas page)))
]
@reference-figure["draw-output-page-rotated-stage10.png"
                  "A complete output page is drawn onto another canvas under a translated and rotated current transform."]
}

@defproc[(output-page->image [page output-page?]
                            [#:dpi dpi (real-in 1 9600) 96]
                            [#:text-mode text-mode (or/c 'native 'outline) 'native]
                            [#:color-space color-space (or/c color-space? #f) #f]) image?]{
Returns an owned raster image of the page. Pixel dimensions are the ceilings
of each point extent multiplied by @racket[(/ dpi 72)]. The canvas scale accounts
for that rounding without changing the page's logical dimensions. The surface
starts transparent unless a page background is drawn. Dimensions and storage
must fit the ordinary raster limits, and the effective fallback scale must be
valid. The temporary surface is released; the image remains independently owned.
}

@defproc[(output->bytes [source (or/c output-page? (listof output-page?))]
                       [format (or/c 'pdf 'svg)]
                       [#:title title string? ""] [#:description description string? ""]
                       [#:text-mode text-mode (or/c 'auto 'native 'outline) 'auto]
                       [#:raster-dpi raster-dpi (real-in 1 9600) 144]
                       [#:id-prefix id-prefix (or/c string? #f) #f]
                       [#:encoding-quality quality (or/c (integer-in 0 101) #f) #f]
                       [#:pdfa? pdfa? boolean? #f]) (and/c bytes? (not/c immutable?))]{
Returns a completed PDF or SVG byte string. The source is one page or a nonempty
list of pages. PDF exports all pages in order; SVG requires exactly one page
and never silently drops extra pages. All page descriptions and format settings
are validated before the first callback is invoked.

Automatic text mode selects @racket['native] for PDF and @racket['outline] for
SVG. Explicit modes override that choice. Neither mode is a guarantee of
searchable text or exact reproduction of glyphs with no monochrome outline.
Use explicit raster fallback when pixels, rather than outlines, must be preserved.

The title is PDF title metadata or SVG title metadata. The description becomes
the PDF subject or SVG description. The PDF settings for raster DPI, encoding
quality, and PDF/A have the meaning given at @racket[make-pdf-document]. A false
quality selects 101 for PDF. The ID prefix is SVG-only and defaults to
@racket["skia"] when false. PDF rejects a nonfalse ID prefix; SVG rejects a
nonfalse encoding quality or true PDF/A option. These are rejected options, not
ignored format-specific arguments.

SVG root dimensions are written in points with a corresponding view box, giving
the PDF and SVG the same nominal physical size. Native fallback and viewer
behavior can still differ. Completion must succeed before any bytes are returned.

@racketblock[
(define page
  (make-output-page 60 40
    (lambda (canvas)
      (with-skia ([paint (make-paint #:color 'blue)])
        (draw-circle canvas 10 10 8 paint)))
    #:unit 'mm #:margins 5 #:background 'white))
(save-output page "page.pdf" 'pdf #:exists 'replace)
(save-output page "page.svg" 'svg #:exists 'replace)
(with-skia ([preview (output-page->image page #:dpi 25.4)])
  (list (image-width preview) (image-height preview)))
]

The same callback runs once for each export and once for the explicit raster preview; it creates
its paint inside each call. At 25.4 DPI, the preview has one pixel per millimeter.

@reference-figure["output-page-preview.png"
                  "A proportional 120 by 80 screen preview rasterized from the documented 60 by 40 millimeter page. The blue circle's center is at 30, 30 and its radius is 16 in preview pixels, including the five-millimeter margins."]

This is a scaled screen preview built through @racket[output-page->image], not proof of a
physical print size.
}

@defproc[(save-output [source (or/c output-page? (listof output-page?))]
                      [filename path-string?] [format (or/c 'pdf 'svg)]
                      [#:exists exists (or/c 'error 'replace) 'error]
                      [#:title title string? ""] [#:description description string? ""]
                      [#:text-mode text-mode (or/c 'auto 'native 'outline) 'auto]
                      [#:raster-dpi raster-dpi (real-in 1 9600) 144]
                      [#:id-prefix id-prefix (or/c string? #f) #f]
                      [#:encoding-quality quality (or/c (integer-in 0 101) #f) #f]
                      [#:pdfa? pdfa? boolean? #f]) void?]{
Exports as in @racket[output->bytes] and publishes the completed file. The format
is explicit; it is not inferred from the filename suffix. The destination is
resolved before callbacks run. Its parent directory must exist. Publication
uses the temporary-file and rename rules of @racket[save-pdf] or @racket[save-svg].
}

@subsection{Standard Conversion}

Output pages also implement @racketmodname[file/convertible]. They accept
@racket['png-bytes], @racket['svg-bytes], and @racket['pdf-bytes]. PNG first
rasterizes through @racket[output-page->image] at its fixed 96-DPI default
(including its ceiling pixel rounding), then uses @racket[image->png-bytes]. It
therefore produces a raster result. SVG and PDF use @racket[output->bytes] with
their existing defaults. Each supported conversion invokes the page callback
once; a later conversion intentionally invokes it again. Temporary raster
images are released even if the callback raises or escapes. This matters for
deferred Scribble rendering: resources captured by a page must stay live until
the renderer requests its chosen format. Unsupported requests return the exact
supplied default unchanged and do not draw the page. GPU values captured by a
callback retain their ordinary explicit-transfer rules; conversion adds no
implicit transfer.

@section[#:tag "skia-raster-fallback"]{Text Representation and Explicit Raster Fallback}

@defparam[current-text-output-mode mode (or/c 'native 'outline)]{
Selects native text drawing or monochrome outline conversion for the drawing
helpers that honor this parameter. Its initial value is @racket['native].
It is not a global backend switch and does not retroactively alter an already
recorded picture. Outline conversion does not embed a font or preserve text
semantics; unavailable monochrome glyph outlines have the behavior documented
by the relevant text-to-path operation.
}

@defparam[current-raster-output-scale scale (real-in 1/1024 1024)]{
Provides the default pixels-per-logical-unit scale for @racket[draw-rasterized].
Its initial value is 1. Export helpers parameterize it for their page units and
DPI. Changing the parameter neither resamples an existing image nor forces all
drawing to use raster output.
}

@defproc[(draw-rasterized [canvas canvas?] [x real?] [y real?]
                         [width (and/c real? (>/c 0))] [height (and/c real? (>/c 0))]
                         [proc (-> canvas? any)]
                         [#:scale scale (real-in 1/1024 1024) (current-raster-output-scale)]
                         [#:padding padding (or/c real? list?) 0]
                         [#:color-space color-space (or/c color-space? #f) #f]) void?]{
Draws the callback into a temporary transparent CPU surface, then draws its
snapshot onto the destination. The callback receives a separate borrowed canvas
with a local origin corresponding to @racket[x] and @racket[y] on the target.
It does not inherit the target's transform or clip. The final image drawing does
honor the target's transform and clip, and uses linear sampling.

Padding has the same nonnegative left, top, right, bottom interpretation as page
margins. It enlarges the raster region without shrinking or moving the original
logical content. Pixel dimensions are the ceilings of the padded extents times
@racket[scale]; both dimensions and the RGBA allocation must fit the ordinary
surface limits. The snapshot is placed at the original origin minus left/top
padding. Coordinates and padded dimensions must remain drawing scalars.

Text mode is forced to @racket['native] inside the callback so that native
rendered glyphs can be captured. Callback results are ignored and temporary
resources are released on success or escape. A failed callback does not draw
the final snapshot onto the target. The callback canvas must not be retained.

This is explicit CPU rasterization, not automatic GPU readback. A GPU-surface
target is rejected. PDF and SVG can embed the resulting raster image, but that
region is no longer vector geometry or searchable text.

@racketblock[
(with-skia ([document (make-svg-document 120 80)]
            [blur (make-blur-image-filter 3 3)]
            [paint (make-paint #:color 'blue #:image-filter blur)])
  (draw-rasterized (svg-document-canvas document) 20 20 60 40
    (lambda (canvas) (draw-rect canvas 0 0 60 40 paint))
    #:scale 2 #:padding 12)
  (svg-document-finish! document)
  (save-svg document "raster-region.svg" #:exists 'replace))
]

@racketblock[
(with-skia ([surface (make-surface 190 105 #:background 'white)])
  (draw-rasterized (surface-canvas surface) 30 22 120 55
    (lambda (canvas)
      (with-skia ([filter (make-blur-image-filter 5 5)]
                  [paint (make-paint #:color "#326DE6" #:image-filter filter)])
        (draw-rounded-rect canvas 10 8 100 38 10 10 paint)))
    #:scale 2
    #:padding 10))
]

@reference-figure["draw-rasterized.png"
                  "A bounded blue rounded rectangle with blur captured through explicit rasterization."]
}

@section{Additional Visual Example}

@racketblock[
(define page
  (make-output-page
   180 100
   (lambda (canvas)
     (with-skia ([paint (make-paint #:color "#326DE6")])
       (draw-rect canvas 0 0 130 70 paint)))
   #:margins '(20 15 30 15)
   #:background "#EEF1F4"))
(with-skia ([image (output-page->image page #:dpi 72)])
  image)
]
@reference-figure["output-page-margins.png"
                  "A light-gray page with a blue content rectangle inset by unequal left, top, right, and bottom margins."]
