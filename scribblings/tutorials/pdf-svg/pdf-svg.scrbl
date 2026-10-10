#lang scribble/manual

@title{PDF and SVG — Make a Printable Diagram}

@(require "eval.rkt"
          (for-label racket
                     skia))

@section{The Finished Diagram}

@(printable-finished-pict #:scale 0.50)

This tutorial builds the A4 geometry sheet shown above. Two circles construct
an equilateral triangle, with labels for its vertices and a short explanation
of why the construction works.

The figure is a raster preview generated from the complete drawing function in
@filepath{geometry-diagram.rkt}. It is not a screenshot or rasterization of the
exported PDF or SVG. The finished program writes both vector documents and a
separate PNG preview.

The main idea is:

@centered{@bold{One drawing function describes the content. An output page
adds physical size and margins; the exporters write PDF or SVG.}}

The examples build this result in stages. You only need the basic drawing and
text functions from the earlier tutorials.

@section{Draw a Construction}

First, construct the triangle inside the sheet. Each circle has its center at
one end of the base and passes through the other end. Their upper intersection
is the third vertex, C.

Our drawing coordinates will be millimetres, not pixels. An A4 sheet is 210 mm
wide and 297 mm high. We will leave 16 mm margins on every side, giving the
drawing a width of 178 mm:

@printable-racketblock+eval[
(define page-width 210)
(define page-height 297)
(define page-margin 16)
(define content-width (- page-width (* 2 page-margin)))

(define ink-color "#253B50")
(define muted-color "#586A7D")
(define accent-color "#187E89")
(define rule-color "#D1D9E1")

(define point-a-x 60)
(define point-b-x 118)
(define point-y 126)
(define side-length (- point-b-x point-a-x))
(define point-c-x (/ (+ point-a-x point-b-x) 2))
(define point-c-y (- point-y (* side-length (/ (sqrt 3) 2))))
]

The height of the equilateral triangle is the base length multiplied by
@racket[(/ (sqrt 3) 2)]. The two circles both have radius @racket[side-length].

The drawing function uses two light circle outlines, three darker edges, and
small dots for the vertices:

@printable-racketblock+eval[
(define (draw-construction canvas)
  (define first-circle
    (make-paint #:color "#6CADB2"
                #:style 'stroke
                #:stroke-width 0.5))
  (define second-circle
    (make-paint #:color "#DBA05D"
                #:style 'stroke
                #:stroke-width 0.5))
  (define edge
    (make-paint #:color ink-color
                #:style 'stroke
                #:stroke-width 0.9))
  (define point
    (make-paint #:color ink-color))
  (draw-circle canvas point-a-x point-y side-length first-circle)
  (draw-circle canvas point-b-x point-y side-length second-circle)
  (draw-line canvas point-a-x point-y point-b-x point-y edge)
  (draw-line canvas point-a-x point-y point-c-x point-c-y edge)
  (draw-line canvas point-b-x point-y point-c-x point-c-y edge)
  (for ([position (list (list point-a-x point-y)
                        (list point-b-x point-y)
                        (list point-c-x point-c-y))])
    (draw-circle canvas (first position) (second position) 1.35 point)))
]

Here is the construction without page decorations. The figure is a raster
preview of the Skia drawing, scaled down for the manual.

@printable-image[
(printable-page-pict
 (make-output-page content-width 202 draw-construction
                   #:unit 'mm #:background 'white)
 #:dpi 84 #:scale 0.72)
]

Notice that the stroke widths are also in the drawing's millimetres. The
triangle edges are 0.9 mm wide, independently of the resolution used for a
raster preview.

@section{Add the Printable Details}

Now add a heading, the names of the three points, and a short explanation.
The example uses the same text and paragraph functions as the earlier text
tutorials. We can keep these helpers separate from the construction itself.

The font helper disables pixel-rounded metrics and enables subpixel placement.
This is useful when small millimetre-sized fonts are scaled to PDF points or
raster pixels. The exact typeface still depends on the platform.

@printable-racketblock+eval[
(define (make-print-font size)
  (make-font #:size size
             #:linear-metrics? #t
             #:subpixel? #t
             #:hinting 'none))

(define (draw-heading canvas)
  (define small-font (make-print-font 3.7))
  (define title-font (make-print-font 8))
  (define subtitle-font (make-print-font 4.2))
  (define ink (make-paint #:color ink-color))
  (define accent (make-paint #:color accent-color))
  (define muted (make-paint #:color muted-color))
  (define rule (make-paint #:color rule-color
                           #:style 'stroke
                           #:stroke-width 0.45))
  (draw-simple-text canvas "SKIA / GEOMETRY STUDY" 0 9 small-font accent)
  (draw-simple-text canvas "An equilateral triangle" 0 27 title-font ink)
  (draw-simple-text canvas "A straightedge-and-compass construction" 0 37
                    subtitle-font muted)
  (draw-line canvas 0 45 content-width 45 rule))

(define (draw-point-labels canvas)
  (define font (make-print-font 5.2))
  (define ink (make-paint #:color ink-color))
  (draw-simple-text canvas "A" 52 134 font ink)
  (draw-simple-text canvas "B" 122 134 font ink)
  (draw-simple-text canvas "C" 94 (- point-c-y 5) font ink))
]

A note below the construction will explain why the three side lengths are
equal. The note uses @racket[layout-text] so it fits the available width:

@printable-racketblock+eval[
(define (draw-caption canvas)
  (define tag-font (make-print-font 3.7))
  (define body-font (make-print-font 4.4))
  (define shaper (make-shaper body-font))
  (define ink (make-paint #:color ink-color))
  (define accent (make-paint #:color accent-color))
  (define muted (make-paint #:color muted-color))
  (define rule (make-paint #:color rule-color
                           #:style 'stroke
                           #:stroke-width 0.45))
  (define explanation
    (layout-text
     shaper
     (string-append
      "Both circles have radius AB. Their upper intersection is C. "
      "Since C lies on both circles, AB, AC, and BC have the same length.")
     #:width content-width))
  (draw-line canvas 0 209 content-width 209 rule)
  (draw-simple-text canvas "WHY IT WORKS" 0 221 tag-font accent)
  (draw-text-layout canvas explanation 0 227 ink)
  (draw-simple-text canvas "COMPASS / STRAIGHTEDGE" 0 257 tag-font muted)
  (draw-simple-text canvas "SKIA / 09" 155 257 tag-font muted))

(define (draw-diagram canvas)
  (draw-heading canvas)
  (draw-construction canvas)
  (draw-point-labels canvas)
  (draw-caption canvas))
]

The @racket[draw-diagram] function draws the complete content, but it does not
create a raster surface or a file. It receives only a canvas, so the same
function can draw onto several kinds of output.

@printable-image[
(printable-page-pict
 (make-output-page content-width 265 draw-diagram
                   #:unit 'mm #:background 'white)
 #:dpi 84 #:scale 0.58)
]

This preview shows the complete drawing in its own coordinates, before A4
margins are applied. The opening figure shows how it will look on the page.

@section{Give the Drawing a Physical Page}

The @racket[make-output-page] function describes a page without allocating a
full-page pixel buffer. Its third argument is a drawing function that receives
a canvas whenever the page is rendered or exported.

@printable-racketblock+eval[
(define page
  (make-output-page page-width page-height draw-diagram
                    #:unit 'mm
                    #:margins page-margin
                    #:background 'white))
]

The page is 210 by 297 mm. The callback sees the drawing area's upper-left
corner as the point @tt{(0, 0)}, after the exporter applies the margins. The
positive y axis points down, just as it does on a raster surface. The callback
continues to draw at the same coordinates; we do not add the margins ourselves.

The @racket[output-page-content-size] function reports the dimensions after
subtracting the margins:

@printable-interaction[
(call-with-values (lambda () (output-page-content-size page)) list)
]

The result is 178 by 265 mm. Here is the A4 page with a red frame added only
to show the content area and a red dot marking its local origin:

@printable-racketblock+eval[
(define (draw-content-guide canvas)
  (define frame
    (make-paint #:color "#CC5544"
                #:style 'stroke
                #:stroke-width 0.55))
  (define origin
    (make-paint #:color "#CC5544"))
  (draw-diagram canvas)
  (draw-rect canvas 0 0 content-width
             (- page-height (* 2 page-margin)) frame)
  (draw-circle canvas 0 0 1.6 origin))

(define guided-page
  (make-output-page page-width page-height draw-content-guide
                    #:unit 'mm #:margins page-margin
                    #:background 'white))
]

@printable-image[
(printable-page-pict guided-page #:dpi 84 #:scale 0.54)
]

The red frame is a teaching guide. The real @racket[page] still uses
@racket[draw-diagram] and does not contain it. Margins describe where content
starts; they do not require adding 16 to all the coordinates in the drawing.

@section{Save the Page as PDF}

The @racket[save-output] function takes the page, a destination path, and an
explicit format:

@racketblock[
(save-output page "equilateral-triangle.pdf" 'pdf
             #:exists 'replace)
]

The page is converted to PDF points for the document. One inch contains
72 points. The @racket[unit->points] function reports the exact conversion
for a millimetre:

@printable-interaction[
(unit->points 1 'mm)
]

Skia applies the conversion to shapes, strokes, and text. The documentation
build can exercise the same PDF exporter without creating
a file:

@printable-interaction[
(define pdf-bytes (output->bytes page 'pdf))
(positive? (bytes-length pdf-bytes))
]

The PDF contains a physical page size, not just a bitmap enlarged to fit
paper. Supported geometry remains vector drawing. Native PDF text is the
default text policy, though font handling and extraction can depend on the
backend and the selected typeface.

@section{Save the Same Page as SVG}

We can export the very same page to SVG. There is no need for a second drawing
function or a new set of coordinates:

@racketblock[
(save-output page "equilateral-triangle.svg" 'svg
             #:exists 'replace)
]

The SVG exporter is also exercised during the documentation build:

@printable-interaction[
(define svg-bytes (output->bytes page 'svg))
(positive? (bytes-length svg-bytes))
]

The shared output API gives SVG a point-sized view box and physical dimensions
with @tt{pt} units, matching the PDF page's nominal size. A browser or printer
can still scale either document when displaying or printing it.

By default, the shared exporter outlines SVG text. Outlined letters preserve
their available glyph shapes without relying on the viewer having the same
font. They are no longer searchable or editable as ordinary text. The Guide
covers the choice between native and outlined text in more detail.

@section{Make a Raster Preview}

A PDF or SVG is not a surface whose pixels we can simply read. For an image
preview, the @racket[output-page->image] function renders the drawing callback
to a separate raster image:

@printable-racketblock+eval[
(define preview (output-page->image page #:dpi 96))
]

At 96 dots per inch, the preview has the following pixel dimensions:

@printable-interaction[
(list (image-width preview) (image-height preview))
]

The preview is a new raster rendering of @racket[draw-diagram]. It is not a
rasterization of the PDF file or SVG file. Its resolution affects the PNG
preview, not the vector resolution of either document. The first figure in
this tutorial is made in the same way.

The @racket[save-image] function can save the preview as a PNG:

@racketblock[
(save-image preview "equilateral-triangle.png" 'png
            #:exists 'replace)
]

@section{The Finished Printable Diagram}

The opening figure showed the finished A4 page. Here it is again, at a
slightly larger size so you can inspect the text and construction lines. Both
figures are generated by calling @racket[draw-diagram] from
@filepath{geometry-diagram.rkt}, not from a separately maintained image:

@(printable-finished-pict #:scale 0.59)

Run @filepath{geometry-diagram.rkt} to create
@filepath{equilateral-triangle.pdf}, @filepath{equilateral-triangle.svg}, and
@filepath{equilateral-triangle.png} in the current directory. The program
exports one page three times, creating a fresh rendering for each output.

@section{Try It}

Try increasing @racket[page-margin] from 16 to 20. The content area will
become 170 mm wide, while the right circle still reaches x = 176. Notice
how the exporter clips it instead of shrinking the drawing.

Try changing the diagram's line widths or its title. Compare the PDF and SVG
at different zoom levels, then compare them with the finite-resolution PNG
preview.

@section{Where to Go From Here}

This tutorial used one canvas drawing function for PDF and SVG, introduced
physical page units and margins, and distinguished vector output from a raster
preview.

It left multipage documents, detailed text extraction, document annotations,
output auditing, and raster fallbacks for the Guide and later tutorials. The
next tutorial will use effects and image filters to make a card with shadows.
