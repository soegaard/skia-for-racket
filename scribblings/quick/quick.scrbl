#lang scribble/manual

@title{Quick: An Introduction to Skia with Pictures}

@(require "eval.rkt"
          (for-label racket
                     skia))

Skia is a graphics library for Racket. This short tutorial builds one picture
from simple shapes. The finished picture shows a moonlit lake.

The tutorial assumes that you already know the basics of Racket. You should
know how to call a function, define a value, define a function, and use
@racket[require].

The definitions build on one another. The complete program appears in
@filepath{moonlight.rkt}.

@section{Ready...}

After installing Skia, start a new Racket program:

@racketmod[
racket

(require skia)
]

This tutorial uses only the public @racketmodname[skia] module.

@section{Set...}

The picture will be 800 pixels wide and 500 pixels high:

@skia-racketblock+eval[
(define width 800)
(define height 500)
]

The first drawing target will be a raster surface. A raster surface stores
pixels. A canvas represents the drawing state used with a surface or document.
The drawing state includes the current transform and clip.

The @racket[make-surface] function creates a raster surface. The
@racket[surface-canvas] function returns its canvas.

@section{Go!}

First, fill the picture with a dark blue rectangle:

@skia-racketblock+eval[
(define flat-sky-color "#101936")

(define (draw-flat-sky canvas)
  (with-skia ([paint (make-paint #:color flat-sky-color)])
    (draw-rect canvas 0 0 width height paint)))
]

The @racket[make-paint] function creates a paint. A paint describes how Skia
fills or strokes geometry.

The @racket[draw-rect] function draws a rectangle. The first two numbers give
the position of its upper-left corner. The next two numbers give its width and
height.

A complete raster program can create a surface, draw through its canvas, and
save the surface as a PNG file:

@racketblock[
(with-skia ([surface (make-surface width height)])
  (define canvas (surface-canvas surface))

  (draw-flat-sky canvas)

  (save-png surface "moonlight.png"
            #:exists 'replace))
]

The @racket[with-skia] form manages the resources listed in its bindings. The
form closes those resources when the body finishes, including when an exception
is raised. The canvas borrows the lifetime of the surface.

@skia-image[
(quick-render-pict width height draw-flat-sky)
]

@section{Add the Moon}

The point @tt{(0, 0)} is the origin of the canvas. With the default transform,
the x coordinate grows toward the right, and the y coordinate grows toward the
bottom.

The grid below shows the coordinate system for the 800 by 500 surface. Each
grid line is 100 units from the next one. The point @tt{(650, 90)} will be the
center of the moon.

@skia-image[
(quick-coordinate-grid-pict width height)
]

The moon is a filled circle:

@skia-racketblock+eval[
(define moon-color "#F6E7B0")

(define (draw-moon canvas)
  (with-skia ([paint (make-paint #:color moon-color)])
    (draw-circle canvas 650 90 42 paint)))
]

The numbers @racket[650] and @racket[90] give the center of the circle. The
number @racket[42] gives its radius.

Small circles can also serve as stars:

@skia-racketblock+eval[
(define star-color "#E8ECF5")

(define stars
  '((100 75 2)
    (170 135 2)
    (255 65 3)
    (330 120 2)
    (420 55 2)
    (510 145 2)
    (730 55 2)
    (760 150 3)
    (85 205 2)
    (375 185 2)))

(define (draw-stars canvas)
  (with-skia ([paint (make-paint #:color star-color)])
    (for ([star (in-list stars)])
      (draw-circle canvas
                   (first star)
                   (second star)
                   (third star)
                   paint))))
]

The list fixes the star positions. The picture therefore looks the same each
time the program runs.

@skia-image[
(quick-render-pict
 width height
 (lambda (canvas)
   (draw-flat-sky canvas)
   (draw-stars canvas)
   (draw-moon canvas)))
]

@section{Draw the Mountains}

Rectangles and circles are useful, but many shapes need more general geometry.
A path is a sequence of drawing commands.

The back mountain range uses only straight lines:

@skia-racketblock+eval[
(define back-mountain-color "#596480")

(define back-mountains
  '((move 0 330)
    (line 0 285)
    (line 95 210)
    (line 160 275)
    (line 265 170)
    (line 365 280)
    (line 475 205)
    (line 585 285)
    (line 690 215)
    (line 800 290)
    (line 800 330)
    (close)))
]

The @racket[make-path] function reads each list as a path command. A command
that starts with @racket['move] begins a contour at a point. A command that
starts with @racket['line] adds a straight segment. A command that starts with
@racket['close] connects the last point back to the first point.

A second, darker range sits in front of the first one:

@skia-racketblock+eval[
(define front-mountain-color "#29334D")

(define front-mountains
  '((move 0 330)
    (line 0 305)
    (line 120 235)
    (line 205 305)
    (line 325 220)
    (line 445 320)
    (line 565 255)
    (line 705 325)
    (line 800 280)
    (line 800 330)
    (close)))

(define (draw-mountains canvas)
  (with-skia ([back-path (make-path back-mountains)]
              [back-paint (make-paint #:color back-mountain-color)]
              [front-path (make-path front-mountains)]
              [front-paint (make-paint #:color front-mountain-color)])
    (draw-path canvas back-path back-paint)
    (draw-path canvas front-path front-paint)))
]

Later drawing normally appears on top of earlier drawing. The darker range is
therefore visible in front of the lighter range.

@skia-image[
(quick-render-pict
 width height
 (lambda (canvas)
   (draw-flat-sky canvas)
   (draw-stars canvas)
   (draw-moon canvas)
   (draw-mountains canvas)))
]

@section{Add the Lake}

The first sky used one color. A vertical gradient can use one color at the top
and another color near the horizon.

@skia-racketblock+eval[
(define lake-top 330)
(define sky-top "#0B1026")
(define sky-bottom "#344A78")

(define (draw-sky canvas)
  (with-skia ([shader
               (make-linear-gradient-shader
                0 0 0 lake-top
                (list sky-top sky-bottom))]
              [paint (make-paint #:shader shader)])
    (draw-rect canvas 0 0 width height paint)))
]

The rectangle has not changed. The paint now uses a shader instead of one
color.

The lake is another rectangle with another gradient:

@skia-racketblock+eval[
(define lake-top-color "#263F63")
(define lake-bottom-color "#0D192B")

(define (draw-lake canvas)
  (with-skia ([shader
               (make-linear-gradient-shader
                0 lake-top 0 height
                (list lake-top-color lake-bottom-color))]
              [paint (make-paint #:shader shader)])
    (draw-rect canvas
               0 lake-top
               width (- height lake-top)
               paint)))
]

The value @racket[lake-top] marks the shoreline. The same value will also help
place the cabin and trees.

@skia-image[
(quick-render-pict
 width height
 (lambda (canvas)
   (draw-sky canvas)
   (draw-stars canvas)
   (draw-moon canvas)
   (draw-mountains canvas)
   (draw-lake canvas)))
]

@section{Build a Cabin}

The cabin is made from rectangles and one triangle. The cabin needs several
drawing operations, so it is useful to put them in one function.

@skia-racketblock+eval[
(define cabin-color "#49352F")
(define roof-color "#182238")
(define door-color "#291F1D")
(define window-color "#FFD47A")

(define (draw-cabin canvas x y)
  (with-skia ([body-paint (make-paint #:color cabin-color)]
              [roof-paint (make-paint #:color roof-color)]
              [window-paint (make-paint #:color window-color)]
              [door-paint (make-paint #:color door-color)])
    (draw-rect canvas x y 95 60 body-paint)
    (draw-polygon canvas
                  (list (list (- x 13) (+ y 4))
                        (list (+ x 47) (- y 38))
                        (list (+ x 107) (+ y 4)))
                  roof-paint)
    (draw-rect canvas (+ x 20) (+ y 17) 25 20 window-paint)
    (draw-rect canvas (+ x 63) (+ y 32) 20 28 door-paint)))
]

The @racket[draw-polygon] function joins the given points and closes the shape.
The @racket[x] and @racket[y] arguments choose the cabin position.

@skia-image[
(quick-render-pict
 width height
 (lambda (canvas)
   (draw-sky canvas)
   (draw-stars canvas)
   (draw-moon canvas)
   (draw-mountains canvas)
   (draw-lake canvas)
   (draw-cabin canvas 545 270)))
]

@section{Plant Some Trees}

The tree is easier to define around its own origin:

@skia-racketblock+eval[
(define tree-color "#182A31")

(define (draw-tree canvas)
  (with-skia ([paint (make-paint #:color tree-color)])
    (draw-rect canvas -3 -18 6 18 paint)
    (draw-polygon canvas '((-18 -12) (0 -50) (18 -12)) paint)
    (draw-polygon canvas '((-15 -32) (0 -65) (15 -32)) paint)
    (draw-polygon canvas '((-12 -50) (0 -80) (12 -50)) paint)))
]

The @racket[canvas-translate!] function changes the current coordinate system.
For this drawing, the translation places the local point @tt{(0, 0)} at the
chosen tree position.

The @racket[canvas-scale!] function changes the scale of later drawing
operations. The @racket[with-canvas-state] form restores the previous drawing
state when its body finishes.

@skia-racketblock+eval[
(define (draw-tree-at canvas x y scale)
  (with-canvas-state canvas
    (canvas-translate! canvas x y)
    (canvas-scale! canvas scale)
    (draw-tree canvas)))

(define (draw-trees canvas)
  (draw-tree-at canvas 85 lake-top 1.15)
  (draw-tree-at canvas 150 lake-top 0.80)
  (draw-tree-at canvas 495 lake-top 0.75)
  (draw-tree-at canvas 680 lake-top 1.15)
  (draw-tree-at canvas 735 lake-top 0.85)
  (draw-tree-at canvas 775 lake-top 0.65))
]

Each tree uses the same geometry. Translation changes its position, and scaling
changes its size.

@skia-image[
(quick-render-pict
 width height
 (lambda (canvas)
   (draw-sky canvas)
   (draw-stars canvas)
   (draw-moon canvas)
   (draw-mountains canvas)
   (draw-lake canvas)
   (draw-cabin canvas 545 270)
   (draw-trees canvas)))
]

@section{Add the Reflection}

The moon reflection should appear only in the lake. A clip limits where later
drawing can affect the canvas.

@skia-racketblock+eval[
(define reflection-streaks
  '((355 26)
    (372 42)
    (392 62)
    (414 88)
    (438 112)
    (466 140)))

(define (draw-reflection canvas)
  (with-canvas-state canvas
    (canvas-clip-rect! canvas
                       0 lake-top
                       width (- height lake-top))
    (with-skia ([paint
                 (make-paint #:color (rgba 246 231 176 55))])
      (for ([streak (in-list reflection-streaks)])
        (define y (first streak))
        (define w (second streak))
        (draw-rounded-rect canvas
                           (- 650 (/ w 2)) y
                           w 4
                           2 2
                           paint)))))
]

The alpha value @racket[55] makes each reflection streak partly transparent.
The @racket[with-canvas-state] form restores the previous clip when the body
finishes.

@skia-image[
(quick-render-pict
 width height
 (lambda (canvas)
   (draw-sky canvas)
   (draw-stars canvas)
   (draw-moon canvas)
   (draw-mountains canvas)
   (draw-lake canvas)
   (draw-reflection canvas)
   (draw-cabin canvas 545 270)
   (draw-trees canvas)))
]

@section{Add a Title}

The simplest text API needs a font, a paint, and a baseline position.

@skia-racketblock+eval[
(define text-color "#E8ECF5")

(define (draw-title canvas)
  (with-skia ([title-font (make-font #:size 36)]
              [small-font (make-font #:size 15)]
              [paint (make-paint #:color text-color)])
    (draw-simple-text canvas
                      "MOONLIGHT"
                      45 445
                      title-font paint)
    (draw-simple-text canvas
                      "A quiet night by the lake"
                      47 474
                      small-font paint)))
]

The y coordinate in @racket[draw-simple-text] gives the text baseline. Skia also
supports shaping, positioned glyphs, text blobs, and paragraph layout. The Guide
will cover those subjects later.

@skia-image[
(quick-render-pict
 width height
 (lambda (canvas)
   (draw-sky canvas)
   (draw-stars canvas)
   (draw-moon canvas)
   (draw-mountains canvas)
   (draw-lake canvas)
   (draw-reflection canvas)
   (draw-cabin canvas 545 270)
   (draw-trees canvas)
   (draw-title canvas)))
]

@section{Use the Drawing Again}

The picture now has several parts. Each part has its own drawing function, so
the complete scene is short:

@skia-racketblock+eval[
(define (draw-moonlight canvas)
  (draw-sky canvas)
  (draw-stars canvas)
  (draw-moon canvas)
  (draw-mountains canvas)
  (draw-lake canvas)
  (draw-reflection canvas)
  (draw-cabin canvas 545 270)
  (draw-trees canvas)
  (draw-title canvas))
]

The @racket[draw-moonlight] function receives a canvas. The function does not
know what kind of output lies behind that canvas.

Raster output can use the function directly:

@racketblock[
(with-skia ([surface (make-surface width height)])
  (draw-moonlight (surface-canvas surface))
  (save-png surface "moonlight.png"
            #:exists 'replace))
]

@section{Save PDF and SVG}

An output page can use the same drawing function:

@racketblock[
(define page
  (make-output-page width height draw-moonlight
                    #:unit 'px))

(save-output page
             "moonlight.pdf"
             'pdf
             #:exists 'replace)

(save-output page
             "moonlight.svg"
             'svg
             #:exists 'replace)
]

The @racket[#:unit 'px] option keeps the page coordinates on the same 800 by
500 scale as the raster drawing. The drawing function itself is unchanged.

The PNG file contains raster pixels. The PDF and SVG files can keep supported
drawing operations as vector content.

The Guide will discuss document output, text policies, raster fallbacks, and
output auditing in more detail.

@section{Try It}

The finished picture is a good place to experiment. Try moving the moon by
changing its center from @tt{(650, 90)} to another point. Use the coordinate
grid to predict where the moon will appear before you run the program.

Try changing the moon radius, changing one of the colors, or adding another
call to @racket[draw-tree-at]. These changes use only the ideas from this
tutorial.

@section{Where to Go From Here}

This tutorial used only a small part of Skia.

The Guide will cover resource management, paths, transforms, text, images,
color, document output, and GPU rendering in more detail. The Reference will
give exact contracts for the public functions and forms.

The complete @filepath{moonlight.rkt} example contains the finished program
from this tutorial.
