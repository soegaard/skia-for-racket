#lang racket/base
(require rackunit json racket/list "../main.rkt" "../gpu.rkt" "gpu-fixtures.rkt"
         "../private/gpu-io-trace.rkt" "gpu-image-native-test.rkt")
(provide make-gpu-cache-native-tests gpu-cache-native-test-count)
(define gpu-cache-native-test-count 20)
(define (make-gpu-cache-native-tests context other)
  (define (using proc)
    (call-with-gpu-context context
      (lambda ()
        (define old (hash-ref (gpu-cache-info context) 'limit_bytes))
        (dynamic-wind void proc
          (lambda () (gpu-set-cache-limit! context old) (gpu-wait! context))))))
  (define (image-proc proc)
    (using (lambda ()
      (with-skia ([cpu (rgba-bytes->image 8 8 image-test-pixels #:premultiplied? #t)]
                  [im (gpu-upload-image context cpu)]) (proc im)))))
  (test-suite "Live GPU cache control"
    (test-case "query has live native values"
      (using (lambda () (define s (gpu-cache-info context)) (check-true (exact-nonnegative-integer? (hash-ref s 'budgeted_bytes))) (check-equal? (hash-ref s 'backend) (symbol->string (gpu-context-backend context))))))
    (test-case "snapshot is immutable JSON"
      (using (lambda () (define s (gpu-cache-info context)) (check-true (immutable? s)) (check-not-exn (lambda () (jsexpr->string s))))))
    (test-case "inactive queries fail"
      (check-exn exn:fail? (lambda () (gpu-cache-info context))))
    (test-case "foreign active context rejected"
      (call-with-gpu-context other (lambda () (check-exn exn:fail? (lambda () (gpu-cache-info context))))))
    (test-case "foreign owner rejected"
      (check-true (exn:fail? (in-worker (lambda () (gpu-cache-info context))))))
    (test-case "zero budget roundtrip"
      (using (lambda () (gpu-set-cache-limit! context 0) (check-equal? (hash-ref (gpu-cache-info context) 'limit_bytes) 0))))
    (test-case "nonzero budget roundtrip"
      (using (lambda () (gpu-set-cache-limit! context 1048576) (check-equal? (hash-ref (gpu-cache-info context) 'limit_bytes) 1048576))))
    (test-case "old query remains detached"
      (using (lambda () (define old (gpu-cache-info context)) (define n (hash-ref old 'limit_bytes)) (gpu-set-cache-limit! context (add1 n)) (check-equal? (hash-ref old 'limit_bytes) n))))
    (test-case "all unlocked purge succeeds"
      (using (lambda () (check-true (void? (gpu-purge-unlocked! context))))))
    (test-case "scratch purge succeeds"
      (using (lambda () (check-true (void? (gpu-purge-unlocked! context #:scratch-only? #t))))))
    (test-case "byte purge LRU succeeds"
      (using (lambda () (check-true (void? (gpu-purge-bytes! context 1048576 #:prefer-scratch? #f))))))
    (test-case "byte purge scratch preference succeeds"
      (using (lambda () (check-true (void? (gpu-purge-bytes! context 0))))))
    (test-case "age zero and large accepted age"
      (using (lambda () (gpu-perform-deferred-cleanup! context 0) (gpu-perform-deferred-cleanup! context #x7fffffff))))
    (test-case "free keeps existing target alive"
      (using (lambda () (with-skia ([s (make-gpu-surface context 8 8 #:background 'red)]) (gpu-free-resources! context) (canvas-clear! (surface-canvas s) 'blue) (check-equal? (subbytes (gpu-surface->rgba-bytes s) 0 4) (bytes 0 0 255 255))))))
    (test-case "purge keeps GPU image alive"
      (image-proc (lambda (im) (gpu-purge-unlocked! context) (check-equal? (gpu-image->rgba-bytes im) image-test-pixels))))
    (test-case "zero cache budget does not destroy live image"
      (image-proc (lambda (im) (gpu-set-cache-limit! context 0) (gpu-free-resources! context) (check-equal? (gpu-image->rgba-bytes im) image-test-pixels))))
    (test-case "retained picture survives cache pressure"
      (image-proc (lambda (im) (with-skia ([sh (make-image-shader im)] [p (make-paint #:shader sh)] [pic (call-with-picture 8 8 (lambda (c) (draw-rect c 0 0 8 8 p)))] [s (make-gpu-surface context 8 8)]) (gpu-free-resources! context) (draw-picture (surface-canvas s) pic) (check-equal? (gpu-surface->rgba-bytes s) image-test-pixels)))))
    (test-case "free ledger declares implicit submission not completion"
      (using (lambda () (define b (box '())) (parameterize ([current-gpu-io-ledger b]) (gpu-free-resources! context)) (check-true (hash-ref (car (unbox b)) 'native_may_submit)) (check-false (hash-ref (car (unbox b)) 'completion_guaranteed)))))
    (test-case "limits are per context"
      (define other-limit (call-with-gpu-context other (lambda () (hash-ref (gpu-cache-info other) 'limit_bytes)))) (using (lambda () (gpu-set-cache-limit! context 12345))) (check-equal? (call-with-gpu-context other (lambda () (hash-ref (gpu-cache-info other) 'limit_bytes))) other-limit))
    (test-case "bad native arguments fail explicitly"
      (using (lambda () (check-exn exn:fail? (lambda () (gpu-set-cache-limit! context -1))) (check-exn exn:fail? (lambda () (gpu-perform-deferred-cleanup! context +inf.0))) (check-exn exn:fail? (lambda () (gpu-purge-unlocked! context #:scratch-only? 1))))))
    ))
