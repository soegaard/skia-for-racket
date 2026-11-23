#lang racket

;;;
;;; Navigation Tests
;;;

;; Checks Navigation tutorial behavior with focused regression tests.
;; This module guards the documentation's examples and support code against regressions.


;;;
;;; Imports and Exports
;;;

(require rackunit "model.rkt")

;;;
;;; Regression Checks
;;;

(module+ test
  (test-case "coordinate conversion round trips"
    (for* ([view (list home-view (view-state 2 40 -30) (view-state 1/4 -80 120))]
           [point initial-points])
      (define-values (sx sy)
        (model->screen view (control-point-x point) (control-point-y point)))
      (check-equal? (call-with-values (lambda () (screen->model view sx sy)) list)
                    (list (control-point-x point) (control-point-y point)))))
  (test-case "pan is in screen units, even when zoomed"
    (check-equal? (pan-view (view-state 3 40 50) 12 -7) (view-state 3 52 43)))
  (test-case "cursor anchor survives zoom and both zoom limits"
    (for* ([view (list home-view (view-state 3 80 -20))] [factor '(1/100 1/2 2 100)])
      (define next (zoom-at view 310 230 factor))
      (check-equal? (call-with-values (lambda () (screen->model view 310 230)) list)
                    (call-with-values (lambda () (screen->model next 310 230)) list))
      (check-true (<= minimum-zoom (view-state-zoom next) maximum-zoom))))
  (test-case "hit radius stays eighteen logical pixels"
    (for ([zoom '(1/4 1 4)])
      (define view (view-state zoom 30 70))
      (define-values (x y) (model->screen view 120 365))
      (check-equal? (hit-point initial-points view (+ x 18) y) 0)
      (check-false (hit-point initial-points view (+ x 19) y))))
  (test-case "pan and zoom never edit the points"
    (define before initial-points)
    (void (zoom-at (pan-view home-view 20 30) 80 90 2))
    (check-eq? before initial-points))
  (test-case "moving one point leaves the source model unchanged"
    (define moved (move-point initial-points 1 -25 600))
    (check-equal? (second moved) (control-point -25 600))
    (check-equal? (first moved) (first initial-points))
    (check-equal? (second initial-points) (control-point 240 150)))
  (test-case "the figure anchor stays attached to P1"
    (define point (second initial-points))
    (define next (zoom-at home-view 240 150 2))
    (check-equal? (call-with-values
                  (lambda () (model->screen next (control-point-x point)
                                                  (control-point-y point))) list)
                  '(240 150)))
  (test-case "P3 stays inside the translated introductory figure"
    (define next (pan-view home-view 50 30))
    (define point (fourth initial-points))
    (define-values (x y) (model->screen next (control-point-x point) (control-point-y point)))
    ;; Leave room for the right-hand label, not just the marker center.
    (check-true (< (+ x 60) 800))
    (check-true (< y 462)))
  (test-case "the coordinate diagram uses the forward mapping and its inverse"
    (define view (view-state 2 40 -30))
    (define-values (x y) (model->screen view 120 150))
    (check-equal? (list x y) '(280 270))
    (check-equal? (call-with-values (lambda () (screen->model view x y)) list) '(120 150)))
  (test-case "invalid zoom factors are rejected"
    (for ([factor (list 0 -1 +inf.0 +nan.0 'large)])
      (check-exn exn:fail:contract? (lambda () (zoom-at home-view 0 0 factor))))))
