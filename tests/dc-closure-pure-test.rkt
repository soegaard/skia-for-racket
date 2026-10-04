#lang racket/base
;; No Skia, HarfBuzz, Pango parser, GUI, or installed-font probe in these tests.
(require rackunit racket/class racket/list
         (prefix-in rd: racket/draw)
         "../private/dc-support.rkt" "../private/dc-class.rkt"
         "../private/dc-font-name.rkt" "../private/dc-text-spec.rkt"
         "../private/dc-compatibility.rkt"
         (only-in "../private/check.rkt" current-skia-byte-limit))
(provide dc-closure-pure-tests dc-closure-pure-test-count)
(define f (rd:make-font #:face "Arial" #:size 12 #:size-in-pixels? #t))
(define (request text [mode #t] [offset 0])
  (dc-text-description 'closure-test text f mode offset))
(define fields '#("Arial" 700 2 4 0 63))
(define (parse [v fields] [weight 'normal] [style 'normal])
  (dc-face-from-description 'closure-test v weight style))
(define (edited index value)
  (for/vector ([x (in-vector fields)] [i (in-naturals)]) (if (= i index) value x)))
(define (with-dummy proc [events #f])
  (define (record kind)
    (when events (set-box! events (cons kind (unbox events))))
    (void))
  (define renderer
    (dc-renderer/styles
     (lambda (_w _h) (box #t)) void
     (lambda _ (record 'draw)) (lambda _ (record 'clear))
     (lambda (_) #f) (lambda (_s _p) #"") (lambda (_) #"")
     (lambda _ (record 'measure) (values 1.0 2.0 0.0 0.0))
     (lambda _ (record 'text)) (lambda _ #t)
     (lambda _ (void)) (lambda _ (void)) (lambda _ (void))
     (lambda _ (values 0.0 0.0 0.0 0.0))))
  (define dc (new (make-skia-dc-class renderer) [width 16] [height 16]))
  (dynamic-wind void (lambda () (proc dc)) (lambda () (send dc close))))
(define dc-closure-pure-tests
  (test-suite
   "0.64 declared DC contract, font translation and single-line boundaries"
   (test-case "every actual interface member is accounted for exactly once"
     (define names (map car dc-interface-arities))
     (check-equal? (length names) (length (remove-duplicates names)))
     (check-equal? (sort names symbol<?) (sort (interface->method-names rd:dc<%>) symbol<?)))
   (test-case "production class has the declared arities, including both set-pen forms"
     (with-dummy
      (lambda (dc)
        (for* ([row (in-list dc-interface-arities)] [n (in-range 12)])
          (check-equal? (object-method-arity-includes? dc (car row) n)
                        (and (memv n (cdr row)) #t)
                        (format "~a arity ~a" (car row) n))))))
   (test-case "declarations are detached immutable reports, not backend probes"
     (for ([target '(raster gpu pdf svg)])
       (define r (skia-dc-compatibility target))
       (check-true (immutable? r))
       (check-eq? (hash-ref r 'target) target)
       (check-false (hash-ref r 'native_probe_performed))
       (check-false (hash-ref r 'full_drop_in_compatibility))
       (check-equal? (length (hash-ref r 'methods)) (length dc-interface-arities))))
   (test-case "declarations retain the raster versus borrowed lifetime distinction"
     (check-eq? (hash-ref (skia-dc-compatibility) 'dc_lifetime) 'persistent)
     (for ([target '(gpu pdf svg)])
       (check-eq? (hash-ref (skia-dc-compatibility target) 'dc_lifetime) 'callback-scoped)))
   (test-case "document copy and erase explicitly require raster groups"
     (for* ([target '(pdf svg)] [method '(copy erase)])
       (define row (findf (lambda (r) (eq? method (hash-ref r 'name)))
                          (hash-ref (skia-dc-compatibility target) 'methods)))
       (check-eq? (hash-ref row 'status) 'explicit-raster-group)))
   (test-case "unknown report targets are not guessed"
     (for ([target '(auto metal opengl direct3d #f)])
       (check-exn exn:fail:contract? (lambda () (skia-dc-compatibility target)))))
   (test-case "plain family names do not interpret trailing style words"
     (check-equal? (dc-font-face 'test "Arial Bold" 'normal 'normal)
                   (dc-face "Arial Bold" 400 'upright 5)))
   (test-case "plain weight and slant use the public font values"
     (check-equal? (dc-font-face 'test "Arial" 'semibold 'slant)
                   (dc-face "Arial" 600 'oblique 5)))
   (test-case "plain numeric weight is preserved"
     (check-equal? (dc-face-weight (dc-font-face 'test "Arial" 450 'italic)) 450))
   (test-case "font names are copied before later caller mutation"
     (define name (string-copy "Arial"))
     (define result (dc-font-face 'test name 'normal 'normal))
     (string-set! name 0 #\X)
     (check-equal? (dc-face-family result) "Arial")
     (check-true (immutable? (dc-face-family result))))
   (test-case "NUL font names reject before native parsing"
     (check-exn exn:fail:contract? (lambda () (dc-font-face 'test "A\u0000, Bold" 'normal 'normal))))
   (test-case "font-name budget includes the UTF-8 terminator"
     (parameterize ([current-skia-byte-limit 4])
       (check-equal? (dc-face-family (dc-font-face 'test "abc" 'normal 'normal)) "abc")
       (check-exn exn:fail:contract? (lambda () (dc-font-face 'test "abcd" 'normal 'normal)))
       (check-exn exn:fail:contract? (lambda () (dc-font-face 'test "αβ" 'normal 'normal)))))
   (test-case "invalid overrides reject before forcing a comma parser"
     (check-exn exn:fail:contract? (lambda () (dc-font-face 'test "Arial, Bold" 'bogus 'normal)))
     (check-exn exn:fail:contract? (lambda () (dc-font-face 'test "Arial, Bold" 'normal 'bogus))))
   (test-case "description modifiers apply when overrides are normal"
     (check-equal? (parse) (dc-face "Arial" 700 'italic 5)))
   (test-case "non-normal explicit weight overrides the description"
     (check-equal? (dc-face-weight (parse fields 'light)) 300))
   (test-case "explicit numeric 400 is not the default normal symbol"
     (check-equal? (dc-face-weight (parse fields 400)) 400))
   (test-case "non-normal explicit style overrides the description"
     (check-eq? (dc-face-slant (parse fields 'normal 'slant)) 'oblique))
   (test-case "Pango normal oblique italic enum order is translated exactly"
     (for ([n '(0 1 2)] [want '(upright oblique italic)])
       (check-eq? (dc-face-slant (parse (edited 2 n))) want)))
   (test-case "all nine Pango stretches map to Skia width classes"
     (for ([n (in-range 9)])
       (check-equal? (dc-face-width (parse (edited 3 n))) (add1 n))))
   (test-case "description size does not enter the resulting face request"
     (check-equal? (parse (edited 5 31)) (parse (edited 5 63))))
   (test-case "ordered family cascades do not silently degrade to one family"
     (check-exn exn:fail:skia-dc:unsupported? (lambda () (parse (edited 0 "Arial,Helvetica")))))
   (test-case "empty parsed families reject instead of choosing an implicit family"
     (for ([name '("" "  ")])
       (check-exn exn:fail:skia-dc:unsupported? (lambda () (parse (edited 0 name))))))
   (test-case "all non-normal font variants reject"
     (for ([n '(1 2 3 4 5 6)])
       (check-exn exn:fail:skia-dc:unsupported? (lambda () (parse (edited 4 n))))))
   (test-case "gravity and variable axes reject, including with weight overrides"
     (for ([bit '(64 128 256 512 1024)])
       (check-exn exn:fail:skia-dc:unsupported?
                  (lambda () (parse (edited 5 (bitwise-ior 31 bit)) 'bold 'italic)))))
   (test-case "invalid parsed enum values are not clamped"
     (for ([entry '((1 -1) (1 1001) (2 3) (3 9) (4 -1) (5 #f))])
       (check-exn exn:fail:contract? (lambda () (parse (edited (car entry) (cadr entry)))))))
   (test-case "parsed field schema rejects wrong shape"
     (for ([v (list #f '() '#("Arial") fields)])
       (unless (eq? v fields) (check-exn exn:fail:contract? (lambda () (parse v))))))
   (test-case "ordinary font requests retain width 5 and explicit pixel sizes"
     (define spec (dc-font-description 'test f))
     (check-equal? (dc-font-request-width spec) 5)
     (check-= (dc-font-spec-size spec) 12.0 0.00001))
   (test-case "explicit font faces honour font-name-directory overrides"
     (define name "__skia_064_directory_pure__")
     (define font (rd:make-font #:face name))
     (define id (send font get-font-id))
     (define directory rd:the-font-name-directory)
     (define original (send directory get-screen-name id 'normal 'normal))
     (dynamic-wind
      (lambda () (send directory set-screen-name id 'normal 'normal "Arial"))
      (lambda ()
        ;; Honour the installed public resolver; do not assume a particular
        ;; directory implementation or reproduce its mapping algorithm.
        (check-equal? (dc-font-spec-family (dc-font-description 'test font))
                      (send directory get-screen-name id 'normal 'normal)))
      (lambda () (send directory set-screen-name id 'normal 'normal original))))
   (test-case "tab and all hard separators reject in combined and grapheme modes"
     (for* ([sep '(#\tab #\return #\newline #\u000B #\u000C #\u0085 #\u2028 #\u2029)]
            [mode '(#t grapheme other-true-value)])
       (check-exn exn:fail:skia-dc:unsupported? (lambda () (request (string #\a sep #\b) mode)))))
   (test-case "character mode still ignores control and formatting characters"
     (check-equal? (dc-text-spec-units (request "a\t\n\r\u000B\u000Cb\u200Ec" #f)) '("a" "b" "c")))
   (test-case "NUL truncation precedes the unsupported-separator check"
     (check-equal? (dc-text-spec-units (request "ok\u0000\n")) '("ok")))
   (test-case "offset selection precedes NUL truncation and separator validation"
     (check-equal? (dc-text-spec-units (request "\n\u0000ok" #t 2)) '("ok")))
   (test-case "grapheme clusters are not split while character mode stays additive"
     (check-equal? (dc-text-spec-units (request "a\u0301b" 'grapheme)) '("á" "b"))
     (check-equal? (dc-text-spec-units (request "a\u0301b" #f)) '("a" "́" "b")))
   (test-case "unsupported text does not reach the production renderer"
     (define events (box '()))
     (with-dummy (lambda (dc)
       (for ([op (list (lambda () (send dc get-text-extent "x\u000By" #f #t))
                       (lambda () (send dc draw-text "x\u000Cy" 0 0 'grapheme)))])
         (check-exn exn:fail:skia-dc:unsupported? op))
       (check-true (send dc ok?))) events)
     (check-equal? (unbox events) '()))
   (test-case "closed DC still rejects text before parsing fonts"
     (with-dummy (lambda (dc)
       (send dc close)
       (check-exn exn:fail? (lambda () (send dc get-text-extent "x")))
       (check-false (send dc ok?)))))))
(define dc-closure-pure-test-count 35)
(module+ main
  (require rackunit/text-ui)
  (define failures (run-tests dc-closure-pure-tests))
  (printf "dc-closure-pure: ~a cases, ~a failures\n" dc-closure-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
