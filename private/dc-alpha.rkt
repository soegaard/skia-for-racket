#lang racket/base

;;;
;;; Drawing Context Alpha Layers
;;;

;; Tracks nested transparency layers and their temporary render targets.
;; Implements racket/draw alpha-layer semantics for Skia-backed drawing contexts.

;; Pure ownership/opacity controller for persistent raster alpha groups.
;; The production renderer supplies synchronous CPU allocation/compositing.
;;;
;;; Exports
;;;

(provide make-dc-alpha dc-alpha-target dc-alpha-root dc-alpha-root-alpha dc-alpha-depth dc-alpha-clip
         dc-alpha-set-clip! dc-alpha-start! dc-alpha-end! dc-alpha-discard! dc-alpha-close!)
;;;
;;; Saved Layer State
;;;

(struct layer (parent parent-clip old-alpha opacity) #:transparent)
;; Fields:
;;   parent: previous renderer target, retained while its child is active. parent-clip: saved #f
;;   or dc-clip. old-alpha: previous per-draw alpha in [0,1]. opacity: layer opacity in [0,1].
;;   Merge multiplies old-alpha by opacity and restores parent state in last-in, first-out order.

(struct alpha-state ([root #:mutable] [target #:mutable] [clip #:mutable] [layers #:mutable]
                          width height create release composite limit [closed? #:mutable]))
;; Fields:
;;   root and target: mutable root/current renderer targets, cleared to #f after closure. clip:
;;   #f or the current detached dc-clip. layers: mutable list of layer records, innermost first.
;;   width and height: positive exact target pixel dimensions shared by every layer.
;;   create: (width height -> target); release: (target -> void); composite: #f or
;;   (parent child clip opacity -> void). limit: zero-argument procedure returning the current
;;   byte budget. closed?: mutable boolean. Each target uses the renderer's representation and is
;;   released once; ending/discarding a layer never releases its still-owned parent.

;;;
;;; Target Access and Layer Transitions
;;;

; make-dc-alpha : any/c exact-positive-integer? exact-positive-integer? procedure? procedure? (or/c #f
; procedure?) procedure? -> alpha-state?
;   Takes ownership of the root target and records renderer callbacks plus a thunk for the current
;   byte limit.
(define (make-dc-alpha root width height create release composite limit)
  (alpha-state root root #f '() width height create release composite limit #f))

; live! : symbol? alpha-state? -> void?
;   Rejects access after the controller has released its root and temporary targets.
(define (live! who s)
  (when (alpha-state-closed? s) (error who "alpha target is closed")))

; dc-alpha-root : alpha-state? -> any/c
;   Returns the live root target, excluding unfinished alpha groups from snapshots.
(define (dc-alpha-root s) (live! 'snapshot s) (alpha-state-root s))

; dc-alpha-target : alpha-state? -> any/c
;   Returns the live target receiving draws, which may be the innermost isolated layer.
(define (dc-alpha-target s) (live! 'draw s) (alpha-state-target s))

; dc-alpha-root-alpha : alpha-state? real? -> real?
;   Returns the outermost saved per-draw alpha, or the supplied current alpha when no layer is open.
(define (dc-alpha-root-alpha s current-alpha)
  (live! 'root-alpha s)
  (if (null? (alpha-state-layers s)) current-alpha
      (layer-old-alpha (car (reverse (alpha-state-layers s))))))

; dc-alpha-depth : alpha-state? -> exact-nonnegative-integer?
;   Counts open isolated layers, excluding the root target.
(define (dc-alpha-depth s) (length (alpha-state-layers s)))

; dc-alpha-clip : alpha-state? -> (or/c #f dc-clip?)
;   Returns the active target's clip; #f means no clipping constraint.
(define (dc-alpha-clip s) (live! 'clip s) (alpha-state-clip s))

; dc-alpha-set-clip! : alpha-state? (or/c #f dc-clip?) -> void?
;   Replaces the active clip without changing clips saved by enclosing layers.
(define (dc-alpha-set-clip! s clip)
  (live! 'set-clipping-region s) (set-alpha-state-clip! s clip) (void))

; opacity! : symbol? any/c -> void?
;   Rejects alpha values outside the finite interval from zero through one.
(define (opacity! who a)
  (unless (and (real? a) (<= 0 a 1))
    (raise-argument-error who "finite real in [0,1]" a)))

; dc-alpha-start! : alpha-state? real? real? -> real?
;   Allocates a budgeted child, saves the parent state, and returns 1.0 for the child's initial draw
;   alpha.
(define (dc-alpha-start! s opacity old-alpha)
  (live! 'start-alpha s)
  (opacity! 'start-alpha opacity) (opacity! 'start-alpha old-alpha)
  (unless (alpha-state-composite s)
    (error 'start-alpha "renderer does not support alpha groups"))
  ;; Bound the root plus every live full-sized RGBA layer. Snapshots retained
  ;; by clients and driver/allocator overhead are outside this storage budget.
  (define bytes (* 4 (alpha-state-width s) (alpha-state-height s)
                   (+ 2 (dc-alpha-depth s))))
  (when (> bytes ((alpha-state-limit s)))
    (raise-arguments-error 'start-alpha "root and alpha layers exceed current-skia-byte-limit"
                           "required bytes" bytes "limit" ((alpha-state-limit s))))
  (parameterize-break #f
    (define child ((alpha-state-create s) (alpha-state-width s) (alpha-state-height s)))
    (unless child (error 'start-alpha "renderer returned no alpha surface"))
    ;; Allocation must succeed before any DC state changes.
    (set-alpha-state-layers! s
      (cons (layer (alpha-state-target s) (alpha-state-clip s) old-alpha opacity)
            (alpha-state-layers s)))
    (set-alpha-state-target! s child)
    ;; Like racket/draw's independent group context: the parent clip applies
    ;; at merge, not once per overlapping draw AND again at merge.
    (set-alpha-state-clip! s #f))
  1.0)

; dc-alpha-end! : alpha-state? procedure? -> void?
;   Pops and composites the innermost child, restoring parent alpha and releasing the child even on
;   failure.
(define (dc-alpha-end! s restore-alpha!)
  (live! 'end-alpha s)
  (unless (null? (alpha-state-layers s))
    (parameterize-break #f
      (define frame (car (alpha-state-layers s)))
      (define child (alpha-state-target s))
      ;; Pop first: even failed compositing cannot be retried and doubled.
      (set-alpha-state-layers! s (cdr (alpha-state-layers s)))
      (set-alpha-state-target! s (layer-parent frame))
      (set-alpha-state-clip! s (layer-parent-clip frame))
      (restore-alpha! (layer-old-alpha frame))
      (dynamic-wind
       void
       (lambda ()
         ((alpha-state-composite s) (layer-parent frame) child
          (layer-parent-clip frame) (* (layer-old-alpha frame) (layer-opacity frame))))
       (lambda () ((alpha-state-release s) child)))))
  (void))

; release-targets! : alpha-state? list? -> void?
;   Attempts every detached target's release and re-raises the first failure after cleanup.
(define (release-targets! s targets)
  ;; Detach targets before calling this helper. Every release is attempted,
  ;; even when a renderer reports a failure, and none can be retried later.
  (define failures '())
  (for ([target (in-list targets)])
    (with-handlers ([(lambda (_) #t) (lambda (e) (set! failures (cons e failures)))])
      ((alpha-state-release s) target)))
  (unless (null? failures) (raise (car (reverse failures)))))

; dc-alpha-discard! : alpha-state? procedure? -> void?
;   Discards all unfinished children without compositing and restores the root's saved clip and draw
;   alpha.
(define (dc-alpha-discard! s restore-alpha!)
  (live! 'discard-alpha s)
  (unless (null? (alpha-state-layers s))
    (parameterize-break #f
      (define frames (alpha-state-layers s))
      (define outer (car (reverse frames)))
      ;; The last parent is the root, which remains owned and usable. Retire
      ;; only child surfaces, from the innermost layer outwards.
      (define targets
        (let loop ([target (alpha-state-target s)] [frames frames])
          (cons target
                (if (null? (cdr frames)) '()
                    (loop (layer-parent (car frames)) (cdr frames))))))
      (set-alpha-state-layers! s '())
      (set-alpha-state-target! s (alpha-state-root s))
      (set-alpha-state-clip! s (layer-parent-clip outer))
      (dynamic-wind
       void
       (lambda () (restore-alpha! (layer-old-alpha outer)))
       (lambda () (release-targets! s targets)))))
  (void))

; dc-alpha-close! : alpha-state? -> void?
;   Idempotently detaches and releases the root and all children without implicitly ending alpha
;   groups.
(define (dc-alpha-close! s)
  (unless (alpha-state-closed? s)
    (parameterize-break #f
      (define targets (cons (alpha-state-target s) (map layer-parent (alpha-state-layers s))))
      (set-alpha-state-closed?! s #t)
      ;; A closed frame DC must not retain a still-live borrowed GPU root.
      ;; The detached local targets list preserves ownership during release.
      (set-alpha-state-root! s #f)
      (set-alpha-state-target! s #f)
      (set-alpha-state-layers! s '())
      (set-alpha-state-clip! s #f)
      ;; Discard unfinished groups; closing is never an implicit end-alpha.
      (release-targets! s targets)))
  (void))
