#lang racket/base

;;;
;;; Advanced Canvas Layers
;;;

;; Saves and scopes native canvas layers with explicit bounds, paint, and backdrop.
;; This public extension joins detached layer options to the core canvas lifetime
;; and audit machinery while protecting restoration across callback exits.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe "layer-options.rkt" (submod "layer-options.rkt" internals)
         "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/advanced-canvas-types.rkt" "private/check.rkt"
         "private/audit-trace.rkt"
         (submod "private/core.rkt" advanced-canvas-internals))
(provide canvas-save-layer-rec! call-with-canvas-layer-rec canvas-discard!)

;;;
;;; Native Layer Arguments
;;;

; layer-arguments : symbol? layer-options? (or/c #f paint?) (or/c #f image-filter?)
;                   -> (values any/c any/c any/c)
;   Validates layer inputs and returns optional native bounds and owned handles.
(define (layer-arguments who options paint backdrop)
  (unless (layer-options? options) (raise-argument-error who "layer-options?" options))
  (values (and (layer-options-bounds options)
               (apply rect who (vector->list (layer-options-bounds options))))
          (and paint (paint-h who paint)) (and backdrop (image-filter-h who backdrop))))

; save-layer : symbol? canvas? layer-options? any/c any/c any/c -> exact-integer?
;   Saves the native layer while pinning dependencies and reporting its audit flags.
(define (save-layer who c options bounds ph bh)
  (define handles (append (if ph (list ph) '()) (if bh (list bh) '())))
  (call-on-canvas who c handles
    (lambda (cp . ps)
      (define pp (and ph (car ps)))
      (define bp (and bh (if ph (cadr ps) (car ps))))
      (define flags (layer-options-flags options))
      (define rec (make-sk-save-layer-rec bounds pp bp flags))
      (call-with-audit-layer-rec flags (and bh #t)
        (lambda ()
          (begin0 (sk_canvas_save_layer_rec cp rec)
            (void/reference-sink rec bounds ps options)))))))
;;;
;;; Public Layer Operations
;;;

; canvas-save-layer-rec! : canvas? [#:options layer-options?]
;                          [#:paint (or/c #f paint?)]
;                          [#:backdrop (or/c #f image-filter?)] -> exact-integer?
;   Pushes an explicitly configured layer and returns the prior canvas save count.
(define (canvas-save-layer-rec! c #:options [options (make-layer-options)]
                                #:paint [paint #f] #:backdrop [backdrop #f])
  (define who 'canvas-save-layer-rec!)
  (define-values (bounds ph bh) (layer-arguments who options paint backdrop))
  (save-layer who c options bounds ph bh))

; call-with-canvas-layer-rec : canvas? (-> any) [#:options layer-options?]
;                             [#:paint (or/c #f paint?)]
;                             [#:backdrop (or/c #f image-filter?)]
;                             [#:clip (or/c #f list? vector?)] -> any
;   Runs a callback in a protected layer and composites it when the scope exits.
(define (call-with-canvas-layer-rec c thunk #:options [options (make-layer-options)]
                                    #:paint [paint #f] #:backdrop [backdrop #f]
                                    #:clip [clip #f])
  (define who 'call-with-canvas-layer-rec)
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0)
               (let-values ([(required allowed) (procedure-keywords thunk)]) (null? required)))
    (raise-argument-error who "procedure accepting zero arguments without required keywords" thunk))
  (define-values (bounds ph bh) (layer-arguments who options paint backdrop))
  (define checked-clip (checked-bounds who clip))
  (define owner (canvas-owner who c))
  (define (run)
    (define old-count #f)
    (define entered? #f)
    (call-with-continuation-barrier
      (lambda ()
        (dynamic-wind
          (lambda ()
            (when entered? (error who "layer scope cannot be reentered"))
            (parameterize-break #f
              (set! old-count (save-layer who c options bounds ph bh))
              (set-owner-floors! owner (cons (add1 old-count) (owner-floors owner)))
              (pin-canvas-owner! owner)
              (set! entered? #t)))
          thunk
          (lambda ()
            (parameterize-break #f
              ;; Composite even on a callback exception, exactly like the
              ;; existing layer helper. State cleanup is not pixel rollback.
              (dynamic-wind void
                (lambda ()
                  (call-on-canvas who c '()
                    (lambda (cp) (sk_canvas_restore_to_count cp old-count))))
                (lambda ()
                  (set-owner-floors! owner (cdr (owner-floors owner)))
                  (unpin-canvas-owner! owner)))))))))
  (if checked-clip
      (call-with-canvas-state c
        (lambda () (apply canvas-clip-rect! c (vector->list checked-clip)) (run)))
      (run)))

; canvas-discard! : canvas? -> void?
;   Marks prior canvas contents as disposable before a complete overwrite.
(define (canvas-discard! c)
  ;; Discard is a content-invalidating optimization hint, NOT a clear. A
  ;; complete overwrite must precede any subsequent use of discarded pixels.
  (call-on-canvas 'canvas-discard! c '() sk_canvas_discard))
