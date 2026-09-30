#lang racket/base
;; UNSAFE: these inputs must be live Objective-C protocol objects. A protocol
;; check cannot make an arbitrary address, freed object or forged pointer safe.
(require "../private/gpu-metal-interop.rkt")
(provide make-metal-external-texture call-with-gpu-metal-device)
