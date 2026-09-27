#lang racket/base
(require rackunit racket/list "../color-filters.rkt" "../private/check.rkt"
         "../private/color-filter-util.rkt")
(provide color-filter-pure-tests)
(define identity '(1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0))
(define table (apply bytes (build-list 256 values)))
(define (fail thunk) (check-exn exn:fail? thunk))
(define color-filter-pure-tests
  (test-suite
   "CPU color filters: validation without native loading"
   (test-case "matrix list becomes immutable snapshot"
     (define m (checked-filter-matrix 'test identity))
     (check-true (immutable? m)) (check-equal? (vector-length m) 20)
     (check-equal? (vector-ref m 0) 1.0))
   (test-case "matrix input mutation is independent"
     (define input (list->vector identity))
     (define m (checked-filter-matrix 'test input))
     (vector-set! input 0 0) (check-equal? (vector-ref m 0) 1.0))
   (test-case "matrix length rejects before native creation"
     (for ([n '(0 19 21)]) (fail (lambda () (make-hsla-matrix-filter (make-list n 0))))))
   (test-case "matrix wrong type rejected"
     (fail (lambda () (make-hsla-matrix-filter table))))
   (test-case "matrix NaN rejected"
     (fail (lambda () (make-hsla-matrix-filter (cons +nan.0 (cdr identity))))))
   (test-case "matrix infinity rejected"
     (fail (lambda () (make-hsla-matrix-filter (cons +inf.0 (cdr identity))))))
   (test-case "matrix C float overflow rejected"
     (fail (lambda () (make-hsla-matrix-filter (cons 1e100 (cdr identity))))))
   (test-case "matrix non-real rejected"
     (fail (lambda () (make-hsla-matrix-filter (cons 1+2i (cdr identity))))))
   (test-case "matrix byte budget enforced"
     (parameterize ([current-skia-byte-limit 79])
       (fail (lambda () (make-hsla-matrix-filter identity)))))
   (test-case "table bytes copied and immutable"
     (define input (bytes-copy table))
     (define copy (checked-filter-table 'test input))
     (bytes-set! input 0 99) (check-equal? (bytes-ref copy 0) 0)
     (check-true (immutable? copy)))
   (test-case "table list accepted"
     (check-equal? (checked-filter-table 'test (build-list 256 values)) table))
   (test-case "table vector accepted"
     (check-equal? (checked-filter-table 'test (list->vector (build-list 256 values))) table))
   (test-case "table vector copied"
     (define v (make-vector 256 72))
     (define c (checked-filter-table 'test v))
     (vector-set! v 120 9) (check-equal? (bytes-ref c 120) 72))
   (test-case "short and long byte tables rejected"
     (for ([n '(0 255 257)]) (fail (lambda () (make-table-color-filter (make-bytes n))))))
   (test-case "table list length rejected"
     (fail (lambda () (make-table-color-filter '(1 2 3)))))
   (test-case "negative table entry rejected"
     (fail (lambda () (make-table-color-filter (cons -1 (make-list 255 0))))))
   (test-case "large table entry rejected"
     (fail (lambda () (make-table-color-filter (cons 256 (make-list 255 0))))))
   (test-case "inexact table entry rejected"
     (fail (lambda () (make-table-color-filter (cons 1.0 (make-list 255 0))))))
   (test-case "false single table rejected"
     (fail (lambda () (make-table-color-filter #f))))
   (test-case "table byte budget enforced"
     (parameterize ([current-skia-byte-limit 255])
       (fail (lambda () (make-table-color-filter table)))))
   (test-case "ARGB null channels mean identity"
     (check-equal? (checked-filter-tables 'test #f #f #f #f) '(#f #f #f #f)))
   (test-case "ARGB order is alpha red green blue"
     (define a (make-bytes 256 1)) (define r (make-bytes 256 2))
     (check-equal? (map (lambda (x) (and x (bytes-ref x 0)))
                        (checked-filter-tables 'test a r #f table)) '(1 2 #f 0)))
   (test-case "ARGB invalid channel rejected"
     (fail (lambda () (make-table-argb-color-filter #:blue #t))))
   (test-case "ARGB total budget enforced"
     (parameterize ([current-skia-byte-limit 511])
       (fail (lambda () (make-table-argb-color-filter #:red table #:blue table)))))
   (test-case "ARGB budget boundary accepted by validator"
     (parameterize ([current-skia-byte-limit 512])
       (check-equal? (length (checked-filter-tables 'test table table #f #f)) 4)))
   (test-case "weight endpoints and midpoint accepted"
     (for ([w '(0 1/2 1)]) (check-= (checked-filter-weight 'test w) w 0)))
   (test-case "weight range checked before rounding"
     (for ([w (list -1/1000000000000000000 (+ 1 1/1000000000000000000) +nan.0 +inf.0)])
       (fail (lambda () (make-lerp-color-filter w #f #f)))))
   (test-case "lerp requires two filters even at endpoints"
     (fail (lambda () (make-lerp-color-filter 0 #f #f)))
     (fail (lambda () (make-lerp-color-filter 1 'bad 'bad))))
   (test-case "high contrast invert enumeration"
     (for ([mode '(none brightness lightness)] [i '(0 1 2)])
       (check-equal? (call-with-values (lambda () (checked-high-contrast 'test #t mode 0)) list)
                     (list #t i 0.0))))
   (test-case "high contrast endpoints accepted by validator"
     (for ([v '(-1 0 1)])
       (check-equal? (length (call-with-values (lambda () (checked-high-contrast 'test #f 'none v)) list)) 3)))
   (test-case "high contrast grayscale must be boolean"
     (fail (lambda () (make-high-contrast-color-filter #:grayscale? 1))))
   (test-case "high contrast inversion must be known"
     (fail (lambda () (make-high-contrast-color-filter #:invert-style 'rgb))))
   (test-case "high contrast invalid range rejected"
     (for ([v (list -1.1 1.1 +nan.0 -inf.0)])
       (fail (lambda () (make-high-contrast-color-filter #:contrast v)))))
   (test-case "high contrast native record budget enforced"
     (parameterize ([current-skia-byte-limit 11])
       (fail (lambda () (make-high-contrast-color-filter)))))
   (test-case "lighting validates both colors before native creation"
     (fail (lambda () (make-lighting-color-filter 'bad 'white)))
     (fail (lambda () (make-lighting-color-filter 'white 'bad))))
   (test-case "factory arities are stable"
     (check-true (procedure-arity-includes? make-hsla-matrix-filter 1))
     (check-true (procedure-arity-includes? make-lerp-color-filter 3))
     (check-true (procedure-arity-includes? make-luma-color-filter 0)))))
