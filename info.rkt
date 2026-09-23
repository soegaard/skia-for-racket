#lang info
(define collection "skia")
(define version "0.2.0")
(define pkg-desc "Experimental standalone CPU Skia drawing and simple text through the SkiaSharp C ABI")
(define deps '(("base" #:version "8.7") "draw-lib"))
(define build-deps '("rackunit-lib"))
(define license 'MIT)
(define test-omit-paths '("examples" "tools" "native"))
(define compile-omit-paths '("native"))
