#lang racket/base

;;;
;;; Public API Reflection Fixture
;;;

;; Exports synthetic procedures, syntax, classes, structures, and data for reflection tests.
;; The public API inventory uses this non-native fixture to verify arities, keywords, aliases,
;; and value classification without calling exported operations.

;;;
;;; Imports and Exports
;;;
;; Synthetic reflection fixtures. No Skia modules, renderer, GUI or FFI.
(require racket/class racket/contract/base (for-syntax racket/base))
(provide fixed optional variadic alternatives keywords all-keywords current-choice
         never-call (rename-out [fixed renamed]) alias macro-form
         (struct-out sample) fixture% fixture<%> datum
         (contract-out [contracted (-> integer? integer?)])
         (for-syntax compile-value))

;;;
;;; Fixtures and Assertions
;;;

; never-call : any/c ... -> none/c
;   Always fails so reflection tests detect accidental invocation of exported operations.
(define (never-call . _) (error 'public-api-fixture "an exported operation was called"))

; fixed : any/c any/c any/c -> none/c
;   Exposes a fixed three-argument arity without providing callable behavior.
(define (fixed a b c) (never-call))

; optional : any/c [any/c] -> none/c
;   Exposes one required and one optional positional argument for reflection.
(define (optional a [b 1]) (never-call))

; variadic : any/c any/c ... -> none/c
;   Exposes a required positional argument followed by an arbitrary rest list.
(define (variadic a . rest) (never-call))

; alternatives : procedure?
;   Exposes zero, two, and at-least-four arities through case-lambda.
(define alternatives
  (case-lambda [() (never-call)] [(x y) (never-call)] [(a b c d . rest) (never-call)]))

; keywords : any/c #:required any/c [#:optional any/c] -> none/c
;   Exposes required and optional keyword metadata without being called.
(define (keywords x #:required y #:optional [z 0]) (never-call))

; all-keywords : procedure?
;   Accepts arbitrary keyword names so reflection can identify an unrestricted keyword procedure.
(define all-keywords (make-keyword-procedure (lambda (ks vs . args) (never-call))))

; current-choice : parameter?
;   Exposes a parameter binding with the initial symbolic value.
(define current-choice (make-parameter 'initial))

; alias : syntax
;   Renames the keyword procedure so export reflection must follow binding identity.
(define-syntax alias (make-rename-transformer #'keywords))

; macro-form : syntax
;   Provides a simple macro export that is distinct from a runtime procedure.
(define-syntax-rule (macro-form expression) expression)
(struct sample (a b) #:transparent)
;; a, b: unconstrained Racket values in constructor order. They exist only to
;; expose a two-field transparent structure to reflection; no ordering,
;; ownership, or relationship invariant is imposed on their contents.

; fixture<%> : interface?
;   Exposes an interface with one inspect method for value-shape classification.
(define fixture<%> (interface () inspect))

; fixture% : class?
;   Implements the reflection fixture interface without permitting inspect to be called.
(define fixture% (class* object% (fixture<%>) (super-new) (define/public (inspect) (never-call))))

; datum : vector?
;   Exposes a plain immutable data value alongside callable and syntax exports.
(define datum '#(1 2 3))

; contracted : integer? -> integer?
;   Exposes an integer contract boundary; invoking its implementation deliberately fails.
(define (contracted value) (never-call))
(begin-for-syntax

  ; compile-value : exact-integer?
  ;   Supplies a phase-one export so reflection can distinguish compile-time bindings.
  (define compile-value 42))
