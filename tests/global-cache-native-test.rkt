#lang racket/base
(require rackunit rackunit/text-ui json "../main.rkt" "global-cache-support.rkt")
(provide global-cache-native-tests global-cache-native-test-count)
(define global-cache-native-test-count 31)
(define global-cache-native-tests
  (test-suite "Native global caches and memory statistics"
   (test-case "explicit initialization is idempotent"
     (skia-initialize!) (skia-initialize!))
   (test-case "query values are nonnegative exact integers"
     (define h (skia-cache-statistics))
     (for ([(k v) (in-hash h)] #:unless (memq k '(scope atomic?)))
       (check-true (exact-nonnegative-integer? v)))
     (check-true (immutable? h))
     (check-equal? (hash-ref h 'scope) 'process-global-skia-caches)
     (check-false (hash-ref h 'atomic?)))
   (test-case "font byte limit returns prior setting"
     (with-restored-limits
      (lambda ()
        (define old (skia-font-cache-limit))
        (check-equal? (skia-set-font-cache-limit! 2097152) old)
        (check-equal? (skia-font-cache-limit) 2097152))))
   (test-case "font byte limit accepts zero"
     (with-restored-limits
      (lambda () (skia-set-font-cache-limit! 0) (check-equal? (skia-font-cache-limit) 0))))
   (test-case "font entry limit returns prior setting"
     (with-restored-limits
      (lambda ()
        (define old (skia-font-cache-count-limit))
        (check-equal? (skia-set-font-cache-count-limit! 128) old)
        (check-equal? (skia-font-cache-count-limit) 128))))
   (test-case "font entry limit accepts zero"
     (with-restored-limits
      (lambda () (skia-set-font-cache-count-limit! 0) (check-equal? (skia-font-cache-count-limit) 0))))
   (test-case "resource byte limit returns prior setting"
     (with-restored-limits
      (lambda ()
        (define old (skia-resource-cache-limit))
        (check-equal? (skia-set-resource-cache-limit! 4194304) old)
        (check-equal? (skia-resource-cache-limit) 4194304))))
   (test-case "resource byte limit accepts zero"
     (with-restored-limits
      (lambda () (skia-set-resource-cache-limit! 0) (check-equal? (skia-resource-cache-limit) 0))))
   (test-case "single allocation limit returns prior setting"
     (with-restored-limits
      (lambda ()
        (define old (skia-resource-cache-single-allocation-limit))
        (check-equal? (skia-set-resource-cache-single-allocation-limit! 524288) old)
        (check-equal? (skia-resource-cache-single-allocation-limit) 524288))))
   (test-case "single allocation limit accepts zero"
     (with-restored-limits
      (lambda () (skia-set-resource-cache-single-allocation-limit! 0) (check-equal? (skia-resource-cache-single-allocation-limit) 0))))
   (test-case "cache limit is independent of transfer allocation bound"
     (with-restored-limits
       (lambda ()
         (parameterize ([current-skia-byte-limit 1])
           (skia-set-font-cache-limit! 4194304)
           (check-equal? (skia-font-cache-limit) 4194304)))))
   (test-case "font purge preserves limits and rendering"
     (with-restored-limits
       (lambda ()
         (define saved (limit-settings))
         (define pixels (cache-test-pixels))
         (skia-purge-font-cache!)
         (check-equal? (limit-settings) saved)
         (check-equal? (cache-test-pixels) pixels))))
   (test-case "resource purge preserves limits and rendering"
     (with-restored-limits
       (lambda ()
         (define saved (limit-settings))
         (define pixels (cache-test-pixels))
         (skia-purge-resource-cache!)
         (check-equal? (limit-settings) saved)
         (check-equal? (cache-test-pixels) pixels))))
   (test-case "all purge preserves limits and rendering"
     (with-restored-limits
       (lambda ()
         (define saved (limit-settings))
         (define pixels (cache-test-pixels))
         (skia-purge-all-caches!)
         (check-equal? (limit-settings) saved)
         (check-equal? (cache-test-pixels) pixels))))
   (test-case "rendering survives reduced cache limits"
     (with-restored-limits
       (lambda ()
         (define pixels (cache-test-pixels))
         (skia-set-font-cache-limit! 1) (skia-set-font-cache-count-limit! 1)
         (skia-set-resource-cache-limit! 1)
         (check-equal? (cache-test-pixels) pixels)
         (check-true (bytes? (warm-cache!))))))
   (test-case "font work produces measured cache usage"
     (with-restored-limits
       (lambda ()
         (skia-set-font-cache-limit! 8388608) (skia-set-font-cache-count-limit! 256)
         (warm-cache!)
         (check-true (positive? (skia-font-cache-used)))
         (check-true (positive? (skia-font-cache-count-used))))))
   (test-case "global snapshot contains measured numeric byte entries"
     (with-restored-limits
       (lambda ()
         (skia-set-font-cache-limit! 8388608) (skia-set-font-cache-count-limit! 256)
         (warm-cache!)
         (define r (skia-memory-statistics))
         (check-false (memory-statistics-truncated? r))
         (check-true (for/or ([e (in-vector (memory-statistics-entries r))])
                       (and (eq? (memory-statistic-kind e) 'numeric)
                            (equal? (memory-statistic-units e) "bytes")
                            (positive? (memory-statistic-value e))))))))
   (test-case "detailed metadata is faithfully reported"
     (define r (skia-memory-statistics #:detailed? #t #:dump-wrapped? #t))
     (check-true (memory-statistics-detailed? r))
     (check-true (memory-statistics-dump-wrapped? r))
     (check-true (jsexpr? (memory-statistics->jsexpr r))))
   (test-case "empty entry budget reports truncation"
     (warm-cache!)
     (define r (skia-memory-statistics #:max-entries 0))
     (check-equal? (memory-statistics-entries r) '#())
     (check-true (memory-statistics-truncated? r))
     (check-true (positive? (memory-statistics-dropped-count r))))
   (test-case "short string budget drops full records"
     (warm-cache!)
     (define r (skia-memory-statistics #:string-limit 0))
     (check-equal? (memory-statistics-entries r) '#())
     (check-true (memory-statistics-truncated? r)))
   (test-case "aggregate byte budget remains bounded"
     (define r (skia-memory-statistics #:byte-limit 16))
     (check-true (<= (memory-statistics-string-bytes r) 16)))
   (test-case "copied snapshots survive purge and collection"
     (warm-cache!)
     (define r (skia-memory-statistics #:detailed? #t))
     (define j (memory-statistics->jsexpr r))
     (skia-purge-all-caches!) (collect-garbage)
     (check-equal? (memory-statistics->jsexpr r) j))
   (test-case "success after a truncated snapshot retains the provider"
     (skia-memory-statistics #:max-entries 0) (collect-garbage)
     (define r (skia-memory-statistics))
     (check-false (memory-statistics-truncated? r)))
   (test-case "ordinary Racket threads can query global caches"
     (define result (make-channel))
     (thread (lambda () (channel-put result
                          (with-handlers ([(lambda (_) #t) values]) (skia-font-cache-limit)))))
     (check-equal? (sync/timeout 10 result) (skia-font-cache-limit)))
   (test-case "successive Racket threads can take independent snapshots"
     (define result (make-channel))
     (thread (lambda () (channel-put result
                          (with-handlers ([(lambda (_) #t) values]) (skia-memory-statistics)))))
     (check-pred memory-statistics? (sync/timeout 10 result)))
   (test-case "snapshot table does not replace the live port table"
     (skia-memory-statistics)
     (define out (open-output-bytes))
     (check-equal? (copy-port/streaming (open-input-bytes #"cache-provider") out) 14)
     (check-equal? (get-output-bytes out) #"cache-provider")
     (check-pred memory-statistics? (skia-memory-statistics)))
   (test-case "snapshot table does not replace incremental input table"
     (with-skia ([s (make-codec-incremental)])
       (codec-incremental-feed! s #"\211PNG\r\n\32\n")
       (skia-memory-statistics)
       (check-not-exn (lambda () (codec-incremental-step! s)))))
   (test-case "global cache operations reject live port callback reentry"
     (define rejected? #f)
     (define sink (open-output-bytes))
     (define out
       (make-output-port 'cache-callback-test always-evt
         (lambda (bytes start end nonblocking? breakable?)
           (with-handlers ([exn:fail? (lambda (e)
                                      (set! rejected? (regexp-match? #rx"live port callback" (exn-message e))))])
             (skia-cache-statistics))
           (write-bytes bytes sink start end))
         void))
     (dynamic-wind void
       (lambda ()
         (check-equal? (copy-port/streaming (open-input-bytes #"abc") out) 3)
         (check-true rejected?)
         (check-equal? (get-output-bytes sink) #"abc"))
       (lambda () (close-output-port out))))
   (test-case "ordinary callers reject cache operations while live I/O waits"
     (define entered (make-semaphore 0))
     (define release (make-semaphore 0))
     (define result (box #f))
     (define output
       (make-output-port 'blocked-cache-test always-evt
         (lambda (bytes start end nonblocking? breakable?)
           (semaphore-post entered)
           (sync (semaphore-peek-evt release))
           (- end start))
         void))
     (define input (open-input-bytes #"abc"))
     (define worker
       (thread (lambda ()
                 (set-box! result
                   (with-handlers ([(lambda (_) #t) values])
                     (copy-port/streaming input output))))))
     (dynamic-wind void
       (lambda ()
         (check-not-false (sync/timeout 10 entered))
         (check-exn #rx"live stream operation" skia-font-cache-used)
         (check-exn #rx"live stream operation" (lambda () (skia-set-font-cache-count-limit! 128)))
         (check-exn #rx"live stream operation" skia-memory-statistics))
       (lambda () (semaphore-post release)))
     (check-not-false (sync/timeout 10 (thread-dead-evt worker)))
     (check-equal? (unbox result) 3)
     (close-input-port input) (close-output-port output)
     (check-true (exact-nonnegative-integer? (skia-font-cache-used))))
   (test-case "restoration occurs when a test operation raises"
     (define saved (limit-settings))
     (check-exn exn:fail?
       (lambda () (with-restored-limits
                    (lambda () (skia-set-font-cache-count-limit! 1) (error 'test "stop")))))
     (check-equal? (limit-settings) saved))
   (test-case "repeated collection and dumps keep callback roots alive"
     (for ([i (in-range 5)])
       (collect-garbage)
       (check-pred memory-statistics? (skia-memory-statistics #:detailed? #t))))))
(module+ main
  (define failures (with-restored-limits (lambda () (run-tests global-cache-native-tests))))
  (printf "global-cache-native: ~a cases, ~a failures\n" global-cache-native-test-count failures)
  (exit (if (zero? failures) 0 1)))
