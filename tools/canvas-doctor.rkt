#lang racket/base
(require "../main.rkt")
(provide canvas-doctor!)
(define (canvas-doctor!)
  (with-skia ([s (make-surface 50 40 #:background 'white)]
              [red (make-paint #:color 'red)]
              [blue (make-paint #:color 'blue)]
              [opacity (make-paint #:color (rgba 0 0 0 128))])
    (define c (surface-canvas s))
    (unless (equal? (canvas-device-clip-bounds c) #(0 0 50 40))
      (error 'doctor "canvas clip readback failed"))
    (with-canvas-layer c #:paint opacity
      (draw-rect c 0 0 20 20 red)
      (draw-rect c 10 0 20 20 blue))
    (define p (surface-pixel s 15 10))
    (unless (and (<= 126 (rgba-red p) 128) (<= 126 (rgba-green p) 128)
                 (= (rgba-blue p) 255) (= (canvas-save-count c) 1))
      (error 'doctor "group opacity or layer restore failed: ~a" p))
    (draw-arc c 32 2 14 14 0 90 red #:use-center? #t)
    (draw-rrect c (make-rounded-rect 3 24 30 12 #:radii '((2 2) (5 4) (0 0) (3 3))) blue)
    (unless (canvas-quick-reject? c 100 100 10 10)
      (error 'doctor "quick reject failed")))
  (define p
    (make-output-page 60 40
      (lambda (c) (with-canvas-layer c (draw-color c 'red)))))
  (define report (analyze-output-page p 'svg))
  (unless (output-audit-report-blocking? report)
    (error 'doctor "SVG layer risk was not audited"))
  (printf "Canvas primitives passed: arcs/rrects, clip queries, group opacity, protected restore, SVG layer audit\n"))
