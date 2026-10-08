#lang racket/base
(require rackunit rackunit/text-ui json ffi/unsafe
         "../graphics.rkt" "../private/graphics-data.rkt"
         (only-in "../private/check.rkt" current-skia-byte-limit)
         (submod "../private/graphics-trace-native.rkt" test-support))
(provide global-cache-pure-tests global-cache-pure-test-count)
(define global-cache-pure-test-count 28)
(define global-cache-pure-tests
  (test-suite "Global cache values and bounded memory collector"
   (test-case "byte limits accept zero"
     (check-equal? (cache-byte-limit 'test 0) 0))
   (test-case "byte limits accept size_t maximum"
     (define max (sub1 (expt 2 (* 8 (ctype-sizeof _size)))))
     (check-equal? (cache-byte-limit 'test max) max))
   (test-case "byte limits reject overflow"
     (check-exn exn:fail:contract? (lambda () (cache-byte-limit 'test (expt 2 (* 8 (ctype-sizeof _size)))))))
   (test-case "cache byte limits are not allocation budgets"
     (parameterize ([current-skia-byte-limit 1])
       (check-equal? (cache-byte-limit 'test 1048576) 1048576)))
   (test-case "byte limits reject invalid values"
     (for ([v (in-list (list -1 1.0 1/2 +inf.0 +nan.0 #f 'large))])
       (check-exn exn:fail:contract? (lambda () (cache-byte-limit 'test v)))))
   (test-case "entry limits use signed C int"
     (check-equal? (cache-count-limit 'test 0) 0)
     (check-equal? (cache-count-limit 'test #x7fffffff) #x7fffffff)
     (check-exn exn:fail:contract? (lambda () (cache-count-limit 'test #x80000000))))
   (test-case "entry limits reject negative and inexact values"
     (for ([v (in-list (list -1 2.0 #f))])
       (check-exn exn:fail:contract? (lambda () (cache-count-limit 'test v)))))
   (test-case "public invalid setters reject without native calls"
     (for ([f (in-list (list skia-set-font-cache-limit! skia-set-font-cache-count-limit!
                            skia-set-resource-cache-limit! skia-set-resource-cache-single-allocation-limit!))])
       (check-exn exn:fail:contract? (lambda () (f -1)))))
   (test-case "snapshot options require booleans"
     (check-exn exn:fail:contract? (lambda () (memory-options 'test 1 #f 1 1 1)))
     (check-exn exn:fail:contract? (lambda () (memory-options 'test #f 'yes 1 1 1))))
   (test-case "snapshot options reject negative or inexact bounds"
     (check-exn exn:fail:contract? (lambda () (memory-options 'test #f #f -1 1 1)))
     (check-exn exn:fail:contract? (lambda () (memory-options 'test #f #f 1 1.0 1))))
   (test-case "snapshot limits include bounded entry overhead"
     (parameterize ([current-skia-byte-limit 128])
       (memory-options 'test #f #f 1 0 0)
       (check-exn exn:fail? (lambda () (memory-options 'test #f #f 1 1 1)))))
   (test-case "entry and string caps reject extreme settings"
     (check-exn exn:fail? (lambda () (memory-options 'test #f #f 65537 1 1)))
     (check-exn exn:fail? (lambda () (memory-options 'test #f #f 1 65537 1))))
   (test-case "zero snapshot quotas are valid"
     (memory-options 'test #f #f 0 0 0))
   (test-case "numeric entries preserve uint64"
     (define c (make-memory-collector 1 40 #f #f))
     (collector-add! c 'numeric #"node" #"size" #"bytes" #xffffffffffffffff)
     (define r (collector-finish c))
     (check-equal? (memory-statistic-value (vector-ref (memory-statistics-entries r) 0)) #xffffffffffffffff)
     (check-equal? (memory-statistics-string-bytes r) 13))
   (test-case "string entries are detached and immutable"
     (define c (make-memory-collector 1 100 #t #t))
     (define input (bytes-copy #"family"))
     (collector-add! c 'string #"node" #"type" #f input)
     (bytes-fill! input 0)
     (define e (vector-ref (memory-statistics-entries (collector-finish c)) 0))
     (check-equal? (memory-statistic-value e) "family")
     (check-true (immutable? (memory-statistic-value e))))
   (test-case "entry limit drops complete entries"
     (define c (make-memory-collector 1 100 #f #f))
     (collector-add! c 'numeric #"n" #"k" #"bytes" 3)
     (collector-add! c 'numeric #"n" #"k" #"bytes" 5)
     (define r (collector-finish c))
     (check-true (memory-statistics-truncated? r))
     (check-equal? (memory-statistics-dropped-count r) 1)
     (check-equal? (vector-length (memory-statistics-entries r)) 1))
   (test-case "aggregate string limit drops rather than truncates labels"
     (define c (make-memory-collector 3 6 #f #f))
     (collector-add! c 'numeric #"n" #"k" #"bytes" 3)
     (check-equal? (memory-statistics-entries (collector-finish c)) '#())
     (check-equal? (collector-room c) 6))
   (test-case "duplicate native labels are retained not added together"
     (define c (make-memory-collector 2 100 #f #f))
     (collector-add! c 'numeric #"same" #"size" #"bytes" 4)
     (collector-add! c 'numeric #"same" #"size" #"bytes" 8)
     (check-equal? (vector-length (memory-statistics-entries (collector-finish c))) 2))
   (test-case "collector snapshots do not alias later additions"
     (define c (make-memory-collector 2 100 #f #f))
     (define old (collector-finish c))
     (collector-add! c 'numeric #"n" #"k" #"bytes" 1)
     (check-equal? (memory-statistics-entries old) '#())
     (check-true (immutable? (memory-statistics-entries (collector-finish c)))))
   (test-case "strict UTF8 rejects invalid native text"
     (define c (make-memory-collector 1 100 #f #f))
     (check-exn exn:fail? (lambda () (collector-add! c 'string #"n" #"k" #f (bytes 255)))))
   (test-case "snapshot metadata and JSON preserve scope"
     (define c (make-memory-collector 0 0 #t #t))
     (collector-drop! c)
     (define r (collector-finish c))
     (define j (memory-statistics->jsexpr r))
     (check-equal? (memory-statistics-scope r) 'process-global-skia-caches)
     (check-true (hash-ref j 'truncated))
     (check-false (hash-ref j 'atomic))
     (check-true (jsexpr? j)))
   (test-case "bounded C-string copy stops at NUL"
     (define p (malloc 8 'atomic-interior))
     (memcpy p #"abc\0xxx\0" 8)
     (check-equal? (copy-c-string p 3) #"abc")
     (check-false (copy-c-string p 2)))
   (test-case "empty C string fits zero bytes"
     (define p (malloc 1 'atomic-interior))
     (ptr-set! p _ubyte 0)
     (check-equal? (copy-c-string p 0) #""))
   (test-case "null C string errors before dereferencing"
     (check-exn exn:fail? (lambda () (copy-c-string #f 10))))
   (test-case "foreign callback objects are ignored"
     (check-not-exn (lambda () (capture-value 'numeric #f #f #f #f #f 7))))
   (test-case "callback errors are deferred rather than escaping"
     (define marker (malloc 1 'atomic-interior))
     (define dump (malloc 1 'atomic-interior))
     (define c (make-memory-collector 2 100 #f #f))
     (define state (capture c 10 marker dump no-error))
     (dynamic-wind (lambda () (set-active-for-test! state))
       (lambda ()
         (check-not-exn (lambda () (capture-value 'numeric dump marker #f #f #f 7)))
         (check-pred exn:fail? (capture-error state)))
       (lambda () (set-active-for-test! #f))))
   (test-case "zero entry limit avoids native string access"
     (define marker (malloc 1 'atomic-interior))
     (define dump (malloc 1 'atomic-interior))
     (define c (make-memory-collector 0 0 #f #f))
     (define state (capture c 0 marker dump no-error))
     (dynamic-wind (lambda () (set-active-for-test! state))
       (lambda ()
         (capture-value 'numeric dump marker #f #f #f 1)
         (check-eq? (capture-error state) no-error)
         (check-equal? (memory-statistics-dropped-count (collector-finish c)) 1))
       (lambda () (set-active-for-test! #f))))
   (test-case "false deferred errors are not mistaken for success"
     (define marker (malloc 1 'atomic-interior))
     (define c (make-memory-collector 1 100 #f #f))
     (define state (capture c 10 marker marker #f))
     (dynamic-wind (lambda () (set-active-for-test! state))
       (lambda ()
         (capture-value 'numeric marker marker #f #f #f 7)
         (check-false (capture-error state))
         (check-equal? (memory-statistics-entries (collector-finish c)) '#()))
       (lambda () (set-active-for-test! #f))))))
(module+ main
  (define failures (run-tests global-cache-pure-tests))
  (printf "global-cache-pure: ~a cases, ~a failures\n" global-cache-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
