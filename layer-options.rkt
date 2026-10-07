#lang racket/base
;; Detached m119 SaveLayerRec options. Paints/backdrops are supplied at use,
;; never hidden in a pure value or borrowed across application callbacks.
(require "private/check.rkt" "private/types.rkt")
(provide layer-options? make-layer-options layer-options-bounds layer-options-flags
         layer-options-preserve-lcd-text? layer-options-initialize-with-previous?
         layer-options-f16?)
(struct layer-options (bounds flags) #:transparent #:constructor-name make-options)
(define (checked-bounds who bounds)
  (cond
    [(not bounds) #f]
    [else
     (define xs (cond [(list? bounds) bounds] [(vector? bounds) (vector->list bounds)]
                      [else (raise-argument-error who "#f or (x y width height) list/vector" bounds)]))
     (unless (= (length xs) 4)
       (raise-argument-error who "four-element bounds" bounds))
     (define r (apply rect who xs))
     (vector-immutable (sk-rect-left r) (sk-rect-top r)
                       (- (sk-rect-right r) (sk-rect-left r))
                       (- (sk-rect-bottom r) (sk-rect-top r)))]))
(define (make-layer-options #:bounds [bounds #f]
                            #:preserve-lcd-text? [lcd? #f]
                            #:initialize-with-previous? [previous? #f]
                            #:f16? [f16? #f])
  (define who 'make-layer-options)
  (for ([flag (in-list (list lcd? previous? f16?))]) (boolean who flag))
  (make-options (checked-bounds who bounds)
                (bitwise-ior (if lcd? 2 0) (if previous? 4 0) (if f16? 16 0))))
(define (flag? who v bit)
  (unless (layer-options? v) (raise-argument-error who "layer-options?" v))
  (not (zero? (bitwise-and bit (layer-options-flags v)))))
(define (layer-options-preserve-lcd-text? v) (flag? 'layer-options-preserve-lcd-text? v 2))
(define (layer-options-initialize-with-previous? v) (flag? 'layer-options-initialize-with-previous? v 4))
(define (layer-options-f16? v) (flag? 'layer-options-f16? v 16))
(module* internals #f (provide checked-bounds))
