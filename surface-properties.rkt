#lang racket/base

;;;
;;; Surface Properties
;;;

;; Describes native pixel geometry and supported surface-rendering flags.
;; This detached public configuration is shared by surface construction and native metadata queries
;; without retaining a drawing target.

;;;
;;; Imports and Exports
;;;

;; Detached values only. Importing this module never resolves native symbols.
(provide surface-properties? make-surface-properties
         surface-properties-pixel-geometry surface-properties-flags
         surface-properties-device-independent-fonts?
         surface-properties-dynamic-msaa? surface-properties-always-dither?
         surface-properties->jsexpr)
(struct surface-properties (pixel-geometry flags)
  #:transparent #:constructor-name properties)
;; A surface-properties value contains detached surface-rendering requests.
;;  - pixel-geometry  symbol?  'unknown, 'rgb-h, 'bgr-h, 'rgb-v, or 'bgr-v;
;;                            channel order and horizontal/vertical layout matter.
;;  - flags           exact nonnegative integer  Mask 1 requests device-independent
;;                                               fonts, 2 dynamic MSAA, and 4 dither.
;; Public construction permits only those enum values and flags. These are
;; requests, not evidence that a particular backend applies every option.

; geometries : (listof symbol?)
;   Lists the accepted native pixel-geometry names in enum order.
(define geometries '(unknown rgb-h bgr-h rgb-v bgr-v))

; make-surface-properties : [#:pixel-geometry (or/c 'unknown 'rgb-h 'bgr-h 'rgb-v 'bgr-v)]
;   [#:device-independent-fonts? boolean?] [#:dynamic-msaa? boolean?] [#:always-dither? boolean?] ->
;   surface-properties?
;   Creates a detached value.
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

; flag? : surface-properties? exact-positive-integer? -> boolean?
;   Tests one requested surface-property mask in a detached value.
(define (flag? p bit) (not (zero? (bitwise-and (surface-properties-flags p) bit))))

; surface-properties-device-independent-fonts? : surface-properties? -> boolean?
;   Reports whether the device-independent-fonts request is set.
(define (surface-properties-device-independent-fonts? p) (flag? p 1))

; surface-properties-dynamic-msaa? : surface-properties? -> boolean?
;   Reports whether the dynamic-MSAA request is set.
(define (surface-properties-dynamic-msaa? p) (flag? p 2))

; surface-properties-always-dither? : surface-properties? -> boolean?
;   Reports whether the always-dither request is set.
(define (surface-properties-always-dither? p) (flag? p 4))

; surface-properties->jsexpr : surface-properties? -> (and/c hash? immutable?)
;   Returns an immutable JSON-compatible hash with keys 'pixel_geometry, 'flags,
;   'device_independent_fonts, 'dynamic_msaa, and 'always_dither.
(define (surface-properties->jsexpr p)
  (hasheq 'pixel_geometry (symbol->string (surface-properties-pixel-geometry p))
          'flags (surface-properties-flags p)
          'device_independent_fonts (surface-properties-device-independent-fonts? p)
          'dynamic_msaa (surface-properties-dynamic-msaa? p)
          'always_dither (surface-properties-always-dither? p)))
(module* internals #f
  (provide properties->geometry-code properties-from-native)

  ; properties->geometry-code : surface-properties? -> exact-nonnegative-integer?
  ;   Maps pixel geometry to the pinned native enumeration.
  (define (properties->geometry-code p)
    (case (surface-properties-pixel-geometry p)
      [(unknown) 0] [(rgb-h) 1] [(bgr-h) 2] [(rgb-v) 3] [(bgr-v) 4]))

  ; properties-from-native : symbol? exact-integer? exact-integer? -> surface-properties?
  ;   Rejects unknown native flags or geometry codes before constructing detached surface properties.
  (define (properties-from-native who flags geometry)
    (unless (and (exact-integer? flags) (<= 0 flags 7)
                 (exact-integer? geometry) (<= 0 geometry 4))
      (error who "unreviewed native surface properties: flags ~a, geometry ~a" flags geometry))
    (properties (list-ref geometries geometry) flags)))
