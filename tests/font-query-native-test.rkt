#lang racket/base
(require rackunit racket/list racket/vector "../main.rkt" "typeface-fixtures.rkt"
         (submod "../private/core.rkt" font-query-internals))
(provide font-query-native-tests)
(define (fixture proc)
  (with-skia ([face (typeface-from-bytes (fixture-font-bytes))]
              [font (make-font face #:size 20 #:hinting 'none #:linear-metrics? #t
                               #:subpixel? #t #:baseline-snap? #f)])
    (proc font face)))
(define (near-list actual expected)
  (check-equal? (length actual) (length expected))
  (for ([a (in-list actual)] [e (in-list expected)]) (check-= a e 0.002)))
(define (path-rect p) (call-with-values (lambda () (path-bounds p)) list))
(define (release-paths paths)
  (for ([p (in-vector paths)] #:when p) (skia-close! p)))
(define (path-pixels p)
  (with-skia ([surface (make-surface 96 64)] [paint (make-paint #:color (rgb 0 0 0))])
    (define canvas (surface-canvas surface))
    (canvas-clear! canvas (rgb 255 255 255))
    (canvas-translate! canvas 20 40)
    (draw-path canvas p paint)
    (surface->rgba-bytes surface)))
(define (options f)
  (list (font-embedded-bitmaps? f) (font-force-auto-hinting? f) (font-baseline-snap? f)))
(define font-query-native-tests
  (test-suite
   "Font options and glyph queries (native)"
   (test-case "constructor defaults preserve pinned m119 flags"
     (with-skia ([f (make-font)]) (check-equal? (options f) '(#f #f #t))))
   (test-case "constructor explicitly selects every new flag"
     (with-skia ([f (make-font #:embedded-bitmaps? #t #:force-auto-hinting? #t #:baseline-snap? #f)])
       (check-equal? (options f) '(#t #t #f))))
   (test-case "option setters roundtrip true and false"
     (fixture (lambda (f _)
                (for ([value (in-list '(#t #f #t))])
                  (font-set-embedded-bitmaps! f value)
                  (font-set-force-auto-hinting! f value)
                  (font-set-baseline-snap! f value)
                  (check-equal? (options f) (list value value value))))))
   (test-case "typeface getter returns an independent owned reference"
     (define retained
       (fixture (lambda (f _) (font-typeface f))))
     (with-skia ([face retained])
       (check-equal? (typeface-postscript-name face) "SkiaRacketFixture-Regular")))
   (test-case "replacing a typeface preserves all numeric and boolean font controls"
     (fixture (lambda (f _)
                (font-set-scale-x! f 1.5) (font-set-skew-x! f 0.25)
                (font-set-embedded-bitmaps! f #t) (font-set-force-auto-hinting! f #t)
                (with-skia ([bold (typeface-from-bytes (fixture-font-bytes #:bold? #t))])
                  (font-set-typeface! f bold))
                (check-equal? (options f) '(#t #t #f))
                (check-= (font-size f) 20 0.001)
                (check-= (font-scale-x f) 1.5 0.001)
                (check-= (font-skew-x f) 0.25 0.001)
                (near-list (vector->list (font-glyph-widths f '#(2 3))) '(24 24)))))
   (test-case "typeface setter keeps a reference after the supplied wrapper closes"
     (fixture (lambda (f _)
                (define face (typeface-from-bytes (fixture-font-bytes #:bold? #t)))
                (font-set-typeface! f face) (skia-close! face)
                (near-list (vector->list (font-glyph-widths f '#(2 3))) '(16 16)))))
   (test-case "default-owner wrapper is retired on successful replacement"
     (with-skia ([f (make-font)] [face (typeface-from-bytes (fixture-font-bytes))])
       (define old (font-owner f))
       (check-true (typeface? old))
       (font-set-typeface! f face)
       (check-true (skia-closed? old)) (check-false (font-owner f))
       (check-false (skia-closed? face))))
   (test-case "closed replacement leaves the previous typeface unchanged"
     (fixture (lambda (f _)
                (define face (typeface-from-bytes (fixture-font-bytes #:bold? #t)))
                (skia-close! face)
                (check-exn exn:fail? (lambda () (font-set-typeface! f face)))
                (near-list (vector->list (font-glyph-widths f '#(2))) '(12)))))
   (test-case "repeated replacement and self-typeface replacement are safe"
     (fixture (lambda (f face)
                (with-skia ([bold (typeface-from-bytes (fixture-font-bytes #:bold? #t))])
                  (for ([i (in-range 12)])
                    (font-set-typeface! f (if (even? i) bold face))
                    (with-skia ([same (font-typeface f)]) (font-set-typeface! f same)))
                  (near-list (vector->list (font-glyph-widths f '#(2))) '(12))))))
   (test-case "shaper snapshots every option and its own typeface"
     (fixture (lambda (f _)
                (font-set-embedded-bitmaps! f #t) (font-set-force-auto-hinting! f #t)
                (with-skia ([sh (make-shaper f)] [bold (typeface-from-bytes (fixture-font-bytes #:bold? #t))])
                  (define before (shape-text sh "AV"))
                  (font-set-typeface! f bold) (font-set-size! f 48)
                  (font-set-embedded-bitmaps! f #f) (font-set-force-auto-hinting! f #f)
                  (font-set-baseline-snap! f #t)
                  (check-equal? (options (shaper-font sh)) '(#t #t #f))
                  (define after (shape-text sh "AV"))
                  (check-equal? (shaped-run-glyphs after) (shaped-run-glyphs before))
                  (check-equal? (shaped-run-positions after) (shaped-run-positions before))
                  (with-skia ([face (font-typeface (shaper-font sh))])
                    (check-equal? (typeface-postscript-name face) "SkiaRacketFixture-Regular"))))))
   (test-case "text-blob native and outline snapshots survive source mutation and close"
     (fixture (lambda (f _)
                (font-set-embedded-bitmaps! f #t)
                (with-skia ([blob (make-positioned-text-blob f '#(2 3) '((0 0) (12 0)))]
                            [before (text-blob->path blob)]
                            [bold (typeface-from-bytes (fixture-font-bytes #:bold? #t))])
                  (font-set-typeface! f bold) (font-set-size! f 60)
                  (font-set-embedded-bitmaps! f #f) (font-set-baseline-snap! f #t)
                  (skia-close! f)
                  (check-equal? (options (text-blob-font blob)) '(#t #f #f))
                  (with-skia ([after (text-blob->path blob)])
                    (check-equal? (path-pixels before) (path-pixels after)))))))
   (test-case "fixture advances use the same configured font as simple measurement"
     (fixture (lambda (f _)
                (define ws (font-glyph-widths f (font-text->glyphs f "AVA")))
                (check-true (immutable? ws))
                (near-list (vector->list ws) '(12 12 12))
                (check-= (apply + (vector->list ws)) (measure-simple-text f "AVA") 0.002))))
   (test-case "bounds are x y width height, not LTRB"
     (fixture (lambda (f _)
                (define bs (font-glyph-bounds f '#(2 3 1)))
                (check-true (immutable? bs))
                ;; Native glyph mask bounds may include platform-specific
                ;; antialias padding. Verify extent semantics, not padding.
                (for ([i (in-list '(0 1))])
                  (define b (vector-ref bs i))
                  (check-true (< (list-ref b 1) 0))
                  (check-true (> (list-ref b 2) 0))
                  (check-true (> (list-ref b 3) 0)))
                (near-list (vector-ref bs 2) '(0 0 0 0)))))
   (test-case "combined query agrees with individual queries"
     (fixture (lambda (f _)
                (define-values (ws bs) (font-glyph-widths+bounds f '#(2 3 1)))
                (check-equal? ws (font-glyph-widths f '#(2 3 1)))
                (check-equal? bs (font-glyph-bounds f '#(2 3 1))))))
   (test-case "paint participates in bounds but does not silently shape advances"
     (fixture (lambda (f _)
                (with-skia ([p (make-paint #:style 'stroke #:stroke-width 4)])
                  (define b (vector-ref (font-glyph-bounds f '#(2) #:paint p) 0))
                  (check-true (> (list-ref b 2) 8))
                  (check-true (> (list-ref b 3) 14))
                  (near-list (vector->list (font-glyph-widths f '#(2) #:paint p)) '(12))))))
   (test-case "positions have an explicit non-null origin and no pair kerning"
     (fixture (lambda (f _)
                (define ps (font-glyph-positions f '#(2 3 2) #:origin '(3.5 4.25)))
                (check-true (immutable? ps))
                (for ([p (in-vector ps)] [x (in-list '(3.5 15.5 27.5))])
                  (near-list p (list x 4.25)))
                (near-list (vector->list (font-glyph-x-positions f '#(2 3 2) #:origin 3.5))
                           '(3.5 15.5 27.5)))))
   (test-case "empty queries return immutable empty vectors"
     (fixture (lambda (f _)
                (for ([query (in-list (list font-glyph-widths font-glyph-bounds font-glyph-positions
                                            font-glyph-x-positions font-glyph-paths))])
                  (check-equal? (query f #()) #()))
                (define-values (ws bs) (font-glyph-widths+bounds f #()))
                (check-equal? ws #()) (check-equal? bs #()))))
   (test-case "glyph range is checked against the current typeface"
     (fixture (lambda (f _)
                (for ([g (in-list '(4 65535))])
                  (for ([query (in-list (list font-glyph-widths font-glyph-bounds font-glyph-positions
                                              font-glyph-x-positions font-glyph-paths))])
                    (check-exn exn:fail? (lambda () (query f (vector g)))))))))
   (test-case "glyph outputs are independent of inputs and later font mutations"
     (fixture (lambda (f _)
                (define input (vector 2 3))
                (define ws (font-glyph-widths f input))
                (define ps (font-glyph-positions f input))
                (vector-set! input 0 1) (font-set-size! f 40) (skia-close! f)
                (near-list (vector->list ws) '(12 12))
                (check-equal? (vector-length ps) 2)
                (near-list (vector-ref ps 0) '(0.0 0.0))
                (near-list (vector-ref ps 1) '(12.0 0.0)))))
   (test-case "batch glyph outlines apply the native scale and skew matrices"
     (fixture (lambda (f _)
                (font-set-size! f 31) (font-set-scale-x! f 1.5) (font-set-skew-x! f 0.25)
                (for ([bold? (in-list '(#f #t))])
                  (font-set-embolden! f bold?)
                  (define paths (font-glyph-paths f '#(2 3 2)))
                  (dynamic-wind void
                    (lambda ()
                      (check-true (immutable? paths))
                      (check-false (eq? (vector-ref paths 0) (vector-ref paths 2)))
                      (for ([p (in-vector paths)] [g (in-list '(2 3 2))])
                        (with-skia ([single (font-glyph-path f g)])
                          (near-list (path-rect p) (path-rect single))
                          (check-equal? (path-pixels p) (path-pixels single)))))
                    (lambda () (release-paths paths)))))))
   (test-case "batch results retain slots for whitespace without inventing ink"
     (fixture (lambda (f _)
                (define paths (font-glyph-paths f '#(2 1 3)))
                (dynamic-wind void
                  (lambda ()
                    (check-equal? (vector-length paths) 3)
                    (define blank (vector-ref paths 1))
                    (when blank (check-equal? (path-point-count blank) 0)))
                  (lambda () (release-paths paths))))))
   (test-case "batch result paths outlive source font and typeface wrappers"
     (define paths (fixture (lambda (f _) (font-glyph-paths f '#(2 3)))))
     (dynamic-wind void
       (lambda () (for ([p (in-vector paths)]) (check-true (positive? (path-point-count p)))))
       (lambda () (release-paths paths))))
   (test-case "batch copy budget failure is deferred and leaves native calls usable"
     (fixture (lambda (f _)
                (parameterize ([current-skia-byte-limit 330])
                  (check-exn exn:fail? (lambda () (font-glyph-paths f '#(2 3)))))
                (define paths (font-glyph-paths f '#(2 3)))
                (release-paths paths)
                (near-list (vector->list (font-glyph-widths f '#(2))) '(12)))))
   (test-case "break-text gives a Racket scalar count rather than a UTF-8 byte count"
     (fixture (lambda (f _)
                (define text "Aéλ𝄞\0V")
                (define-values (n w) (font-break-text f text 36))
                (check-equal? n 3) (check-= w 36 0.002)
                (check-equal? (substring text 0 n) "Aéλ"))))
   (test-case "break-text exact fit and zero or empty cases"
     (fixture (lambda (f _)
                (for ([width (in-list '(0 11 12 23 24))] [expected (in-list '(0 0 1 1 2))])
                  (define-values (n w) (font-break-text f "AV" width))
                  (check-equal? n expected) (check-= w (* expected 12) 0.002))
                (define-values (n w) (font-break-text f "" 0))
                (check-equal? n 0) (check-= w 0 0.001))))
   (test-case "break-text deliberately does not promise grapheme-safe shaping"
     (fixture (lambda (f _)
                (define-values (n w) (font-break-text f "A\u0301" 12))
                (check-equal? n 1) (check-= w 12 0.002))))
   (test-case "closed fonts and paints reject even empty work"
     (fixture (lambda (f _)
                (define p (make-paint)) (skia-close! p)
                (check-exn exn:fail? (lambda () (font-glyph-widths f #() #:paint p)))
                (check-exn exn:fail? (lambda () (font-break-text f "" 0 #:paint p)))
                (skia-close! f)
                (for ([query (in-list (list font-glyph-widths font-glyph-bounds font-glyph-positions
                                            font-glyph-x-positions font-glyph-paths))])
                  (check-exn exn:fail? (lambda () (query f #()))))
                (check-exn exn:fail? (lambda () (font-break-text f "" 0))))))
   (test-case "resource thread affinity is enforced for the new queries"
     (fixture (lambda (f _)
                (define result (make-channel))
                (define worker
                  (thread (lambda ()
                            (channel-put result
                                         (with-handlers ([exn:fail? (lambda (_) 'rejected)])
                                           (font-glyph-widths f #()) 'unexpected)))))
                (check-equal? (channel-get result) 'rejected)
                (thread-wait worker))))
))
