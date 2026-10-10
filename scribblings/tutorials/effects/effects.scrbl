#lang scribble/manual

@title{Effects and Filters — Make a Card with Shadows}

@(require "eval.rkt"
          (for-label racket
                     skia))

@section{The Finished Card}

@(effects-finished-pict #:scale 0.65)

This tutorial builds the card shown above. Its shapes are familiar: rounded
rectangles, circles, lines, and text. The new part is how filters change those
shapes after they are drawn.

The figure is rendered with Skia from @filepath{card-with-shadows.rkt} during
the documentation build. It is not a separately designed illustration.

The main idea is:

@centered{@bold{A filter changes how a painted shape looks without changing
its geometry. Different filters change different parts of the result.}}

The complete program will save @filepath{card-with-shadows.png}.

@section{Begin with a Flat Card}

Start with a 960 by 640 raster surface. The card has a white face and sits on
an almost-white blue background.

@effects-racketblock+eval[
(define card-image-width 960)
(define card-image-height 640)
(define background-color "#EEF3F8")
(define ink-color "#243850")
(define muted-color "#64778B")
(define blue-color "#326DE6")
(define teal-color "#1AA6AD")

(define card-x 80)
(define card-y 74)
(define card-width 800)
(define card-height 478)

(define (draw-flat-card canvas)
  (define white (make-paint #:color 'white))
  (draw-rounded-rect canvas
                     card-x card-y card-width card-height
                     28 28 white))
]

The @racket[draw-flat-card] function draws an ordinary rounded rectangle.
The flat shape is the starting point: its geometry will stay exactly the same
when we add the shadow.

@effects-image[
(effects-render-pict card-image-width card-image-height draw-flat-card
                     #:scale 0.64)
]

@section{Give the Card a Shadow}

A shadow makes the card appear to float above its background. A drop-shadow
image filter works on the drawing attached to a paint.

@effects-racketblock+eval[
(define (draw-shadowed-card canvas)
  (define shadow
    (make-drop-shadow-image-filter
     0 14 14 14 (rgba 27 47 70 90)))
  (define white
    (make-paint #:color 'white
                #:image-filter shadow))
  (draw-rounded-rect canvas
                     card-x card-y card-width card-height
                     28 28 white))
]

The @racket[make-drop-shadow-image-filter] function takes horizontal and
vertical offsets, two blur standard deviations (sigma x and sigma y), and a
color. Here, the shadow is shifted 14 drawing units downward, with no
horizontal offset. The alpha value 90 in @racket[(rgba 27 47 70 90)] is out
of 255, so the dark blue shadow is translucent.

The @racket[#:image-filter] argument attaches the filter to the paint. The
@racket[draw-rounded-rect] call still uses the same dimensions and radii;
the filtered drawing now includes a shadow beyond the original rectangle.

@effects-image[
(effects-render-pict card-image-width card-image-height draw-shadowed-card
                     #:scale 0.64)
]

The drop-shadow image filter draws both the original white card and its
shadow. The filter does not become part of the canvas state and does not
change later drawing operations. A shadow also needs room outside its source
shape: anything extending beyond the surface boundary will be clipped.

@section{Change One Shadow Setting at a Time}

A shadow has both a displacement and a softness. The offset moves the shadow
relative to its source shape. The sigma controls the spread of its blur; it is
a standard deviation, not a corner radius or a hard-edged blur distance.

To see the difference, draw four copies of the same rectangle. The top row
changes only the vertical offset. The bottom row changes only the sigma.
The values appear in the figure so you can compare them directly.

@effects-racketblock+eval[
(define (draw-shadow-variants canvas)
  (define font (make-font #:size 18))
  (define label-paint (make-paint #:color ink-color))
  (for ([x '(55 397 55 397)]
        [y '(88 88 317 317)]
        [offset '(4 22 14 14)]
        [sigma '(10 10 4 18)]
        [caption '("offset 4 / sigma 10" "offset 22 / sigma 10"
                   "offset 14 / sigma 4" "offset 14 / sigma 18")])
    (define shadow
      (make-drop-shadow-image-filter
       0 offset sigma sigma (rgba 27 47 70 110)))
    (define white
      (make-paint #:color 'white #:image-filter shadow))
    (draw-simple-text canvas caption x (- y 35) font label-paint)
    (draw-rounded-rect canvas x y 230 118 18 18 white)))
]

@effects-image[
(effects-render-pict 730 535 draw-shadow-variants #:scale 0.84)
]

The first two shadows are equally soft but land at different distances below
the card. The last two have the same displacement, but the larger sigma makes
the shadow broader and less defined. The white rectangles themselves have
not changed.

@section{Blur the Decorative Colors}

Next, add two soft circles inside the card. The @racket[make-blur-image-filter]
function softens the rendered content of each circle, including its edge.

@effects-racketblock+eval[
(define (draw-soft-accents canvas)
  (define blur (make-blur-image-filter 22 22))
  (define teal
    (make-paint #:color (rgba 46 184 192 150)
                #:image-filter blur))
  (define apricot
    (make-paint #:color (rgba 245 154 108 165)
                #:image-filter blur))
  (draw-circle canvas 665 288 78 teal)
  (draw-circle canvas 744 373 58 apricot))
]

The circles use translucent colors. Both paints use the same blur filter,
which spreads their colors gently into the white card.

@effects-racketblock+eval[
(define (draw-card-with-accents canvas)
  (draw-shadowed-card canvas)
  (draw-soft-accents canvas))
]

@effects-image[
(effects-render-pict card-image-width card-image-height draw-card-with-accents
                     #:scale 0.64)
]

The colors now fade gradually rather than ending at a sharp circular edge.
The shadow remains attached only to the card rectangle. Because the two
accent circles are drawn afterward with different paints, their blur does
not blur the card's outline. The blur is also not automatically clipped to
the rounded card; we placed the circles far enough inside it for their colors
to fade out.

@section{Blur Coverage or Blur Content?}

A mask filter changes the coverage of a shape: a mask blur makes its outer
edge soft. An image filter processes the rendered source image, so an image
blur softens internal color changes as well as the outer edge. A gradient
with a sharp color boundary makes the difference easier to see.

The following comparison uses a gradient with two stops at the midpoint, so
its teal and orange halves meet at a hard edge.

@effects-racketblock+eval[
(define (draw-blur-comparison canvas)
  (define stripe
    (make-linear-gradient-shader
     48 0 288 0
     '("#159BA6" "#159BA6" "#EEA16A" "#EEA16A")
     #:positions '(0 1/2 1/2 1)))
  (define mask-blur (make-blur-mask-filter 9))
  (define image-blur (make-blur-image-filter 9 9))
  (define mask-paint
    (make-paint #:shader stripe #:mask-filter mask-blur))
  (define image-paint
    (make-paint #:shader stripe #:image-filter image-blur))
  (define font (make-font #:size 18))
  (define label-paint (make-paint #:color ink-color))
  (draw-simple-text canvas "Mask blur" 48 33 font label-paint)
  (draw-rounded-rect canvas 48 95 240 110 16 16 mask-paint)
  (with-canvas-state canvas
    (canvas-translate! canvas 324 0)
    (draw-simple-text canvas "Image blur" 48 33 font label-paint)
    (draw-rounded-rect canvas 48 95 240 110 16 16 image-paint)))
]

@effects-image[
(effects-render-pict 700 260 draw-blur-comparison #:scale 0.86)
]

On the left, the mask filter blurs the coverage at the outer edge, but the
teal-to-orange boundary stays sharp. On the right, the image filter also blurs
that internal boundary. This distinction matters when the paint contains a
shader or another source with details inside its outline.

@section{Draw Sharp Geometry over the Blur}

The decorative color is soft, but the ring motif should stay sharp. We can
now add ordinary strokes and filled dots. These paints do not have filters.

@effects-racketblock+eval[
(define (draw-ring-motif canvas)
  (define ring
    (make-paint #:color ink-color
                #:style 'stroke
                #:stroke-width 2.4))
  (define light-ring
    (make-paint #:color "#7A97B0"
                #:style 'stroke
                #:stroke-width 1.2))
  (define blue (make-paint #:color blue-color))
  (define teal (make-paint #:color teal-color))
  (draw-circle canvas 703 319 101 ring)
  (draw-circle canvas 703 319 72 light-ring)
  (draw-line canvas 595 319 811 319 light-ring)
  (draw-line canvas 703 210 703 428 light-ring)
  (draw-circle canvas 703 319 9 blue)
  (draw-circle canvas 703 218 5 teal)
  (draw-circle canvas 804 319 5 teal))

(define (draw-card-with-rings canvas)
  (draw-shadowed-card canvas)
  (draw-soft-accents canvas)
  (draw-ring-motif canvas))
]

@effects-image[
(effects-render-pict card-image-width card-image-height draw-card-with-rings
                     #:scale 0.64)
]

The geometry is drawn after the filtered accents, so its edges remain crisp.
The image filter from a previous paint does not carry over to these new
paints, and the rings do not inherit the card's drop shadow.

@section{Add the Labels}

Now add the heading, subtitle, and supporting labels. The text uses ordinary
paints and sits above the colored decorations, just like the ring motif.

@effects-racketblock+eval[
(define (draw-card-labels canvas)
  (define face (make-typeface))
  (define kicker-font (make-font face #:size 17))
  (define title-font (make-font face #:size 53))
  (define subtitle-font (make-font face #:size 22))
  (define caption-font (make-font face #:size 15))
  (define ink (make-paint #:color ink-color))
  (define muted (make-paint #:color muted-color))
  (define blue (make-paint #:color blue-color))
  (define rule
    (make-paint #:color "#D5DFE9"
                #:style 'stroke
                #:stroke-width 2))
  (draw-simple-text canvas "SKIA / LIGHT STUDY" 132 137 kicker-font blue)
  (draw-simple-text canvas "Light and depth" 129 225 title-font ink)
  (draw-simple-text canvas "A few filters change the mood." 132 270
                    subtitle-font muted)
  (draw-line canvas 132 318 516 318 rule)
  (draw-simple-text canvas "SOFT SHADOW" 132 367 caption-font blue)
  (draw-simple-text canvas "BLURRED COLOR" 132 405 caption-font blue)
  (draw-simple-text canvas "SHARP DETAILS" 132 443 caption-font blue)
  (draw-simple-text canvas "GEOMETRY  /  COLOR  /  LIGHT" 132 514 caption-font muted)
  (draw-simple-text canvas "10" 829 514 caption-font muted))

(define (draw-card canvas)
  (draw-card-with-rings canvas)
  (draw-card-labels canvas))
]

The @racket[draw-card] function now assembles four layers: the shadowed
rectangle, the blurred accents, sharp geometry, and labels. Later drawing
appears over earlier drawing. The selected default typeface may differ across
platforms, but the drawing order and filter behavior are the same.

@(effects-finished-pict #:scale 0.65)

This final figure calls the actual @racket[draw-card] function from the
standalone example, just like the figure at the beginning.

@section{Save the Card}

The complete @filepath{card-with-shadows.rkt} file saves the image as PNG:

@racketblock[
(define surface
  (make-surface card-image-width card-image-height
                #:background background-color))
(draw-card (surface-canvas surface))
(save-png surface "card-with-shadows.png" #:exists 'replace)
]

The surface and filters are ordinary owned CPU resources. Racket can reclaim
their native storage when they are no longer reachable. The
@racket[with-skia] form is useful when prompt deterministic cleanup matters,
but it is not required around every paint and filter.

@section{Try It}

Try changing only the vertical shadow offset in @racket[draw-shadowed-card]
from 14 to 24. The source rectangle will stay put. Which part of the result
moves? Then restore the offset and reduce both shadow sigmas from 14 to 5.
Notice which edges change instead.

Try changing the two decorative blur sigmas from 22 to 5. Keep the alpha
values unchanged for the first comparison, then make the colors opaque.
These are two separate adjustments: one changes softness, and the other
changes how much of the underlying white shows through.

@section{Where to Go From Here}

This tutorial used one unchanged source shape to study drop shadows and their
parameters, compared two kinds of blur, and built a card from separately
filtered and unfiltered drawing operations.

Effects do not necessarily remain vector graphics in PDF or SVG. Some effects
need rasterization, depending on the exporter and the drawing operation.
The later tutorial on vector output and raster fallbacks will examine that
boundary in detail. More complex filter graphs, color matrices, and custom
effects belong in the Guide.

The complete @filepath{card-with-shadows.rkt} file contains the finished
program. The next tutorial will record and replay drawings as pictures.
