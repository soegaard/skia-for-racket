#lang racket/base
(require "gpu-backends.rkt")
;; Pure execution protocol. No GUI or GPU/native module is loaded here.
(require "gpu-provider.rkt")
(provide output-raster-executor? make-output-raster-executor
         check-output-raster-executor! prepare-output-raster
         (struct-out output-raster-plan) cpu-output-raster-plan
         output-execution-details call-with-lazy-output-raster-executor)

(struct output-raster-executor (creator check prepare))
;; render, when present, calls replay with an ordinary canvas and consume with
;; a detached CPU image plus a native target diagnostic. It owns both temporaries.
(struct output-raster-plan (backend generation fallback render) #:transparent)
(define cpu-output-raster-plan (output-raster-plan 'raster #f #f #f))
(define (accepts! who proc n)
  (unless (and (procedure? proc) (procedure-arity-includes? proc n)
               (let-values ([(required allowed) (procedure-keywords proc)])
                 (null? required)))
    (raise-argument-error who (format "procedure accepting ~a arguments without required keywords" n) proc)))
(define (make-output-raster-executor check prepare)
  (accepts! 'make-output-raster-executor check 0)
  (accepts! 'make-output-raster-executor prepare 1)
  (output-raster-executor (current-thread) check prepare))
(define (check-output-raster-executor! who executor)
  (unless (or (eq? executor 'cpu) (output-raster-executor? executor))
    (raise-argument-error who "'cpu or output-raster-executor?" executor))
  (when (output-raster-executor? executor)
    (unless (eq? (current-thread) (output-raster-executor-creator executor))
      (error who "raster executor belongs to another Racket thread"))
    ((output-raster-executor-check executor)))
  (void))
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

;; An owned, lazy factory is invoked ONLY after the representation and outer
;; audit policies have accepted rasterization. Unavailability is distinct from
;; invalid context state, failed rendering, allocation limits, and user errors.
;; No failure after preparation may trigger a second render or authoring pass.
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
