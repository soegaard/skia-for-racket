#lang racket/base

;;;
;;; Raster Drawing Context
;;;

;; Exposes persistent and callback-scoped Skia-backed raster drawing contexts.
;; This opt-in entry point presents the supported Racket draw interface without exposing the private
;; class implementation.

;; Opt-in Racket drawing compatibility. Do not re-export from skia/main:
;; callers choose this DC; no process-global drawing backend is replaced.
(require racket/class "private/dc-class.rkt" "private/dc-render.rkt" "private/dc-support.rkt"
         "private/dc-compatibility.rkt")
(provide skia-dc% skia-dc? call-with-skia-dc skia-dc-capabilities skia-dc-compatibility
         (struct-out exn:fail:skia-dc:unsupported))

; skia-dc% : class?
;   Instantiates the shared drawing-context implementation with the raster Skia renderer.
(define skia-dc% (make-skia-dc-class skia-dc-renderer))

; call-with-skia-dc : exact-positive-integer? exact-positive-integer? procedure?
;   [#:backing-scale real?] [#:background (or/c string? (is-a?/c color%))]
;   [#:smoothing (or/c 'unsmoothed 'smoothed 'aligned)] -> any
;   Creates a raster DC for one callback and closes it on every exit, returning the callback's values.
(define (call-with-skia-dc width height proc
                           #:backing-scale [backing-scale 1.0]
                           #:background [background "white"]
                           #:smoothing [smoothing 'smoothed])
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1)
               (let-values ([(required allowed) (procedure-keywords proc)])
                 (null? required)))
    (raise-argument-error 'call-with-skia-dc
                          "procedure accepting one DC argument without required keywords" proc))
  (call-with-continuation-barrier
   (lambda ()
     (define dc #f)
     (define entered? #f)
     (dynamic-wind
      (lambda ()
        (when entered? (error 'call-with-skia-dc "an expired DC scope cannot be reentered"))
        (set! entered? #t)
        ;; Install the DC before breaks can escape past its cleanup.
        (parameterize-break #f
          (set! dc (new skia-dc% [width width] [height height]
                        [backing-scale backing-scale] [background background]
                        [smoothing smoothing]))))
      (lambda () (proc dc))
      (lambda () (parameterize-break #f (when dc (send dc close))))))))

; skia-dc? : any/c -> boolean?
;   Returns whether v is an instance of skia-dc%.
(define (skia-dc? value) (is-a? value skia-dc%))

; skia-dc-capabilities : -> (and/c hash? immutable?)
;   Returns detached declarations for the historical raster-DC capability surface, including
;   supported drawing families and explicit exclusions.
(define skia-dc-capabilities dc-capabilities)
