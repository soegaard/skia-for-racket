#lang racket/base

;;;
;;; Advanced Canvas Fixtures
;;;

;; Provides shared inputs and drawing fixtures for save layers, native drawables, and specialized
;; canvases.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
(require "../main.rkt")
(provide advanced-width advanced-height advanced-url draw-advanced-vector draw-advanced-layer
         draw-advanced-backdrop draw-advanced-initialization)

;;;
;;; Fixtures and Assertions
;;;

; advanced-width : exact-positive-integer?
;   Sets the shared advanced-canvas scene width in pixels.
(define advanced-width 64)

; advanced-height : exact-positive-integer?
;   Sets the shared advanced-canvas scene height in pixels.
(define advanced-height 48)

; advanced-url : string?
;   Supplies a non-network annotation target for document-output checks.
(define advanced-url "https://example.invalid/advanced-canvases")

; rectangle : canvas? real? real? real? real? color -> void?
;   Draws an unantialiased filled rectangle for exact interior-pixel checks.
(define (rectangle c x y w h color)
  (with-skia ([p (make-paint #:color color #:antialias? #f)]) (draw-rect c x y w h p)))

; draw-advanced-vector : canvas? -> void?
;   Draws two opaque rectangles as the vector-output baseline.
(define (draw-advanced-vector c)
  (rectangle c 8 8 24 24 'red) (rectangle c 36 16 20 16 'blue))

; draw-advanced-layer : canvas? -> void?
;   Draws one half-opacity layer and a separate opaque comparison rectangle.
(define (draw-advanced-layer c)
  (with-skia ([p (make-paint #:color (rgba 0 0 0 128))])
    (call-with-canvas-layer-rec c (lambda () (rectangle c 8 8 24 24 'red)) #:paint p))
  (rectangle c 36 16 20 16 'blue))

; draw-advanced-initialization : canvas? -> void?
;   Exercises a layer initialized from prior pixels with source blending.
(define (draw-advanced-initialization c)
  (rectangle c 8 8 24 24 'red)
  (with-skia ([p (make-paint #:blend-mode 'src)])
    (call-with-canvas-layer-rec c void #:paint p
      #:options (make-layer-options #:initialize-with-previous? #t)))
  (rectangle c 36 16 20 16 'blue))

; draw-advanced-backdrop : canvas? -> void?
;   Offsets a clipped backdrop while leaving a separate rectangle unchanged.
(define (draw-advanced-backdrop c)
  (rectangle c 8 8 24 24 'red)
  (with-skia ([f (make-offset-image-filter 4 0)] [p (make-paint #:blend-mode 'src)])
    (call-with-canvas-layer-rec c void #:backdrop f #:paint p #:clip '(4 4 32 32)))
  (rectangle c 36 16 20 16 'blue))
