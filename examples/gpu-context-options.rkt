#lang racket/base

;;;
;;; GPU Context Options Example
;;;

;; Builds GPU context options without opening a native GPU context.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; A native-free configuration example; real selected GPU use is tested by
;; tests/gpu-context-control-gpu-test.rkt and its independent inspector.
;;;
;;; Imports and Exports
;;;

(require json "../gpu-context-options.rkt")
;;;
;;; Drawing Data and Helpers
;;;

; options : gpu-context-options?
;;   Collects the explicit GPU context settings demonstrated by this example.
(define options
  (make-gpu-context-options #:runtime-program-cache-size 128
                            #:glyph-cache-texture-maximum-bytes (* 4 1024 1024)
                            #:allow-path-mask-caching? #f))
;;;
;;; Command-Line Entry Point
;;;

(module+ main (write-json (gpu-context-options->jsexpr options)) (newline))
