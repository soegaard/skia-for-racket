#lang racket/base
(require rackunit rackunit/text-ui ffi/unsafe racket/list
         "../main.rkt" (prefix-in util: "../private/runtime-util.rkt") "../private/types.rkt")
(provide runtime-pure-tests)
(define (u name type count flags total [offset 0])
  (util:checked-runtime-uniform 'test name offset type count flags total))
(define (pack size fields values)
  (util:runtime-pack-uniforms 'test size fields values))
(define (read-float bs [at 0])
  (floating-point-bytes->real bs (system-big-endian?) at (+ at 4)))
(define (read-int bs [at 0])
  (integer-bytes->integer bs #t (system-big-endian?) at (+ at 4)))
(define runtime-pure-tests
  (test-suite
   "Runtime effects: pure validation and uniform packing"
   (test-case "new predicates are total and do not load Skia"
     (for ([p (in-list (list runtime-effect? blender? runtime-uniform? runtime-child? exn:fail:skia-sksl?))])
       (check-false (p #f)) (check-false (p 12))))
   (test-case "source snapshots mutable strings"
     (define source (string-copy "half4 main(float2 p) { return half4(1); }"))
     (define-values (copy encoded) (util:runtime-source 'test source))
     (string-set! source 0 #\x)
     (check-equal? (string-ref copy 0) #\h)
     (check-true (immutable? copy))
     (check-equal? encoded (string->bytes/utf-8 copy)))
   (test-case "source validation rejects nonstring empty and NUL"
     (for ([v (in-list (list #f #"sksl" "" "abc\u0000def"))])
       (check-exn exn:fail:contract? (lambda () (util:runtime-source 'test v)))))
   (test-case "source byte limit counts UTF-8 not characters"
     (parameterize ([current-skia-byte-limit 2])
       (check-exn exn:fail:contract? (lambda () (util:runtime-source 'test "\u20ac")))))
   (test-case "invalid effect kind fails before library loading"
     (check-exn exn:fail:contract? (lambda () (make-runtime-effect "anything" #:kind 'gpu))))
   (test-case "factory arguments reject non-effects before loading"
     (check-exn exn:fail:contract? (lambda () (runtime-effect->shader #f)))
     (check-exn exn:fail:contract? (lambda () (runtime-effect->color-filter #f)))
     (check-exn exn:fail:contract? (lambda () (runtime-effect->blender #f))))
   (test-case "metadata accessors reject wrong values"
     (for ([f (in-list (list runtime-effect-kind runtime-effect-source runtime-effect-uniforms
                             runtime-effect-children runtime-effect-uniform-byte-size))])
       (check-exn exn:fail:contract? (lambda () (f #f)))))
   (test-case "invalid blend mode rejects before loading"
     (check-exn exn:fail:contract? (lambda () (make-blend-mode-blender 'not-a-mode))))
   (test-case "reflection ABI sizes and field offsets"
     (define word (ctype-sizeof _pointer))
     (check-equal? (ctype-sizeof _sk-runtime-uniform) (if (= word 8) 40 24))
     (check-equal? (ctype-sizeof _sk-runtime-child) (+ (* 2 word) 8))
     (define sample (make-sk-runtime-uniform 0 0 20 3 2 #x13))
     (check-equal? (ptr-ref sample _size 2) 20)
     (check-equal? (ptr-ref (ptr-add sample (* 3 word)) _int) 3)
     (check-equal? (ptr-ref (ptr-add sample (+ (* 3 word) 8)) _uint32) #x13))
   (test-case "reflected names are copied"
     (define name (string-copy "tone"))
     (define field (u name 0 1 0 4))
     (string-set! name 0 #\x)
     (check-equal? (runtime-uniform-name field) "tone")
     (check-true (immutable? (runtime-uniform-name field))))
   (test-case "all numeric types have packed four-byte components"
     (for ([type (in-range 11)] [n (in-list '(1 2 3 4 4 9 16 1 2 3 4))])
       (check-equal? (runtime-uniform-byte-size (u "v" type 1 0 (* 4 n))) (* 4 n))))
   (test-case "half and layout-color flags remain independent"
     (define f (u "tint" 3 1 #x12 16))
     (check-true (runtime-uniform-half-precision? f))
     (check-true (runtime-uniform-color? f))
     (check-false (runtime-uniform-array? f)))
   (test-case "unsupported reflection types and flags fail closed"
     (check-exn exn:fail? (lambda () (u "x" 11 1 0 4)))
     (check-exn exn:fail? (lambda () (u "x" 0 1 #x80 4)))
     (check-exn exn:fail? (lambda () (u "x" 0 1 #x04 4))))
   (test-case "invalid color or half flags fail closed"
     (check-exn exn:fail? (lambda () (u "x" 0 1 2 4)))
     (check-exn exn:fail? (lambda () (u "x" 7 1 #x10 4))))
   (test-case "offset count and bounds are checked"
     (check-exn exn:fail? (lambda () (u "x" 0 1 0 4 1)))
     (check-exn exn:fail? (lambda () (u "x" 3 1 0 4)))
     (check-exn exn:fail? (lambda () (u "x" 0 0 1 4)))
     (check-exn exn:fail? (lambda () (u "x" 0 2 0 8))))
   (test-case "layout rejects gaps and overlaps"
     (check-exn exn:fail? (lambda () (util:validate-runtime-layout 'test 8 (list (u "x" 0 1 0 8 4)) '())))
     (check-exn exn:fail? (lambda () (util:validate-runtime-layout 'test 8 (list (u "x" 0 1 0 8) (u "y" 0 1 0 8)) '()))))
   (test-case "layout checks duplicate names across child and numeric slots"
     (check-exn exn:fail?
                (lambda () (util:validate-runtime-layout 'test 4 (list (u "x" 0 1 0 4))
                                                     (list (util:checked-runtime-child 'test "x" 0 0))))))
   (test-case "child reflection has strict kinds and indices"
     (define c (util:checked-runtime-child 'test "layer" 2 0))
     (check-equal? (runtime-child-kind c) 'blender)
     (check-equal? (runtime-child-index c) 0)
     (check-exn exn:fail? (lambda () (util:checked-runtime-child 'test "x" 3 0)))
     (check-exn exn:fail? (lambda () (util:checked-runtime-child 'test "x" 0 -1)))
     (check-exn exn:fail? (lambda () (util:validate-runtime-layout 'test 0 '()
                                                          (list (util:checked-runtime-child 'test "x" 0 1))))))
   (test-case "empty uniforms have empty immutable bytes"
     (define b (pack 0 '() (hash)))
     (check-equal? b #"") (check-true (immutable? b)))
   (test-case "scalar float packing has IEEE binary32 representation"
     (define b (pack 4 (list (u "x" 0 1 0 4)) (hash 'x 1)))
     (check-equal? (bytes->list b) (if (system-big-endian?) '(63 128 0 0) '(0 0 128 63))))
   (test-case "float3 is 12 bytes, without GPU-style alignment padding"
     (define b (pack 16 (list (u "v" 2 1 0 16) (u "x" 0 1 0 16 12))
                     (hash 'v '#(1 2 3) 'x 4)))
     (check-equal? (bytes-length b) 16)
     (check-equal? (read-float b 12) 4.0))
   (test-case "integers pack signed 32-bit values including extremes"
     (define b (pack 12 (list (u "v" 9 1 0 12)) (hash 'v (list (- (expt 2 31)) -7 (sub1 (expt 2 31))))))
     (check-equal? (map (lambda (at) (read-int b at)) '(0 4 8)) (list (- (expt 2 31)) -7 (sub1 (expt 2 31)))))
   (test-case "integer values reject inexact booleans fractions and overflow"
     (for ([v (in-list (list 2.0 #t 1/2 (expt 2 31)))])
       (check-exn exn:fail:contract? (lambda () (pack 4 (list (u "x" 7 1 0 4)) (hash 'x v))))))
   (test-case "float values reject infinity NaN complex and overflow"
     (for ([v (in-list (list +inf.0 -inf.0 +nan.0 1+2i 1e100 #f))])
       (check-exn exn:fail:contract? (lambda () (pack 4 (list (u "x" 0 1 0 4)) (hash 'x v))))))
   (test-case "matrix input is flat and column-major"
     (define b (pack 36 (list (u "m" 5 1 0 36)) (hash 'm '(1 2 3 4 5 6 7 8 9))))
     (check-equal? (for/list ([at (in-range 0 36 4)]) (read-float b at)) '(1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0)))
   (test-case "arrays are tightly packed and flagged even at length one"
     (define one (u "a" 0 1 1 4))
     (check-true (runtime-uniform-array? one))
     (check-equal? (read-float (pack 4 (list one) (hash 'a '(5)))) 5.0)
     (check-exn exn:fail:contract? (lambda () (pack 4 (list one) (hash 'a 5)))))
   (test-case "array of float3 has no stride padding"
     (define b (pack 24 (list (u "a" 2 2 1 24)) (hash 'a '#(1 2 3 4 5 6))))
     (check-equal? (read-float b 12) 4.0)
     (check-equal? (bytes-length b) 24))
   (test-case "half uniforms are supplied as four-byte floats"
     (define b (pack 8 (list (u "h" 1 1 #x10 8)) (hash 'h '(0.25 0.75))))
     (check-equal? (bytes-length b) 8)
     (check-equal? (read-float b 4) 0.75))
   (test-case "raw uniform colors are not automatically premultiplied"
     (define b (pack 16 (list (u "c" 3 1 2 16)) (hash 'c '(1 0.5 0 0.25))))
     (check-equal? (read-float b) 1.0)
     (check-equal? (read-float b 12) 0.25))
   (test-case "extended-range color components remain numeric inputs"
     (define b (pack 12 (list (u "c" 2 1 2 12)) (hash 'c '(-0.1 1.2 0.5))))
     (check-true (< (read-float b) 0)) (check-true (> (read-float b 4) 1)))
   (test-case "wrong vector lengths and nested matrices are rejected"
     (for ([v (in-list (list '(1 2) '#(1 2 3 4) '((1 2) (3 4))))])
       (check-exn exn:fail:contract? (lambda () (pack 12 (list (u "v" 2 1 0 12)) (hash 'v v))))))
   (test-case "both symbol and string keys resolve"
     (check-equal? (pack 4 (list (u "x" 0 1 0 4)) (hash 'x 3))
                   (pack 4 (list (u "x" 0 1 0 4)) (hash "x" 3))))
   (test-case "missing and unknown names are errors"
     (check-exn exn:fail:contract? (lambda () (pack 4 (list (u "x" 0 1 0 4)) (hash))))
     (check-exn exn:fail:contract? (lambda () (pack 4 (list (u "x" 0 1 0 4)) (hash 'x 1 'typo 2)))))
   (test-case "duplicate normalized names do not overwrite"
     (check-exn exn:fail:contract? (lambda () (pack 4 (list (u "x" 0 1 0 4)) (hash 'x 1 "x" 2)))))
   (test-case "binding dictionaries and keys have checked types"
     (check-exn exn:fail:contract? (lambda () (pack 0 '() #"")))
     (check-exn exn:fail:contract? (lambda () (util:runtime-bindings 'test 'child '("x") (hash 12 1)))))
   (test-case "packing freezes caller vectors"
     (define v (vector 0.2 0.3 0.4 1))
     (define b (pack 16 (list (u "v" 3 1 0 16)) (hash 'v v)))
     (vector-set! v 0 1)
     (check-= (read-float b) 0.2 1e-6)
     (check-true (immutable? b)))
   (test-case "lowered byte limit is checked before output allocation"
     (define field (u "x" 0 1 0 4))
     (parameterize ([current-skia-byte-limit 3])
       (check-exn exn:fail? (lambda () (pack 4 (list field) (hash 'x 1))))))
   (test-case "structured compiler errors preserve source kind and diagnostics"
     (define e
       (with-handlers ([exn:fail:skia-sksl? values])
         (util:raise-sksl-error 'shader "source" "diagnostic")))
     (check-true (exn:fail:skia-sksl? e))
     (check-equal? (exn:fail:skia-sksl-kind e) 'shader)
     (check-equal? (exn:fail:skia-sksl-source e) "source")
     (check-equal? (exn:fail:skia-sksl-diagnostics e) "diagnostic"))))
(module+ test (run-tests runtime-pure-tests))
