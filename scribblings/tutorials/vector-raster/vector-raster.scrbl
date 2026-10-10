#lang scribble/manual

@title{Vector Output and Raster Fallbacks — What Stays Vector?}

@(require "eval.rkt"
          (for-label racket
                     skia))

@section{The Finished Comparison Sheet}

@(vector-finished-pict #:scale 0.64)

This tutorial builds the comparison sheet shown above. The three panels look
like parts of one drawing, but they are not stored in the same way by PDF and
SVG. The left panel uses vector shapes and a linear gradient. The middle panel
contains an image made of pixels. The right panel keeps only a filtered region
as an embedded image, while its border and labels remain vector geometry.

The figure is a separate raster rendering of the finished page, generated from
the @racket[draw-study] function in @filepath{vector-raster.rkt}. It is not a
screenshot or a rendering of either exported document.

The main idea is:

@centered{@bold{A vector document can contain both drawing operations and
pixels. Choose a bounded raster fallback when an effect cannot be preserved
reliably by a document backend.}}

@section{Draw Geometry That Can Stay Vector}

Begin with familiar geometry and a linear gradient. These constants also set
the dimensions and colors of the finished sheet:

@vector-racketblock+eval[
(define sheet-width 900)
(define sheet-height 610)
(define paper-color "#F3F7FB")
(define ink-color "#243852")
(define muted-color "#62768C")
(define blue-color "#326BC4")
(define teal-color "#159F99")
]

The motif combines a filled rounded rectangle, stroked circles, and a small
accent dot:

@vector-racketblock+eval[
(define (draw-vector-art canvas)
  (define gradient
    (make-linear-gradient-shader 0 0 200 0
                                 (list blue-color teal-color)))
  (define fill (make-paint #:shader gradient))
  (define ring
    (make-paint #:color "#EAF6FA"
                #:style 'stroke
                #:stroke-width 3))
  (define dot (make-paint #:color "#F6B86C"))
  (draw-rounded-rect canvas 2 4 196 170 22 22 fill)
  (for ([radius '(62 43 24)])
    (draw-circle canvas 100 89 radius ring))
  (draw-line canvas 27 142 173 142 ring)
  (draw-circle canvas 100 89 10 dot))
]

@vector-image[
(vector-render-pict
 240 215
 (lambda (canvas)
   (with-canvas-state canvas
     (canvas-translate! canvas 20 16)
     (draw-vector-art canvas)))
 #:scale 0.90)
]

The @racket[draw-rounded-rect], @racket[draw-circle], and @racket[draw-line]
functions describe geometry. The linear gradient is a supported native vector
paint in both PDF and SVG for this example. A viewer can enlarge these shapes
without first enlarging a stored grid of source pixels.

The word @italic{vector} describes the output representation, not the fact
that the program used particular drawing functions. Another operation may
produce pixels even when the program uses the same canvas API.

@section{Make an Image from Pixels}

First, draw a small pattern on a 32 by 32 surface and capture its contents:

@vector-racketblock+eval[
(define (make-pixel-tile)
  (define surface
    (make-surface 32 32 #:background "#234D74"))
  (define canvas (surface-canvas surface))
  (define teal (make-paint #:color "#54B9B5"))
  (define amber (make-paint #:color "#F6B86C"))
  (for* ([row (in-range 4)]
         [column (in-range 4)]
         #:when (even? (+ row column)))
    (draw-rect canvas (* column 8) (* row 8) 8 8 teal))
  (draw-rect canvas 9 9 14 14 amber)
  (surface-snapshot surface))
]

The @racket[surface-snapshot] function captures the current pixels as an
immutable image. Once captured, the image is not a recording of the calls that
made it. The surface could change afterward without changing the snapshot.

Here is the actual 32 by 32 image, displayed at four times its natural size.
The enlargement uses nearest-neighbor sampling so the source pixels remain
visible:

@vector-image[
(vector-source-tile-pict (make-pixel-tile))
]

Now place that same kind of image on a canvas at six times its original size:

@vector-racketblock+eval[
(define (draw-pixel-art canvas)
  (define tile (make-pixel-tile))
  (draw-image-rect canvas tile 4 0 192 192
                   #:sampling 'nearest))
]

@vector-image[
(vector-render-pict
 230 222
 (lambda (canvas)
   (with-canvas-state canvas
     (canvas-translate! canvas 17 12)
     (draw-pixel-art canvas)))
 #:scale 0.90)
]

The image has exactly 32 by 32 source pixels. The figure displays it at
192 by 192 drawing units, with @racket[#:sampling 'nearest] so that individual
pixels remain visible. The illustrated image is the actual snapshot returned
by @racket[make-pixel-tile], not a second version redrawn for the manual.

When this image is drawn into PDF or SVG, it is embedded as raster content.
Saving the containing page as SVG does not reconstruct vector rectangles from
the stored pixels.

@section{Recognize an Effect That Needs Special Care}

The previous tutorial introduced image filters. Here, the same kind of filter
will provide a soft shadow for a small badge:

@vector-racketblock+eval[
(define (draw-filtered-badge canvas)
  (define shadow
    (make-drop-shadow-image-filter
     0 9 7 7 (rgba 22 52 87 130)))
  (define fill
    (make-paint #:color "#24A7A0"
                #:image-filter shadow))
  (draw-rounded-rect canvas 26 18 146 116 24 24 fill))
]

@vector-image[
(vector-render-pict
 225 188 draw-filtered-badge #:scale 0.98)
]

The figure above comes from a raster surface, where the filter produces the
expected shadow. That does not establish that a native SVG exporter can express
the same effect. A PDF backend may expand an effect internally, while SVG
support for image filters is limited.

We can check the direct drawing before attempting an SVG export:

@vector-racketblock+eval[
(define direct-shadow-page
  (make-output-page 206 180 draw-filtered-badge #:unit 'px))
]

@vector-interaction[
(define direct-shadow-report
  (analyze-output-page direct-shadow-page 'svg))
(output-audit-report-blocking? direct-shadow-report)
]

The result is @racket[#t] because the SVG output policy classifies the image
filter as requiring a raster fallback. The preflight observes the callback;
it does not insert the fallback, and it does not produce a usable SVG file.
We must make the representation choice explicitly.

@section{Rasterize Only the Filtered Region}

The @racket[draw-rasterized] function draws one bounded region into a temporary
raster surface and places its snapshot on the receiving canvas. The following
function uses that boundary for the filtered badge. It then draws a crisp
border and center dot @italic{outside} the raster group:

@vector-racketblock+eval[
(define (draw-fallback-art canvas)
  (define border
    (make-paint #:color ink-color
                #:style 'stroke
                #:stroke-width 2.5))
  (define center (make-paint #:color "#FFF3DA"))
  (with-output-label "bounded raster"
    (draw-rasterized canvas 0 0 206 180 draw-filtered-badge
                     #:scale 2))
  (with-output-label "vector details"
    (draw-rounded-rect canvas 26 18 146 116 24 24 border)
    (draw-circle canvas 99 76 15 center)))
]

@vector-image[
(vector-render-pict
 245 220
 (lambda (canvas)
   (define boundary
     (make-paint #:color "#CE554A"
                 #:style 'stroke
                 #:stroke-width 1.5))
   (with-canvas-state canvas
     (canvas-translate! canvas 19 14)
     (draw-fallback-art canvas)
     (draw-rect canvas 0 0 206 180 boundary)))
 #:scale 0.92)
]

The red rectangle in this figure marks the raster group's actual bounds.
It is a presentation guide, not part of the finished drawing. The group is
206 by 180 drawing units. Its explicit scale of 2 makes a 412 by 360 pixel
image before that image is placed on the PDF or SVG page. Unlike the page's
@racket[#:raster-dpi] setting, this explicit @racket[#:scale] fixes the
group's pixel density.

The filtered rectangle sits far enough inside the bounds for this shadow to
fit. Larger blurs may require more room or the @racket[#:padding] option.
Padding enlarges the raster boundary without moving the callback's origin.

The outer document still receives the border and the center dot as ordinary
drawing operations. Rasterizing the badge does not rasterize the rest of the
page. A raster group starts transparent; it does not automatically include
pixels already drawn behind it. This matters for effects that blend with a
backdrop.

@section{Build the Comparison Sheet}

The finished composition places the three demonstrations next to one another.
The frame, captions, and footer are also drawn outside the raster group:

@vector-racketblock+eval[
(define (draw-study canvas)
  (define title-font (make-font #:size 39))
  (define subtitle-font (make-font #:size 18))
  (define label-font (make-font #:size 16))
  (define caption-font (make-font #:size 15))
  (define small-font (make-font #:size 14))
  (define ink (make-paint #:color ink-color))
  (define muted (make-paint #:color muted-color))
  (define blue (make-paint #:color blue-color))
  (define panel-fill (make-paint #:color 'white))
  (define rule
    (make-paint #:color "#D2E0EA"
                #:style 'stroke
                #:stroke-width 1.5))

  (draw-simple-text canvas "What stays vector?" 48 84 title-font ink)
  (draw-simple-text canvas "One page can contain shapes and pixels." 50 119
                    subtitle-font muted)
  (for ([x '(44 328 612)])
    (draw-rounded-rect canvas x 159 244 354 18 18 panel-fill)
    (draw-rounded-rect canvas x 159 244 354 18 18 rule))

  (draw-simple-text canvas "01   PATHS + GRADIENT" 62 201 label-font blue)
  (draw-simple-text canvas "02   RASTER IMAGE" 346 201 label-font blue)
  (draw-simple-text canvas "03   LOCAL FALLBACK" 630 201 label-font blue)

  (with-output-label "vector motif"
    (with-canvas-state canvas
      (canvas-translate! canvas 66 244)
      (draw-vector-art canvas)))
  (with-output-label "source pixels"
    (with-canvas-state canvas
      (canvas-translate! canvas 348 230)
      (draw-pixel-art canvas)))
  (with-canvas-state canvas
    (canvas-translate! canvas 630 238)
    (draw-fallback-art canvas))

  (draw-simple-text canvas "Resizable geometry" 63 471 caption-font ink)
  (draw-simple-text canvas "32 x 32 source pixels" 347 471 caption-font ink)
  (draw-simple-text canvas "Pixels only in this group" 631 471
                    caption-font ink)

  (draw-line canvas 48 546 850 546 rule)
  (draw-simple-text canvas "SVG and PDF can keep the frame, paths and labels as vectors."
                    50 573 small-font muted)
  (draw-simple-text canvas "Embedded images and the bounded effect remain pixels."
                    50 593 small-font muted))
]

@vector-image[
(vector-render-pict sheet-width sheet-height draw-study #:scale 0.64)
]

The first panel remains authored as geometry and a gradient. The middle panel
draws an immutable image captured from a surface. Only the shadowed area of
the last panel goes through @racket[draw-rasterized]. The page is therefore a
mixture of representations.

The @racket[with-output-label] forms in the drawing code name the important
regions for the output audit. They do not change what Skia draws.

@section{Check the Output Policy}

As in the previous PDF and SVG tutorial, one output page can describe the
finished drawing:

@vector-racketblock+eval[
(define page
  (make-output-page sheet-width sheet-height draw-study
                    #:unit 'px
                    #:background paper-color))
]

The output auditor can observe the drawing operations for a particular
backend. Ask it to inspect the SVG and PDF versions:

@vector-interaction[
(define svg-report
  (analyze-output-page page 'svg #:text-mode 'outline))
(define pdf-report
  (analyze-output-page page 'pdf #:text-mode 'outline))
(output-audit-report-vector-only? svg-report)
(output-audit-report-vector-only? pdf-report)
(output-audit-report-blocking? svg-report)
]

Both pages intentionally include embedded images, so neither is vector-only.
The completed SVG drawing has no known blocking operations. That is not a
promise of visual equivalence: the audit reports observed wrapper operations,
not the exact rendered output.

We can also inspect the recorded status of each labeled region:

@vector-racketblock+eval[
(define (statuses-for report label)
  (remove-duplicates
   (for/list ([event (in-list (output-audit-report-events report))]
              #:when (member label (output-audit-event-scope event)))
     (output-audit-event-status event))))
]

@vector-interaction[
(for/list ([label '("vector motif" "source pixels"
                    "bounded raster" "vector details")])
  (list label (statuses-for svg-report label)))
]

The vector motif and the crisp badge details are recorded as vector operations.
The source image is embedded raster content; the explicit group is rasterized.
The group also places an image on the SVG canvas. The precise event list may
contain several observations for one drawing call.

The @racket[#:text-mode 'outline] choice keeps available text glyph geometry
as paths in both formats. Those outlines are not searchable text. Native PDF
text may be preferable when selection and extraction matter, but text policy
is separate from the image-versus-vector question in this tutorial.

@section{Export PDF and SVG}

An audited export can reject known unsupported operations while still allowing
intentional embedded images. The @racket['error] policy permits explicit raster
groups; it does not require the entire document to be vector-only.

The following expressions exercise both exporters during the documentation
build, without writing files:

@vector-interaction[
(define-values (svg-bytes svg-export-report)
  (output->bytes/audit page 'svg
                       #:text-mode 'outline
                       #:policy 'error))
(define-values (pdf-bytes pdf-export-report)
  (output->bytes/audit page 'pdf
                       #:text-mode 'outline
                       #:policy 'error))
(bytes? svg-bytes)
(bytes? pdf-bytes)
(regexp-match? #rx#"<linearGradient" svg-bytes)
(regexp-match? #rx#"<image" svg-bytes)
]

The final two checks inspect the actual SVG bytes, confirming that the
serializer emitted a linear gradient and at least one embedded image. They
do not establish how a browser or PDF viewer renders the result. The audit
explains @italic{why} a raster image appears; the markup check confirms
that SVG data was emitted.

The complete program uses @racket[save-output/audit] to write the two documents:

@racketblock[
(save-output/audit page "what-stays-vector.pdf" 'pdf
                   #:text-mode 'outline
                   #:policy 'error
                   #:exists 'replace)

(save-output/audit page "what-stays-vector.svg" 'svg
                   #:text-mode 'outline
                   #:policy 'error
                   #:exists 'replace)
]

The @racket['error] policy blocks known operations that need an explicit
raster boundary; it does not certify visual identity. The stricter
@racket['vector-only] policy would reject this page, because the two kinds of
embedded raster content are deliberate.

@section{Make a Raster Preview}

We can also render the same callback to a raster image. The
@racket[output-page->image] function produces a new image from the page
callback; it does not rasterize the saved PDF or SVG file.

@vector-racketblock+eval[
(define preview
  (output-page->image page #:dpi 96 #:text-mode 'outline))
]

@vector-image[
(vector-image-pict preview #:scale 0.64)
]

The complete @filepath{vector-raster.rkt} file saves this result as
@filepath{what-stays-vector.png}, alongside
@filepath{what-stays-vector.pdf} and @filepath{what-stays-vector.svg}.

Open the actual PDF and SVG and zoom in. The geometric lines and outlines can
be enlarged as vector content, while the pixel tile and the rasterized badge
keep their finite source resolution. The separate PNG provides a visual
reference, but it is not evidence of the representation inside either document.

@section{Try It}

Try changing @racket[#:scale 2] in @racket[draw-fallback-art] to a smaller
value. Export the SVG again and examine the badge at high zoom. The rest of
the drawing should remain vector-based.

Try changing the sampling mode in @racket[draw-pixel-art] from
@racket['nearest] to @racket['linear]. This changes how source pixels are
interpolated, not whether the result is an embedded image.

Try removing the explicit raster group and drawing the filtered badge directly
into SVG. Use @racket[analyze-output-page] to inspect the policy warnings
before exporting; do not assume the backend will make an equivalent image.

@section{Where to Go From Here}

This tutorial distinguished vector drawing, embedded raster images, and
bounded raster fallbacks. It also introduced conservative output auditing as
a way to catch known representation risks before publication.

The Guide covers complex filters, native expansion, padding, raster density,
font and color policies, and detailed PDF/SVG inspection. The next tutorial
will render a shared scene with a GPU backend.

The complete @filepath{vector-raster.rkt} program contains the finished
comparison sheet.
