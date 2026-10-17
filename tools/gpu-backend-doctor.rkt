#lang racket/base

;;;
;;; Selected GPU Backend Diagnostic
;;;

;; Runs the backend-specific diagnostic chosen by command-line arguments.
;; This entry point gives external validation one dispatcher for supported GPU backends.

;;;
;;; Imports and Exports
;;;
;; This metadata command must also work with nonexistent native-library paths.
(require json "../gpu.rkt")
(module+ main
  (write-json
   (hasheq 'schema 1 'native_probe_performed #f
           'backends (map gpu-backend-capabilities (gpu-backends))))
  (newline))
