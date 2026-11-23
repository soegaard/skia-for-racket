#lang racket/base

;;;
;;; GPU Output Fixtures
;;;

;; Provides shared inputs and drawing fixtures for bounded GPU raster fallbacks within vector
;; documents.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
(require "../main.rkt")
(provide output-probe-names output-probe-width output-probe-height output-probe-padding
         output-probe-scale output-document-width output-document-height
         draw-output-probe draw-output-document)

;;;
;;; Fixtures and Assertions
;;;

; output-probe-names : (listof symbol?)
;   Lists pattern, effects, perspective, and nested document-fallback scenes.
(define output-probe-names '(pattern effects perspective nested))

; output-probe-width : exact-positive-integer?
;   Sets the fixture width in pixels for drawing and storage-layout checks.
(define output-probe-width 120)

; output-probe-height : exact-positive-integer?
;   Sets the fixture height in pixels for drawing and storage-layout checks.
(define output-probe-height 72)

; output-probe-padding : (listof real?)
;   Specifies asymmetric left, top, right, and bottom padding for placement checks.
(define output-probe-padding '(8 10 12 14))

; output-probe-scale : positive-real?
;   Uses a fractional rasterization scale to expose incorrect rounding or offset calculations.
(define output-probe-scale 3/2)

; output-document-width : exact-positive-integer?
;   Sets the fixture width in pixels for drawing and storage-layout checks.
(define output-document-width 240)

; output-document-height : exact-positive-integer?
;   Sets the fixture height in pixels for drawing and storage-layout checks.
(define output-document-height 180)

; rect : canvas? real? real? real? real? color -> void?
;   Draws an unantialiased colored rectangle for stable document landmarks.
(define (rect c x y w h color)
  (with-skia ([p (make-paint #:color color #:antialias? #f)]) (draw-rect c x y w h p)))

; markers : canvas? -> void?
;   Draws four distinct edge markers to expose cropping, padding, and placement errors.
(define (markers c)
  (rect c 0 0 8 6 (rgb 255 0 0))
  (rect c 112 0 8 10 (rgb 0 255 0))
  (rect c 0 60 12 12 (rgb 0 0 255))
  (rect c 108 64 12 8 (rgb 255 255 0)))

; draw-output-probe : canvas? symbol? -> any
;   Draws the selected raster-fallback workload and its placement landmarks.
(define (draw-output-probe c name)
  (case name
    [(pattern) (rect c 16 16 56 32 (rgba 128 0 0 128))]
    [(effects nested)
     (with-skia ([effect (make-runtime-effect
                         "half4 main(float2 p) { return half4(0.15+0.005*p.x, 0.55, 0.65, 1); }")]
                 [shader (runtime-effect->shader effect)]
                 [paint (make-paint #:shader shader)]
                 [shadow (make-drop-shadow-image-filter 3 4 3 3 (rgba 0 0 0 120))]
                 [disk (make-paint #:color "#E79536" #:image-filter shadow)])
       (draw-rounded-rect c 18 12 70 35 7 7 paint)
       (draw-circle c 84 45 18 disk))]
    [(perspective)
     (with-skia ([p (make-paint #:color (rgba 24 130 184 210))])
       (with-canvas-state c
         (canvas-concat-matrix3! c (matrix3-perspective 0.003 0.002))
         (draw-rounded-rect c 20 14 84 54 10 10 p)))]
    [else (error 'draw-output-probe "unknown fixture: ~a" name)])
  (markers c))

;; A real vector page around exactly one bounded embedded raster. The nested
;; case rasterizes its inner child and replays the outer group natively.

; draw-output-document : canvas? symbol? output-raster-executor? box? -> any
;   Embeds the workload in a larger document while recording raster-executor calls.
(define (draw-output-document c name executor calls)
  (rect c 0 0 output-document-width output-document-height 'white)
  (with-skia ([font (make-font #:size 14 #:hinting 'none)]
              [ink (make-paint #:color "#17354B")]
              [stroke (make-paint #:color "#17354B" #:style 'stroke #:stroke-width 1)])
    (draw-simple-text c "Bounded GPU fallback" 20 28 font ink)
    (draw-line c 20 34 216 34 ink)
    (draw-rect c 31 43 142 98 stroke)
    (canvas-annotate-url! c 20 14 170 18 "https://example.org/gpu-output")
    (draw-output-group c 40 54 output-probe-width output-probe-height
      (lambda (g)
        (set-box! calls (add1 (unbox calls)))
        (if (eq? name 'nested)
            (draw-output-group g 0 0 output-probe-width output-probe-height
              (lambda (inner)
                (set-box! calls (add1 (unbox calls)))
                (draw-output-probe inner 'effects))
              #:padding output-probe-padding #:scale output-probe-scale #:label "inner-effects")
            (draw-output-probe g name)))
      #:policy (if (eq? name 'pattern) 'raster 'prefer-vector)
      #:padding output-probe-padding #:scale output-probe-scale
      #:raster-executor executor #:label (symbol->string name))))
