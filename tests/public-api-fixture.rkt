#lang racket/base
;; Synthetic reflection fixtures. No Skia modules, renderer, GUI or FFI.
(require racket/class racket/contract/base (for-syntax racket/base))
(provide fixed optional variadic alternatives keywords all-keywords current-choice
         never-call (rename-out [fixed renamed]) alias macro-form
         (struct-out sample) fixture% fixture<%> datum
         (contract-out [contracted (-> integer? integer?)])
         (for-syntax compile-value))
(define (never-call . _) (error 'public-api-fixture "an exported operation was called"))
(define (fixed a b c) (never-call))
(define (optional a [b 1]) (never-call))
(define (variadic a . rest) (never-call))
(define alternatives (case-lambda [() (never-call)] [(x y) (never-call)] [(a b c d . rest) (never-call)]))
(define (keywords x #:required y #:optional [z 0]) (never-call))
(define all-keywords (make-keyword-procedure (lambda (ks vs . args) (never-call))))
(define current-choice (make-parameter 'initial))
(define-syntax alias (make-rename-transformer #'keywords))
(define-syntax-rule (macro-form expression) expression)
(struct sample (a b) #:transparent)
(define fixture<%> (interface () inspect))
(define fixture% (class* object% (fixture<%>) (super-new) (define/public (inspect) (never-call))))
(define datum '#(1 2 3))
(define (contracted value) (never-call))
(begin-for-syntax (define compile-value 42))
