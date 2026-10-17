#lang racket/base

;;;
;;; Raster Drawing Context
;;;

;; Exposes the Skia-backed raster drawing-context class and its capability query.
;; This opt-in entry point presents the supported Racket draw interface without exposing the private
;; class implementation.

;;;
;;; Imports and Exports
;;;

;; Opt-in Racket drawing compatibility. Do not re-export from skia/main:
;; callers choose this DC; no process-global drawing backend is replaced.
(require racket/class "private/dc-class.rkt" "private/dc-render.rkt" "private/dc-support.rkt"
         "private/dc-compatibility.rkt")
(provide skia-dc% skia-dc? skia-dc-capabilities skia-dc-compatibility
         (struct-out exn:fail:skia-dc:unsupported))

; skia-dc% : class?
;   Instantiates the shared drawing-context implementation with the raster Skia renderer.
(define skia-dc% (make-skia-dc-class skia-dc-renderer))

; skia-dc? : any/c -> boolean?
;   Returns whether v is an instance of skia-dc%.
(define (skia-dc? value) (is-a? value skia-dc%))

; skia-dc-capabilities : -> (and/c hash? immutable?)
;   Returns detached declarations for the historical raster-DC capability surface, including
;   supported drawing families and explicit exclusions.
(define skia-dc-capabilities dc-capabilities)
