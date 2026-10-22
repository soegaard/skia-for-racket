#lang racket/base

;;;
;;; Text Blob Pure Test
;;;

;; Covers multi-run text blobs (pure).
;; This source-only regression layer checks contracts and lifecycle rules before native rendering
;; is involved.

;;;
;;; Imports and Exports
;;;
(require rackunit racket/list racket/vector "../main.rkt" "../private/text-run-util.rkt"
         "text-blob-fixtures.rkt" "typeface-fixtures.rkt")
(provide text-blob-pure-tests)

;;;
;;; Fixtures and Assertions
;;;

; bad : (-> any) -> void?
;   Requires exn:fail? for the deliberately invalid operation.
(define (bad thunk) (check-exn exn:fail? thunk))

; metadata : string? any/c exact-nonnegative-integer? -> any
;   Validates source text, cluster offsets, and glyph count without constructing native runs.
(define (metadata text clusters count)
  (call-with-values (lambda () (text-run-metadata 'test text clusters count)) list))

;;;
;;; Regression Suite
;;;

; text-blob-pure-tests : test-suite?
;   Collects the regression cases for multi-run text blobs (pure).
(define text-blob-pure-tests
  (test-suite
   "Multi-run text blobs (pure)"
   (test-case "metadata is optional only as a pair"
     (check-equal? (metadata #f #f 2) '(#f #f))
     (bad (lambda () (metadata "A" #f 1))) (bad (lambda () (metadata #f '(0) 1))))
   (test-case "UTF-8 clusters are byte offsets, not scalar indices"
     (check-equal? (metadata "Aéλ𝄞\0" '(0 1 3 5 9) 5)
                   (list (string->bytes/utf-8 "Aéλ𝄞\0") '(0 1 3 5 9)))
     (for ([v '(2 4 6 7 8 10)]) (bad (lambda () (metadata "Aéλ𝄞\0" (list v) 1)))))
   (test-case "duplicate and descending cluster offsets are retained"
     (check-equal? (cadr (metadata "אב" '(2 0 0) 3)) '(2 0 0)))
   (test-case "malformed UTF-8 rejects rather than inserting replacement characters"
     (for ([text (list #"\377" #"\300\200" #"\355\240\200" #"\360\237")])
       (bad (lambda () (metadata text '(0) 1)))))
   (test-case "metadata copies caller bytes and vectors"
     (define text (bytes 65 86)) (define clusters (vector 0 1))
     (define result (metadata text clusters 2))
     (bytes-fill! text 0) (vector-set! clusters 0 1)
     (check-true (immutable? (car result))) (check-equal? result '(#"AV" (0 1))))
   (test-case "empty metadata is accepted only for empty glyphs"
     (check-equal? (metadata "" '() 0) '(#"" ()))
     (bad (lambda () (metadata "" '(0) 1))) (bad (lambda () (metadata "A" '() 0))))
   (test-case "cluster shape and range errors reject"
     (for ([c (list '(0 1) '(-1) '(1.0) '(#t) '(1) #f)])
       (bad (lambda () (metadata "A" c 1)))))
   (test-case "glyph input is checked uint16 and copied"
     (define gs (vector 0 2 65535)) (define out (text-run-glyphs 'test gs))
     (vector-set! gs 1 3) (check-equal? out '(0 2 65535))
     (for ([g '(-1 65536 1.0 #t a)]) (bad (lambda () (text-run-glyphs 'test (list g))))))
   (test-case "improper and cyclic-ish non-list inputs reject"
     (for ([v (list '(2 . 3) #"AV" "AV" #f)]) (bad (lambda () (text-run-glyphs 'test v)))))
   (test-case "position counts match glyph counts"
     (check-equal? (text-run-points 'test '(#(1 2) (3 4)) 2) '((1.0 2.0) (3.0 4.0)))
     (bad (lambda () (text-run-points 'test '((1 2)) 2))))
   (test-case "positions reject malformed and nonfinite coordinates"
     (for ([p (list '(1) '(1 2 3) '(a 0) (list +inf.0 0) (list 0 +nan.0))])
       (bad (lambda () (text-run-points 'test (list p) 1)))))
   (test-case "horizontal positions use the same count and scalar rules"
     (check-equal? (text-run-scalars 'test '#(0 12) 2) '(0.0 12.0))
     (bad (lambda () (text-run-scalars 'test '(1) 2)))
     (bad (lambda () (text-run-scalars 'test '(+inf.0) 1))))
   (test-case "RSXform coefficients permit rotation, scale and zero scale"
     (check-equal? (text-run-transforms 'test '((0 1 20 30) #(0 0 0 0)) 2)
                   '((0.0 1.0 20.0 30.0) (0.0 0.0 0.0 0.0))))
   (test-case "RSXform shape/count/nonfinite inputs reject"
     (bad (lambda () (text-run-transforms 'test '((1 0 0)) 1)))
     (bad (lambda () (text-run-transforms 'test '((1 0 0 0)) 2)))
     (bad (lambda () (text-run-transforms 'test '((1 0 0 +inf.0)) 1))))
   (test-case "byte limits charge text and cluster payload before native allocation"
     (parameterize ([current-skia-byte-limit 15])
       (bad (lambda () (text-run-glyphs 'test '(2))))
       (bad (lambda () (metadata "AV" '(0 1) 2)))
       (bad (lambda () (text-run-transforms 'test '((1 0 0 0)) 1)))))
   (test-case "budget exact limits and nonnumeric requirements"
     (parameterize ([current-skia-byte-limit 64])
       (check-equal? (text-run-budget 'test 64) 64)
       (bad (lambda () (text-run-budget 'test 65)))
       (bad (lambda () (text-run-budget 'test -1)))))
   (test-case "intercept bands require strictly ordered finite values"
     (check-equal? (text-run-band 'test -5 0) '(-5.0 0.0))
     (for ([ab (list '(0 0) '(2 1) (list +nan.0 2) (list 0 +inf.0))])
       (bad (lambda () (apply text-run-band 'test ab)))))
   (test-case "run indices are exact nonnegative and in range"
     (check-equal? (text-run-index 'test 0 1) 0)
     (for ([i '(1 -1 0.0 #f)]) (bad (lambda () (text-run-index 'test i 1)))))
   (test-case "positive normal offset points down on a horizontal path"
     (check-equal? (text-run-path-placement 'test 10 20 1 0 3) '(1.0 0.0 10.0 23.0)))
   (test-case "normal offset rotates with the tangent"
     (check-equal? (text-run-path-placement 'test 10 20 0 1 3) '(0.0 1.0 7.0 20.0)))
   (test-case "builder predicates and invalid resources reject without loading Skia"
     (check-false (text-blob-builder? #f))
     (bad (lambda () (text-blob-builder-run-count #f)))
     (bad (lambda () (text-blob-builder-finish! #f)))
     (bad (lambda () (text-blob-run-count #f)))
     (bad (lambda () (text-blob-runs #f))))
   (test-case "all append variants reject invalid pure arguments"
     (bad (lambda () (text-blob-builder-add-run! #f #f '(65536))))
     (bad (lambda () (text-blob-builder-add-horizontal-run! #f #f '(2) '(0 1))))
     (bad (lambda () (text-blob-builder-add-positioned-run! #f #f '(2) '(#(0 +nan.0)))))
     (bad (lambda () (text-blob-builder-add-transformed-run! #f #f '(2) '((1 0 0)))))
     (bad (lambda () (text-blob-builder-add-shaped-run! #f #f))))
   (test-case "path text rejects invalid shaper/run/path and scalar options"
     (bad (lambda () (shaped-run->text-blob/on-path #f #f)))
     (bad (lambda () (shaped-run->text-blob/on-path #f #f #:contour -1)))
     (bad (lambda () (shaped-run->text-blob/on-path #f #f #:start-offset +inf.0))))
   (test-case "run consumers have only their new calling forms"
     (check-equal? (procedure-arity draw-shaped-run) 5)
     (check-equal? (procedure-arity shaped-run->text-blob) 1)
     (check-equal? (procedure-arity shaped-run->path) 1)
     (check-equal? (procedure-arity text-blob-builder-add-shaped-run!) 2)
     (check-equal? (procedure-arity shaped-run->text-blob/on-path) 2)
     (check-equal? (procedure-arity draw-shaped-run/on-path) 4)
     (define-values (_required append-keywords)
       (procedure-keywords text-blob-builder-add-shaped-run!))
     (check-equal? append-keywords '(#:origin))
     (define-values (_path-required path-keywords)
       (procedure-keywords shaped-run->text-blob/on-path))
     (check-false (memq '#:text path-keywords)))
   (test-case "whole-text conversions reject unknown missing-outline policies"
     (for ([convert (in-list
                     (list (lambda () (simple-text-path #f "" #:missing-outline 'omit))
                           (lambda () (shaped-run->path #f #:missing-outline 'omit))
                           (lambda () (text-blob->path #f #:missing-outline 'omit))
                           (lambda () (positioned-glyphs->path #f #() #()
                                                              #:missing-outline 'omit))))])
       (bad convert)))
   (test-case "positioned outline utility checks counts and resource types"
     (bad (lambda () (positioned-glyphs->path #f '(2) '())))
     (bad (lambda () (positioned-glyphs->path #f '() '()))))
   (test-case "procedural Unicode/ligature fixture has a valid global checksum"
     (define data (text-blob-fixture-font-bytes))
     (check-equal? (fixture-checksum data) #xb1b0afba)
     (check-true (regexp-match? #rx#"GSUB" data))
     (check-true (regexp-match? #rx#"liga" data)))
))
