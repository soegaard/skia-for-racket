#lang racket/base
(require rackunit rackunit/text-ui "../private/lifetime.rkt")
(provide lifetime-tests)

;; Synthetic native tokens exercise the actual lifetime implementation,
;; not a separate implementation, without loading libSkiaSharp.
(define (make-fake released)
  (new-owned 'test 'synthetic-resource
             (lambda () 'synthetic-pointer)
             (lambda (_) (set-box! released (add1 (unbox released))))))

(define lifetime-tests
  (test-suite
   "Ownership and scoped cleanup (no native library)"
   (test-case "double close releases exactly once"
     (define count (box 0))
     (define h (make-fake count))
     (check-false (owned-closed? h))
     (check-equal? (call-with-owned 'test (list h) values) 'synthetic-pointer)
     (owned-close! 'test h)
     (owned-close! 'test h)
     (check-true (owned-closed? h))
     (check-equal? (unbox count) 1))
   (test-case "aliases see closure"
     (define count (box 0))
     (define h (make-fake count))
     (define alias h)
     (owned-close! 'test h)
     (check-exn #rx"closed" (lambda () (call-with-owned 'test (list alias) values))))
   (test-case "multiple values survive lifetime protection"
     (define count (box 0))
     (define h (make-fake count))
     (check-equal?
      (call-with-values (lambda () (call-with-owned 'test (list h) (lambda (_) (values 1 2)))) list)
      '(1 2))
     (owned-close! 'test h))
   (test-case "exceptions close scoped resources"
     (define count (box 0))
     (define h (make-fake count))
     (check-exn #rx"deliberate"
       (lambda ()
         (call-with-scoped-resource h (lambda (x) (owned-close! 'test x))
                                    (lambda (_) (error 'test "deliberate")))))
     (check-equal? (unbox count) 1))
   (test-case "cross-thread access is rejected"
     (define count (box 0))
     (define h (make-fake count))
     (define results (make-channel))
     (define worker
       (thread
        (lambda ()
          (channel-put results
            (with-handlers ([exn:fail? exn-message])
              (call-with-owned 'test (list h) values))))))
     (check-regexp-match #rx"another Racket thread" (channel-get results))
     (thread-wait worker)
     (owned-close! 'test h))
   (test-case "null allocation raises before registration"
     (check-exn #rx"allocation failed"
       (lambda () (new-owned 'test 'synthetic (lambda () #f) void))))))

(module+ test
  (define failures (run-tests lifetime-tests))
  (unless (zero? failures) (error 'lifetime-tests "~a failures" failures)))
