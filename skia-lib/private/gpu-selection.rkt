#lang racket/base

;;;
;;; GPU Adapter Selection
;;;

;; Validates Direct3D adapter requests without loading GUI or native GPU code.
;; Context constructors and GUI backend selection share these limits and WARP rules.

(provide d3d12-selection!)

; d3d12-selection! : any/c any/c [#:who symbol?] -> void?
;   Checks the adapter kind and index before any device or window is created.
(define (d3d12-selection! adapter index #:who [who 'make-gpu-context])
  (unless (memq adapter '(hardware warp))
    (raise-argument-error who "'hardware or 'warp" adapter))
  (unless (and (exact-nonnegative-integer? index) (< index #xffffffff))
    (raise-argument-error who "adapter index in [0, 4294967294]" index))
  (when (and (eq? adapter 'warp) (not (zero? index)))
    (raise-arguments-error who "WARP has no selectable adapter index" "index" index))
  (void))
