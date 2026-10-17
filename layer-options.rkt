#lang racket/base

;;;
;;; Canvas Layer Options
;;;

;; Describes optional layer bounds and the supported native SaveLayerRec flags.
;; These detached public values configure the layer operations in
;; advanced-layers.rkt without retaining paints, filters, or canvas ownership.

;; Detached m119 SaveLayerRec options. Paints/backdrops are supplied at use,
;; never hidden in a pure value or borrowed across application callbacks.

;;;
;;; Imports and Exports
;;;

(require "private/check.rkt" "private/types.rkt")
(provide layer-options? make-layer-options layer-options-bounds layer-options-flags
         layer-options-preserve-lcd-text? layer-options-initialize-with-previous?
         layer-options-f16?)
;;;
;;; Layer Representation and Construction
;;;

(struct layer-options (bounds flags) #:transparent #:constructor-name make-options)
;; A layer-options value contains only copied bounds and an integer flag mask.
;;  - bounds  #f or immutable vector  Local x, y, width, and height in that order;
;;                                   extents are nonnegative and values fit the
;;                                   native drawing-scalar range.
;;  - flags   exact-nonnegative-integer?  Mask 2 preserves LCD text, mask 4 copies
;;                                      previous content, and mask 16 requests F16.
;; Public construction validates bounds and permits only those three flag bits.

; checked-bounds : symbol? (or/c #f list? vector?) -> (or/c #f vector?)
;;   Copies optional position-and-size bounds into validated native coordinates.
(define (checked-bounds who bounds)
  (cond
    [(not bounds) #f]
    [else
     (define xs (cond [(list? bounds) bounds] [(vector? bounds) (vector->list bounds)]
                      [else
                       (raise-argument-error who "#f or (x y width height) list/vector" bounds)]))
     (unless (= (length xs) 4)
       (raise-argument-error who "four-element bounds" bounds))
     (define r (apply rect who xs))
     (vector-immutable (sk-rect-left r) (sk-rect-top r)
                       (- (sk-rect-right r) (sk-rect-left r))
                       (- (sk-rect-bottom r) (sk-rect-top r)))]))
; make-layer-options : [#:bounds (or/c #f list? vector?)]
;                      [#:preserve-lcd-text? boolean?]
;                      [#:initialize-with-previous? boolean?]
;                      [#:f16? boolean?] -> layer-options?
;;   Constructs the bounds and flag mask used when saving a canvas layer.
(define (make-layer-options #:bounds [bounds #f]
                            #:preserve-lcd-text? [lcd? #f]
                            #:initialize-with-previous? [previous? #f]
                            #:f16? [f16? #f])
  (define who 'make-layer-options)
  (for ([flag (in-list (list lcd? previous? f16?))]) (boolean who flag))
  (make-options (checked-bounds who bounds)
                (bitwise-ior (if lcd? 2 0) (if previous? 4 0) (if f16? 16 0))))
;;;
;;; Flag Queries
;;;

; flag? : symbol? layer-options? exact-positive-integer? -> boolean?
;;   Checks whether an options value contains the requested native flag bit.
(define (flag? who v bit)
  (unless (layer-options? v) (raise-argument-error who "layer-options?" v))
  (not (zero? (bitwise-and bit (layer-options-flags v)))))
; layer-options-preserve-lcd-text? : layer-options? -> boolean?
;;   Reports whether the saved layer requests preservation of LCD text.
(define (layer-options-preserve-lcd-text? v) (flag? 'layer-options-preserve-lcd-text? v 2))
; layer-options-initialize-with-previous? : layer-options? -> boolean?
;;   Reports whether the layer begins with the previous canvas contents.
(define (layer-options-initialize-with-previous? v)
  (flag? 'layer-options-initialize-with-previous? v 4))
; layer-options-f16? : layer-options? -> boolean?
;;   Reports whether the saved layer requests a floating-point backing format.
(define (layer-options-f16? v) (flag? 'layer-options-f16? v 16))
(module* internals #f (provide checked-bounds))
