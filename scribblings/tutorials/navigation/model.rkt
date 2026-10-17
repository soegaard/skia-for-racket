#lang racket

;;;
;;; Navigation Model
;;;

;; Models pan, zoom, coordinate conversion, and screen-sized point hit testing as pure data.
;; This native-free tutorial model is shared by its window/controller and pure regression tests.


;;;
;;; Imports and Exports
;;;

(provide (struct-out control-point)
         (struct-out view-state)
         initial-points home-view minimum-zoom maximum-zoom
         model->screen screen->model pan-view zoom-at hit-point move-point)

;; This module contains data and arithmetic only. It needs no native library.
;;;
;;; Drawing Data and Helpers
;;;

(struct control-point (x y) #:transparent)
;; x, y: real model-space coordinates, independent of screen pan and zoom.
;; Points are immutable. The list order is start, first handle, second handle, end.
;; Replacing one point preserves that order and never applies the view transform to stored data.
(struct view-state (zoom pan-x pan-y) #:transparent)
;; zoom: positive real scale from model units to screen units.
;; pan-x, pan-y: real screen-coordinate offsets applied after scaling.
;; All fields are immutable; pan-view and zoom-at return replacement view states.
;; zoom-at clamps scale between minimum-zoom and maximum-zoom; direct construction must
;; still supply a nonzero positive zoom so screen->model remains defined.

; initial-points : list?
;   Orders the cubic's start, first handle, second handle, and end in model coordinates.
(define initial-points
  (list (control-point 120 365) (control-point 240 150)
        (control-point 560 170) (control-point 680 365)))

; home-view : view-state?
;   Defines the unscaled, untranslated initial editor view.
(define home-view (view-state 1 0 0))

; minimum-zoom : real?
;   Sets the smallest scale accepted by interactive zoom updates.
(define minimum-zoom 1/4)

; maximum-zoom : exact-integer?
;   Sets the largest scale accepted by interactive zoom updates.
(define maximum-zoom 4)

; model->screen : view-state? real? real? -> (values real? real?)
;   Applies model scaling followed by screen-space pan and returns x then y.
(define (model->screen view x y)
  (values (+ (view-state-pan-x view) (* (view-state-zoom view) x))
          (+ (view-state-pan-y view) (* (view-state-zoom view) y))))

; screen->model : view-state? real? real? -> (values real? real?)
;   Inverts screen-space pan and zoom and returns model x then y.
(define (screen->model view x y)
  (values (/ (- x (view-state-pan-x view)) (view-state-zoom view))
          (/ (- y (view-state-pan-y view)) (view-state-zoom view))))

; pan-view : view-state? real? real? -> view-state?
;   Returns a view translated by the supplied screen-coordinate displacement.
(define (pan-view view dx dy)
  (struct-copy view-state view
               [pan-x (+ (view-state-pan-x view) dx)]
               [pan-y (+ (view-state-pan-y view) dy)]))

; zoom-at : view-state? real? real? real? -> view-state?
;   Clamps zoom while keeping the model point under the screen anchor fixed.
(define (zoom-at view screen-x screen-y factor)
  (unless (and (real? factor) (< 0 factor +inf.0))
    (raise-argument-error 'zoom-at "positive finite real" factor))
  (define-values (model-x model-y) (screen->model view screen-x screen-y))
  (define zoom
    (max minimum-zoom (min maximum-zoom (* factor (view-state-zoom view)))))
  (view-state zoom (- screen-x (* zoom model-x)) (- screen-y (* zoom model-y))))

; hit-point : list? view-state? real? real? [real?] -> (or/c exact-nonnegative-integer? #f)
;   Finds the nearest control point within a screen-sized hit radius.
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

; move-point : list? exact-nonnegative-integer? real? real? -> list?
;   Replaces one model-space control point without reordering the remaining points.
(define (move-point points index x y)
  (unless (and (exact-nonnegative-integer? index) (< index (length points)))
    (raise-argument-error 'move-point "valid point index" index))
  (for/list ([point (in-list points)] [i (in-naturals)])
    (if (= i index) (control-point x y) point)))
