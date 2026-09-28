#lang racket/base
;; Private diagnostic ledger. It stores detached values, never native pointers,
;; callbacks, images, or contexts. Native-internal driver stalls are not measured.
(provide current-gpu-io-ledger record-gpu-io!)
(define current-gpu-io-ledger (make-parameter #f))
(define (record-gpu-io! value)
  (define ledger (current-gpu-io-ledger))
  (when ledger (set-box! ledger (cons value (unbox ledger)))))
