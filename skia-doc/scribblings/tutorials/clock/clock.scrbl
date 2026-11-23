#lang scribble/manual

@(require "../support/reader.rkt"
          "../support/accessible-figures.rkt")

@title[#:style (tutorial-feedback-style)]{Transforms and Coordinate Systems — Build a Clock}
@(tutorial-navigation "clock")

@(require "eval.rkt"
          (for-label racket
                     skia))

@(define-values (finished-preview finish-figure) (make-figure-preview))

@section[#:tag "finished-result"]{The Finished Clock}

@|finished-preview|

The clock shows 10:10:30. This is a static drawing: the program does not read
the current time or update the hands. Translation, rotation, and scaling place
simple geometry around a shared center.

@tutorial-entry["clock"]

@section{The Clock Face}

The drawing will use a 600 by 600 surface:

@clock-racketblock+eval[
(define size 600)
(define center (/ size 2))
(define face-radius 220)

(define background-color "#E9EDF2")
(define face-color "#F6F1E7")
(define ink-color "#293241")
(define second-color "#C94F3D")
]

The clock face is centered around the point @tt{(0, 0)}:

@clock-racketblock+eval[
(define (draw-clock-face canvas)
  (define fill (make-paint #:color face-color))
  (define rim (make-paint #:color ink-color
    #:style 'stroke
    #:stroke-width 5))
  (draw-circle canvas 0 0 face-radius fill)
  (draw-circle canvas 0 0 face-radius rim))
]

Drawing the face on an unchanged canvas puts its center at the upper-left
corner of the surface:

@(tutorial-figure
 (string-append
   "Intentional partial result: a clock face centered at (0, 0) is mostly outside "
   "the surface."
)
 (clock-image
(clock-render-pict size size draw-clock-face)
))

Most of the circle is outside the surface. We could change every coordinate in
the clock, but a transform gives us a simpler solution.

@section{Move the Origin}

The @racket[canvas-translate!] function changes the coordinate system used by
later drawing operations. The following code moves the local origin to the
center of the surface:

@racketblock[
(with-canvas-state canvas
  (canvas-translate! canvas center center)
  (draw-clock-face canvas))
]

The surface is still 600 by 600. The transform does not move the surface, and
it does not move anything that has already been drawn. The transform changes
how local coordinates map to positions on the surface for later drawing.

The diagram below shows both coordinate systems. The gray axes start at the
surface origin. The red axes show the local coordinate system after the
translation.

@(tutorial-figure
 (string-append
   "Surface and local axes: translating by (300, 300) places the local origin at "
   "the clock center."
)
 (clock-image
(clock-coordinate-pict)
))

The local point @tt{(0, 0)} now maps to surface position @tt{(300, 300)}.
Negative y coordinates move upward from the clock center, and positive y
coordinates move downward. The red axes are not a second surface. They show the
local coordinate system that is in effect after the translation.

@(tutorial-figure
 "The translated clock face is fully visible at the center of the 600 by 600 surface."
 (clock-image
(clock-render-pict
 size size
 (lambda (canvas)
   (with-canvas-state canvas
     (canvas-translate! canvas center center)
     (draw-clock-face canvas))))
))

The clock functions can now use @tt{(0, 0)} as the clock center. They do not
need to know where that point lies on the surface.

@section{Draw One Tick}

The twelve o'clock mark can now be described relative to the local origin:

@clock-racketblock+eval[
(define (draw-hour-tick canvas paint)
  (draw-line canvas 0 -184 0 -210 paint))
]

Both endpoints have x coordinate zero. Their negative y coordinates put the
mark above the clock center.

@(tutorial-figure
 "One hour tick points upward from the local origin to the twelve o'clock position."
 (clock-image
(clock-render-pict
 size size
 (lambda (canvas)
   (with-canvas-state canvas
     (canvas-translate! canvas center center)
     (draw-clock-face canvas)
     (let ()
       (define paint (make-paint #:color ink-color
         #:style 'stroke
         #:stroke-width 6
         #:cap 'round))
       (draw-hour-tick canvas paint)))))
))

@section{Rotate the Tick}

The @racket[canvas-rotate!] function rotates the local coordinate system. The
angle is measured in degrees.

The following code draws another copy of the same tick after a 30 degree
rotation:

@racketblock[
(with-canvas-state canvas
  (canvas-rotate! canvas 30)
  (draw-hour-tick canvas paint))
]

Positive rotation appears clockwise with the default Skia coordinate system
because the y axis points downward.

@(tutorial-figure
 "The original tick and its 30-degree clockwise copy use identical geometry."
 (clock-image
(clock-render-pict
 size size
 (lambda (canvas)
   (with-canvas-state canvas
     (canvas-translate! canvas center center)
     (draw-clock-face canvas)
     (let ()
       (define paint (make-paint #:color ink-color
         #:style 'stroke
         #:stroke-width 6
         #:cap 'round))
       (draw-hour-tick canvas paint)
       (with-canvas-state canvas
         (canvas-rotate! canvas 30)
         (draw-hour-tick canvas paint))))))
))

The tick geometry did not change. The coordinate system changed before Skia
drew the second copy.

Most of this tutorial follows the same pattern:

@(tutorial-figure
 "Transform sequence: choose a local origin, transform its axes, then draw the geometry."
 (clock-image
(clock-transform-flow-pict)
))

First, choose a useful local origin. Next, transform the local coordinate
system. Finally, draw simple geometry in that system.

@section{Around the Clock}

Twelve hour marks need rotations of 0, 30, 60 degrees, and so on. A first
attempt might look like this:

@racketblock[
(for ([hour (in-range 12)])
  (canvas-rotate! canvas (* hour 30))
  (draw-hour-tick canvas paint))
]

The code does not produce twelve evenly spaced marks. Each rotation starts from
the coordinate system left by the previous iteration. The rotations therefore
accumulate.

The first iteration adds 0 degrees. The second adds 30 degrees. The third then
adds 60 degrees to the existing 30 degree rotation, so the third mark appears
at 90 degrees instead of 60 degrees.

@(tutorial-figure
 (string-append
   "Intentional wrong result: accumulated rotations fail to produce twelve evenly "
   "spaced ticks."
)
 (clock-image
(clock-render-pict
 size size
 (lambda (canvas)
   (with-canvas-state canvas
     (canvas-translate! canvas center center)
     (draw-clock-face canvas)
     (let ()
       (define paint (make-paint #:color ink-color
         #:style 'stroke
         #:stroke-width 6
         #:cap 'round))
       (for ([hour (in-range 12)])
         (canvas-rotate! canvas (* hour 30))
         (draw-hour-tick canvas paint))))))
))

@section{Save and Restore the Drawing State}

The @racket[with-canvas-state] form saves the current canvas state before its
body runs and restores that state afterward. The saved state includes the
current transform and clip. Each mark can therefore start from the same
coordinate system:

@clock-racketblock+eval[
(define (draw-hour-ticks canvas)
  (define paint (make-paint #:color ink-color
    #:style 'stroke
    #:stroke-width 6
    #:cap 'round))
  (for ([hour (in-range 12)])
    (with-canvas-state canvas
      (canvas-rotate! canvas (* hour 30))
      (draw-hour-tick canvas paint))))
]

@(tutorial-figure
 "Twelve hour ticks are evenly spaced because each rotation starts from the saved state."
 (clock-image
(clock-render-pict
 size size
 (lambda (canvas)
   (with-canvas-state canvas
     (canvas-translate! canvas center center)
     (draw-clock-face canvas)
     (draw-hour-ticks canvas))))
))

Minute marks use the same idea. A full turn is 360 degrees, so sixty marks are
six degrees apart:

@clock-racketblock+eval[
(define (draw-minute-tick canvas paint)
  (draw-line canvas 0 -198 0 -210 paint))

(define (draw-ticks canvas)
  (define hour-paint (make-paint #:color ink-color
    #:style 'stroke
    #:stroke-width 6
    #:cap 'round))
  (define minute-paint (make-paint #:color ink-color
    #:style 'stroke
    #:stroke-width 2
    #:cap 'round))
  (for ([minute (in-range 60)])
    (with-canvas-state canvas
      (canvas-rotate! canvas (* minute 6))
      (if (zero? (remainder minute 5))
          (draw-hour-tick canvas hour-paint)
          (draw-minute-tick canvas minute-paint)))))
]

@(tutorial-figure
 "Sixty ticks surround the face; every fifth tick is longer and thicker."
 (clock-image
(clock-render-pict
 size size
 (lambda (canvas)
   (with-canvas-state canvas
     (canvas-translate! canvas center center)
     (draw-clock-face canvas)
     (draw-ticks canvas))))
))

The final version uses a longer, thicker mark for each hour and a shorter,
thinner mark for the other minutes.

@section{Add the Hands}

A clock hand is also easiest to describe around the local origin. The hand
points toward twelve o'clock before any rotation is applied:

@clock-racketblock+eval[
(define (draw-hand canvas length tail paint)
  (draw-line canvas 0 tail 0 (- length) paint))
]

The hour, minute, and second values determine three rotation angles:

@clock-racketblock+eval[
(define (draw-hands canvas hour minute second)
  (define hour-angle
    (+ (* (modulo hour 12) 30)
       (* minute 1/2)
       (/ second 120)))
  (define minute-angle
    (+ (* minute 6)
       (/ second 10)))
  (define second-angle (* second 6))
  (define hour-paint (make-paint #:color ink-color
    #:style 'stroke
    #:stroke-width 11
    #:cap 'round))
  (define minute-paint (make-paint #:color ink-color
    #:style 'stroke
    #:stroke-width 7
    #:cap 'round))
  (define second-paint (make-paint #:color second-color
    #:style 'stroke
    #:stroke-width 3
    #:cap 'round))
  (with-canvas-state canvas
    (canvas-rotate! canvas hour-angle)
    (draw-hand canvas 120 16 hour-paint))
  (with-canvas-state canvas
    (canvas-rotate! canvas minute-angle)
    (draw-hand canvas 165 20 minute-paint))
  (with-canvas-state canvas
    (canvas-rotate! canvas second-angle)
    (draw-hand canvas 185 28 second-paint)))
]

The angles include fractional hours and minutes for the supplied time. Ten
minutes add five degrees to the hour hand. Thirty seconds add three degrees to
the minute hand and one quarter of a degree to the hour hand. These calculations
position the hands; they do not schedule another drawing.

A small center pin finishes the mechanism:

@clock-racketblock+eval[
(define (draw-center-pin canvas)
  (define outer (make-paint #:color ink-color))
  (define inner (make-paint #:color second-color))
  (draw-circle canvas 0 0 11 outer)
  (draw-circle canvas 0 0 5 inner))

(define (draw-clock-at-origin canvas hour minute second)
  (draw-clock-face canvas)
  (draw-ticks canvas)
  (draw-hands canvas hour minute second)
  (draw-center-pin canvas))
]

@(finish-figure
 (tutorial-figure
 (string-append
   "A completed static clock at 10:10:30, with hour, minute, and second hands and "
   "a center pin."
)
 (clock-image
(clock-render-pict
 size size
 (lambda (canvas)
   (with-canvas-state canvas
     (canvas-translate! canvas center center)
     (draw-clock-at-origin canvas 10 10 30))))
)))

The drawing functions use the clock center as their local origin. None of them
needs to know that the surface center is @tt{(300, 300)}.

@section{Transform Order Matters}

The order of transforms matters. The following sequence first moves the local
origin to the center and then rotates the local axes:

@racketblock[
(canvas-translate! canvas center center)
(canvas-rotate! canvas 45)
]

Reversing the calls has a different result:

@racketblock[
(canvas-rotate! canvas 45)
(canvas-translate! canvas center center)
]

The second sequence rotates first. Its translation therefore happens in an
already rotated coordinate system.

The two pictures below draw the same red hand. The gray dot marks the center of
the surface.

@centered{@bold{Translate, then rotate}}

@(tutorial-figure
 "Translate, then rotate: the hand rotates around the surface center at (300, 300)."
 (clock-image
(clock-render-pict
 size size
 (lambda (canvas)
   (define guide (make-paint #:color "#8A94A3"))
   (define hand (make-paint #:color second-color
     #:style 'stroke
     #:stroke-width 6
     #:cap 'round))
   (draw-circle canvas center center 7 guide)
   (with-canvas-state canvas
     (canvas-translate! canvas center center)
     (canvas-rotate! canvas 45)
     (draw-circle canvas 0 0 7 hand)
     (draw-hand canvas 150 0 hand))))
))

@centered{@bold{Rotate, then translate}}

@(tutorial-figure
 (string-append
   "Rotate, then translate: the hand's origin moves to the left edge, away from "
   "the center dot."
)
 (clock-image
(clock-render-pict
 size size
 (lambda (canvas)
   (define guide (make-paint #:color "#8A94A3"))
   (define hand (make-paint #:color second-color
     #:style 'stroke
     #:stroke-width 6
     #:cap 'round))
   (draw-circle canvas center center 7 guide)
   (with-canvas-state canvas
     (canvas-rotate! canvas 45)
     (canvas-translate! canvas center center)
     (draw-circle canvas 0 0 7 hand)
     (draw-hand canvas 150 0 hand))))
))

The two sequences contain the same operations, but they produce different
coordinate systems. Each transform affects the operations that follow it.

@section{Scale the Clock}

The @racket[canvas-scale!] function changes the size of the local coordinate
system. We can use the same clock drawing at different positions and sizes:

@clock-racketblock+eval[
(define (draw-clock-at canvas x y scale hour minute second)
  (with-canvas-state canvas
    (canvas-translate! canvas x y)
    (canvas-scale! canvas scale)
    (draw-clock-at-origin canvas hour minute second)))
]

@(tutorial-figure
 "Three copies of the same clock have different centers and scales but show the same time."
 (clock-image
(clock-render-pict
 900 360
 (lambda (canvas)
   (draw-clock-at canvas 110 180 0.35 10 10 30)
   (draw-clock-at canvas 390 180 0.50 10 10 30)
   (draw-clock-at canvas 735 180 0.65 10 10 30)))
))

Scaling affects the whole local coordinate system. Distances and stroke widths
therefore scale together.

The complete 600 by 600 clock can now be drawn with one call:

@racketblock[
(define surface (make-surface size size
  #:background background-color))
(draw-clock-at (surface-canvas surface)
               center center 1
               10 10 30)
(save-png surface "clock.png" #:exists 'replace)
]

@section[#:tag "try-it"]{Try It}

Try changing the fixed time. Predict the hand angles before you run the
program.

Try changing the scale or the point passed to @racket[draw-clock-at]. Draw two
or three clocks on the same surface at different sizes.

Try using negative rotation angles for the hands. Predict their positions
before saving the new drawing. Updating the time repeatedly would require an
animation loop, as in @tutorial-link["animation"].

@section[#:tag "next-steps"]{Where to Go From Here}

You can now place the same geometry at different origins, angles, and sizes.

@tutorial-next["clock"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["clock"]
