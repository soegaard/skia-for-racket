#lang racket/base
;; No native library or GUI initialization in this module.
(provide make-gpu-provider gpu-provider? gpu-provider-name gpu-provider-backend
         gpu-provider-key gpu-provider-activate gpu-provider-current?
         gpu-provider-describe gpu-provider-creator gpu-provider-resolve
         provider-with-resolver provider-call freeze-gpu-details
         exn:fail:gpu:unavailable? exn:fail:gpu:unavailable-step
         gpu-unavailable)

(struct exn:fail:gpu:unavailable exn:fail (step) #:transparent)
(define (gpu-unavailable step message . arguments)
  (raise (exn:fail:gpu:unavailable
          (apply format message arguments) (current-continuation-marks) step)))
(struct gpu-provider (name backend key activate current? describe creator resolve))
(define (provider-with-resolver p resolver)
  (struct-copy gpu-provider p [resolve resolver]))
(define (arity who p n)
  (unless (and (procedure? p) (procedure-arity-includes? p n))
    (raise-argument-error who (format "procedure accepting ~a arguments" n) p)))
(define (make-gpu-provider #:name name #:backend backend #:key key
                           #:call-as-current activate #:current? current?
                           #:describe [describe (lambda () (hasheq))]
                           #:get-proc-address [resolve #f])
  (define who 'make-gpu-provider)
  (unless (symbol? name) (raise-argument-error who "symbol?" name))
  (unless (memq backend '(opengl metal))
    (raise-argument-error who "'opengl or 'metal" backend))
  (unless (or (symbol? key) (exact-positive-integer? key))
    (raise-argument-error who "symbol or exact-positive-integer context identity" key))
  (arity who activate 1) (arity who current? 0) (arity who describe 0)
  (when resolve (arity who resolve 1))
  (gpu-provider name backend key activate current? describe (current-thread) resolve))

;; Protect the activation contract independently of any provider's lock. The
;; thunk must run exactly once, synchronously, on this Racket thread. Saved
;; provider thunks and continuation reentry cannot reactivate a retired lease.
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
