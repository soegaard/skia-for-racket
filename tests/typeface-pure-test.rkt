#lang racket/base
(require rackunit rackunit/text-ui "../typefaces.rkt" "../private/typeface-util.rkt"
         "../private/check.rkt" "typeface-fixtures.rkt")
(provide typeface-pure-tests)
(define (bad thunk) (check-exn exn:fail:contract? thunk))
(define typeface-pure-tests
  (test-suite
   "0.68a pure typeface values, ranges and original generated fixtures"
   (test-case "style defaults are normalized values"
     (define s (make-font-style))
     (check-equal? (list (font-style-weight s) (font-style-width s) (font-style-slant s)) '(400 5 upright)))
   (test-case "style accepts the existing weight and stretch vocabulary"
     (check-equal? (make-font-style #:weight 'bold #:width 'condensed #:slant 'italic)
                   (make-font-style #:weight 700 #:width 3 #:slant 'italic)))
   (test-case "style rejects invalid weights, widths and slants"
     (for ([v (list -1 1001 1.5 #t)]) (bad (lambda () (make-font-style #:weight v))))
     (for ([v '(0 10 #f)]) (bad (lambda () (make-font-style #:width v))))
     (bad (lambda () (make-font-style #:slant 'sideways))))
   (test-case "collection index is signed int32, not an arbitrary integer"
     (check-equal? (typeface-index 'test #x7fffffff) #x7fffffff)
     (for ([v (list -1 #x80000000 #t 0.0)]) (bad (lambda () (typeface-index 'test v)))))
   (test-case "table tags have big-endian byte order"
     (check-equal? (font-table-tag "head") #x68656164)
     (check-equal? (font-table-tag #"OS/2") #x4f532f32)
     (check-equal? (font-table-tag->bytes #x68656164) #"head"))
   (test-case "all uint32 tags roundtrip without text loss"
     (for ([tag (list 0 #x00ff00ff #xffffffff)])
       (check-equal? (font-table-tag (font-table-tag->bytes tag)) tag)
       (check-true (immutable? (font-table-tag->bytes tag)))))
   (test-case "malformed tags are rejected"
     (for ([v (list "abc" "abcde" #"" "数学字体" #t -1 #x100000000)])
       (bad (lambda () (font-table-tag v)))))
   (test-case "copied input is independent"
     (define src (bytes 1 2 3))
     (define copy (typeface-input-bytes 'test src))
     (bytes-fill! src 0)
     (check-equal? copy (bytes 1 2 3)))
   (test-case "empty, wrong-kind and oversized font inputs reject before native calls"
     (bad (lambda () (typeface-from-bytes #"")))
     (bad (lambda () (typeface-from-bytes "font")))
     (bad (lambda () (typeface-from-bytes #"bad" #:index -1)))
     (parameterize ([current-skia-byte-limit 2])
       (bad (lambda () (typeface-from-bytes #"abc")))))
   (test-case "manager argument cannot be silently treated as default"
     (bad (lambda () (font-manager-typeface-from-bytes #f #"abc"))))
   (test-case "family names reject NUL and excessive UTF-8 payload"
     (bad (lambda () (typeface-family-bytes 'test "A\0B")))
     (parameterize ([current-skia-byte-limit 4])
       (bad (lambda () (typeface-family-bytes 'test "éé")))))
   (test-case "table slice end is exclusive and may be empty"
     (check-equal? (call-with-values (lambda () (typeface-slice 'test 8 2 #f)) list) '(2 8))
     (check-equal? (call-with-values (lambda () (typeface-slice 'test 8 8 8)) list) '(8 8)))
   (test-case "out-of-bounds and reversed slices reject"
     (for ([p '((-1 2) (3 2) (0 9) (9 #f))])
       (bad (lambda () (typeface-slice 'test 8 (car p) (cadr p))))))
   (test-case "slice budget charges requested data, not the whole table"
     (parameterize ([current-skia-byte-limit 4])
       (check-equal? (call-with-values (lambda () (typeface-slice 'test 1000 100 104)) list) '(100 104))
       (bad (lambda () (typeface-slice 'test 1000 100 105)))))
   (test-case "glyph IDs are uint16 and snapshot caller vectors"
     (define gs (vector 1 2))
     (define snap (typeface-glyphs 'test gs))
     (vector-set! gs 0 0)
     (check-equal? snap '(1 2))
     (for ([g '(-1 65536 #f 1.5)]) (bad (lambda () (typeface-glyphs 'test (list g))))))
   (test-case "kerning accounts for input and output buffers"
     (parameterize ([current-skia-byte-limit 7])
       (bad (lambda () (typeface-glyphs 'test '(1 2)))))
     (parameterize ([current-skia-byte-limit 8]) (check-equal? (typeface-glyphs 'test '(1 2)) '(1 2))))
   (test-case "fixture fonts have the complete SFNT checksum"
     (check-equal? (fixture-checksum (fixture-font-bytes)) #xb1b0afba)
     (check-equal? (fixture-checksum (fixture-font-bytes #:bold? #t)) #xb1b0afba))
   (test-case "fixture is generated afresh and supports two distinct collection members"
     (define a (fixture-font-bytes))
     (define b (fixture-font-bytes))
     (bytes-fill! a 0)
     (check-equal? b (fixture-font-bytes))
     (check-equal? (subbytes (fixture-collection-bytes) 0 4) #"ttcf")
     (check-not-equal? (fixture-font-bytes) (fixture-font-bytes #:bold? #t)))
   (test-case "TTC extraction produces checksum-complete standalone members"
     (define collection (fixture-collection-bytes))
     (check-equal? (ttc-member->sfnt 'test collection 0) (fixture-font-bytes))
     (check-equal? (ttc-member->sfnt 'test collection 1) (fixture-font-bytes #:bold? #t))
     (check-equal? (fixture-checksum (ttc-member->sfnt 'test collection 1)) #xb1b0afba)
     (bad (lambda () (ttc-member->sfnt 'test collection 2)))
     (bad (lambda () (ttc-member->sfnt 'test (fixture-font-bytes) 1))))))
(module+ main (exit (if (zero? (run-tests typeface-pure-tests)) 0 1)))
