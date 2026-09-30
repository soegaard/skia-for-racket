#lang racket/base
;; Opt-in Racket drawing compatibility. Do not re-export from skia/main:
;; callers choose this DC; no process-global drawing backend is replaced.
(require racket/class "private/dc-class.rkt" "private/dc-render.rkt" "private/dc-support.rkt")
(provide skia-dc% skia-dc? skia-dc-capabilities
         (struct-out exn:fail:skia-dc:unsupported))
(define skia-dc% (make-skia-dc-class skia-dc-renderer))
(define (skia-dc? value) (is-a? value skia-dc%))
(define skia-dc-capabilities dc-capabilities)
