#lang racket/base

;;;
;;; GPU Transfer Tracing
;;;

;; Provides the shared hook for recording GPU transfer events.
;; Makes uploads and readbacks observable to diagnostics without changing their behavior.

;; Private diagnostic ledger. It stores detached values, never native pointers,
;; callbacks, images, or contexts. Native-internal driver stalls are not measured.
(provide current-gpu-io-ledger record-gpu-io!)
; current-gpu-io-ledger : parameter?
;;   Holds an optional diagnostic receiver for explicit upload, readback, and target-cache events.
(define current-gpu-io-ledger (make-parameter #f))
; record-gpu-io! : any/c -> void?
;;   Delivers a detached transfer event only when an I/O ledger has been installed.
(define (record-gpu-io! value)
  (define ledger (current-gpu-io-ledger))
  (when ledger (set-box! ledger (cons value (unbox ledger)))))
