#lang racket/base

;;;
;;; Float Pixel Fixtures
;;;

;; Provides shared inputs and drawing fixtures for floating-point pixel storage, colors, and
;; conversion.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
(require "../main.rkt")
(provide float-fixture-info with-float-buffer float-scene-names draw-float-scene
         make-float-fixture-buffer make-float-fixture-image)

;;;
;;; Fixtures and Assertions
;;;

; float-fixture-info : symbol? [exact-positive-integer? exact-positive-integer? symbol? any/c] ->
; image-info?
;   Builds explicit float storage metadata for size, alpha interpretation, and color space.
(define (float-fixture-info format [width 64] [height 32] [alpha 'premul] [space 'srgb])
  (make-image-info width height #:color-type format #:alpha-type alpha #:color-space space))

; with-float-buffer : symbol? procedure? [#:width exact-positive-integer? #:height
; exact-positive-integer? #:alpha-type symbol? #:color-space any/c] -> any
;   Scopes a float raster buffer with the requested storage interpretation.
(define (with-float-buffer format proc #:width [width 4] #:height [height 2]
                           #:alpha-type [alpha 'premul] #:color-space [space 'srgb])
  (with-skia ([b (make-raster-buffer-from-info (float-fixture-info format width height alpha space))])
    (proc b)))

; float-scene-names : (listof symbol?)
;   Lists clear and shader scenes used for CPU/GPU float-color comparisons.
(define float-scene-names '(clear solid linear radial sweep conical))

; draw-float-scene : symbol? canvas? -> any
;   Draws a shared floating-color scene without converting its colors to byte arguments.
(define (draw-float-scene name canvas)
  (define fixed (make-color4f 0.125 0.375 0.625))
  (define same (list fixed fixed))
  (case name
    [(clear) (canvas-clear-color4f! canvas fixed)]
    [else
     (define shader
       (case name
         [(solid) (make-color4f-shader fixed #:color-space 'srgb)]
         [(linear) (make-linear-gradient-color4f-shader '(0 0) '(64 0)
                     (list (make-color4f 0.25 0.5 0.75) (make-color4f 0.75 0.5 0.25)) #:color-space
                     'srgb)]
         [(radial) (make-radial-gradient-color4f-shader '(32 16) 128 same #:color-space 'srgb)]
         [(sweep) (make-sweep-gradient-color4f-shader '(32 16) same #:color-space 'srgb)]
         [(conical)
           (make-two-point-conical-gradient-color4f-shader '(32 16) 0 '(32 16) 128 same
             #:color-space 'srgb)]
         [else (error 'draw-float-scene "unknown scene")]))
     (call-with-skia-resource shader
       (lambda (s)
         (with-skia ([p (make-paint #:shader s #:antialias? #f)])
           (draw-rect canvas 0 0 64 32 p))))]))

; make-float-fixture-buffer : symbol? symbol? -> raster-buffer?
;   Creates an owned float buffer containing the requested sample or drawing scene.
(define (make-float-fixture-buffer format scene)
  (define b (make-raster-buffer-from-info (float-fixture-info format)))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! b) (raise e))])
    (case scene
      [(samples)
       (call-with-raster-buffer-pixmap b
         (lambda (p)
           (for* ([y (in-range 32)] [x (in-range 64)])
             (pixmap-set-sample! p x y
               (cond [(< x 16) '#(1.5 -0.25 0.5 1)] [(< x 32) '#(0.25 0.5 0.75 1)]
                     [(< x 48) '#(0.5009765625 0.5 0.5 1)] [else '#(0.125 0.875 0.375 1)]))))
         #:writable? #t)]
      [(linear) (call-with-raster-buffer-canvas b (lambda (c) (draw-float-scene 'linear c)))]
      [else (error 'make-float-fixture-buffer "unknown scene")])
    b))

; make-float-fixture-image : symbol? symbol? -> image?
;   Converts the float fixture explicitly to an sRGB integer image for ordinary output.
(define (make-float-fixture-image format scene)
  (with-skia ([source (make-float-fixture-buffer format scene)]
              [integer (raster-buffer-convert source (make-image-info 64 32 #:color-space 'srgb))])
    ;; Explicit conversion is the sole precision/quantization boundary here.
    (raster-buffer->image integer)))
