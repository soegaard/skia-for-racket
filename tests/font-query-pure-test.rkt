#lang racket/base
(require rackunit racket/list racket/vector "../main.rkt" "../private/font-query-util.rkt")
(provide font-query-pure-tests)
(define (bad thunk) (check-exn exn:fail? thunk))
(define font-query-pure-tests
  (test-suite
   "Font queries (pure)"
   (test-case "glyph vectors are detached and immutable"
     (define input (vector 0 2 65535))
     (define out (font-query-glyphs 'test input 2))
     (vector-set! input 1 3)
     (check-equal? out '#(0 2 65535)) (check-true (immutable? out)))
   (test-case "glyph lists produce the same snapshot"
     (check-equal? (font-query-glyphs 'test '(0 2 3) 2) '#(0 2 3)))
   (test-case "invalid glyph elements are rejected"
     (for ([g (in-list (list -1 65536 #t 1.5 +nan.0 'x))])
       (bad (lambda () (font-query-glyphs 'test (list g) 2)))))
   (test-case "improper lists and other containers are rejected"
     (for ([v (in-list (list '(1 . 2) "AV" #"AV" #f))])
       (bad (lambda () (font-query-glyphs 'test v 2)))))
   (test-case "glyph buffer budget is enforced before copying"
     (parameterize ([current-skia-byte-limit 5])
       (bad (lambda () (font-query-glyphs 'test '(1 2 3) 2)))))
   (test-case "exact glyph budget is accepted"
     (parameterize ([current-skia-byte-limit 6])
       (check-equal? (font-query-glyphs 'test '(1 2 3) 2) '#(1 2 3))))
   (test-case "empty glyph input has no buffer charge"
     (parameterize ([current-skia-byte-limit 1])
       (check-equal? (font-query-glyphs 'test #() 100) #())))
   (test-case "origins accept detached pairs and vectors"
     (check-equal? (font-query-origin 'test '(1 -2)) '(1.0 -2.0))
     (check-equal? (font-query-origin 'test '#(1/2 3/4)) '(0.5 0.75)))
   (test-case "bad origin shapes fail"
     (for ([v (in-list (list '() '(1) '(1 2 3) '(1 . 2) '#(1) #f))])
       (bad (lambda () (font-query-origin 'test v)))))
   (test-case "nonfinite origins fail"
     (for ([v (in-list (list +nan.0 +inf.0 -inf.0 1e100))])
       (bad (lambda () (font-query-origin 'test (list v 0))))))
   (test-case "UTF-8 snapshots include embedded NUL and astral scalars"
     (check-equal? (font-query-text 'test "Aéλ𝄞\0") (string->bytes/utf-8 "Aéλ𝄞\0")))
   (test-case "byte strings are not silently reinterpreted as text"
     (bad (lambda () (font-query-text 'test #"AV"))))
   (test-case "text scratch budget is checked"
     (parameterize ([current-skia-byte-limit 39])
       (bad (lambda () (font-query-text 'test "AV")))))
   (test-case "UTF-8 byte counts become Racket character indices"
     (define bs (string->bytes/utf-8 "Aéλ𝄞\0"))
     (for ([b (in-list '(0 1 3 5 9 10))] [n (in-naturals)])
       (check-equal? (font-break-prefix-length 'test bs b) n)))
   (test-case "native UTF-8 splits are not replaced by replacement characters"
     (define bs (string->bytes/utf-8 "Aéλ𝄞"))
     (for ([b (in-list '(2 4 6 7 8))])
       (bad (lambda () (font-break-prefix-length 'test bs b)))))
   (test-case "native byte counts are range checked"
     (for ([b (in-list (list -1 3 #f 1.0))])
       (bad (lambda () (font-break-prefix-length 'test #"AV" b)))))
   (test-case "zero callback results"
     (check-equal? (collect-glyph-path-results 'test 0 (lambda (_) (void)) list void) #()))
   (test-case "batch callbacks preserve order and matrices"
     (define out (collect-glyph-path-results
                  'test 2 (lambda (receive) (receive 'a 'ma #f) (receive 'b 'mb #f))
                  list void))
     (check-equal? out '#((a ma) (b mb))) (check-true (immutable? out)))
   (test-case "null paths preserve slots without invoking the copier"
     (define calls 0)
     (define out (collect-glyph-path-results
                  'test 2 (lambda (receive) (receive #f #f #f) (receive 'a 'm #f))
                  (lambda (p m) (set! calls (add1 calls)) p) void))
     (check-equal? calls 1) (check-equal? out '#(#f a)))
   (test-case "callback failure is deferred until the native invocation returns"
     (define returned? #f) (define closed '())
     (with-handlers ([(lambda (v) (eq? v 'copy-failed))
                      (lambda (_) (check-true returned?))])
       (collect-glyph-path-results
        'test 2
        (lambda (receive) (receive 'a 'm #f) (receive 'b 'm #f) (set! returned? #t))
        (lambda (p m) (if (eq? p 'b) (raise 'copy-failed) p))
        (lambda (p) (set! closed (cons p closed))))
       (fail "copy failure was swallowed"))
     (check-equal? closed '(a)))
   (test-case "even a raised false value is deferred and re-raised"
     (define returned? #f) (define caught? #f)
     (with-handlers ([(lambda (v) (eq? v #f))
                      (lambda (_) (set! caught? #t) (check-true returned?))])
       (collect-glyph-path-results
        'test 1 (lambda (receive) (receive 'a 'm #f) (set! returned? #t))
        (lambda (_p _m) (raise #f)) void))
     (check-true caught?))
   (test-case "extra callbacks fail after return and release completed results"
     (define returned? #f) (define closed '())
     (bad (lambda ()
            (collect-glyph-path-results
             'test 1
             (lambda (receive) (receive 'a 'm #f) (receive 'b 'm #f) (set! returned? #t))
             (lambda (p m) p) (lambda (p) (set! closed (cons p closed))))))
     (check-true returned?) (check-equal? closed '(a)))
   (test-case "short callback sequences release completed results"
     (define closed '())
     (bad (lambda ()
            (collect-glyph-path-results
             'test 2 (lambda (receive) (receive 'a 'm #f)) (lambda (p m) p)
             (lambda (p) (set! closed (cons p closed))))))
     (check-equal? closed '(a)))
   (test-case "invocation errors also release completed results"
     (define closed '())
     (bad (lambda ()
            (collect-glyph-path-results
             'test 2 (lambda (receive) (receive 'a 'm #f) (error 'invoke "failed"))
             (lambda (p m) p) (lambda (p) (set! closed (cons p closed))))))
     (check-equal? closed '(a)))
   (test-case "cleanup attempts every result even after a release error"
     (define closed '())
     (bad (lambda ()
            (collect-glyph-path-results
             'test 3 (lambda (receive) (receive 'a 'm #f) (receive 'b 'm #f))
             (lambda (p m) p)
             (lambda (p) (set! closed (cons p closed)) (error 'release "failed")))))
     (check-equal? (reverse closed) '(a b)))
   (test-case "callbacks after a failure do not allocate more results"
     (define copies 0)
     (bad (lambda ()
            (collect-glyph-path-results
             'test 2 (lambda (receive) (receive 'a 'm #f) (receive 'b 'm #f))
             (lambda (p m) (set! copies (add1 copies)) (error 'copy "failed")) void)))
     (check-equal? copies 1))
   (test-case "new font constructor options validate without loading Skia"
     (bad (lambda () (make-font #:embedded-bitmaps? 1)))
     (bad (lambda () (make-font #:force-auto-hinting? 'yes)))
     (bad (lambda () (make-font #:baseline-snap? 0))))
   (test-case "new option setters reject non-booleans"
     (for ([setter (in-list (list font-set-embedded-bitmaps! font-set-force-auto-hinting!
                                  font-set-baseline-snap!))])
       (bad (lambda () (setter #f 'yes)))))
   (test-case "empty queries do not bypass font argument checks"
     (for ([query (in-list (list font-glyph-widths font-glyph-bounds font-glyph-widths+bounds
                                 font-glyph-positions font-glyph-x-positions font-glyph-paths))])
       (bad (lambda () (query #f #()))))
     (bad (lambda () (font-break-text #f "" 0))))
   (test-case "break width validation precedes native access"
     (for ([width (in-list (list -1 +inf.0 +nan.0 'wide))])
       (bad (lambda () (font-break-text #f "AV" width)))))
   (test-case "typeface replacement has no null reset sentinel"
     (bad (lambda () (font-set-typeface! #f #f))))))
