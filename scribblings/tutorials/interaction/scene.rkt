#lang racket

;;;
;;; Interaction Scene
;;;

;; Defines editable control points, hit testing, and the shared curve-editor drawing.
;; This shared tutorial drawing is used by the runnable program, documentation figures, and
;; checks.


;;;
;;; Imports and Exports
;;;

(require skia)

(provide editor-width editor-height editor-background
         (struct-out control-point)
         initial-control-points hit-radius marker-radius
         hit-control-point move-control-point
         draw-curve draw-guides draw-points draw-editor)

;;;
;;; Drawing Data and Helpers
;;;

; editor-width : exact-integer?
;   Specifies editor width in the drawing's local coordinate units.
(define editor-width 760)

; editor-height : exact-integer?
;   Specifies editor height in the drawing's local coordinate units.
(define editor-height 480)

; editor-background : string?
;   Specifies the editor background color used by this drawing.
(define editor-background "#0C182B")

;; Points live in logical canvas coordinates, not device pixels.
(struct control-point (x y) #:transparent)
;; x, y: real coordinates in the editor's local drawing space, with y increasing downward.
;; Points are immutable; moving a point replaces its record rather than changing it.
;; The editor list keeps cubic Bézier order: start, first handle, second handle, end.

; initial-control-points : list?
;   Orders the cubic's start, first handle, second handle, and end in model coordinates.
(define initial-control-points
  (list (control-point 120 320)
        (control-point 195 94)
        (control-point 548 108)
        (control-point 665 324)))

; hit-radius : exact-integer?
;   Specifies hit radius in the drawing's local coordinate units.
(define hit-radius 18)

; marker-radius : exact-integer?
;   Specifies marker radius in the drawing's local coordinate units.
(define marker-radius 10)

; squared-distance : control-point? real? real? -> real?
;   Returns squared distance from a control point to the supplied coordinates.
(define (squared-distance point x y)
  (+ (sqr (- x (control-point-x point)))
     (sqr (- y (control-point-y point)))))

; hit-control-point : list? real? real? [real?] -> (or/c exact-nonnegative-integer? #f)
;   Finds the nearest editable control point within the hit radius.
(define (hit-control-point points x y [radius hit-radius])
  (for/fold ([chosen #f] [nearest (* radius radius)]
             #:result chosen)
            ([point (in-list points)] [index (in-naturals)])
    (define distance (squared-distance point x y))
    (if (<= distance nearest)
        (values index distance)
        (values chosen nearest))))

; move-control-point : list? exact-nonnegative-integer? real? real? -> list?
;   Returns the control-point list with one validated index moved.
(define (move-control-point points index x y)
  (unless (and (exact-nonnegative-integer? index) (< index (length points)))
    (raise-argument-error 'move-control-point "valid control-point index" index))
  (for/list ([point (in-list points)] [i (in-naturals)])
    (if (= i index) (control-point x y) point)))

;; Reuse ordinary CPU Skia paints across frames; no GPU resource is retained.

; grid-paint : paint?
;   Retains the grid paint for repeated drawing calls.
(define grid-paint
  (make-paint #:color "#1B304A" #:style 'stroke #:stroke-width 1))

; guide-paint : paint?
;   Retains the guide paint for repeated drawing calls.
(define guide-paint
  (make-paint #:color "#7892AE" #:style 'stroke #:stroke-width 1.8))

; curve-paint : paint?
;   Retains the curve paint for repeated drawing calls.
(define curve-paint
  (make-paint #:color "#F1F7FD" #:style 'stroke #:stroke-width 5 #:cap 'round))

; endpoint-paint : paint?
;   Retains the endpoint paint for repeated drawing calls.
(define endpoint-paint (make-paint #:color "#FFBF72"))

; handle-paint : paint?
;   Retains the handle paint for repeated drawing calls.
(define handle-paint (make-paint #:color "#56D3E1"))

; selected-paint : paint?
;   Retains the selected paint for repeated drawing calls.
(define selected-paint
  (make-paint #:color "#FFFFFF" #:style 'stroke #:stroke-width 3))

; title-paint : paint?
;   Retains the title paint for repeated drawing calls.
(define title-paint (make-paint #:color "#E6F2FB"))

; muted-paint : paint?
;   Retains the muted paint for repeated drawing calls.
(define muted-paint (make-paint #:color "#A0BDD1"))

; title-font : font?
;   Selects the title font used by the scene.
(define title-font (make-font #:size 24))

; label-font : font?
;   Selects the label font used by the scene.
(define label-font (make-font #:size 16))

; caption-font : font?
;   Selects the caption font used by the scene.
(define caption-font (make-font #:size 13))

; draw-background : canvas? real? real? -> void?
;   Draws the background component in the current canvas coordinate system.
(define (draw-background canvas width height)
  (canvas-clear! canvas editor-background)
  (for ([x (in-range 24 width 40)])
    (draw-line canvas x 0 x height grid-paint))
  (for ([y (in-range 24 height 40)])
    (draw-line canvas 0 y width y grid-paint)))

; draw-guides : canvas? list? -> void?
;   Draws the guides component in the current canvas coordinate system.
(define (draw-guides canvas points)
  (for ([start (in-list (take points 3))]
        [end (in-list (rest points))])
    (draw-line canvas
               (control-point-x start) (control-point-y start)
               (control-point-x end) (control-point-y end)
               guide-paint)))

; draw-curve : canvas? list? -> void?
;   Draws the curve component in the current canvas coordinate system.
(define (draw-curve canvas points)
  (define start (first points))
  (define handle-one (second points))
  (define handle-two (third points))
  (define end (fourth points))
  (with-skia
      ([path
        (make-path
         `((move ,(control-point-x start) ,(control-point-y start))
           (cubic ,(control-point-x handle-one) ,(control-point-y handle-one)
                  ,(control-point-x handle-two) ,(control-point-y handle-two)
                  ,(control-point-x end) ,(control-point-y end))))])
    (draw-path canvas path curve-paint)))

;; Put P1 below/right and P2 below/left so their labels avoid the
;; subtitle and the diagonal control guide in the initial arrangement.

; control-point-label-position : control-point? exact-nonnegative-integer? -> (values real? real?)
;   Chooses a label position that distinguishes endpoints from curve handles.
(define (control-point-label-position point index)
  (define x (control-point-x point))
  (define y (control-point-y point))
  (case index
    [(1) (values (+ x 15) (+ y 30))]
    [(2) (values (- x 46) (+ y 30))]
    [else (values (+ x 15) (- y 15))]))

;; Bounds are the measured ink offsets and size relative to a text baseline.
;; Reserve space for the fixed header (through y = 88) and the footer.
;; A client area too small for a complete label returns #f, #f instead of clipping it.

; fit-label-origin : real? real? real? real? real? real? real? real? -> (values real? real?)
;   Clamps a label origin so its measured ink bounds fit the drawing area.
(define (fit-label-origin x y bx by bw bh width height)
  (define left 8)
  (define right (- width 8))
  (define top 88)
  (define bottom (- height 40))
  (cond
    [(or (> bw (- right left)) (> bh (- bottom top))) (values #f #f)]
    [else
     (values (min (- right bx bw) (max (- left bx) x))
             (min (- bottom by bh) (max (- top by) y)))]))

; draw-points : canvas? list? (or/c exact-nonnegative-integer? #f) [real?] [real?] -> void?
;   Draws the points component in the current canvas coordinate system.
(define (draw-points canvas points selected
                     [width editor-width] [height editor-height])
  (for ([point (in-list points)] [index (in-naturals)])
    (define x (control-point-x point))
    (define y (control-point-y point))
    (define endpoint? (or (= index 0) (= index 3)))
    (define label (format "P~a" index))
    (define-values (preferred-x preferred-y)
      (control-point-label-position point index))
    (define-values (bx by bw bh) (simple-text-bounds label-font label))
    (define-values (label-x label-y)
      (fit-label-origin preferred-x preferred-y bx by bw bh width height))
    (when (equal? selected index)
      (draw-circle canvas x y 15 selected-paint))
    (draw-circle canvas x y marker-radius (if endpoint? endpoint-paint handle-paint))
    (when label-x
      (draw-simple-text canvas label label-x label-y label-font title-paint))))

; draw-editor : canvas? list? real? real? [(or/c exact-nonnegative-integer? #f)] -> void?
;   Draws the editor component in the current canvas coordinate system.
(define (draw-editor canvas points width height [selected #f])
  (draw-background canvas width height)
  (draw-guides canvas points)
  (draw-curve canvas points)
  (draw-points canvas points selected width height)
  (draw-simple-text canvas "BEZIER WORKSHOP" 28 42 title-font title-paint)
  (draw-simple-text canvas "Amber: endpoints   /   Cyan: control handles"
                    29 74 label-font muted-paint)
  (draw-simple-text canvas "DRAG A POINT TO CHANGE THE CURVE"
                    28 (- height 20) caption-font muted-paint))

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; surface : surface?
  ;   Owns the raster drawing target used to produce the example's output.
  (define surface
    (make-surface editor-width editor-height #:background editor-background))
  (draw-editor (surface-canvas surface)
               initial-control-points editor-width editor-height)
  (save-png surface "bezier-editor.png" #:exists 'replace))

;;;
;;; Regression Checks
;;;

(module+ test
  (require rackunit)
  (check-equal? (hit-control-point initial-control-points 120 320) 0)
  (check-equal? (hit-control-point initial-control-points 548 108) 2)
  (check-false (hit-control-point initial-control-points 400 410))
  (check-equal? (hit-control-point initial-control-points 138 320) 0)

  ; moved : list?
  ;   Contains a replacement control-point list used to test hit testing after a drag.
  (define moved (move-control-point initial-control-points 1 260 145))
  (check-equal? (second moved) (control-point 260 145))
  (check-equal? (first moved) (first initial-control-points))
  (check-equal? (second initial-control-points) (control-point 195 94))
  (check-exn exn:fail:contract?
             (lambda () (move-control-point initial-control-points 4 10 10)))
  ;; Handle labels must clear the subtitle (baseline y = 74).
  (check-equal?
   (call-with-values
    (lambda () (control-point-label-position (second initial-control-points) 1))
    list)
   '(210 124))
  (check-equal?
   (call-with-values
    (lambda () (control-point-label-position (first initial-control-points) 0))
    list)
   '(135 305))
  (check-equal?
   (call-with-values
    (lambda () (control-point-label-position (third initial-control-points) 2))
    list)
   '(502 138))
  (check-equal? (hit-control-point initial-control-points 213 94) 1)
  (check-false (hit-control-point initial-control-points 214 94)))

;;;
;;; Regression Checks
;;;

(module+ test
  (for* ([size '((760 480) (320 240) (80 170) (24 110))]
         [index (in-range 4)]
         [x (list 16 (- (first size) 16))]
         [y (list 16 (- (second size) 16))])
    (define point (control-point x y))
    (define-values (preferred-x preferred-y) (control-point-label-position point index))
    (define-values (bx by bw bh) (simple-text-bounds label-font (format "P~a" index)))
    (define-values (label-x label-y)
      (fit-label-origin preferred-x preferred-y bx by bw bh (first size) (second size)))
    (when label-x
      (check-true (<= 8 (+ label-x bx)))
      (check-true (<= (+ label-x bx bw) (- (first size) 8)))
      (check-true (<= 88 (+ label-y by)))
      (check-true (<= (+ label-y by bh) (- (second size) 40))))))

;;;
;;; Regression Checks
;;;

(module+ test
  (require rackunit)
  ;; Preserve a preferred baseline when all of its ink already fits.
  (check-equal?
   (call-with-values (lambda () (fit-label-origin 210 124 1 -12 19 15 760 480)) list)
   '(210 124))
  ;; The two audited edge cases, with representative (not native) text bounds.
  (check-equal?
   (call-with-values (lambda () (fit-label-origin -30 138 1 -12 19 15 760 480)) list)
   '(7 138))
  (check-equal?
   (call-with-values (lambda () (fit-label-origin 210 494 1 -12 19 15 760 480)) list)
   '(210 437))
  (for* ([width '(24 80 320 760)] [height '(110 170 240 480)]
         [x '(-30 16 135 502 900)] [y '(-15 30 124 494)]
         [bounds '((1 -12 19 15) (-3 -16 25 20) (0 0 20 20))])
    (define bx (car bounds))
    (define by (cadr bounds))
    (define bw (caddr bounds))
    (define bh (cadddr bounds))
    (define-values (label-x label-y) (fit-label-origin x y bx by bw bh width height))
    (cond
      [(and (<= bw (- width 16)) (<= bh (- height 128)))
       (check-not-false label-x)
       (check-not-false label-y)
       (check-true (<= 8 (+ label-x bx) (+ label-x bx bw) (- width 8)))
       (check-true (<= 88 (+ label-y by) (+ label-y by bh) (- height 40)))]
      [else (check-false label-x) (check-false label-y)])))
