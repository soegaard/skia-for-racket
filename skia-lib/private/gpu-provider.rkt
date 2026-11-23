#lang racket/base

;;;
;;; GPU Context Providers
;;;

;; Defines provider identity, activation, capability descriptions, and unavailability errors.
;; Separates host-context ownership from Skia's backend-independent GPU domain.

(require "gpu-backends.rkt")
;; No native library or GUI initialization in this module.
(provide make-gpu-provider gpu-provider? gpu-provider-name gpu-provider-backend
         gpu-provider-key gpu-provider-activate gpu-provider-current?
         gpu-provider-describe gpu-provider-creator gpu-provider-resolve
         provider-with-resolver provider-call freeze-gpu-details
         exn:fail:gpu:unavailable? exn:fail:gpu:unavailable-step
         gpu-unavailable)

;;;
;;; Provider Contract and Availability Errors
;;;

(struct exn:fail:gpu:unavailable exn:fail (step) #:transparent)
;; Fields:
;;   step: symbolic backend-setup step that failed. Inherited exception fields preserve the
;;   diagnostic and continuation marks without exposing native handles.

; gpu-unavailable : symbol? string? any/c ... -> none/c
;   Raises a backend-setup exception tagged with the failing selection or initialization step.
(define (gpu-unavailable step message . arguments)
  (raise (exn:fail:gpu:unavailable
          (apply format message arguments) (current-continuation-marks) step)))
(struct gpu-provider (name backend key activate current? describe creator resolve))
;; Fields:
;;   name and backend: provider/backend symbols. key: stable host-context identity used to prevent
;;   duplicate domains. activate: scoped activation procedure. current?: zero-argument
;;   current-context predicate.
;;   describe: detached diagnostic query. creator: owning Racket thread. resolve: native procedure
;;   lookup. Provider activation must preserve host context ownership and restore surrounding state.

; provider-with-resolver : gpu-provider? (or/c #f procedure?) -> gpu-provider?
;   Copies a provider while replacing only its native procedure resolver.
(define (provider-with-resolver p resolver)
  (struct-copy gpu-provider p [resolve resolver]))

; arity : symbol? procedure? exact-nonnegative-integer? -> void?
;   Requires a procedure accepting the positional arity needed by a private provider operation.
(define (arity who p n)
  (unless (and (procedure? p) (procedure-arity-includes? p n))
    (raise-argument-error who (format "procedure accepting ~a arguments" n) p)))

; make-gpu-provider : #:name symbol? #:backend 'opengl #:key (or/c symbol?
;   exact-positive-integer?) #:call-as-current procedure? #:current? procedure? [#:describe
;   procedure?] [#:get-proc-address (or/c procedure? #f)] -> gpu-provider?
;   Creates an external OpenGL provider owned by the current Racket thread.
(define (make-gpu-provider #:name name #:backend backend #:key key
                           #:call-as-current activate #:current? current?
                           #:describe [describe (lambda () (hasheq))]
                           #:get-proc-address [resolve #f])
  (unless (eq? backend 'opengl)
    (raise-argument-error 'make-gpu-provider "'opengl" backend))
  (make-host-provider #:name name #:backend backend #:key key
                      #:call-as-current activate #:current? current?
                      #:describe describe #:get-proc-address resolve))

; make-host-provider : #:name symbol? #:backend symbol? #:key (or/c symbol? exact-positive-integer?)
;   #:call-as-current procedure? #:current? procedure? [#:describe procedure?]
;   [#:get-proc-address (or/c procedure? #f)] -> gpu-provider?
;   Constructs checked host callbacks for external GL or the private owned-device adapters.
(define (make-host-provider #:name name #:backend backend #:key key
                            #:call-as-current activate #:current? current?
                            #:describe [describe (lambda () (hasheq))]
                            #:get-proc-address [resolve #f])
  (define who 'make-gpu-provider)
  (unless (symbol? name) (raise-argument-error who "symbol?" name))
  (check-gpu-backend! who backend)
  (unless (or (symbol? key) (exact-positive-integer? key))
    (raise-argument-error who "symbol or exact-positive-integer context identity" key))
  (arity who activate 1) (arity who current? 0) (arity who describe 0)
  (when resolve (arity who resolve 1))
  (gpu-provider name backend key activate current? describe (current-thread) resolve))

(module* host-internals #f (provide make-host-provider))

;;;
;;; Activation, Restoration, and Detached Diagnostics
;;;

;; Protect the activation contract independently of any provider's lock. The
;; thunk must run exactly once, synchronously, on this Racket thread. Saved
;; provider thunks and continuation reentry cannot reactivate a retired lease.

; provider-call : gpu-provider? procedure? -> any
;   Runs a thunk through the provider's activation protocol while enforcing creator-thread
;   ownership.
(define (provider-call p thunk)
  (unless (gpu-provider? p) (raise-argument-error 'provider-call "gpu-provider?" p))
  (unless (eq? (gpu-provider-creator p) (current-thread))
    (error 'provider-call "provider belongs to another Racket thread"))
  (define used? #f)
  (define retired? #f)
  (define results #f)
  (define failure #f)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (when retired? (error 'provider-call "activation scope has expired")))
       (lambda ()
         ;; A provider must not turn an intercepted callback failure into a
         ;; successful constructor, or replace the user's multiple values.
         (call-with-values
          (lambda ()
            ((gpu-provider-activate p)
             (lambda ()
               (with-handlers ([(lambda (_) #t)
                                (lambda (e) (set! failure (list e)) (raise e))])
                 (unless (eq? (gpu-provider-creator p) (current-thread))
                   (error 'provider-call "provider invoked its callback on another thread"))
                 (when (or used? retired?)
                   (error 'provider-call "provider callback reused or invoked after return"))
                 (set! used? #t)
                 (unless ((gpu-provider-current? p))
                   (error 'provider-call "provider did not activate its native context"))
                 (call-with-values thunk
                   (lambda values-list
                     (set! results values-list)
                     (apply values values-list)))))))
          (lambda ignored (void)))
         (when failure (raise (car failure)))
         (unless used? (error 'provider-call "provider did not invoke its callback"))
         (unless results (error 'provider-call "provider callback did not complete normally"))
         (apply values results))
       (lambda () (set! retired? #t))))))

;; Detach provider diagnostics and keep raw OS handles out of public reports.

; freeze-gpu-details : hash? -> any
;   Copies diagnostic data into detached immutable values before exposing it outside native setup.
(define (freeze-gpu-details value)
  (cond
    [(string? value) (string->immutable-string value)]
    [(boolean? value) value]
    [(and (real? value) (= value value) (< -inf.0 value +inf.0))
     (if (exact-integer? value) value (exact->inexact value))]
    [(list? value) (map freeze-gpu-details value)]
    [(hash? value)
     (for/hasheq ([(key item) (in-hash value)])
       (unless (symbol? key) (error 'gpu-provider "diagnostic hash keys must be symbols"))
       (values key (freeze-gpu-details item)))]
    [else (error 'gpu-provider "diagnostics must contain JSON-compatible detached values")]))
