#lang racket/base
;; Backend-neutral lifecycle. This module does not initialize GUI or native GPU
;; facilities. Adapters own target acquisition/cleanup; frames never expose a
;; closeable surface, drawable, framebuffer, command buffer or raw pointer.
(require ffi/unsafe/atomic ffi/unsafe/custodian racket/list racket/future
         "gpu-provider.rkt" "gpu-frame-target-cache.rkt"
         (submod "gpu-domain.rkt" presentation-internals))
(provide gpu-presenter? gpu-presenter-backend gpu-presenter-context
         gpu-presenter-state gpu-presenter-info gpu-presenter-render!
         gpu-presenter-request-render! gpu-presenter-set-render! gpu-presenter-close!
         gpu-drain-pending-presenters!
         gpu-frame? gpu-frame-expired? gpu-frame-canvas gpu-frame-context gpu-frame-info
         gpu-frame-width gpu-frame-height gpu-frame-logical-width gpu-frame-logical-height
         gpu-frame-scale-x gpu-frame-scale-y gpu-frame-generation gpu-frame-index)
(module* adapter-internals #f
  (provide (struct-out presentation-adapter) make-presenter presentation-metrics presentation-active?
           call-with-gpu-frame-target))
;; call-target(metrics, receive) calls receive(canvas, description, present!)
;; exactly once, or returns #f if no drawable is available. It must retire its
;; target on EVERY exit. post queues (never invokes inline) on the owner thread.
(struct presentation-adapter (backend context measure call-target post close describe))
(struct gpu-presenter
  (adapter owner [render #:mutable] on-error [state #:mutable] [busy? #:mutable]
           [dirty? #:mutable] [ticket #:mutable] [queued? #:mutable]
           [generation #:mutable] [signature #:mutable] [index #:mutable]
           [presented #:mutable] [skipped #:mutable] [cancelled #:mutable]
           [last #:mutable] [error #:mutable] [requested? #:mutable] [cleanup-posted? #:mutable] [unregister #:mutable]
           targets))
(struct gpu-frame (owner [canvas-value #:mutable] [context-value #:mutable] info [live? #:mutable]
                         [targets #:mutable]))
(define pending-cleanup (make-hasheq)) ; only requested cleanup, never all live presenters
(define active-presenter (make-parameter #f))
(define (presentation-active?) (or (and (active-presenter) #t) (domain-execution-active?)))
(define deferred-redraws (make-hasheq))
(define (owner! who p)
  (unless (gpu-presenter? p) (raise-argument-error who "gpu-presenter?" p))
  (unless (and (eq? (current-thread) (gpu-presenter-owner p)) (not (current-future)))
    (error who "presenter operations require its eventspace handler/creator thread")))
(define (check-open! who p)
  (owner! who p)
  (when (or (gpu-presenter-requested? p) (memq (gpu-presenter-state p) '(closing closed failed)))
    (error who "presenter is ~a" (gpu-presenter-state p))))
(define (procedure! who v arity)
  (unless (and (procedure? v) (procedure-arity-includes? v arity))
    (raise-argument-error who (format "procedure accepting ~a argument(s)" arity) v)))
(define (error-text v) (if (exn? v) (exn-message v) (format "~s" v)))
(define (presentation-metrics pw ph lw lh #:visible? [visible? #t])
  (for ([n (in-list (list pw ph))])
    (unless (and (exact-nonnegative-integer? n) (<= n #x7fffffff))
      (error 'gpu-presenter "invalid drawable pixel extent ~e" n)))
  (for ([n (in-list (list lw lh))])
    (unless (and (real? n) (<= 0 n #x7fffffff))
      (error 'gpu-presenter "invalid logical extent ~e" n)))
  (unless (boolean? visible?) (raise-argument-error 'gpu-presenter "boolean?" visible?))
  (hasheq 'pixel_width pw 'pixel_height ph 'logical_width lw 'logical_height lh
          'scale_x (if (positive? lw) (/ (exact->inexact pw) lw) 0.0)
          'scale_y (if (positive? lh) (/ (exact->inexact ph) lh) 0.0)
          'drawable (and visible? (positive? pw) (positive? ph) (positive? lw) (positive? lh))
          'visible visible?))
(define (metrics! a)
  (define m ((presentation-adapter-measure a)))
  (unless (and (hash? m) (immutable? m)) (error 'gpu-presenter "adapter metrics must be immutable"))
  ;; Revalidate the adapter's numbers before they are passed to native FFI.
  (define checked (presentation-metrics
    (hash-ref m 'pixel_width) (hash-ref m 'pixel_height)
    (hash-ref m 'logical_width) (hash-ref m 'logical_height)
    #:visible? (hash-ref m 'visible)))
  (unless (equal? checked m) (error 'gpu-presenter "inconsistent adapter metrics"))
  m)
(define (gpu-presenter-backend p)
  (owner! 'gpu-presenter-backend p) (presentation-adapter-backend (gpu-presenter-adapter p)))
(define (gpu-presenter-context p)
  (owner! 'gpu-presenter-context p) (presentation-adapter-context (gpu-presenter-adapter p)))
(define (gpu-presenter-info p)
  (owner! 'gpu-presenter-info p)
  (hasheq 'backend (symbol->string (gpu-presenter-backend p))
          'state (symbol->string (gpu-presenter-state p))
          'target_generation (gpu-presenter-generation p) 'frames_acquired (gpu-presenter-index p)
          'presents_requested (gpu-presenter-presented p) 'frames_skipped (gpu-presenter-skipped p)
          'frames_cancelled (gpu-presenter-cancelled p) 'redraw_queued (gpu-presenter-queued? p) 'shutdown_requested (gpu-presenter-requested? p)
          'last_frame (gpu-presenter-last p) 'last_error (gpu-presenter-error p)
          'frame_target_cache (frame-target-cache-info (gpu-presenter-targets p))
          'adapter ((presentation-adapter-describe (gpu-presenter-adapter p)))
          'visible_pixels_verified #f 'performance_measured #f))
(define (gpu-frame-expired? f)
  (unless (gpu-frame? f) (raise-argument-error 'gpu-frame-expired? "gpu-frame?" f))
  (not (gpu-frame-live? f)))
(define (gpu-frame-canvas f)
  (unless (gpu-frame? f) (raise-argument-error 'gpu-frame-canvas "gpu-frame?" f))
  (unless (and (eq? (current-thread) (gpu-frame-owner f)) (not (current-future)))
    (error 'gpu-frame-canvas "frame belongs to another execution owner"))
  (when (gpu-frame-expired? f) (error 'gpu-frame-canvas "presentation frame has expired"))
  (gpu-frame-canvas-value f))
;; Avoid exporting the raw mutable canvas accessor.
(define (gpu-frame-context f)
  (gpu-frame-canvas f) ; identical owner/expiration checks
  (gpu-frame-context-value f))
;; The cache is an implementation resource of THIS presenter/context. A frame
;; may borrow it only while live; invalidate its reference along with the canvas
;; so retaining expired public frames cannot keep GPU staging storage alive.
(define (call-with-gpu-frame-target f width height create dispose proc)
  (gpu-frame-canvas f)
  (unless (and (= width (gpu-frame-width f)) (= height (gpu-frame-height f)))
    (error 'gpu-frame-target "staging extent differs from the live frame"))
  (call-with-frame-target (gpu-frame-targets f) width height create dispose proc))
(define (gpu-frame-width f) (hash-ref (gpu-frame-info f) 'pixel_width))
(define (gpu-frame-height f) (hash-ref (gpu-frame-info f) 'pixel_height))
(define (gpu-frame-logical-width f) (hash-ref (gpu-frame-info f) 'logical_width))
(define (gpu-frame-logical-height f) (hash-ref (gpu-frame-info f) 'logical_height))
(define (gpu-frame-scale-x f) (hash-ref (gpu-frame-info f) 'scale_x))
(define (gpu-frame-scale-y f) (hash-ref (gpu-frame-info f) 'scale_y))
(define (gpu-frame-generation f) (hash-ref (gpu-frame-info f) 'target_generation))
(define (gpu-frame-index f) (hash-ref (gpu-frame-info f) 'frame_index))
(define (invalidate-queue! p)
  (set-gpu-presenter-ticket! p (add1 (gpu-presenter-ticket p)))
  (set-gpu-presenter-queued?! p #f))
(define (report-error! p e)
  (set-gpu-presenter-error! p (error-text e))
  ((gpu-presenter-on-error p) e))
(define (schedule! p)
  (when (and (gpu-presenter-dirty? p) (not (gpu-presenter-busy? p))
             (eq? (gpu-presenter-state p) 'ready) (not (gpu-presenter-requested? p))
             (not (gpu-presenter-queued? p)))
    (set-gpu-presenter-ticket! p (add1 (gpu-presenter-ticket p)))
    (define ticket (gpu-presenter-ticket p))
    (set-gpu-presenter-queued?! p #t)
    (with-handlers ([(lambda (_) #t)
                     (lambda (e) (set-gpu-presenter-queued?! p #f) (raise e))])
      ((presentation-adapter-post (gpu-presenter-adapter p))
       (lambda ()
         (owner! 'gpu-presenter-redraw p)
         (when (and (= ticket (gpu-presenter-ticket p)) (gpu-presenter-queued? p))
           (set-gpu-presenter-queued?! p #f)
           ;; A user yield may dispatch a queued redraw inside another frame.
           ;; Do not reenter a Ganesh context or spin the event loop.
           (if (or (gpu-presenter-busy? p) (presentation-active?))
               (hash-set! deferred-redraws p #t)
               (with-handlers ([(lambda (_) #t) (lambda (e) (report-error! p e))])
               (when (eq? (gpu-presenter-state p) 'ready) (gpu-presenter-render! p))))))))))
(define (gpu-presenter-request-render! p)
  (check-open! 'gpu-presenter-request-render! p)
  (set-gpu-presenter-dirty?! p #t)
  (schedule! p)
  (void))
(define (gpu-presenter-set-render! p render)
  (check-open! 'gpu-presenter-set-render! p)
  (procedure! 'gpu-presenter-set-render! render 1)
  (set-gpu-presenter-render! p render)
  (gpu-presenter-request-render! p))
(define (make-presenter adapter render on-error)
  (unless (presentation-adapter? adapter)
    (raise-argument-error 'make-presenter "private presentation adapter" adapter))
  (unless (memq (presentation-adapter-backend adapter) '(opengl metal direct3d))
    (error 'make-presenter "unsupported backend"))
  (procedure! 'make-presenter render 1) (procedure! 'make-presenter on-error 1)
  (for ([proc (in-list (list (presentation-adapter-measure adapter)
                             (presentation-adapter-close adapter)
                             (presentation-adapter-describe adapter)))])
    (procedure! 'make-presenter proc 0))
  (procedure! 'make-presenter (presentation-adapter-call-target adapter) 2)
  (procedure! 'make-presenter (presentation-adapter-post adapter) 1)
  (define p (gpu-presenter adapter (current-thread) render on-error 'ready #f #f 0 #f
                           0 #f 0 0 0 0 #f #f #f #f #f (make-frame-target-cache)))
  (register-finalizer-and-custodian-shutdown
   p request-cleanup!
   #:custodian-available
   (lambda (unregister) (set-gpu-presenter-unregister! p unregister) p)
   #:custodian-unavailable
   (lambda (_)
     ;; Constructor registration runs atomically; caller owns error cleanup.
     (error 'make-presenter "current custodian has already shut down"))))
(define (post-cleanup! p)
  (unless (or (gpu-presenter-cleanup-posted? p) (eq? (gpu-presenter-state p) 'closed))
    (set-gpu-presenter-cleanup-posted?! p #t)
    (with-handlers ([(lambda (_) #t)
                     (lambda (_) (set-gpu-presenter-cleanup-posted?! p #f))])
      ((presentation-adapter-post (gpu-presenter-adapter p))
       (lambda ()
         (owner! 'gpu-presenter-cleanup p)
         (set-gpu-presenter-cleanup-posted?! p #f)
         ;; A GUI yield can dispatch cleanup while another GPU callback is
         ;; active. The domain-idle notifier will queue it once more later.
         (unless (presentation-active?)
           (with-handlers ([(lambda (_) #t)
                            (lambda (e) (set-gpu-presenter-error! p (error-text e)))])
             (gpu-presenter-close! p))))))))
(define (schedule-deferred-owner-work!)
  ;; Called after a domain or presenter scope. Queue only; do not run user
  ;; callbacks or switch a native context from this notification hook.
  (unless (presentation-active?)
    (define redraws
      (for/list ([p (in-hash-keys deferred-redraws)]
                 #:when (eq? (current-thread) (gpu-presenter-owner p))) p))
    (for ([p (in-list redraws)])
      (hash-remove! deferred-redraws p)
      (schedule! p))
    (define closing
      (for/list ([p (in-hash-keys pending-cleanup)]
                 #:when (eq? (current-thread) (gpu-presenter-owner p))) p))
    (for ([p (in-list closing)]) (post-cleanup! p))))
(register-domain-idle-notifier! schedule-deferred-owner-work!)
(define (request-cleanup! p)
  ;; Finalizers/custodians only mark and enqueue. Neither native destruction
  ;; nor GUI manipulation is performed here; post is the adapter's thread-safe
  ;; queue operation, and an unavailable eventspace leaves a quarantined root.
  (unless (eq? (gpu-presenter-state p) 'closed)
    (set-gpu-presenter-requested?! p #t)
    (hash-set! pending-cleanup p #t)
    (hash-remove! deferred-redraws p)
    (set-gpu-presenter-state! p 'closing)
    (set-gpu-presenter-dirty?! p #f)
    (invalidate-queue! p)
    (post-cleanup! p)))
(define (gpu-presenter-close! p)
  (owner! 'gpu-presenter-close! p)
  (unless (eq? (gpu-presenter-state p) 'closed)
    (set-gpu-presenter-requested?! p #t)
    (set-gpu-presenter-state! p 'closing)
    (hash-remove! deferred-redraws p)
    (set-gpu-presenter-dirty?! p #f)
    (invalidate-queue! p)
    ;; A close during user drawing cancels presentation, but cannot destroy
    ;; a surface underneath the native drawing stack. Finish after unwinding.
    (if (or (gpu-presenter-busy? p) (presentation-active?))
        (begin (hash-set! pending-cleanup p #t) (post-cleanup! p))
      (with-handlers ([(lambda (_) #t)
                       (lambda (e)
                         (set-gpu-presenter-error! p (error-text e))
                         (hash-set! pending-cleanup p #t) (raise e))])
        ;; Retire the staging wrapper before the adapter closes its context.
        ;; skia-close! queues GPU unrefs; the existing context close drains them.
        ;; Deferred close/finalizer/custodian paths all converge here.
        (close-frame-target-cache! (gpu-presenter-targets p))
        ((presentation-adapter-close (gpu-presenter-adapter p)))
        (set-gpu-presenter-state! p 'closed)
        (hash-remove! pending-cleanup p)
        (define unregister (gpu-presenter-unregister p))
        (when unregister (unregister p) (set-gpu-presenter-unregister! p #f)))))
  (void))
(define (gpu-drain-pending-presenters!)
  (when (presentation-active?) (error 'gpu-drain-pending-presenters! "cannot drain inside a GPU or presentation frame"))
  (define candidates
    (call-as-atomic (lambda ()
      (for/list ([p (in-hash-keys pending-cleanup)]
                 #:when (eq? (gpu-presenter-owner p) (current-thread))) p))))
  (for/list ([p (in-list candidates)])
    (with-handlers ([(lambda (_) #t) (lambda (e) (gpu-presenter-info p))])
      (gpu-presenter-close! p) (gpu-presenter-info p))))
(define (gpu-presenter-render! p)
  (check-open! 'gpu-presenter-render! p)
  (when (or (gpu-presenter-busy? p) (presentation-active?))
    (error 'gpu-presenter-render! "nested presentation is not allowed; request a queued redraw"))
  ;; Custodian shutdown can arrive from another Racket thread. Do not let an
  ;; intervening request be overwritten by a new rendering transition.
  (call-as-atomic
   (lambda ()
     (check-open! 'gpu-presenter-render! p)
     (invalidate-queue! p)
     (set-gpu-presenter-dirty?! p #f)
     (set-gpu-presenter-busy?! p #t)
     (set-gpu-presenter-state! p 'rendering)))
  (define a (gpu-presenter-adapter p))
  (define result 'skipped)
  (define callback-error? #f)
  (define completed? #f)
  (define entered? #f)
  (define acquired? #f)
  (define (cancel!)
    (unless (memq result '(cancelled present-requested))
      (set! result 'cancelled)
      (set-gpu-presenter-cancelled! p (add1 (gpu-presenter-cancelled p)))
      (when (hash? (gpu-presenter-last p))
        (set-gpu-presenter-last! p (hash-set (gpu-presenter-last p) 'result "cancelled")))))
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (when entered? (error 'gpu-presenter-render! "frame operation has expired"))
         (set! entered? #t))
       (lambda ()
         (with-handlers ([(lambda (_) #t)
                          (lambda (e)
                            (set-gpu-presenter-error! p (error-text e))
                            (unless (or callback-error? (eq? (gpu-presenter-state p) 'closing))
                              (set-gpu-presenter-state! p 'failed))
                            (raise e))])
           (parameterize ([active-presenter p])
             (define m (metrics! a))
             (set-gpu-presenter-last! p (hash-set m 'result "skipped"))
             (cond
               [(or (gpu-presenter-requested? p) (not (hash-ref m 'drawable)))
                (set-gpu-presenter-signature! p #f)]
               [else
                ((presentation-adapter-call-target a) m
                 (lambda (canvas target present!)
                   (when acquired? (error 'gpu-presenter-render! "adapter delivered more than one target"))
                   (set! acquired? #t)
                   (unless (and (hash? target) (immutable? target)
                                (equal? (hash-ref target 'backend #f)
                                        (symbol->string (presentation-adapter-backend a))))
                     (error 'gpu-presenter-render! "target backend metadata mismatch"))
                   (define signature (list m (hash-ref target 'target_identity #f)))
                   (unless (equal? signature (gpu-presenter-signature p))
                     (set-gpu-presenter-signature! p signature)
                     (set-gpu-presenter-generation! p (add1 (gpu-presenter-generation p))))
                   (set-gpu-presenter-index! p (add1 (gpu-presenter-index p)))
                   (define info
                     (hash-set* m 'backend (symbol->string (presentation-adapter-backend a))
                                  'target_generation (gpu-presenter-generation p)
                                  'frame_index (gpu-presenter-index p) 'target target))
                   (define f (gpu-frame (current-thread) canvas (presentation-adapter-context a) info #t
                                        (gpu-presenter-targets p)))
                   (set-gpu-presenter-last! p (hash-set info 'result "acquired"))
                   (dynamic-wind
                     void
                     (lambda ()
                       (with-handlers ([(lambda (_) #t)
                                        (lambda (e) (set! callback-error? #t) (raise e))])
                         ((gpu-presenter-render p) f))
                       (cond
                         [(gpu-presenter-requested? p) (cancel!)]
                         [(not (equal? m (metrics! a)))
                          ;; A resize/hide during a yield invalidates the acquired
                          ;; target. Never present old-size contents as a new frame.
                          (set-gpu-presenter-signature! p #f)
                          (set-gpu-presenter-dirty?! p #t)
                          (cancel!)]
                         [else
                          ;; DXGI can finish a submitted frame but report occlusion.
                          ;; Do not count that status as successful presentation.
                          ;; Existing GL/Metal adapters return void, as before.
                          (define outcome (present!))
                          (cond
                            [(eq? outcome 'occluded) (set! result 'skipped)]
                            [else
                             (set! result 'present-requested)
                             (set-gpu-presenter-presented! p (add1 (gpu-presenter-presented p)))])])
                       (set-gpu-presenter-last! p (hash-set info 'result (symbol->string result))))
                     (lambda ()
                       (set-gpu-frame-live?! f #f)
                       (set-gpu-frame-canvas-value! f #f)
                       (set-gpu-frame-context-value! f #f)
                       (set-gpu-frame-targets! f #f)))))]))
           (when (eq? result 'skipped)
             (set-gpu-presenter-signature! p #f)
             (set-gpu-presenter-skipped! p (add1 (gpu-presenter-skipped p))))
           (set! completed? #t)
           result))
       (lambda ()
         (when (and acquired? (not completed?)) (cancel!))
         (set-gpu-presenter-busy?! p #f)
         (cond
           [(gpu-presenter-requested? p)
            ;; Preserve an original user exception while retaining a failed
            ;; cleanup request for an explicit owner-side retry.
            (if completed? (gpu-presenter-close! p)
                (with-handlers ([(lambda (_) #t) (lambda (_) (void))]) (gpu-presenter-close! p)))]
           [else
            (unless (eq? (gpu-presenter-state p) 'failed) (set-gpu-presenter-state! p 'ready))
            (when completed? (schedule! p))])
         (schedule-deferred-owner-work!))))))
