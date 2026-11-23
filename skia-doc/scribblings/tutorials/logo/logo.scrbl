#lang scribble/manual

@(require "../support/reader.rkt"
          "../support/accessible-figures.rkt")

@title[#:style (tutorial-feedback-style)]{Paths and Geometry — Draw a Logo}
@(tutorial-navigation "logo")

@(require "eval.rkt"
          (for-label racket
                     skia))

@(define-values (finished-preview finish-figure) (make-figure-preview))

@section[#:tag "finished-result"]{The Finished Logo}

@|finished-preview|

The leaf logo has smooth sides and a curved cutout. Start with a polygon,
replace its edges with curves, and use a second contour to cut the hole.

A path describes the geometry. A paint determines how that geometry is filled
or stroked.

@tutorial-entry["logo"]

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
  (define path (make-path polygon-commands))
  (define paint (make-paint #:color fill-color))
  (draw-path canvas path paint))
]

@(tutorial-figure
 "A filled six-sided polygon is the first rough version of the leaf logo."
 (logo-image
(logo-render-pict size size draw-polygon-logo)
))

The path contains the geometry. The paint contains the color and drawing
style.

@section{Fill and Stroke}

The same path can be filled, stroked, or both. The geometry does not need to
change.

@logo-racketblock+eval[
(define (draw-filled-and-stroked-logo canvas)
  (define path (make-path polygon-commands))
  (define fill (make-paint #:color fill-color))
  (define outline (make-paint #:color outline-color
    #:style 'stroke
    #:stroke-width 5
    #:join 'round))
  (draw-path canvas path fill)
  (draw-path canvas path outline))
]

@(tutorial-figure
 "The same polygon has a filled interior and a separate dark outline."
 (logo-image
(logo-render-pict size size draw-filled-and-stroked-logo)
))

The fill covers the inside of the closed path. The stroke follows the path
itself.

The @racket[#:style] argument has three choices. The default @racket['fill]
fills the inside of a path. The @racket['stroke] style draws along the path.
The @racket['stroke-and-fill] style does both with one paint.

@(tutorial-figure
 (string-append
   "Three triangle styles: fill covers the interior, stroke follows the boundary, "
   "and both combine them."
)
 (logo-image
(logo-style-pict)
))

A stroke also has a join style where two segments meet. The @racket[#:join]
argument accepts @racket['miter], @racket['round], and @racket['bevel].
The default is @racket['miter].

@(tutorial-figure
 (string-append
   "Three joins at a pointed corner: miter extends it, round curves it, and bevel "
   "cuts it off."
)
 (logo-image
(logo-join-pict)
))

A miter extends the outer edges until they meet. A round join rounds the
corner. A bevel join cuts the corner off. The join style affects stroked
geometry; it does not change the path itself.

@section{Bend the Sides}

Straight segments give the logo sharp sides. A quadratic curve uses one
control point to bend a segment.

The diagram below shows the first quadratic segment used by the next logo.
The gray lines connect the start point, the control point, and the endpoint.

@(tutorial-figure
 (string-append
   "Quadratic curve: a start, one control point off the curve, and an endpoint "
   "joined by guide lines."
)
 (logo-image
(logo-quadratic-control-pict)
))

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
  (define path (make-path quadratic-commands))
  (define fill (make-paint #:color fill-color))
  (define outline (make-paint #:color outline-color
    #:style 'stroke
    #:stroke-width 5))
  (draw-path canvas path fill)
  (draw-path canvas path outline))
]

@(tutorial-figure
 "Four quadratic segments replace the polygon's straight edges with curved sides."
 (logo-image
(logo-render-pict size size draw-quadratic-logo)
))

A @racket['quad] command has a control point followed by its endpoint. The
curve starts at the current point and bends toward the control point before it
reaches the endpoint.

@section{Use Cubic Curves}

A cubic curve has two control points. The extra control point gives us more
control over the direction of the curve near each endpoint.

The diagram below shows one cubic segment from the final logo. The gray lines
connect the start point, the two control points, and the endpoint.

@(tutorial-figure
 (string-append
   "Cubic curve: two control points guide the direction near the start and end of "
   "the segment."
)
 (logo-image
(logo-cubic-control-pict)
))

The final outer contour needs only two cubic curves:

@logo-racketblock+eval[
(define outer-logo-commands
  '((move 250 50)
    (cubic 405 85 440 280 250 440)
    (cubic 60 280 95 85 250 50)
    (close)))

(define (draw-outer-logo canvas)
  (define path (make-path outer-logo-commands))
  (define fill (make-paint #:color fill-color))
  (define outline (make-paint #:color outline-color
    #:style 'stroke
    #:stroke-width 5))
  (draw-path canvas path fill)
  (draw-path canvas path outline))
]

@(tutorial-figure
 (string-append
   "Two cubic segments form the outer leaf contour, from its top point to its "
   "bottom and back."
)
 (logo-image
(logo-render-pict size size draw-outer-logo)
))

The first cubic runs from the top point to the bottom point. The second cubic
returns to the top on the other side.

@section{Cut a Hole with a Second Contour}

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

The command list now contains two closed contours. A fill rule decides which
parts of their combined geometry count as inside. The
@racket[#:fill-rule] argument has two choices: @racket['winding] and
@racket['even-odd]. The default is @racket['winding].

The winding rule takes contour direction into account. Two nested contours
with the same direction remain filled in the middle. Reversing the inner
contour can make that middle area a hole.

The even-odd rule uses a different test. Each contour crossing switches
between outside and inside. An odd number of surrounding contours means
inside, and an even number means outside.

@(tutorial-figure
 (string-append
   "Nested contours: winding fills equal directions; reversed winding and even-odd "
   "leave a hole."
)
 (logo-image
(logo-fill-rule-pict)
))

The logo uses @racket['even-odd], so its inner contour makes a hole without
depending on the direction of that contour.

@logo-racketblock+eval[
(define (make-logo-path)
  (make-path logo-commands #:fill-rule 'even-odd))

(define (draw-logo canvas)
  (define path (make-logo-path))
  (define fill (make-paint #:color fill-color))
  (define outline (make-paint #:color outline-color
    #:style 'stroke
    #:stroke-width 5
    #:join 'round))
  (draw-path canvas path fill)
  (draw-path canvas path outline))
]

@(finish-figure
 (tutorial-figure
 "The finished leaf logo has a curved cutout and a dark stroke around both contours."
 (logo-image
(logo-render-pict size size draw-logo)
)))

The path now describes the complete logo. The inner contour is still geometry.
The fill rule determines how the two contours combine when Skia fills the
path.

@section{Save PNG and SVG}

The same drawing function can be used for raster and vector output.

The PNG version uses an ordinary raster surface:

@racketblock[
(define surface (make-surface size size
  #:background background-color))
(draw-logo (surface-canvas surface))
(save-png surface "logo.png" #:exists 'replace)
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

@section[#:tag "try-it"]{Try It}

Try moving one control point in the outer contour. Predict which part of the
curve will change before you run the program.

Try removing @racket['close] from one contour and compare the fill and stroke.

Try changing the fill rule from @racket['even-odd] to @racket['winding].
Then reverse the inner contour and compare the result with the fill-rule
diagram.

Try changing @racket[#:join] from @racket['round] to @racket['miter] or
@racket['bevel].

Try drawing only the outline by removing the filled @racket[draw-path] call.

@section[#:tag "next-steps"]{Where to Go From Here}

You can now build contours from straight and curved segments and choose how they are filled.

@tutorial-next["logo"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["logo"]
