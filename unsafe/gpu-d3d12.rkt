#lang racket/base
;; UNSAFE: inputs must be valid live COM pointers of the stated interface
;; types. QueryInterface cannot make an arbitrary/freed pointer safe.
(require "../private/gpu-d3d12-interop.rkt")
(provide make-d3d12-external-texture call-with-gpu-d3d12-device)
