#lang racket/base
(require rackunit racket/list json
         "../private/gpu-cache.rkt" "../private/gpu-cache-util.rkt"
         (submod "../private/gpu-cache.rkt" testing)
         "../private/gpu-context.rkt" "../private/gpu-domain.rkt"
         "../private/gpu-io-trace.rkt" "../private/gpu-interop-guard.rkt"
         "gpu-fixtures.rkt")
(provide gpu-cache-pure-tests)
(define (with-mock proc)
  (call-with-mock
    (lambda (d provider driver log abandoned?)
      (define c (wrap-gpu-domain d)) (define limit (box 1024)) (define calls (box '()))
      (define (dispatch op p . args)
        (set-box! calls (cons (cons op args) (unbox calls)))
        (case op [(abandoned?) #f] [(info) (values (unbox limit) 2 256)]
          [(set-limit) (set-box! limit (car args))] [else (void)]))
      (dynamic-wind void
        (lambda () (parameterize ([current-cache-dispatch dispatch]) (proc c d calls)))
        (lambda () (gpu-context-close! c))))))
(define (active proc)
  (with-mock (lambda (c d calls) (domain-call d (lambda () (proc c d calls))))))

(define gpu-cache-pure-tests
  (test-suite "gpu-cache-pure-tests"
    (test-case "size_t zero and maximum"
      (check-equal? (cache-size 't 0) 0) (define m (sub1 (expt 2 (system-type 'word)))) (check-equal? (cache-size 't m) m))
    (test-case "invalid size_t arguments"
      (for ([x (list -1 1/2 1.0 #f +inf.0 +nan.0 (expt 2 (system-type 'word)))]) (check-exn exn:fail? (lambda () (cache-size 't x)))))
    (test-case "age bounds avoid chrono conversion overflow"
      (check-equal? (cache-age 't 0) 0) (check-equal? (cache-age 't #x7fffffff) #x7fffffff) (check-exn exn:fail? (lambda () (cache-age 't #x80000000))))
    (test-case "invalid age arguments"
      (for ([x '(-1 1/2 1.0 #f +inf.0)]) (check-exn exn:fail? (lambda () (cache-age 't x)))))
    (test-case "strict boolean"
      (check-false (cache-boolean 't #f)) (check-exn exn:fail? (lambda () (cache-boolean 't 0))))
    (test-case "immutable JSON snapshot"
      (define s (cache-snapshot 'metal 2 0 2 256)) (check-true (immutable? s)) (check-not-exn (lambda () (jsexpr->string s))))
    (test-case "budgeted usage is not total VRAM"
      (define s (cache-snapshot 'opengl 2 0 2 256)) (check-equal? (hash-ref s 'budgeted_bytes) 256) (check-false (hash-ref s 'total_gpu_bytes)) (check-false (hash-ref s 'limit_is_hard_allocation_cap)))
    (test-case "negative native count rejected"
      (check-exn exn:fail? (lambda () (cache-snapshot 'metal 1 0 -1 0))))
    (test-case "invalid context rejected"
      (check-exn exn:fail:contract? (lambda () (gpu-cache-info 'invalid))))
    (test-case "inactive context rejected before dispatch"
      (with-mock (lambda (c d calls) (check-exn exn:fail? (lambda () (gpu-cache-info c))) (check-equal? (unbox calls) '()))))
    (test-case "wrong thread rejected before dispatch"
      (with-mock (lambda (c d calls) (check-true (exn:fail? (in-worker (lambda () (gpu-cache-info c))))) (check-equal? (unbox calls) '()))))
    (test-case "query reflects current generation"
      (active (lambda (c d calls) (check-equal? (hash-ref (gpu-cache-info c) 'context_generation) (domain-generation d)))))
    (test-case "budget setter roundtrip"
      (active (lambda (c d calls) (gpu-set-cache-limit! c 99) (check-equal? (hash-ref (gpu-cache-info c) 'limit_bytes) 99))))
    (test-case "all unlocked default"
      (active (lambda (c d calls) (check-true (void? (gpu-purge-unlocked! c))) (check-equal? (car (unbox calls)) '(purge #f)))))
    (test-case "scratch only explicit"
      (active (lambda (c d calls) (check-true (void? (gpu-purge-unlocked! c #:scratch-only? #t))) (check-equal? (car (unbox calls)) '(purge #t)))))
    (test-case "bytes preference default"
      (active (lambda (c d calls) (check-true (void? (gpu-purge-bytes! c 123))) (check-equal? (car (unbox calls)) '(purge-bytes 123 #t)))))
    (test-case "bytes LRU explicit"
      (active (lambda (c d calls) (check-true (void? (gpu-purge-bytes! c 123 #:prefer-scratch? #f))) (check-equal? (car (unbox calls)) '(purge-bytes 123 #f)))))
    (test-case "deferred age dispatch"
      (active (lambda (c d calls) (check-true (void? (gpu-perform-deferred-cleanup! c 25))) (check-equal? (car (unbox calls)) '(deferred 25)))))
    (test-case "free dispatch"
      (active (lambda (c d calls) (check-true (void? (gpu-free-resources! c))) (check-equal? (car (unbox calls)) '(free-resources)))))
    (test-case "invalid argument never reaches native"
      (active (lambda (c d calls) (check-exn exn:fail? (lambda () (gpu-set-cache-limit! c -1))) (check-equal? (unbox calls) '()))))
    (test-case "free ledger admits native submission"
      (active (lambda (c d calls) (define b (box '())) (parameterize ([current-gpu-io-ledger b]) (gpu-free-resources! c)) (check-true (hash-ref (car (unbox b)) 'native_may_submit)) (check-false (hash-ref (car (unbox b)) 'completion_guaranteed)))))
    (test-case "ordinary purge is not completion"
      (active (lambda (c d calls) (define b (box '())) (parameterize ([current-gpu-io-ledger b]) (gpu-purge-unlocked! c)) (check-false (hash-ref (car (unbox b)) 'completion_guaranteed)))))
    (test-case "native failures propagate"
      (active (lambda (c d calls) (parameterize ([current-cache-dispatch (lambda (op p . args) (if (eq? op 'abandoned?) #f (error 'native "failure")))]) (check-exn #rx"failure" (lambda () (gpu-free-resources! c)))))))
    (test-case "native loss requests shutdown"
      (with-mock (lambda (c d calls) (domain-call d (lambda () (parameterize ([current-cache-dispatch (lambda args #t)]) (check-exn #rx"lost" (lambda () (gpu-cache-info c)))))) (check-true (hash-ref (domain-info d) 'shutdown_requested)))))
    (test-case "closed context stays rejected"
      (with-mock (lambda (c d calls) (gpu-context-close! c) (check-exn exn:fail? (lambda () (gpu-cache-info c))))))
    (test-case "snapshot cannot change retroactively"
      (active (lambda (c d calls) (define h (gpu-cache-info c)) (gpu-set-cache-limit! c 1) (check-equal? (hash-ref h 'limit_bytes) 1024))))
    (test-case "nested same-domain scope"
      (active (lambda (c d calls) (domain-call d (lambda () (gpu-cache-info c))) (check-not-exn (lambda () (gpu-cache-info c))))))
    (test-case "foreign active domain rejected"
      (with-mock (lambda (c d calls) (call-with-mock (lambda (other p driver log abandoned?) (domain-call other (lambda () (check-exn exn:fail? (lambda () (gpu-cache-info c))))))) (check-equal? (unbox calls) '()))))
    (test-case "external raw GL excludes cache access"
      (active (lambda (c d calls) (parameterize ([current-external-gl? #t]) (check-exn exn:fail? (lambda () (gpu-cache-info c)))))))
    (test-case "query never allocates resource wrappers"
      (active (lambda (c d calls) (gpu-cache-info c) (check-equal? (domain-live-count d) 0) (check-equal? (domain-pending-count d) 0))))
    ))
