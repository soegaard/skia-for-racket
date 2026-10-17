#lang racket/base

;;;
;;; CI Runtime Identity
;;;

;; Prints the Racket version, VM, operating system, and architecture as structured evidence.
;; The CI runner uses this receipt to identify the runtime that performed its checks.

;;;
;;; Imports and Exports
;;;
;; No Skia/GUI dependency: validate the selected interpreter before installing.
(require json ffi/unsafe)
(module+ main
  (write-json
   (hasheq 'os (symbol->string (system-type 'os))
           'architecture (symbol->string (system-type 'arch))
           'vm (symbol->string (system-type 'vm))
           'version (version)
           'pointer_bytes (ctype-sizeof _pointer)))
  (newline))
