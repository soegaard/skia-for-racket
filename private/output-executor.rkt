#lang racket/base

;;;
;;; Raster Output Execution
;;;

;; Defines deferred raster plans and validates their execution owner.
;; Allows document output to request raster work without coupling planning to a backend.

(require "gpu-backends.rkt")
;; Pure execution protocol. No GUI or GPU/native module is loaded here.
(require "gpu-provider.rkt")
(provide output-raster-executor? make-output-raster-executor
         check-output-raster-executor! prepare-output-raster
         (struct-out output-raster-plan) cpu-output-raster-plan
         output-execution-details call-with-lazy-output-raster-executor)

;;;
;;; Raster Executor and Plan Contracts
;;;

(struct output-raster-executor (creator check prepare))
;; Fields:
;;   creator: owner thread. check: preflight procedure. prepare: procedure producing an
;;   output-raster-plan. Execution cannot silently move to another thread or generation.

;; render, when present, calls replay with an ordinary canvas and consume with
;; a detached CPU image plus a native target diagnostic. It owns both temporaries.
(struct output-raster-plan (backend generation fallback render) #:transparent)
;; Fields:
;;   backend: chosen raster backend symbol. generation: optional executor generation. fallback:
;;   detached fallback description. render: deferred rendering procedure. Planning does not itself
;;   perform native rendering.

; cpu-output-raster-plan : output-raster-plan?
;   Selects ordinary CPU rasterization without a GPU generation, fallback record, or deferred
;   renderer.
(define cpu-output-raster-plan (output-raster-plan 'raster #f #f #f))

; accepts! : symbol? procedure? exact-nonnegative-integer? -> void?
;   Checks the positional callback protocol before a deferred executor can allocate native
;   resources.
(define (accepts! who proc n)
  (unless (and (procedure? proc) (procedure-arity-includes? proc n)
               (let-values ([(required allowed) (procedure-keywords proc)])
                 (null? required)))
    (raise-argument-error who (format "procedure accepting ~a arguments without required keywords" n)
      proc)))

; make-output-raster-executor : procedure? procedure? -> output-raster-executor?
;   Captures the owner thread together with preflight and deferred plan-construction callbacks.
(define (make-output-raster-executor check prepare)
  (accepts! 'make-output-raster-executor check 0)
  (accepts! 'make-output-raster-executor prepare 1)
  (output-raster-executor (current-thread) check prepare))

; check-output-raster-executor! : symbol? output-raster-executor? -> void?
;   Accepts the CPU sentinel or checks the private executor's owner and current lifecycle state.
(define (check-output-raster-executor! who executor)
  (unless (or (eq? executor 'cpu) (output-raster-executor? executor))
    (raise-argument-error who "'cpu or output-raster-executor?" executor))
  (when (output-raster-executor? executor)
    (unless (eq? (current-thread) (output-raster-executor-creator executor))
      (error who "raster executor belongs to another Racket thread"))
    ((output-raster-executor-check executor)))
  (void))

;;;
;;; Preflight and Execution Details
;;;

; prepare-output-raster : output-raster-executor? any/c -> any
;   Obtains a checked raster plan and requires a positive context generation and renderer for GPU
;   plans.
(define (prepare-output-raster executor picture)
  (check-output-raster-executor! 'draw-output-group executor)
  (define plan
    (if (eq? executor 'cpu) cpu-output-raster-plan
        ((output-raster-executor-prepare executor) picture)))
  (unless (and (output-raster-plan? plan)
               (or (eq? (output-raster-plan-backend plan) 'raster)
                   (gpu-backend? (output-raster-plan-backend plan))))
    (error 'draw-output-group "invalid private raster execution plan"))
  (unless (eq? (output-raster-plan-backend plan) 'raster)
    (unless (exact-positive-integer? (output-raster-plan-generation plan))
      (error 'draw-output-group "GPU executor has no context generation"))
    (accepts! 'draw-output-group (output-raster-plan-render plan) 5))
  plan)

; output-execution-details : any/c symbol? symbol? [#:plan (or/c #f output-raster-plan?)] [#:target
;   any/c] -> hash?
;   Builds detached execution evidence, distinguishing requested backend, fallback, phase, and
;   completed readback.
(define (output-execution-details executor phase backend
                                  #:plan [plan #f] #:target [target #f])
  (define gpu? (and plan (gpu-backend? (output-raster-plan-backend plan))))
  (define complete? (memq phase '(rasterized completed)))
  (hasheq 'requested (if (eq? executor 'cpu) "cpu" "gpu")
          'phase (symbol->string phase)
          'backend (and backend (symbol->string backend))
          'context_generation (and plan (output-raster-plan-generation plan))
          'fallback (and plan (output-raster-plan-fallback plan))
          'readback_count (if (and gpu? complete?) 1 0)
          'transfer (if (and gpu? complete?) "gpu-to-cpu" "none")
          'image_storage (and complete? "cpu-owned")
          'target target))

;;;
;;; Lazy Executor Acquisition and Cleanup
;;;

;; An owned, lazy factory is invoked ONLY after the representation and outer
;; audit policies have accepted rasterization. Unavailability is distinct from
;; invalid context state, failed rendering, allocation limits, and user errors.
;; No failure after preparation may trigger a second render or authoring pass.

; call-with-lazy-output-raster-executor : procedure? procedure? procedure? procedure? procedure?
;   [#:on-unavailable any/c] -> any
;   Delays owned GPU creation until accepted raster work and permits CPU fallback only for factory
;   unavailability.
(define (call-with-lazy-output-raster-executor create check make-plan close proc
                                               #:on-unavailable [policy 'error])
  (define who 'call-with-gpu-raster-executor)
  (unless (memq policy '(error cpu))
    (raise-argument-error who "'error or 'cpu" policy))
  (accepts! who create 0) (accepts! who check 1)
  (accepts! who make-plan 2) (accepts! who close 1) (accepts! who proc 1)
  (define live? #t)
  (define owned #f)
  (define state 'unresolved)
  (define failure #f) ; boxed so even (raise #f) is retained
  (define unavailable #f)
  (define (live!)
    (unless live? (error who "raster executor scope has expired")))
  (define executor
    (make-output-raster-executor
     live!
     (lambda (picture)
       (live!)
       (when (eq? state 'resolving) (error who "recursive GPU context factory"))
       (when (eq? state 'failed) (raise (unbox failure)))
       (when (eq? state 'unresolved)
         (set! state 'resolving)
         (with-handlers ([(lambda (_) #t)
                          (lambda (e) (set! failure (box e)) (set! state 'failed) (raise e))])
           ;; Catch ONLY context factory unavailability. check/make-plan and
           ;; every later draw/readback/cleanup failure are NOT CPU fallbacks.
           (with-handlers ([exn:fail:gpu:unavailable?
                            (lambda (e)
                              (if (eq? policy 'cpu)
                                  (begin
                                    (set! unavailable
                                      (hasheq 'reason "gpu-unavailable"
                                              'step (symbol->string (exn:fail:gpu:unavailable-step e))
                                              'message (string->immutable-string (exn-message e))))
                                    (set! state 'cpu))
                                  (raise e)))])
             ;; No break between receiving an owned context and registering it
             ;; for scope cleanup. This is not a Racket atomic section.
             (parameterize-break #f (set! owned (create))))
           (unless (eq? state 'cpu) (check owned) (set! state 'ready))))
       (case state
         [(cpu) (output-raster-plan 'raster #f unavailable #f)]
         [else (check owned) (make-plan owned picture)]))))
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind live!
       (lambda () (proc executor))
       (lambda ()
         ;; Expire before attempting cleanup; an indeterminate destructor is
         ;; never retried by invoking this executor again.
         (set! live? #f)
         (when owned
           (define value owned)
           (set! owned #f)
           (close value)))))))
