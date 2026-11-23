#lang racket/base

;;;
;;; Native GPU Scope Management
;;;

;; Pairs per-call native thread-local setup and cleanup with execution-owner checks.
;; Gives GPU FFI calls exception-safe support scopes, including Metal autorelease pools.

(require ffi/unsafe/atomic)
(provide make-gpu-native-scope current-gpu-native-scope
         call-with-gpu-native-scope capture-gpu-native-release)

;; A native scope is private plumbing, not an application callback facility.
;; Metal uses it for an autorelease pool around ONE synchronous FFI operation.
;; Never keep a thread-local Objective-C pool open across a user drawing thunk,
;; sleep/yield, GUI acquisition, or a Racket continuation suspension.
(struct native-scope (creator enter leave))
;; Fields:
;;   creator: owning Racket thread. enter: zero-argument native thread-local setup procedure;
;;   leave: one-argument cleanup procedure receiving enter's token. A scope surrounds one atomic
;;   FFI call, such as a Metal autorelease pool; it does not activate a host GPU context.
;;   Cleanup follows successful entry even when the body exits exceptionally.

; make-gpu-native-scope : procedure? procedure? -> native-scope?
;   Pairs zero-argument entry with one-argument cleanup and binds the scope to its creator thread.
(define (make-gpu-native-scope enter leave)
  (unless (and (procedure? enter) (procedure-arity-includes? enter 0))
    (raise-argument-error 'make-gpu-native-scope "zero-argument enter procedure" enter))
  (unless (and (procedure? leave) (procedure-arity-includes? leave 1))
    (raise-argument-error 'make-gpu-native-scope "one-argument leave procedure" leave))
  (native-scope (current-thread) enter leave))

; current-gpu-native-scope : (parameter/c (or/c #f native-scope?))
;   Selects the private per-operation native scope, such as Metal's thread-local autorelease pool.
(define current-gpu-native-scope
  (make-parameter #f
    (lambda (v)
      (unless (or (not v) (native-scope? v))
        (raise-argument-error 'current-gpu-native-scope "#f or private native scope" v))
      v)))

; running-scope : parameter?
;   Avoids opening a second native scope for nested synchronous FFI calls on the same thread.
(define running-scope (make-parameter #f))

; call-with-gpu-native-scope : procedure? -> any
;   Bounds native thread-local setup to one atomic synchronous operation, never to a suspending
;   drawing callback.
(define (call-with-gpu-native-scope thunk)
  (define scope (current-gpu-native-scope))
  (cond
    ;; Parameters are inherited by child Racket threads. CPU-only work in such
    ;; a child must not inherit its parent's native pool. GPU resource access
    ;; still fails the independent creator/domain checks before reaching FFI.
    [(or (not scope) (not (eq? (native-scope-creator scope) (current-thread)))) (thunk)]
    [(eq? scope (running-scope)) (thunk)]
    [else
     ;; Atomicity is local to this FFI operation, not to the user GPU scope.
     ;; It prevents coroutine scheduling between a native pool push and pop.
     ;; Blocking native calls remain synchronous; no event-loop claim is made.
     (call-as-atomic
      (lambda ()
        (define token #f)
        (define entered? #f)
        (call-with-continuation-barrier
         (lambda ()
           (dynamic-wind
             (lambda ()
               (when entered? (error 'gpu-native-scope "native scope cannot be reentered"))
               (set! token ((native-scope-enter scope)))
               (set! entered? #t))
             (lambda () (parameterize ([running-scope scope]) (thunk)))
             (lambda () ((native-scope-leave scope) token)))))))]))

; capture-gpu-native-release : procedure? -> procedure?
;   Captures the allocator's native scope so deferred owner-thread destruction can reestablish it
;   later.
(define (capture-gpu-native-release release)
  (define scope (current-gpu-native-scope))
  (if scope
      (lambda (pointer)
        ;; Finalizers only ENQUEUE this closure. Owner-side draining calls it,
        ;; including after abandon, when the activation parameter is absent.
        (parameterize ([current-gpu-native-scope scope])
          (call-with-gpu-native-scope (lambda () (release pointer)))))
      release))
