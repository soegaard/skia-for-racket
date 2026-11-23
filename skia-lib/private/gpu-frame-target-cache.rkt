#lang racket/base

;;;
;;; GPU Frame Target Cache
;;;

;; Caches presentation targets by size and configuration and disposes replacements.
;; Avoids recreating compatible frame resources while keeping their ownership explicit.

;; One private staging target per presenter, not a cache of drawing contexts.
;; No GUI/native initialization. Factories own the native implementation;
;; disposal queues retirement through the existing GPU-domain lifetime layer.
(require racket/future "check.rkt" "gpu-io-trace.rkt" "gpu-format-util.rkt")
(provide make-frame-target-cache call-with-frame-target
         close-frame-target-cache! frame-target-cache-info
         current-frame-target-reuse?)

;;;
;;; Cache State and Owner-Thread Guards
;;;

;; Test/reference path only: not re-exported by skia/gpu or skia/gpu-dc.
;; Capture at entry, so a callback cannot change this operation's disposition.

; current-frame-target-reuse? : parameter?
;   Enables target reuse by default and permits diagnostic runs to disable it.
(define current-frame-target-reuse?
  (make-parameter #t
    (lambda (v)
      (unless (boolean? v) (raise-argument-error 'current-frame-target-reuse? "boolean?" v))
      v)))
(struct target-entry (width height configuration value dispose))
;; Fields:
;;   width and height: cached target pixel dimensions. configuration: equality-compared
;;   configuration key. value: backend target value. dispose: matching release procedure. Reuse
;;   requires matching dimensions and configuration.

(struct frame-target-cache
  (owner [entry #:mutable] [busy? #:mutable] [closed? #:mutable] [quarantined? #:mutable]
         [creations #:mutable] [reuses #:mutable] [retirements #:mutable]))
;; Fields:
;;   owner: creator thread. entry: mutable optional target-entry. busy?, closed?, and quarantined?:
;;   scope/lifecycle flags. creations, reuses, and retirements: nonnegative counters.
;;   A busy entry cannot be replaced or disposed; failed cleanup is quarantined to avoid repeated
;;   destruction.

; make-frame-target-cache : -> frame-target-cache?
;   Creates an empty cache bound to the current execution thread.
(define (make-frame-target-cache)
  (when (current-future) (error 'gpu-frame-target "construction in a future is not supported"))
  (frame-target-cache (current-thread) #f #f #f #f 0 0 0))

; owner! : symbol? frame-target-cache? -> void?
;   Rejects cache access outside the thread that owns its native targets.
(define (owner! who cache)
  (unless (frame-target-cache? cache) (raise-argument-error who "frame-target-cache?" cache))
  (unless (and (eq? (current-thread) (frame-target-cache-owner cache)) (not (current-future)))
    (error who "staging target belongs to another execution owner")))

; healthy! : symbol? frame-target-cache? -> void?
;   Rejects a closed or quarantined cache before any target can be reused.
(define (healthy! who cache)
  (owner! who cache)
  (when (frame-target-cache-quarantined? cache)
    (error who "staging target retirement failed; cache is quarantined")))

; idle! : symbol? frame-target-cache? -> void?
;   Requires a healthy cache with no outstanding target borrow before mutation or closure.
(define (idle! who cache)
  (healthy! who cache)
  (when (frame-target-cache-busy? cache)
    (error who "nested staging target use or close is not allowed")))

; event! : target-entry? any/c any/c -> any
;   Records a target-cache lifecycle event through the optional GPU I/O ledger.
(define (event! entry action reason)
  (record-gpu-io!
   (hasheq 'kind "dc-frame-target" 'action action 'reason reason
           'pixel_width (target-entry-width entry) 'pixel_height (target-entry-height entry))))

;;;
;;; Target Retirement and Cache Diagnostics
;;;

; retire! : frame-target-cache? any/c -> void?
;   Detaches the cached entry before disposal and quarantines uncertain cleanup outcomes.
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

; frame-target-cache-info : frame-target-cache? -> hash?
;   Returns detached creation, reuse, retirement, and current-target diagnostic information.
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

; close-frame-target-cache! : frame-target-cache? -> void?
;   Disposes an idle cached target once and marks the cache closed.
(define (close-frame-target-cache! cache)
  (idle! 'close-gpu-frame-target cache)
  (unless (frame-target-cache-closed? cache)
    (parameterize-break #f
      (retire! cache "presenter-close")
      (set-frame-target-cache-closed?! cache #t)))
  (void))

;;;
;;; Scoped Target Reuse and Reconfiguration
;;;

; call-with-frame-target : frame-target-cache? any/c any/c any/c any/c any/c [#:configuration any/c]
;   -> any
;   Reuses a compatible target or creates a replacement, then bounds its borrow to the callback.
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
