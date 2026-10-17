#lang racket/base

;;;
;;; DXGI Layout Probe
;;;

;; Prints the Racket FFI sizes used by the DXGI layout checks.
;; The Windows validation tools compare these values with structures compiled against the SDK.

;;;
;;; Imports and Exports
;;;
(require json "../private/gpu-dxgi-types.rkt")
(module+ main
  (check-dxgi-layouts!)
  (write-json (hasheq 'kind "racket-ffi-layouts" 'status "passed" 'sizes (dxgi-layout-sizes)))
  (newline))
