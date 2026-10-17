#lang racket/base

;;;
;;; Pict Bridge Example
;;;

;; Converts a Skia surface through the pict bridge and saves a Racket bitmap.
;; This is an example-suite client of the project's drawing APIs, not library implementation.


;; Run with: racket examples/pict-bridge.rkt output/pict-bridge.png
;;;
;;; Imports and Exports
;;;

(require racket/class racket/cmdline
         (prefix-in pict: pict)
         skia skia/pict)

;;;
;;; Drawing Data and Helpers
;;;

; output-file : path-string?
;   Selects the destination used by this example's output.
(define output-file
  (command-line
   #:program "pict-bridge"
   #:args (filename)
   filename))

; picture : pict?
;   Retains a pict whose copied bitmap outlives the closed Skia surface.
(define picture
  (with-skia ([surface (make-surface 240 140 #:background 'white)]
              [blue (make-paint #:color 'blue #:antialias? #t)]
              [orange (make-paint #:color 'orange #:antialias? #t)])
    (define canvas (surface-canvas surface))
    (draw-circle canvas 70 70 45 blue)
    (draw-rounded-rect canvas 115 35 90 70 12 12 orange)
    ;; The pict owns a copied bitmap after this scope closes the surface.
    (surface->pict surface #:backing-scale 2)))

; bitmap : (is-a?/c bitmap%)
;   Retains the Racket bitmap used by the interoperability example.
(define bitmap (pict:pict->bitmap picture))
(unless (send bitmap save-file output-file 'png)
  (error 'pict-bridge "could not write PNG: ~a" output-file))
