#lang racket/base
(require rackunit racket/list
         "../private/gpu-frame-target-cache.rkt" "../private/gpu-io-trace.rkt"
         (only-in "../private/check.rkt" current-skia-byte-limit))
(provide gpu-frame-target-pure-tests gpu-frame-target-pure-test-count)
(define (fixture proc)
  (define cache (make-frame-target-cache))
  (define made 0) (define retired '())
  (define (create) (set! made (add1 made)) (vector made))
  (define (dispose v) (set! retired (cons v retired)))
  (define (use [f values] [w 8] [h 6])
    (call-with-frame-target cache w h create dispose f))
  (dynamic-wind void
    (lambda () (proc cache use (lambda () made) (lambda () retired)))
    (lambda () (unless (hash-ref (frame-target-cache-info cache) 'quarantined)
                 (close-frame-target-cache! cache)))))
(define (stat cache key) (hash-ref (frame-target-cache-info cache) key))
(define (in-worker thunk)
  (define ch (make-channel))
  (thread (lambda ()
    (channel-put ch (with-handlers ([(lambda (_) #t) values]) (thunk) 'returned))))
  (or (sync/timeout 5 ch) (error 'test "worker timeout")))
(define gpu-frame-target-pure-tests
  (test-suite
   "Presenter staging target cache: bounded ownership and single-use scopes"
   (test-case "empty cache allocates nothing"
     (fixture (lambda (c use made retired)
       (check-equal? (made) 0) (check-equal? (stat c 'live_targets) 0))))
   (test-case "first use creates one target"
     (fixture (lambda (c use made retired)
       (check-equal? (use) '#(1)) (check-equal? (made) 1)
       (check-equal? (stat c 'creations) 1) (check-equal? (stat c 'reuses) 0))))
   (test-case "repeated compatible extents reuse the identical target"
     (fixture (lambda (c use made retired)
       (define target (use))
       (for ([_ (in-range 100)]) (check-eq? (use) target))
       (check-equal? (made) 1) (check-equal? (stat c 'reuses) 100))))
   (test-case "width change replaces rather than accumulates targets"
     (fixture (lambda (c use made retired)
       (define old (use)) (use values 9 6)
       (check-equal? (retired) (list old)) (check-equal? (made) 2)
       (check-equal? (stat c 'live_targets) 1))))
   (test-case "height change replaces the target"
     (fixture (lambda (c use made retired)
       (use) (use values 8 7) (check-equal? (made) 2)
       (check-equal? (stat c 'pixel_size) '(8 7)))))
   (test-case "returning to an old size does not retain a size-indexed pool"
     (fixture (lambda (c use made retired)
       (use) (use values 9 7) (use)
       (check-equal? (made) 3) (check-equal? (length (retired)) 2))))
   (test-case "old target is retired before allocating replacement"
     (fixture (lambda (c use made retired)
       (use)
       (call-with-frame-target c 9 7
         (lambda () (check-equal? (length (retired)) 1) 'replacement) void void))))
   (test-case "original disposer owns a cached target"
     (fixture (lambda (c use made retired)
       (define target (use))
       (call-with-frame-target c 8 6 (lambda () (error 'test "unexpected allocation"))
         (lambda (_) (error 'test "wrong disposer")) void)
       (close-frame-target-cache! c) (check-equal? (retired) (list target)))))
   (test-case "close retires exactly once and is idempotent"
     (fixture (lambda (c use made retired)
       (use) (close-frame-target-cache! c) (close-frame-target-cache! c)
       (check-equal? (length (retired)) 1) (check-equal? (stat c 'live_targets) 0)
       (check-true (stat c 'closed)))))
   (test-case "closing an empty cache does not call a factory"
     (fixture (lambda (c use made retired)
       (close-frame-target-cache! c) (check-equal? (made) 0) (check-equal? (retired) '()))))
   (test-case "closed cache cannot be reactivated"
     (fixture (lambda (c use made retired)
       (close-frame-target-cache! c) (check-exn #rx"closed" use)) ))
   (test-case "nested borrowing rejects without retiring the outer target"
     (fixture (lambda (c use made retired)
       (use (lambda (v) (check-exn #rx"nested" use) (check-equal? (retired) '())))
       (check-equal? (made) 1))))
   (test-case "closing during use rejects"
     (fixture (lambda (c use made retired)
       (use (lambda (_) (check-exn #rx"nested" (lambda () (close-frame-target-cache! c)))))
       (check-false (stat c 'closed)))))
   (test-case "user exception discards the target before recovery"
     (fixture (lambda (c use made retired)
       (check-exn #rx"user-error" (lambda () (use (lambda (_) (error 'test "user-error")))))
       (check-equal? (length (retired)) 1) (check-equal? (stat c 'live_targets) 0)
       (use) (check-equal? (made) 2))))
   (test-case "non-exception raised value is preserved"
     (fixture (lambda (c use made retired)
       (define got (with-handlers ([(lambda (_) #t) values]) (use (lambda (_) (raise 'user-value)))))
       (check-eq? got 'user-value) (check-equal? (length (retired)) 1))))
   (test-case "continuation escape discards the target"
     (fixture (lambda (c use made retired)
       (check-eq? (let/ec out (use (lambda (_) (out 'escaped)))) 'escaped)
       (check-false (stat c 'busy)) (check-equal? (stat c 'live_targets) 0)
       (use) (check-equal? (made) 2))))
   (test-case "captured continuation cannot resurrect a finished borrow"
     (fixture (lambda (c use made retired)
       (define saved #f)
       (use (lambda (_) (call/cc (lambda (k) (set! saved k) 'first))))
       (check-exn exn:fail? (lambda () (saved 'again)))
       (check-false (stat c 'busy)))))
   (test-case "multiple return values are preserved"
     (fixture (lambda (c use made retired)
       (check-equal? (call-with-values (lambda () (use (lambda (_) (values 1 2 3)))) list) '(1 2 3)))))
   (test-case "allocation failure does not poison an empty cache"
     (fixture (lambda (c use made retired)
       (check-exn #rx"allocation-error"
         (lambda () (call-with-frame-target c 8 6 (lambda () (error 'test "allocation-error")) void void)))
       (check-false (stat c 'busy)) (use) (check-equal? (made) 1))))
   (test-case "false allocation is rejected and never disposed"
     (fixture (lambda (c use made retired)
       (check-exn #rx"allocation returned false"
         (lambda () (call-with-frame-target c 8 6 (lambda () #f)
           (lambda (_) (error 'test "unexpected disposal")) void)))
       (check-equal? (stat c 'live_targets) 0))))
   (test-case "invalid dimensions reject before replacing a good target"
     (fixture (lambda (c use made retired)
       (use)
       (for ([w '(0 -1 1.0 32769)]) (check-exn exn:fail? (lambda () (use values w 6))))
       (check-equal? (made) 1) (check-equal? (retired) '()))))
   (test-case "tightened allocation bound applies even to a cache hit"
     (fixture (lambda (c use made retired)
       (use)
       (parameterize ([current-skia-byte-limit 16]) (check-exn exn:fail? use))
       (check-equal? (made) 1))))
   (test-case "invalid callbacks do not evict a good target"
     (fixture (lambda (c use made retired)
       (use)
       (check-exn exn:fail? (lambda () (call-with-frame-target c 9 7 #f void void)))
       (check-exn exn:fail? (lambda () (call-with-frame-target c 9 7 void (lambda () (void)) void)))
       (check-equal? (stat c 'live_targets) 1) (check-equal? (retired) '()))))
   (test-case "other thread cannot use or close a cache"
     (fixture (lambda (c use made retired)
       (check-true (exn:fail? (in-worker use)))
       (check-true (exn:fail? (in-worker (lambda () (close-frame-target-cache! c)))))
       (check-equal? (made) 0))))
   (test-case "two presenters never share target identities"
     (fixture (lambda (c use made retired)
       (define a (use))
       (fixture (lambda (d other other-made other-retired) (check-false (eq? a (other))))))))
   (test-case "fresh reference retires every successful target"
     (fixture (lambda (c use made retired)
       (parameterize ([current-frame-target-reuse? #f]) (for ([_ (in-range 20)]) (use)))
       (check-equal? (made) 20) (check-equal? (stat c 'reuses) 0)
       (check-equal? (length (retired)) 20) (check-equal? (stat c 'live_targets) 0))))
   (test-case "reference mode change retires the previously cached target"
     (fixture (lambda (c use made retired)
       (use) (parameterize ([current-frame-target-reuse? #f]) (use))
       (check-equal? (made) 2) (check-equal? (length (retired)) 2))))
   (test-case "callback cannot change the captured reference policy"
     (fixture (lambda (c use made retired)
       (parameterize ([current-frame-target-reuse? #f])
         (use (lambda (_) (current-frame-target-reuse? #t))))
       (check-equal? (stat c 'live_targets) 0))))
   (test-case "reference policy requires boolean input"
     (check-exn exn:fail? (lambda () (current-frame-target-reuse? 'yes))))
   (test-case "disposal failure is quarantined and never retried"
     (define c (make-frame-target-cache)) (define calls 0)
     (call-with-frame-target c 8 6 (lambda () 'native)
       (lambda (_) (set! calls (add1 calls)) (error 'test "release-error")) void)
     (check-exn #rx"release-error" (lambda () (close-frame-target-cache! c)))
     (check-true (stat c 'quarantined))
     (check-exn #rx"quarantined" (lambda () (close-frame-target-cache! c)))
     (check-exn #rx"quarantined" (lambda () (call-with-frame-target c 8 6 void void void)))
     (check-equal? calls 1))
   (test-case "cleanup failure does not replace the original user error"
     (define c (make-frame-target-cache))
     (check-exn #rx"original-error"
       (lambda () (call-with-frame-target c 8 6 (lambda () 'native)
         (lambda (_) (error 'test "release-error")) (lambda (_) (error 'test "original-error")))))
     (check-true (stat c 'quarantined)) (check-false (stat c 'busy)))
   (test-case "ledger measures creates and hits without claiming driver allocations"
     (fixture (lambda (c use made retired)
       (define ledger (box '()))
       (parameterize ([current-gpu-io-ledger ledger]) (use) (use) (close-frame-target-cache! c))
       (check-equal? (map (lambda (e) (hash-ref e 'action)) (reverse (unbox ledger)))
                     '("create" "reuse" "retire"))
       (for ([e (in-list (unbox ledger))])
         (check-true (immutable? e)) (check-equal? (hash-ref e 'kind) "dc-frame-target")
         (check-equal? (hash-ref e 'pixel_width) 8)))))))
(define gpu-frame-target-pure-test-count 32)
(module+ main
  (require rackunit/text-ui)
  (define failures (run-tests gpu-frame-target-pure-tests))
  (printf "gpu-frame-target-pure: ~a cases, ~a failures; no native GPU or GUI.\n"
          gpu-frame-target-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
