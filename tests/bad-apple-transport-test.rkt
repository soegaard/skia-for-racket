#lang racket/base

;;;
;;; Bad Apple!! Transport Tests
;;;

(require rackunit
         rackunit/text-ui
         "../examples/bad-apple/transport.rkt")

(provide bad-apple-transport-tests)

(define bad-apple-transport-tests
  (test-suite
   "Bad Apple transport"
   (test-case "starts paused at zero and selects exact 30 fps boundaries"
     (define transport (make-bad-apple-transport 4 30 1 1000.0))
     (check-equal? (bad-apple-transport-state transport) 'paused)
     (check-equal? (bad-apple-transport-current-frame transport) 0)
     (bad-apple-transport-play! transport 1000.0)
     (check-equal? (bad-apple-transport-select-frame! transport 1033.0) 0)
     (check-equal? (bad-apple-transport-select-frame! transport (+ 1000.0 (/ 1000.0 30))) 1))
   (test-case "late callbacks skip to clock-selected frame and end explicitly"
     (define transport (make-bad-apple-transport 4 30 1 0.0))
     (bad-apple-transport-play! transport 0.0)
     (check-equal? (bad-apple-transport-select-frame! transport 85.0) 2)
     (check-equal? (bad-apple-transport-select-frame! transport 1000.0) 3)
     (check-equal? (bad-apple-transport-select-frame! transport 10000.0) 3)
     (check-equal? (bad-apple-transport-state transport) 'ended)
     (check-false (bad-apple-transport-next-delay-ms transport 10000.0)))
   (test-case "pause keeps the anchored media position across an arbitrary wall delay"
     (define transport (make-bad-apple-transport 100 30 1 0.0))
     (bad-apple-transport-play! transport 0.0)
     (bad-apple-transport-pause! transport 100.0)
     (define frame (bad-apple-transport-current-frame transport))
     (check-equal? (bad-apple-transport-select-frame! transport 9000.0) frame)
     (bad-apple-transport-play! transport 9000.0)
     (check-equal? (bad-apple-transport-select-frame! transport (+ 9000.0 (/ 1000.0 30)))
                   (add1 frame)))
   (test-case "integer stepping and seeking clamp exactly at both ends"
     (define transport (make-bad-apple-transport 3 30 1 0.0))
     (bad-apple-transport-step! transport -1 1.0)
     (check-equal? (bad-apple-transport-current-frame transport) 0)
     (bad-apple-transport-step! transport 99 2.0)
     (check-equal? (bad-apple-transport-current-frame transport) 2)
     (bad-apple-transport-seek-frame! transport -50 3.0)
     (check-equal? (bad-apple-transport-current-frame transport) 0))
   (test-case "next deadline is derived from source boundaries, never a busy zero"
     (define transport (make-bad-apple-transport 100 30 1 0.0))
     (bad-apple-transport-play! transport 0.0)
     (check-equal? (bad-apple-transport-next-delay-ms transport 0.0) 34)
     (check-true (positive? (bad-apple-transport-next-delay-ms transport 100.0))))))

(define (run-bad-apple-transport-tests) (run-tests bad-apple-transport-tests))
(module+ main (run-bad-apple-transport-tests))
(module+ test (run-bad-apple-transport-tests))
