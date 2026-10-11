#lang racket

(provide (struct-out control-point)
         (struct-out view-state)
         initial-points home-view minimum-zoom maximum-zoom
         model->screen screen->model pan-view zoom-at hit-point move-point)

;; This module contains data and arithmetic only. It needs no native library.
(struct control-point (x y) #:transparent)
(struct view-state (zoom pan-x pan-y) #:transparent)

(define initial-points
  (list (control-point 120 365) (control-point 240 150)
        (control-point 560 170) (control-point 680 365)))
(define home-view (view-state 1 0 0))
(define minimum-zoom 1/4)
(define maximum-zoom 4)

(define (model->screen view x y)
  (values (+ (view-state-pan-x view) (* (view-state-zoom view) x))
          (+ (view-state-pan-y view) (* (view-state-zoom view) y))))

(define (screen->model view x y)
  (values (/ (- x (view-state-pan-x view)) (view-state-zoom view))
          (/ (- y (view-state-pan-y view)) (view-state-zoom view))))

(define (pan-view view dx dy)
  (struct-copy view-state view
               [pan-x (+ (view-state-pan-x view) dx)]
               [pan-y (+ (view-state-pan-y view) dy)]))

(define (zoom-at view screen-x screen-y factor)
  (unless (and (real? factor) (< 0 factor +inf.0))
    (raise-argument-error 'zoom-at "positive finite real" factor))
  (define-values (model-x model-y) (screen->model view screen-x screen-y))
  (define zoom
    (max minimum-zoom (min maximum-zoom (* factor (view-state-zoom view)))))
  (view-state zoom (- screen-x (* zoom model-x)) (- screen-y (* zoom model-y))))

(define (hit-point points view screen-x screen-y [screen-radius 18])
  (define-values (x y) (screen->model view screen-x screen-y))
  (define model-radius (/ screen-radius (view-state-zoom view)))
  (for/fold ([chosen #f] [nearest (sqr model-radius)] #:result chosen)
            ([point (in-list points)] [index (in-naturals)])
    (define distance (+ (sqr (- x (control-point-x point)))
                        (sqr (- y (control-point-y point)))))
    (if (<= distance nearest)
        (values index distance)
        (values chosen nearest))))

(define (move-point points index x y)
  (unless (and (exact-nonnegative-integer? index) (< index (length points)))
    (raise-argument-error 'move-point "valid point index" index))
  (for/list ([point (in-list points)] [i (in-naturals)])
    (if (= i index) (control-point x y) point)))
