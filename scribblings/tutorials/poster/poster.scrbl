#lang scribble/manual

@title{Paints, Gradients, and Shaders — Make a Poster}

@(require "eval.rkt"
          (for-label racket
                     skia))

This tutorial builds a geometric poster. The shapes stay simple. Most of the
visual character comes from the paints and shaders used to draw them.

The tutorial assumes that you know the basics from
@italic{Quick: An Introduction to Skia with Pictures}. The clock, logo, and
images tutorials are useful background, but they are not required.

The main idea is:

@centered{@bold{Geometry says where to draw. A paint says how to draw it.
A shader can make the paint vary across coordinates.}}

@section{Start with a Paint}

The poster will be 720 by 900:

@poster-racketblock+eval[
(define width 720)
(define height 900)

(define background-top "#0B1026")
(define background-middle "#182950")
(define background-bottom "#304A73")
(define warm-color "#FFAE5D")
(define hot-color "#F35B74")
(define cool-color "#45C2C7")
(define light-color "#F8F1E5")
]

A paint can supply one solid color:

@poster-racketblock+eval[
(define (draw-solid-base canvas)
  (define background
    (make-paint #:color background-top))
  (define accent
    (make-paint #:color warm-color))
  (draw-rect canvas 0 0 width height background)
  (draw-circle canvas 520 190 145 accent)
  (draw-rounded-rect canvas 68 260 190 110 28 28 accent))
]

@poster-image[
(poster-render-pict draw-solid-base)
]

The circle and rounded rectangle use different geometry but the same accent
paint. The paint can be reused because the geometry and its appearance are
separate.

@section{Let a Shader Supply the Color}

A shader supplies colors across a coordinate system. A paint can use a shader
instead of one flat color.

The background uses a vertical linear gradient:

@poster-racketblock+eval[
(define (draw-background canvas)
  (define shader
    (make-linear-gradient-shader
     0 0 0 height
     (list background-top
           background-middle
           background-bottom)
     #:positions '(0 3/5 1)))
  (define paint (make-paint #:shader shader))
  (draw-rect canvas 0 0 width height paint))
]

The points @tt{(0, 0)} and @tt{(0, 900)} define the gradient line. The colors
are sampled along that line.

The @racket[#:positions] argument says where the color stops lie between the
two endpoints:

@poster-image[
(poster-gradient-domain-pict)
]

The three guide lines in the diagram mark positions 0, 3/5, and 1. The middle
color therefore appears three fifths of the way from the first endpoint to the
second endpoint.

The stop positions do not move the gradient endpoints. They only control where
the colors fall between those endpoints. Without @racket[#:positions], Skia
distributes the stops evenly.

@poster-image[
(poster-render-pict
 (lambda (canvas)
   (define accent
     (make-paint #:color warm-color))
   (draw-background canvas)
   (draw-circle canvas 520 190 145 accent)))
]

The circle geometry has not changed. Only the paint used for the background has
changed.

@section{Add a Radial Gradient}

A radial gradient measures distance from a center point. The poster uses one
for a glowing orb:

@poster-racketblock+eval[
(define (draw-orb canvas)
  (define shader
    (make-radial-gradient-shader
     520 190 165
     (list "#FFF1B8"
           warm-color
           (rgba 243 91 116 0))
     #:positions '(0 3/5 1)))
  (define paint (make-paint #:shader shader))
  (draw-circle canvas 520 190 165 paint))
]

The first two numbers give the center. The third gives the radius. The final
color has alpha zero, so the gradient fades into the background near its outer
edge.

@poster-image[
(poster-render-pict
 (lambda (canvas)
   (draw-background canvas)
   (draw-orb canvas)))
]

@section{Add Transparency}

Transparency does not require a shader. An ordinary paint color can include an
alpha value.

The @racket[rgba] function accepts red, green, blue, and alpha values from 0
through 255:

@poster-racketblock+eval[
(define (draw-transparent-shapes canvas)
  (define cool-paint
    (make-paint #:color (rgba 69 194 199 62)))
  (define hot-paint
    (make-paint #:color (rgba 243 91 116 52)))
  (draw-circle canvas 120 255 92 cool-paint)
  (draw-circle canvas 195 330 72 hot-paint)
  (draw-rounded-rect canvas 68 220 220 180 32 32 cool-paint))
]

@poster-image[
(poster-render-pict
 (lambda (canvas)
   (draw-background canvas)
   (draw-transparent-shapes canvas)
   (draw-orb canvas)))
]

Later translucent drawing blends with the colors already on the surface.

@section{Tile a Shader}

A gradient has a finite domain between its endpoints. A tile mode decides what
happens when Skia samples outside that domain.

The gradient tile modes are @racket['clamp], @racket['repeat],
@racket['mirror], and @racket['decal]:

@poster-image[
(poster-tile-modes-pict)
]

The two gray guide lines in each panel mark the original gradient domain.
The @racket['clamp] mode extends the edge colors. The @racket['repeat] mode
starts the gradient again. The @racket['mirror] mode alternates normal and
reflected copies. The @racket['decal] mode is transparent outside the domain.

The poster uses a short repeated gradient to create a band:

@poster-racketblock+eval[
(define (draw-repeat-band canvas)
  (define shader
    (make-linear-gradient-shader
     60 0 156 0
     (list (rgba 69 194 199 0)
           (rgba 69 194 199 200)
           (rgba 243 91 116 170)
           (rgba 69 194 199 0))
     #:positions '(0 7/20 13/20 1)
     #:tile-mode 'repeat))
  (define paint (make-paint #:shader shader))
  (draw-rounded-rect canvas 60 418 600 96 20 20 paint))
]

@poster-image[
(poster-render-pict
 (lambda (canvas)
   (draw-background canvas)
   (draw-transparent-shapes canvas)
   (draw-orb canvas)
   (draw-repeat-band canvas)))
]

The gradient itself spans only 96 units horizontally. The rounded rectangle is
600 units wide, so the repeated shader becomes visible several times.

@section{Use an Image as a Shader}

A shader does not have to be a gradient. An image can also supply colors across
a shape.

The following helper makes a tiny checker image in memory. It first draws on
a temporary surface. Then @racket[surface-snapshot] captures the current pixels
of that surface and returns them as an image value:

@poster-racketblock+eval[
(define (make-checker-image)
  (define surface
    (make-surface 32 32 #:background 'transparent))
  (define canvas (surface-canvas surface))
  (define light
    (make-paint #:color (rgba 248 241 229 55)))
  (define cool
    (make-paint #:color (rgba 69 194 199 26)))
  (draw-rect canvas 0 0 16 16 light)
  (draw-rect canvas 16 16 16 16 light)
  (draw-rect canvas 16 0 16 16 cool)
  (draw-rect canvas 0 16 16 16 cool)
  (surface-snapshot surface))
]

The checker is a 32 by 32 image. It is shown at four times its natural size
below. The enlargement uses nearest-neighbor sampling so the original pixel
boundaries stay sharp.

@poster-image[
(poster-checker-pict (make-checker-image))
]

The figure above displays the actual image returned by
@racket[make-checker-image]. The @racket[surface-snapshot] call captures the
surface contents at that moment and creates a new immutable image. Later
drawing on the surface would not change that snapshot.

The image can therefore be used independently of the temporary surface. In
this tutorial, it becomes the source image for an image shader.

An image shader can repeat that image independently in the x and y directions:

@poster-racketblock+eval[
(define (draw-pattern-strip canvas)
  (define image (make-checker-image))
  (define shader
    (make-image-shader image
                       #:tile-x 'repeat
                       #:tile-y 'repeat
                       #:sampling 'nearest))
  (define paint (make-paint #:shader shader))
  (draw-rounded-rect canvas 82 696 556 56 12 12 paint))
]

The @racket[#:sampling 'nearest] setting preserves the hard boundaries in the
small checker image. The image shader supplies the color; the rounded rectangle
still supplies the geometry.

@poster-image[
(poster-render-pict
 (lambda (canvas)
   (draw-background canvas)
   (draw-transparent-shapes canvas)
   (draw-orb canvas)
   (draw-repeat-band canvas)
   (draw-pattern-strip canvas)))
]

@section{Blend Two Shaders}

Shaders can be combined before they are used by a paint. The poster blends a
linear gradient with a radial glow:

@poster-racketblock+eval[
(define (draw-blended-panel canvas)
  (define base
    (make-linear-gradient-shader
     60 548 660 786
     (list (rgba 55 80 170 230)
           (rgba 126 78 198 205))))
  (define glow
    (make-radial-gradient-shader
     545 660 250
     (list (rgba 255 174 93 230)
           (rgba 243 91 116 0))))
  (define shader
    (make-blend-shader 'screen base glow))
  (define paint (make-paint #:shader shader))
  (define border
    (make-paint #:color (rgba 248 241 229 50)
                #:style 'stroke
                #:stroke-width 2))
  (draw-rounded-rect canvas 60 548 600 238 30 30 paint)
  (draw-rounded-rect canvas 60 548 600 238 30 30 border))
]

The @racket[make-blend-shader] function combines two shader results with a
blend mode. Its first shader is the destination and its second shader is the
source. The @racket['screen] mode produces a lightening combination that works
well for this panel.

The Guide will cover the complete set of blend modes in more detail.

@poster-image[
(poster-render-pict
 (lambda (canvas)
   (draw-background canvas)
   (draw-transparent-shapes canvas)
   (draw-orb canvas)
   (draw-repeat-band canvas)
   (draw-blended-panel canvas)))
]

@section{Add the Text}

The poster uses the simple text API from the Quick tutorial:

@poster-racketblock+eval[
(define (draw-copy canvas)
  (define kicker-font (make-font #:size 14))
  (define title-font (make-font #:size 58))
  (define subtitle-font (make-font #:size 18))
  (define title-paint
    (make-paint #:color light-color))
  (define quiet-paint
    (make-paint #:color (rgba 248 241 229 185)))
  (draw-simple-text canvas
                    "SKIA / STUDY 05"
                    58 76
                    kicker-font quiet-paint)
  (draw-simple-text canvas
                    "NIGHT / SIGNAL"
                    58 842
                    title-font title-paint)
  (draw-simple-text canvas
                    "PAINTS  /  GRADIENTS  /  SHADERS"
                    62 876
                    subtitle-font quiet-paint))
]

Text is not the subject of this tutorial. A later tutorial will cover
measurement, typefaces, shaping, and paragraph layout.

@poster-image[
(poster-render-pict
 (lambda (canvas)
   (draw-background canvas)
   (draw-transparent-shapes canvas)
   (draw-orb canvas)
   (draw-repeat-band canvas)
   (draw-blended-panel canvas)
   (draw-pattern-strip canvas)
   (draw-copy canvas)))
]

@section{Assemble the Poster}

The complete drawing function is now short:

@poster-racketblock+eval[
(define (draw-poster canvas)
  (draw-background canvas)
  (draw-transparent-shapes canvas)
  (draw-orb canvas)
  (draw-repeat-band canvas)
  (draw-blended-panel canvas)
  (draw-pattern-strip canvas)
  (draw-copy canvas))
]

@poster-image[
(poster-render-pict draw-poster)
]

The poster uses the same simple geometry throughout. Most of the visual changes
come from changing the paint or the shader rather than changing the shapes.

@section{Save the Result}

A raster surface can save the poster as a PNG file:

@racketblock[
(define surface
  (make-surface width height))

(draw-poster (surface-canvas surface))

(save-png surface "poster.png"
          #:exists 'replace)
]

Ordinary CPU resources use the normal Racket lifetime style shown in the
earlier tutorials. Use @racket[with-skia] when prompt deterministic release is
important.

@section{Try It}

Try moving the middle background stop from @racket[3/5] to @racket[1/3].
Predict how the background will change before you run the program.

Try changing the repeated band from @racket['repeat] to @racket['mirror].
Use the tile-mode diagram to predict the result.

Try changing the image shader sampling from @racket['nearest] to
@racket['linear]. Look closely at the checker edges.

Try changing the panel blend mode from @racket['screen] to @racket['multiply].
Compare the result with the original.

Try changing the final radial-gradient color from transparent hot pink to an
opaque color. Notice what happens at the edge of the orb.

@section{Where to Go From Here}

This tutorial used solid paints, alpha, linear gradients, radial gradients,
explicit stop positions, tile modes, image shaders, and shader composition.

The Guide will cover sweep and conical gradients, shader-local transforms,
blend modes, color spaces, and more advanced shader composition.

The next tutorial will focus on text and typography.

The complete @filepath{poster.rkt} example contains the finished program from
this tutorial.
