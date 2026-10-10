#lang racket

(require skia)

(provide emblem-size
         sheet-width
         sheet-height
         sheet-background
         draw-emblem
         record-emblem
         draw-placed-emblem
         draw-pattern-sheet)

(define emblem-size 120)

(define (draw-emblem canvas)
  (define blue (make-paint #:color "#326BC4"))
  (define teal (make-paint #:color "#1EA7A0"))
  (define amber (make-paint #:color "#F0AA55"))
  (define ink
    (make-paint #:color "#24405E"
                #:style 'stroke
                #:stroke-width 2))
  (define highlight (make-paint #:color 'white))
  (with-canvas-state canvas
    (canvas-translate! canvas 60 60)
    (for ([petal-index (in-range 8)])
      (with-canvas-state canvas
        (canvas-rotate! canvas (* 45 petal-index))
        (draw-oval canvas -12 -49 24 36
                   (cond
                     [(zero? petal-index) amber]
                     [(even? petal-index) blue]
                     [else teal]))))
    (draw-circle canvas 0 0 19 amber)
    (draw-circle canvas 0 0 19 ink)
    (draw-circle canvas 0 -8 5 highlight)))

(define (record-emblem)
  (call-with-picture emblem-size emblem-size draw-emblem))

(define (draw-placed-emblem canvas picture center-x center-y size angle)
  (with-canvas-state canvas
    (canvas-translate! canvas center-x center-y)
    (canvas-rotate! canvas angle)
    (draw-picture canvas picture
                  #:x (- (/ size 2))
                  #:y (- (/ size 2))
                  #:width size
                  #:height size)))

(define sheet-width 1000)
(define sheet-height 760)
(define sheet-background "#EDF2F7")

(define (draw-pattern-sheet canvas)
  (define picture (record-emblem))
  (define paper (make-paint #:color "#FFFFFF"))
  (define ink (make-paint #:color "#24405E"))
  (define blue (make-paint #:color "#326BC4"))
  (define muted (make-paint #:color "#667A8D"))
  (define rule (make-paint #:color "#D4DEE9"))
  (define label-font (make-font #:size 16))
  (define title-font (make-font #:size 46))
  (define caption-font (make-font #:size 18))
  (define footer-font (make-font #:size 14))

  (draw-rounded-rect canvas 42 35 916 690 24 24 paper)
  (draw-simple-text canvas "SKIA / RECORDING STUDY" 82 94 label-font blue)
  (draw-simple-text canvas "A pattern of pictures" 79 161 title-font ink)
  (draw-simple-text canvas "One recording, many placements." 82 193
                    caption-font muted)
  (draw-rect canvas 82 216 836 2 rule)

  (for* ([row (in-range 3)]
         [column (in-range 5)])
    (define size (+ 72 (* 12 (modulo (+ (* 2 row) column) 4))))
    (define angle (* 13 (+ row (* 2 column))))
    (define center-x (+ 148 (* column 176)))
    (define center-y (+ 301 (* row 139)))
    (draw-placed-emblem canvas picture center-x center-y size angle))

  (draw-rect canvas 82 650 836 2 rule)
  (draw-simple-text canvas "REPLAY  /  RESIZE  /  ROTATE" 82 690 footer-font muted)
  (draw-simple-text canvas "11" 895 690 footer-font blue))

(module+ main
  (define surface
    (make-surface sheet-width sheet-height
                  #:background sheet-background))
  (draw-pattern-sheet (surface-canvas surface))
  (save-png surface "pattern-sheet.png" #:exists 'replace))
