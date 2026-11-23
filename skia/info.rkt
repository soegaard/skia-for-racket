#lang info

(define collection 'multi)
(define version "0.79")
(define pkg-desc "Skia drawing and text shaping, with documentation and tutorials")
(define pkg-authors '(soegaard))
(define license 'MIT)
(define deps '(("base" #:version "8.18")
               ("skia-lib" #:version "0.79") ("skia-doc" #:version "0.79")))
(define build-deps '())
(define setup-collects '())
(define compile-omit-paths 'all)
(define test-omit-paths 'all)
