#lang racket/base
(require rackunit racket/list "../private/gpu-performance-util.rkt")
(provide gpu-performance-pure-tests)
(define (clock xs) (lambda () (begin0 (car xs) (set! xs (cdr xs)))))

(define gpu-performance-pure-tests
  (test-suite "gpu-performance-pure-tests"
    (test-case "defaults"
      (check-equal? (hash-ref (performance-config) 'samples) 12) (check-equal? (hash-ref (performance-config) 'cycles) 3))
    (test-case "too few samples"
      (check-exn exn:fail? (lambda () (performance-config #:samples 2))))
    (test-case "no warmup rejected"
      (check-exn exn:fail? (lambda () (performance-config #:warmup 0))))
    (test-case "too few cycles rejected"
      (check-exn exn:fail? (lambda () (performance-config #:cycles 2))))
    (test-case "partial checkpoint rejected"
      (check-exn exn:fail? (lambda () (performance-config #:frames 61)))
      (check-exn exn:fail? (lambda () (performance-config #:frames 9990 #:cycles 50))))
    (test-case "noninteger extent rejected"
      (check-exn exn:fail? (lambda () (performance-config #:width 640.0))))
    (test-case "negative sample request"
      (check-exn exn:fail? (lambda () (performance-config #:sample-count -1))))
    (test-case "measurement preserves result"
      (parameterize ([performance-clock (clock '(10 15))]) (define-values (v r) (measure-one (lambda () 'result))) (check-eq? v 'result) (check-equal? (hash-ref r 'elapsed_ms) 5.0)))
    (test-case "clock regression rejected"
      (parameterize ([performance-clock (clock '(15 10))]) (check-exn exn:fail? (lambda () (measure-one void)))))
    (test-case "clock NaN rejected"
      (parameterize ([performance-clock (clock '(0 +nan.0))]) (check-exn exn:fail? (lambda () (measure-one void)))))
    (test-case "zero duration valid"
      (parameterize ([performance-clock (clock '(5 5))]) (define-values (v r) (measure-one void)) (check-equal? (hash-ref r 'elapsed_ms) 0.0)))
    (test-case "completed phases sum and order"
      (define events '()) (define (step x) (lambda () (set! events (cons x events)))) (parameterize ([performance-clock (clock '(1 3 6 10 20))]) (define r (measure-completed (step 'draw) (step 'flush) (step 'submit) (step 'wait))) (check-equal? (hash-ref r 'completed_ms) 19.0) (check-equal? (hash-ref r 'completion_wait_ms) 10.0)) (check-equal? (reverse events) '(draw flush submit wait)))
    (test-case "failure prevents later phases"
      (define later? #f) (check-exn exn:fail? (lambda () (measure-completed (lambda () (error 'draw "failed")) (lambda () (set! later? #t)) void void))) (check-false later?))
    (test-case "even median"
      (check-equal? (hash-ref (sample-statistics '(1 3 5 7)) 'median) 4.0))
    (test-case "nearest rank p95"
      (check-equal? (hash-ref (sample-statistics (range 1 21)) 'p95) 19))
    (test-case "invalid statistics rejected"
      (for ([xs (list '() '(1 -1) '(1 +nan.0) '(1 +inf.0) '(#f))]) (check-exn exn:fail? (lambda () (sample-statistics xs)))))
    ))
