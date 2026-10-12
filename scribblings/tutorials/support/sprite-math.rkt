#lang racket

;; Pure helpers shared by Tutorials 21 and 22; no Skia or GUI initialization.
(provide fixed-step advance-clock fit-viewport cell-size cell-gap cell-pitch
         atlas-columns atlas-width atlas-height sprite-source sprite-anchor)

(define fixed-step (/ 1.0 120))
(define cell-size 48)
(define cell-gap 4)
(define cell-pitch (+ cell-size (* 2 cell-gap)))
(define atlas-columns 4)
(define atlas-width (* atlas-columns cell-pitch))
(define sprite-anchor (list (/ cell-size 2) (/ cell-size 2)))

(define (atlas-height count)
  (* cell-pitch (quotient (+ count (sub1 atlas-columns)) atlas-columns)))

(define (sprite-source index)
  (unless (exact-nonnegative-integer? index)
    (raise-argument-error 'sprite-source "exact-nonnegative-integer?" index))
  (list (+ cell-gap (* (remainder index atlas-columns) cell-pitch))
        (+ cell-gap (* (quotient index atlas-columns) cell-pitch))
        cell-size cell-size))

;; Return the number of fixed simulation steps and the fractional remainder.
;; Discard elapsed time beyond 0.1 seconds: do not catch up minutes after a stall.
(define (advance-clock remainder seconds)
  (define total (+ remainder (min 0.1 (max 0 seconds))))
  (define steps (min 12 (inexact->exact (floor (/ total fixed-step)))))
  (values steps (max 0.0 (- total (* steps fixed-step)))))

(define (fit-viewport width height scene-width scene-height)
  (define scale (min (/ width scene-width) (/ height scene-height)))
  (values scale
          (/ (- width (* scale scene-width)) 2)
          (/ (- height (* scale scene-height)) 2)))

(module+ test
  (require rackunit)
  (test-case "source rectangles have gutters on every side"
    (check-equal? (sprite-source 0) '(4 4 48 48))
    (check-equal? (sprite-source 4) '(4 60 48 48))
    (check-equal? (sprite-source 15) '(172 172 48 48)))
  (test-case "atlas dimensions include the last gutter"
    (check-equal? (atlas-height 8) 112)
    (check-equal? (atlas-height 16) 224))
  (test-case "letterboxing preserves aspect ratio"
    (check-equal? (call-with-values (lambda () (fit-viewport 800 600 640 760)) list)
                  (list (/ 15 19) (/ 2800 19) 0)))
  (test-case "fixed clock accumulates small frames"
    (define-values (first remainder) (advance-clock 0.0 0.004))
    (define-values (second rest) (advance-clock remainder 0.006))
    (check-equal? first 0)
    (check-equal? second 1)
    (check-true (< rest fixed-step)))
  (test-case "a long stall has bounded catch-up"
    (define-values (steps remainder) (advance-clock 0.0 300))
    (check-equal? steps 12)
    (check-true (< remainder fixed-step))))
