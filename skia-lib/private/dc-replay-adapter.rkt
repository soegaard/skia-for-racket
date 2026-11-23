#lang racket/base

;;;
;;; Drawing Context Style Leases
;;;

;; Tracks selected pen and brush styles through replayable leases.
;; Keeps drawing-context style snapshots consistent during output capture and replay.

;; Isolate the private member identities used by racket/draw's replay and
;; pen/brush locking protocols. No Cairo context is created or borrowed here.

;;;
;;; Imports and Exports
;;;

(require racket/class
         (only-in ffi/unsafe register-finalizer)
         (only-in ffi/unsafe/atomic call-as-atomic)
         (only-in racket/draw/private/dc
                  [do-set-pen! replay-set-pen!] [do-set-brush! replay-set-brush!])
         (only-in racket/draw/private/local adjust-lock))
(provide dc-replay-mixin make-dc-style-lease dc-style-select! dc-style-release!)

;;;
;;; Replay Identities and Selection Locks
;;;

; dc-replay-mixin : class? -> class?
;   Routes racket/draw's private replay member identities through the DC's validated pen and brush
;   setters.
(define (dc-replay-mixin %)
  (class %
    (super-new)
    ;; These are the actual local-member identities, not public symbols with
    ;; the same spelling. Route replay through the normal validation/locking.
    (define/public (replay-set-pen! p) (send this set-pen p))
    (define/public (replay-set-brush! b) (send this set-brush b))))

; make-dc-style-lease : object? -> vector?
;   Creates weak pen/brush slots in that order and releases their locks when the owning DC is
;   collected.
(define (make-dc-style-lease dc)
  (define lease (vector #f #f))
  ;; Do not keep selected-object -> DC cycles alive through the finalizer.
  (register-finalizer dc (lambda (_dc) (dc-style-release! lease)))
  lease)

; selected : vector? (or/c 0 1) -> (or/c #f object?)
;   Resolves a live weak selection from pen slot zero or brush slot one.
(define (selected lease slot)
  (define w (vector-ref lease slot)) (and w (weak-box-value w)))

; dc-style-select! : vector? (or/c 0 1) object? procedure? procedure? -> void?
;   Atomically validates and locks a replacement style, unlocks the previous selection, and commits
;   DC state.
(define (dc-style-select! lease slot object validate commit)
  (call-as-atomic
   (lambda ()
     (validate object) ; validation and locking cannot race a thread mutation
     (define old (selected lease slot))
     (unless (eq? old object)
       (send object adjust-lock 1)
       (when old (send old adjust-lock -1))
       (vector-set! lease slot (make-weak-box object)))
     (commit object)))
  (void))

; dc-style-release! : vector? -> void?
;   Clears both weak selection slots and releases each still-live pen or brush lock.
(define (dc-style-release! lease)
  (call-as-atomic
   (lambda ()
     (for ([slot (in-range 2)])
       (define old (selected lease slot))
       (vector-set! lease slot #f)
       (when old (send old adjust-lock -1)))))
  (void))
