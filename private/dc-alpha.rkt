#lang racket/base
;; Pure ownership/opacity controller for persistent raster alpha groups.
;; The production renderer supplies synchronous CPU allocation/compositing.
(provide make-dc-alpha dc-alpha-target dc-alpha-root dc-alpha-root-alpha dc-alpha-depth dc-alpha-clip
         dc-alpha-set-clip! dc-alpha-start! dc-alpha-end! dc-alpha-discard! dc-alpha-close!)
(struct layer (parent parent-clip old-alpha opacity) #:transparent)
(struct alpha-state (root [target #:mutable] [clip #:mutable] [layers #:mutable]
                          width height create release composite limit [closed? #:mutable]))
(define (make-dc-alpha root width height create release composite limit)
  (alpha-state root root #f '() width height create release composite limit #f))
(define (live! who s)
  (when (alpha-state-closed? s) (error who "alpha target is closed")))
(define (dc-alpha-root s) (live! 'snapshot s) (alpha-state-root s))
(define (dc-alpha-target s) (live! 'draw s) (alpha-state-target s))
(define (dc-alpha-root-alpha s current-alpha)
  (live! 'root-alpha s)
  (if (null? (alpha-state-layers s)) current-alpha
      (layer-old-alpha (car (reverse (alpha-state-layers s))))))
(define (dc-alpha-depth s) (length (alpha-state-layers s)))
(define (dc-alpha-clip s) (live! 'clip s) (alpha-state-clip s))
(define (dc-alpha-set-clip! s clip)
  (live! 'set-clipping-region s) (set-alpha-state-clip! s clip) (void))
(define (opacity! who a)
  (unless (and (real? a) (<= 0 a 1))
    (raise-argument-error who "finite real in [0,1]" a)))
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
(define (release-targets! s targets)
  ;; Detach targets before calling this helper. Every release is attempted,
  ;; even when a renderer reports a failure, and none can be retried later.
  (define failures '())
  (for ([target (in-list targets)])
    (with-handlers ([(lambda (_) #t) (lambda (e) (set! failures (cons e failures)))])
      ((alpha-state-release s) target)))
  (unless (null? failures) (raise (car (reverse failures)))))
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
(define (dc-alpha-close! s)
  (unless (alpha-state-closed? s)
    (parameterize-break #f
      (define targets (cons (alpha-state-target s) (map layer-parent (alpha-state-layers s))))
      (set-alpha-state-closed?! s #t)
      (set-alpha-state-target! s #f)
      (set-alpha-state-layers! s '())
      (set-alpha-state-clip! s #f)
      ;; Discard unfinished groups; closing is never an implicit end-alpha.
      (release-targets! s targets)))
  (void))
