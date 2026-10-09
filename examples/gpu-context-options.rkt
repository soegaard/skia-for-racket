#lang racket/base
;; A native-free configuration example; real selected GPU use is tested by
;; tests/gpu-context-control-gpu-test.rkt and its independent inspector.
(require json "../gpu-context-options.rkt")
(define options
  (make-gpu-context-options #:runtime-program-cache-size 128
                            #:glyph-cache-texture-maximum-bytes (* 4 1024 1024)
                            #:allow-path-mask-caching? #f))
(module+ main (write-json (gpu-context-options->jsexpr options)) (newline))
