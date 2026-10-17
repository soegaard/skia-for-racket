#lang racket/base

;;;
;;; Live Stream Runtime Identity
;;;

;; Prints the runtime and native-library identity needed for live-stream validation receipts.
;; The callback validation workflow uses this probe to attribute evidence to the loaded binaries.

;;;
;;; Imports and Exports
;;;
(require json ffi/unsafe/os-thread "../private/native.rkt")
(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; p : path?
  ;   Records the loaded Skia native library path for cross-process stream-service identity checks.
  (define p (skia-native-library-path))
  (write-json (hasheq 'path (if (path? p) (path->string p) p)
                      'racket_version (version) 'vm (symbol->string (system-type 'vm))
                      'os_threads (os-thread-enabled?)))
  (newline))
