#lang racket/base

;;;
;;; Native GPU Context Control
;;;

;; Dispatches reset and resource-management operations to native Ganesh contexts.
;; Supplies the low-level bridge behind explicit GPU context control.

(require "gpu-native.rkt")
(provide context-control-dispatch/native)
; context-control-dispatch/native : any/c any/c ... -> any
;;   Routes the reviewed abandonment and resource-flush operations to their corresponding native
;;   entry points.
(define (context-control-dispatch/native operation . arguments)
  (apply
    (case operation
      [(abandoned?) gr_direct_context_is_abandoned]
      [(flush-surface) gr_direct_context_flush_surface]
      [(flush-image) gr_direct_context_flush_image]
      [(release-and-abandon) gr_direct_context_release_resources_and_abandon_context]
      [else (error 'gpu-context-control "unknown private native operation")])
    arguments))
