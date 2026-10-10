#lang scribble/manual

@title{Paths and Geometry — Draw a Logo}

@(require "eval.rkt"
          (for-label racket
                     skia))

This tutorial builds a small geometric logo. The logo starts as a polygon and
gradually becomes a smooth leaf with a curved cut-out.

The tutorial assumes that you know the basics from
@italic{Quick: An Introduction to Skia with Pictures}. The clock tutorial is
not required.

The main idea is simple:

@centered{@bold{A path describes geometry. A paint describes how Skia draws that geometry.}}

@section{One Closed Shape}

The drawing will use a 500 by 500 surface:

@logo-racketblock+eval[
(define size 500)

(define background-color "#F4F0E7")
(define fill-color "#246B5A")
(define outline-color "#173B35")
]

We will start with a rough polygon:

@logo-racketblock+eval[
(define polygon-commands
  '((move 250 50)
    (line 390 170)
    (line 370 320)
    (line 250 440)
    (line 130 320)
    (line 110 170)
    (close)))
]

Each item in the list is a path command. The @racket['move] command chooses
the first point. Each @racket['line] command adds a straight segment. The
@racket['close] command connects the last point back to the first point.

The @racket[make-path] function turns the command list into a path:

@logo-racketblock+eval[
(define (draw-polygon-logo canvas)
  (with-skia ([path (make-path polygon-commands)]
              [paint (make-paint #:color fill-color)])
    (draw-path canvas path paint)))
]

@logo-image[
(logo-render-pict size size draw-polygon-logo)
]

The path contains the geometry. The paint contains the color and drawing
style.

@section{Fill and Stroke}

The same path can be filled, stroked, or both. The geometry does not need to
change.

@logo-racketblock+eval[
(define (draw-filled-and-stroked-logo canvas)
  (with-skia ([path (make-path polygon-commands)]
              [fill (make-paint #:color fill-color)]
              [outline (make-paint #:color outline-color
                                   #:style 'stroke
                                   #:stroke-width 5
                                   #:join 'round)])
    (draw-path canvas path fill)
    (draw-path canvas path outline)))
]

@logo-image[
(logo-render-pict size size draw-filled-and-stroked-logo)
]

The fill covers the inside of the closed path. The stroke follows the path
itself.

The @racket[#:style] argument has three choices. The default @racket['fill]
fills the inside of a path. The @racket['stroke] style draws along the path.
The @racket['stroke-and-fill] style does both with one paint.

@logo-image[
(logo-style-pict)
]

A stroke also has a join style where two segments meet. The @racket[#:join]
argument accepts @racket['miter], @racket['round], and @racket['bevel].
The default is @racket['miter].

@logo-image[
(logo-join-pict)
]

A miter extends the outer edges until they meet. A round join rounds the
corner. A bevel join cuts the corner off. The join style affects stroked
geometry; it does not change the path itself.

@section{Bend the Sides}

Straight segments give the logo sharp sides. A quadratic curve uses one
control point to bend a segment.

The diagram below shows the first quadratic segment used by the next logo.
The gray lines connect the start point, the control point, and the endpoint.

@logo-image[
(logo-quadratic-control-pict)
]

The next path uses four quadratic curves:

@logo-racketblock+eval[
(define quadratic-commands
  '((move 250 50)
    (quad 415 100 390 250)
    (quad 375 365 250 440)
    (quad 125 365 110 250)
    (quad 85 100 250 50)
    (close)))

(define (draw-quadratic-logo canvas)
  (with-skia ([path (make-path quadratic-commands)]
              [fill (make-paint #:color fill-color)]
              [outline (make-paint #:color outline-color
                                   #:style 'stroke
                                   #:stroke-width 5)])
    (draw-path canvas path fill)
    (draw-path canvas path outline)))
]

@logo-image[
(logo-render-pict size size draw-quadratic-logo)
]

A @racket['quad] command has a control point followed by its endpoint. The
curve starts at the current point and bends toward the control point before it
reaches the endpoint.

@section{Use Cubic Curves}

A cubic curve has two control points. The extra control point gives us more
control over the direction of the curve near each endpoint.

The diagram below shows one cubic segment from the final logo. The gray lines
connect the start point, the two control points, and the endpoint.

@logo-image[
(logo-cubic-control-pict)
]

The final outer contour needs only two cubic curves:

@logo-racketblock+eval[
(define outer-logo-commands
  '((move 250 50)
    (cubic 405 85 440 280 250 440)
    (cubic 60 280 95 85 250 50)
    (close)))

(define (draw-outer-logo canvas)
  (with-skia ([path (make-path outer-logo-commands)]
              [fill (make-paint #:color fill-color)]
              [outline (make-paint #:color outline-color
                                   #:style 'stroke
                                   #:stroke-width 5)])
    (draw-path canvas path fill)
    (draw-path canvas path outline)))
]

@logo-image[
(logo-render-pict size size draw-outer-logo)
]

The first cubic runs from the top point to the bottom point. The second cubic
returns to the top on the other side.

@section{Add Another Contour}

A path can contain more than one contour. A new @racket['move] command starts
a new contour without connecting it to the previous one.

The logo will use a second closed contour for the curved cut-out:

@logo-racketblock+eval[
(define logo-commands
  '((move 250 50)
    (cubic 405 85 440 280 250 440)
    (cubic 60 280 95 85 250 50)
    (close)

    (move 165 310)
    (cubic 210 250 280 195 350 145)
    (cubic 315 220 270 305 205 355)
    (cubic 190 340 177 325 165 310)
    (close)))
]

At this point, the command list contains two closed contours.

@section{Cut a Hole}

A fill rule decides which parts of a path count as inside. The
@racket[#:fill-rule] argument has two choices: @racket['winding] and
@racket['even-odd]. The default is @racket['winding].

The winding rule takes contour direction into account. Two nested contours
with the same direction remain filled in the middle. Reversing the inner
contour can make that middle area a hole.

The even-odd rule uses a different test. Each contour crossing switches
between outside and inside. An odd number of surrounding contours means
inside, and an even number means outside.

@logo-image[
(logo-fill-rule-pict)
]

The logo uses @racket['even-odd], so its inner contour makes a hole without
depending on the direction of that contour.

@logo-racketblock+eval[
(define (make-logo-path)
  (make-path logo-commands #:fill-rule 'even-odd))

(define (draw-logo canvas)
  (with-skia ([path (make-logo-path)]
              [fill (make-paint #:color fill-color)]
              [outline (make-paint #:color outline-color
                                   #:style 'stroke
                                   #:stroke-width 5
                                   #:join 'round)])
    (draw-path canvas path fill)
    (draw-path canvas path outline)))
]

@logo-image[
(logo-render-pict size size draw-logo)
]

The path now describes the complete logo. The inner contour is still geometry.
The fill rule determines how the two contours combine when Skia fills the
path.

@section{Save PNG and SVG}

The same drawing function can be used for raster and vector output.

The PNG version uses an ordinary raster surface:

@racketblock[
(with-skia ([surface (make-surface size size
                                  #:background background-color)])
  (draw-logo (surface-canvas surface))
  (save-png surface "logo.png" #:exists 'replace))
]

The SVG version uses an output page:

@racketblock[
(define page
  (make-output-page size size draw-logo
                    #:unit 'px
                    #:background background-color))

(save-output page "logo.svg" 'svg #:exists 'replace)
]

The drawing function is unchanged. The SVG can preserve the path geometry as
vector content.

@section{Try It}

Try moving one control point in the outer contour. Predict which part of the
curve will change before you run the program.

Try removing @racket['close] from one contour and compare the fill and stroke.

Try changing the fill rule from @racket['even-odd] to @racket['winding].
Then reverse the inner contour and compare the result with the fill-rule
diagram.

Try changing @racket[#:join] from @racket['round] to @racket['miter] or
@racket['bevel].

Try drawing only the outline by removing the filled @racket[draw-path] call.

@section{Where to Go From Here}

This tutorial used straight segments, quadratic curves, cubic curves, multiple
contours, fill and stroke paints, and an even-odd fill rule.

The Guide will cover path inspection, bounds, path transforms, shape
recognition, path operations, arcs, conics, and other geometry tools in more
detail.

The complete @filepath{logo.rkt} example contains the finished program from
this tutorial.
