#lang racket/base
;; One private staging target per presenter, not a cache of drawing contexts.
;; No GUI/native initialization. Factories own the native implementation;
;; disposal queues retirement through the existing GPU-domain lifetime layer.
(require racket/future "check.rkt" "gpu-io-trace.rkt" "gpu-format-util.rkt")
(provide make-frame-target-cache call-with-frame-target
         close-frame-target-cache! frame-target-cache-info
         current-frame-target-reuse?)

;; Test/reference path only: not re-exported by skia/gpu or skia/gpu-dc.
;; Capture at entry, so a callback cannot change this operation's disposition.
(define current-frame-target-reuse?
  (make-parameter #t
    (lambda (v)
      (unless (boolean? v) (raise-argument-error 'current-frame-target-reuse? "boolean?" v))
      v)))
(struct target-entry (width height configuration value dispose))
(struct frame-target-cache
  (owner [entry #:mutable] [busy? #:mutable] [closed? #:mutable] [quarantined? #:mutable]
         [creations #:mutable] [reuses #:mutable] [retirements #:mutable]))
(define (make-frame-target-cache)
  (when (current-future) (error 'gpu-frame-target "construction in a future is not supported"))
  (frame-target-cache (current-thread) #f #f #f #f 0 0 0))
(define (owner! who cache)
  (unless (frame-target-cache? cache) (raise-argument-error who "frame-target-cache?" cache))
  (unless (and (eq? (current-thread) (frame-target-cache-owner cache)) (not (current-future)))
    (error who "staging target belongs to another execution owner")))
(define (healthy! who cache)
  (owner! who cache)
  (when (frame-target-cache-quarantined? cache)
    (error who "staging target retirement failed; cache is quarantined")))
(define (idle! who cache)
  (healthy! who cache)
  (when (frame-target-cache-busy? cache)
    (error who "nested staging target use or close is not allowed")))
(define (event! entry action reason)
  (record-gpu-io!
   (hasheq 'kind "dc-frame-target" 'action action 'reason reason
           'pixel_width (target-entry-width entry) 'pixel_height (target-entry-height entry))))
(define (retire! cache reason)
  (define entry (frame-target-cache-entry cache))
  (when entry
    (parameterize-break #f
      ;; A throwing native release has indeterminate ownership. Keep its root,
      ;; never reuse it or invoke the release twice, and refuse context teardown
      ;; through the presenter. Quarantine deliberately has no automatic retry.
      (set-frame-target-cache-quarantined?! cache #t)
      ((target-entry-dispose entry) (target-entry-value entry))
      (set-frame-target-cache-entry! cache #f)
      (set-frame-target-cache-quarantined?! cache #f)
      (set-frame-target-cache-retirements! cache (add1 (frame-target-cache-retirements cache)))
      (event! entry "retire" reason))))
(define (frame-target-cache-info cache)
  (owner! 'gpu-frame-target-info cache)
  (define entry (frame-target-cache-entry cache))
  (hasheq 'policy "one-staging-target-per-presenter"
          'live_targets (if entry 1 0)
          'pixel_size (and entry (list (target-entry-width entry) (target-entry-height entry)))
          'busy (frame-target-cache-busy? cache) 'closed (frame-target-cache-closed? cache)
          'quarantined (frame-target-cache-quarantined? cache)
          'creations (frame-target-cache-creations cache) 'reuses (frame-target-cache-reuses cache)
          'retirements (frame-target-cache-retirements cache)
          'counts "wrapper staging-surface constructors/borrows/retirements; not driver allocations"))
(define (close-frame-target-cache! cache)
  (idle! 'close-gpu-frame-target cache)
  (unless (frame-target-cache-closed? cache)
    (parameterize-break #f
      (retire! cache "presenter-close")
      (set-frame-target-cache-closed?! cache #t)))
  (void))
(define (call-with-frame-target cache width height create dispose proc
                                #:configuration [configuration #f])
  (define who 'gpu-frame-target)
  (idle! who cache)
  (when (frame-target-cache-closed? cache) (error who "staging target cache is closed"))
  ;; Recheck even a hit: tightening the allocation bound must not be bypassed.
  (check-dimensions who width height)
  (for ([p (in-list (list create dispose proc))] [arity '(0 1 1)])
    (unless (and (procedure? p) (procedure-arity-includes? p arity))
      (raise-argument-error who (format "procedure accepting ~a argument(s)" arity) p)))
  (unless (gpu-config-value? configuration)
    (raise-argument-error who "detached immutable configuration" configuration))
  (gpu-cache-budget! who configuration width height)
  (define reuse? (current-frame-target-reuse?))
  (define entered? #f)
  (define completed? #f)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
      (lambda ()
        (when entered? (error who "expired staging target scope cannot be reentered"))
        (idle! who cache)
        (set! entered? #t)
        (set-frame-target-cache-busy?! cache #t))
      (lambda ()
        (define entry (frame-target-cache-entry cache))
        (unless (and reuse? entry (= width (target-entry-width entry))
                     (= height (target-entry-height entry))
                     (equal? configuration (target-entry-configuration entry)))
          ;; Drop the old wrapper first. Domain retirement may remain queued
          ;; until the normal owner/context boundary; no GPU wait is introduced.
          (when entry (retire! cache (if reuse? (if (and (= width (target-entry-width entry))
                                       (= height (target-entry-height entry)))
                                  "configuration-change" "resize") "fresh-reference")))
          (parameterize-break #f
            (define value (create))
            (unless value (error who "staging target allocation returned false"))
            (set! entry (target-entry width height configuration value dispose))
            (set-frame-target-cache-entry! cache entry)
            (set-frame-target-cache-creations! cache (add1 (frame-target-cache-creations cache))))
          (event! entry "create" (if reuse? "cache-miss" "fresh-reference"))
          (set! entry #f))
        (when entry
          (set-frame-target-cache-reuses! cache (add1 (frame-target-cache-reuses cache)))
          (event! entry "reuse" "compatible-extent"))
        (begin0 (proc (target-entry-value (frame-target-cache-entry cache)))
          (set! completed? #t)))
      (lambda ()
        (parameterize-break #f
          (dynamic-wind
           void
           (lambda ()
             (cond
               [(not completed?)
                ;; Preserve the user's original exception or continuation
                ;; escape. An uncertain disposal remains rooted/quarantined.
                (unless (frame-target-cache-quarantined? cache)
                  (with-handlers ([(lambda (_) #t) (lambda (_) (void))])
                    (retire! cache "failed-dc-scope")))]
               [(not reuse?) (retire! cache "fresh-reference")]))
           (lambda () (set-frame-target-cache-busy?! cache #f)))))))))
