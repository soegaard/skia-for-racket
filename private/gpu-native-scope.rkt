#lang racket/base
(require ffi/unsafe/atomic)
(provide make-gpu-native-scope current-gpu-native-scope
         call-with-gpu-native-scope capture-gpu-native-release)

;; A native scope is private plumbing, not an application callback facility.
;; Metal uses it for an autorelease pool around ONE synchronous FFI operation.
;; Never keep a thread-local Objective-C pool open across a user drawing thunk,
;; sleep/yield, GUI acquisition, or a Racket continuation suspension.
(struct native-scope (creator enter leave))
(define (make-gpu-native-scope enter leave)
  (unless (and (procedure? enter) (procedure-arity-includes? enter 0))
    (raise-argument-error 'make-gpu-native-scope "zero-argument enter procedure" enter))
  (unless (and (procedure? leave) (procedure-arity-includes? leave 1))
    (raise-argument-error 'make-gpu-native-scope "one-argument leave procedure" leave))
  (native-scope (current-thread) enter leave))
(define current-gpu-native-scope
  (make-parameter #f
    (lambda (v)
      (unless (or (not v) (native-scope? v))
        (raise-argument-error 'current-gpu-native-scope "#f or private native scope" v))
      v)))
(define running-scope (make-parameter #f))
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
(define (capture-gpu-native-release release)
  (define scope (current-gpu-native-scope))
  (if scope
      (lambda (pointer)
        ;; Finalizers only ENQUEUE this closure. Owner-side draining calls it,
        ;; including after abandon, when the activation parameter is absent.
        (parameterize ([current-gpu-native-scope scope])
          (call-with-gpu-native-scope (lambda () (release pointer)))))
      release))
