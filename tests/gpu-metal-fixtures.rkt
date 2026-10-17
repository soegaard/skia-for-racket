#lang racket/base

;;;
;;; GPU Metal Fixtures
;;;

;; Provides shared inputs and drawing fixtures for Metal device/queue ownership, activation
;; scopes, and abandonment.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
(require "../private/gpu-metal-util.rkt" "../private/gpu-native-scope.rkt"
         "../private/gpu-domain.rkt")
(provide (struct-out metal-fixture) make-metal-fixture with-metal-fixture
         metal-events metal-event-count metal-live-refs)

;;;
;;; Fixtures and Assertions
;;;
(struct metal-fixture (provider driver scope events refs failure in-pool))
;; provider: synthetic Metal provider produced by the injected platform ops.
;; driver: matching context driver; it shares the provider's reference ledger.
;; scope: simulated autorelease-pool scope required around native operations.
;; events: box of event symbols, newest first; metal-events reverses for checks.
;; refs: mutable hash of nonnegative device, queue, and context reference counts.
;; failure: box containing #f or the operation tag that should fail.
;; in-pool: box of a boolean, true only while the synthetic pool is active.
;; No real Metal objects are owned here. Successful teardown balances all
;; reference counts and pool entries, including after injected failures.

; make-metal-fixture : [any/c] -> metal-fixture?
;;   Builds synthetic Metal platform/context operations with pool and reference-count assertions.
(define (make-metal-fixture [fail #f])
  (define events (box '()))
  (define context-token (gensym 'metal-context))
  (define refs (make-hasheq '((device . 0) (queue . 0) (context . 0))))
  (define failure (box fail))
  (define in-pool (box #f))
  (define (emit x) (set-box! events (cons x (unbox events))))
  (define (ref! name n)
    (define count (+ (hash-ref refs name) n))
    (when (< count 0) (error 'metal-mock "double release"))
    (hash-set! refs name count))
  (define (native!) (unless (unbox in-pool) (error 'metal-mock "native call outside pool")))
  (define (fail! tag) (when (eq? tag (unbox failure)) (error 'metal-mock "injected failure")))
  (define scope
    (make-gpu-native-scope
     (lambda ()
       (when (unbox in-pool) (error 'metal-mock "unexpected nested pool"))
       (set-box! in-pool #t) (emit 'pool-enter) 'pool-token)
     (lambda (token)
       (unless (and (eq? token 'pool-token) (unbox in-pool)) (error 'metal-mock "invalid pool exit"))
       (set-box! in-pool #f) (emit 'pool-leave))))
  (define-values (provider driver)
    (make-metal-components
     (metal-platform-ops
      scope
      (lambda () (native!) (emit 'device) (fail! 'device-raise)
        (and (not (eq? (unbox failure) 'device-null)) (begin (ref! 'device 1) 'device)))
      (lambda (device) (native!) (emit 'queue) (fail! 'queue-raise)
        (and (not (eq? (unbox failure) 'queue-null)) (begin (ref! 'queue 1) 'queue)))
      (lambda (object) (native!) (emit (if (eq? object 'queue) 'release-queue 'release-device))
        (ref! object -1))
      (lambda (device) (native!) (emit 'device-info) (fail! 'device-info)
        (hasheq 'renderer "SYNTHETIC Metal" 'device "SYNTHETIC Metal")))
     (metal-context-ops
      (lambda (device queue)
        (native!) (emit 'create) (fail! 'context-raise)
        (and (not (eq? (unbox failure) 'context-null))
             (begin (ref! 'device 1) (ref! 'queue 1) (ref! 'context 1) context-token)))
      (lambda (context)
        (native!) (emit 'release-context)
        (ref! 'context -1) (ref! 'queue -1) (ref! 'device -1))
      (lambda (context) (native!) (emit 'abandon))
      (lambda (context) (native!) (emit 'reset))
      (lambda (context details)
        (native!) (emit 'context-info) (fail! 'context-info)
        (hash-set details 'native_backend 2)))))
  (metal-fixture provider driver scope events refs failure in-pool))

; with-metal-fixture : procedure? -> any
;;   Scopes a GPU domain over the synthetic Metal provider and guarantees domain closure.
(define (with-metal-fixture proc)
  (define f (make-metal-fixture))
  (define d (make-gpu-domain (metal-fixture-provider f) (metal-fixture-driver f)))
  (dynamic-wind void (lambda () (proc f d)) (lambda () (domain-close! d))))

; metal-events : metal-fixture? -> list?
;;   Returns recorded Metal lifecycle events in execution order.
(define (metal-events f) (reverse (unbox (metal-fixture-events f))))

; metal-event-count : metal-fixture? any/c -> exact-nonnegative-integer?
;;   Counts occurrences of a selected synthetic Metal event.
(define (metal-event-count f event)
  (for/sum ([x (in-list (metal-events f))]) (if (eq? x event) 1 0)))

; metal-live-refs : metal-fixture? -> (listof exact-nonnegative-integer?)
;;   Returns outstanding device, queue, and context reference counts in that order.
(define (metal-live-refs f)
  (for/list ([key '(device queue context)]) (hash-ref (metal-fixture-refs f) key)))
