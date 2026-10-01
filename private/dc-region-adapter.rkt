#lang racket/base
;; The ONLY private racket/draw dependency in the DC implementation.
;; No Cairo pointer, rendering, or private pen/brush protocol crosses this file.
(require racket/class racket/list
         (only-in ffi/unsafe register-finalizer)
         (only-in ffi/unsafe/atomic call-as-atomic)
         (prefix-in rd: racket/draw)
         (only-in racket/draw/private/region get-paths)
         (only-in racket/draw/private/local lock-region
                  [get-clipping-matrix private-get-clipping-matrix])
         "dc-support.rkt" "dc-geometry.rkt")
(provide dc-region-mixin dc-region-snapshot make-dc-region-lease dc-region-install!
         dc-region-select!)
(define (dc-region-mixin %)
  (class %
    (super-new)
    ;; region%'s constructor uses a local-member identity, not the symbol
    ;; 'get-clipping-matrix. Implement the exact identity in this adapter.
    (define/public (private-get-clipping-matrix)
      (dc-effective (send this get-transformation)))))
;; The finalizer holds only a weak region reference, never a region -> DC
;; cycle. An externally retained unassociated region is unlocked if its DC is
;; collected without explicit close. Native surface finalization stays separate.
(define (make-dc-region-lease dc)
  (define lease (box #f))
  (register-finalizer dc (lambda (_dc) (dc-region-install! lease #f)))
  lease)
(define (dc-region-install! lease r [commit void])
  ;; Lock-count and DC selection must change together, including finalization.
  (call-as-atomic
   (lambda ()
     (define old (and (unbox lease) (weak-box-value (unbox lease))))
     (unless (eq? old r)
       (when r (send r lock-region 1))
       (when old (send old lock-region -1))
       (set-box! lease (and r (make-weak-box r))))
     (commit)))
  (void))
(define (dc-region-select! who lease r dc matrix backing commit)
  ;; Keep the snapshot, validation, lock acquisition and selection in one
  ;; atomic section: another thread cannot mutate an unassociated region
  ;; between the copied geometry and its installation lock.
  (call-as-atomic
   (lambda ()
     (define data (snapshot-region who r dc matrix))
     (dc-scale-clip data backing)
     (dc-region-install! lease r (lambda () (commit data)))))
  (void))
(define (dc-region-snapshot who r dc matrix)
  ;; Snapshot mutable Racket paths without an intervening thread mutation.
  ;; This does not invoke Cairo or a native renderer.
  (call-as-atomic (lambda () (snapshot-region who r dc matrix))))
(define (snapshot-region who r dc matrix)
  (cond
    [(not r) #f]
    [else
     (unless (is-a? r rd:region%) (raise-argument-error who "region% or #f" r))
     (define attached (send r get-dc))
     (when (and attached (not (eq? attached dc)))
       (raise-arguments-error who "region is associated with another drawing context" "region" r))
     (define paths (send r get-paths))
     (unless (and (list? paths)
                  (andmap (lambda (p) (and (pair? p) (is-a? (car p) rd:dc-path%)
                                          (memq (cdr p) '(any winding odd-even)))) paths))
       (error who "unsupported private region representation; adapter needs review"))
     (define flexible-rule (if (ormap (lambda (p) (eq? (cdr p) 'odd-even)) paths) 'odd-even 'winding))
     ;; Each element is an intersection, not a union. Associated paths already
     ;; contain the construction-time transform. Unassociated paths are frozen
     ;; using the transform at installation. An empty list means an empty clip.
     (dc-clip
      (for/list ([entry (in-list paths)])
        (define commands (dc-path-commands who (car entry)))
        (dc-clip-path
         (if attached commands (dc-path-map commands (lambda (x y) (dc-point matrix x y))))
         (if (eq? (cdr entry) 'any) flexible-rule (cdr entry)))))]))
