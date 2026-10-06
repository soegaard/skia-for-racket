#lang racket/base
;; Detached values only. Importing this module never resolves native symbols.
(provide surface-properties? make-surface-properties
         surface-properties-pixel-geometry surface-properties-flags
         surface-properties-device-independent-fonts?
         surface-properties-dynamic-msaa? surface-properties-always-dither?
         surface-properties->jsexpr)
(struct surface-properties (pixel-geometry flags)
  #:transparent #:constructor-name properties)
(define geometries '(unknown rgb-h bgr-h rgb-v bgr-v))
(define (make-surface-properties #:pixel-geometry [geometry 'unknown]
                                 #:device-independent-fonts? [fonts? #f]
                                 #:dynamic-msaa? [msaa? #f]
                                 #:always-dither? [dither? #f])
  (unless (memq geometry geometries)
    (raise-argument-error 'make-surface-properties
                          "'unknown, 'rgb-h, 'bgr-h, 'rgb-v or 'bgr-v" geometry))
  (for ([v (in-list (list fonts? msaa? dither?))])
    (unless (boolean? v) (raise-argument-error 'make-surface-properties "boolean?" v)))
  (properties geometry (+ (if fonts? 1 0) (if msaa? 2 0) (if dither? 4 0))))
(define (flag? p bit) (not (zero? (bitwise-and (surface-properties-flags p) bit))))
(define (surface-properties-device-independent-fonts? p) (flag? p 1))
(define (surface-properties-dynamic-msaa? p) (flag? p 2))
(define (surface-properties-always-dither? p) (flag? p 4))
(define (surface-properties->jsexpr p)
  (hasheq 'pixel_geometry (symbol->string (surface-properties-pixel-geometry p))
          'flags (surface-properties-flags p)
          'device_independent_fonts (surface-properties-device-independent-fonts? p)
          'dynamic_msaa (surface-properties-dynamic-msaa? p)
          'always_dither (surface-properties-always-dither? p)))
(module* internals #f
  (provide properties->geometry-code properties-from-native)
  (define (properties->geometry-code p)
    (case (surface-properties-pixel-geometry p)
      [(unknown) 0] [(rgb-h) 1] [(bgr-h) 2] [(rgb-v) 3] [(bgr-v) 4]))
  (define (properties-from-native who flags geometry)
    (unless (and (exact-integer? flags) (<= 0 flags 7)
                 (exact-integer? geometry) (<= 0 geometry 4))
      (error who "unreviewed native surface properties: flags ~a, geometry ~a" flags geometry))
    (properties (list-ref geometries geometry) flags)))
