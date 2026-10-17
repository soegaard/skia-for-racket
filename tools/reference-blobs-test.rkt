#lang racket/base

;;;
;;; Reference Blobs Test
;;;

;; Checks text-blob builder consumption, copied metadata, retained fonts, intercepts, and
;; text-on-path placement.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Opt-in CPU/HarfBuzz semantics. No font file is bundled.
;; The selected face must contain monochrome Latin A and B outlines.
;; SKIA_REFERENCE_TEST_FONT may name a local font file; otherwise use the system default.
(require rackunit racket/list racket/vector skia)


;;;
;;; Diagnostic Operations
;;;

; test-face : -> typeface?
;   Creates the explicitly configured test face, or the default face when no font path is supplied.
(define (test-face)
  (define filename (getenv "SKIA_REFERENCE_TEST_FONT"))
  (if filename (typeface-from-file filename) (make-typeface)))


; glyphs-ab : font? -> vector?
;   Requires nonmissing glyphs for A and B before using the font in placement checks.
(define (glyphs-ab font)
  (define glyphs (font-text->glyphs font "AB"))
  (check-equal? (vector-length glyphs) 2)
  (check-true (for/and ([glyph (in-vector glyphs)]) (> glyph 0))
              "The test face must contain A and B; set SKIA_REFERENCE_TEST_FONT otherwise")
  glyphs)


; shape-ab : shaper? -> shaped-run?
;   Shapes A and B left-to-right with kerning and ligatures disabled for predictable comparison.
(define (shape-ab shaper)
  (shape-text shaper "AB" #:direction 'ltr #:script 'latn #:features '("kern=0" "liga=0")))


; coordinates-near : list? list? -> void?
;   Checks matching coordinate counts and a 0.0001 absolute tolerance.
(define (coordinates-near actual expected)
  (check-equal? (length actual) (length expected))
  (for ([a (in-list actual)] [b (in-list expected)]) (check-= a b 0.0001)))

(module+ test
  (skia-check!)
  (harfbuzz-check!)
  (test-case "an empty builder is consumed and cannot be finished twice"
    (with-skia ([builder (make-text-blob-builder)])
      (check-equal? (text-blob-builder-run-count builder) 0)
      (check-false (text-blob-builder-finish! builder))
      (check-true (skia-closed? builder))
      (check-true (text-blob-builder? builder))
      (check-exn exn:fail? (lambda () (text-blob-builder-finish! builder)))
      (check-exn exn:fail? (lambda () (text-blob-builder-run-count builder)))
      (check-not-exn (lambda () (skia-close! builder)))))
  (test-case "empty appends validate every mode without adding a run"
    (with-skia ([face (test-face)] [font (make-font face)]
                [builder (make-text-blob-builder)])
      (text-blob-builder-add-run! builder font '())
      (text-blob-builder-add-horizontal-run! builder font #() #() #:y 5)
      (text-blob-builder-add-positioned-run! builder font '() '() #:text "" #:clusters '())
      (text-blob-builder-add-transformed-run! builder font #() #())
      (check-equal? (text-blob-builder-run-count builder) 0)
      (check-exn exn:fail?
                 (lambda () (text-blob-builder-add-run! builder font '() #:origin '(0))))
      (check-exn exn:fail?
                 (lambda () (text-blob-builder-add-horizontal-run! builder font '() '(1))))
      (check-exn exn:fail?
                 (lambda () (text-blob-builder-add-run! builder font '()
                                                       #:text "A" #:clusters '())))
      (skia-close! font)
      (check-exn exn:fail? (lambda () (text-blob-builder-add-run! builder font '())))
      (check-equal? (text-blob-builder-run-count builder) 0)
      (check-false (text-blob-builder-finish! builder))))
  (test-case "preallocation errors preserve successfully appended runs"
    (with-skia ([face (test-face)] [font (make-font face)]
                [builder (make-text-blob-builder)])
      (define glyphs (glyphs-ab font))
      (text-blob-builder-add-run! builder font glyphs)
      (check-exn exn:fail?
                 (lambda () (text-blob-builder-add-positioned-run! builder font glyphs '((0 0)))))
      (check-exn exn:fail?
                 (lambda () (text-blob-builder-add-run! builder font
                                                       (list (typeface-glyph-count face)))))
      (check-false (skia-closed? builder))
      (check-equal? (text-blob-builder-run-count builder) 1)
      (with-skia ([blob (text-blob-builder-finish! builder)])
        (check-equal? (text-blob-run-count blob) 1))))
  (test-case "append-time fonts are independent and logical runs remain distinct"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [builder (make-text-blob-builder)])
      (define glyphs (glyphs-ab font))
      (text-blob-builder-add-run! builder font glyphs #:origin '(10 30))
      (define expected (font-glyph-positions font glyphs #:origin '(10 30)))
      (font-set-size! font 36)
      (text-blob-builder-add-run! builder font glyphs #:origin '(10 70))
      (text-blob-builder-add-run! builder font glyphs #:origin '(10 110))
      (check-equal? (text-blob-builder-run-count builder) 3)
      (skia-close! font)
      (skia-close! face)
      (with-skia ([blob (text-blob-builder-finish! builder)]
                  [first-font (text-blob-run-font blob 0)]
                  [second-font (text-blob-run-font blob 1)])
        (check-equal? (text-blob-run-count blob) 3)
        (check-equal? (font-size first-font) 24.0)
        (check-equal? (font-size second-font) 36.0)
        (check-equal? (text-run-info-positions (vector-ref (text-blob-runs blob) 0)) expected)
        (check-true (skia-closed? builder)))))
  (test-case "positioning modes preserve absolute coordinates and copied inputs"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [builder (make-text-blob-builder)])
      (define glyphs (glyphs-ab font))
      (define saved-glyphs (vector-copy glyphs))
      (define positions (vector (vector 7 11) (vector 47 13)))
      (define transforms (vector (vector 1 0 5 6) (make-atlas-transform 40 50 #:scale 2)))
      (text-blob-builder-add-horizontal-run! builder font glyphs '(30 10) #:y 20)
      (text-blob-builder-add-positioned-run! builder font glyphs positions)
      (text-blob-builder-add-transformed-run! builder font glyphs transforms)
      (vector-set! glyphs 0 0)
      (vector-set! (vector-ref positions 0) 0 700)
      (vector-set! (vector-ref transforms 0) 2 500)
      (with-skia ([blob (text-blob-builder-finish! builder)])
        (define runs (text-blob-runs blob))
        (check-true (immutable? runs))
        (check-equal? (map text-run-info-positioning (vector->list runs))
                      '(horizontal positioned transformed))
        (check-equal? (text-run-info-positions (vector-ref runs 0)) '#((30.0 20.0) (10.0 20.0)))
        (check-equal? (text-run-info-positions (vector-ref runs 1)) '#((7.0 11.0) (47.0 13.0)))
        (check-equal? (text-run-info-positions (vector-ref runs 2)) #())
        (check-equal? (text-run-info-transforms (vector-ref runs 2))
                      '#((1.0 0.0 5.0 6.0) (2.0 0.0 40.0 50.0)))
        (check-false (text-run-info-transforms (vector-ref runs 0)))
        (for ([run (in-vector runs)])
          (check-true (text-run-info? run))
          (check-false (skia-resource? run))
          (check-true (immutable? (text-run-info-glyphs run)))
          (check-true (immutable? (text-run-info-positions run)))
          (check-equal? (text-run-info-glyphs run) saved-glyphs)))))
  (test-case "UTF-8 metadata copies byte input and accepts repeated descending offsets"
    (with-skia ([face (test-face)] [font (make-font face)]
                [builder (make-text-blob-builder)])
      (define glyphs (font-text->glyphs font "ABA"))
      (define text (bytes-copy (string->bytes/utf-8 "éAB")))
      (define clusters (vector 3 0 0))
      ;; Range-valid metadata need not describe the selected glyphs semantically.
      (text-blob-builder-add-run! builder font glyphs #:text text #:clusters clusters)
      (bytes-fill! text 0)
      (vector-set! clusters 0 2)
      (with-skia ([blob (text-blob-builder-finish! builder)])
        (define run (vector-ref (text-blob-runs blob) 0))
        (skia-close! blob)
        (check-equal? (text-run-info-utf8 run) (string->bytes/utf-8 "éAB"))
        (check-equal? (text-run-info-clusters run) '#(3 0 0))
        (check-true (immutable? (text-run-info-utf8 run)))
        (check-true (immutable? (text-run-info-clusters run))))))
  (test-case "malformed or unpaired metadata does not consume the builder"
    (with-skia ([face (test-face)] [font (make-font face)]
                [builder (make-text-blob-builder)])
      (define glyphs (glyphs-ab font))
      (define (add text clusters)
        (text-blob-builder-add-run! builder font glyphs #:text text #:clusters clusters))
      (for ([clusters (in-list '((0 1) (0 3) (0) (0 -1) (0 2.0)))])
        (check-exn exn:fail? (lambda () (add "éA" clusters))))
      (check-exn exn:fail? (lambda () (add "AB" #f)))
      (check-exn exn:fail? (lambda () (add #f '(0 1))))
      (check-exn exn:fail? (lambda () (add (bytes 255 65) '(0 1))))
      (check-exn exn:fail? (lambda () (add "" '(0 0))))
      (check-false (skia-closed? builder))
      (check-equal? (text-blob-builder-run-count builder) 0)
      (add "éA" '(0 2))
      (with-skia ([blob (text-blob-builder-finish! builder)])
        (check-equal? (text-blob-run-count blob) 1))))
  (test-case "returned fonts and run descriptions survive blob closure independently"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [builder (make-text-blob-builder)])
      (text-blob-builder-add-run! builder font (glyphs-ab font))
      (with-skia ([blob (text-blob-builder-finish! builder)]
                  [copy (text-blob-run-font blob 0)])
        (define run (vector-ref (text-blob-runs blob) 0))
        (font-set-size! copy 72)
        (with-skia ([another (text-blob-run-font blob 0)])
          (check-equal? (font-size another) 24.0))
        (check-exn exn:fail? (lambda () (text-blob-run-font blob 1)))
        (skia-close! blob)
        (check-equal? (font-size copy) 72.0)
        (check-equal? (vector-length (text-run-info-glyphs run)) 2)
        (check-exn exn:fail? (lambda () (text-blob-runs blob))))))
  (test-case "basic positioned blobs have one run but no inferred text metadata"
    (with-skia ([face (test-face)] [font (make-font face)]
                [blob (make-positioned-text-blob font (glyphs-ab font) '((0 0) (30 0)))])
      (define run (vector-ref (text-blob-runs blob) 0))
      (check-equal? (text-blob-run-count blob) 1)
      (check-equal? (text-run-info-positioning run) 'positioned)
      (check-false (text-run-info-utf8 run))
      (check-false (text-run-info-clusters run))
      (check-false (text-run-info-transforms run))))
  (test-case "shaped appends translate positions and retain clusters only with text"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [shaper (make-shaper font)] [builder (make-text-blob-builder)])
      (define run (shape-ab shaper))
      (text-blob-builder-add-shaped-run! builder shaper run #:origin '(7 11) #:text "AB")
      (text-blob-builder-add-shaped-run! builder shaper run)
      (text-blob-builder-add-shaped-run! builder shaper (shape-text shaper ""))
      (skia-close! shaper)
      (with-skia ([blob (text-blob-builder-finish! builder)])
        (define runs (text-blob-runs blob))
        (check-equal? (vector-length runs) 2)
        (check-equal? (text-run-info-positioning (vector-ref runs 0)) 'positioned)
        (check-equal? (vector->list (text-run-info-positions (vector-ref runs 0)))
                      (for/list ([p (in-list (shaped-run-positions run))])
                        (list (+ 7 (car p)) (+ 11 (cadr p)))))
        (check-equal? (vector->list (text-run-info-clusters (vector-ref runs 0)))
                      (shaped-run-clusters run))
        (check-equal? (text-run-info-utf8 (vector-ref runs 0)) #"AB")
        (check-false (text-run-info-clusters (vector-ref runs 1))))))
  (test-case "intercepts return detached intervals and reject transformed runs"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [builder (make-text-blob-builder)] [paint (make-paint #:style 'stroke)])
      (define glyphs (glyphs-ab font))
      (with-skia ([ordinary (make-positioned-text-blob font glyphs '((0 30) (40 30)))])
        (check-equal? (text-blob-intercepts ordinary 10000 10001) #())
        (define intervals (text-blob-intercepts ordinary 20 25 #:paint paint))
        (check-true (immutable? intervals))
        (check-true (<= (vector-length intervals) 2))
        (for ([pair (in-vector intervals)]) (check-true (<= (car pair) (cadr pair))))
        (check-exn exn:fail? (lambda () (text-blob-intercepts ordinary 25 25))))
      (text-blob-builder-add-run! builder font glyphs)
      (text-blob-builder-add-transformed-run! builder font glyphs
                                             '((1 0 10 30) (1 0 40 30)))
      (with-skia ([blob (text-blob-builder-finish! builder)])
        (check-exn exn:fail? (lambda () (text-blob-intercepts blob 10000 10001))))))
  (test-case "positioned outline results and empty paths outlive their font"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [empty (positioned-glyphs->path font #() #())]
                [path (positioned-glyphs->path font (glyphs-ab font) '((0 0) (40 0)))])
      (check-equal? (path-point-count empty) 0)
      (define before (path->commands path))
      (check-true (pair? before) "The test face must provide monochrome A/B outlines")
      (skia-close! font)
      (check-equal? (path->commands path) before)
      (check-false (skia-closed? path))))
  (test-case "horizontal path placement captures its geometry and font"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [shaper (make-shaper font)]
                [path (make-path '((move 10 40) (line 310 40)))])
      (define run (shape-ab shaper))
      (define points (shaped-run-positions run))
      (with-skia ([blob (shaped-run->text-blob/on-path shaper run path
                                                     #:start-offset 20 #:normal-offset 5
                                                     #:text "AB")])
        (define info (vector-ref (text-blob-runs blob) 0))
        (check-equal? (text-run-info-positioning info) 'transformed)
        (for ([transform (in-vector (text-run-info-transforms info))] [p (in-list points)])
          (coordinates-near transform (list 1 0 (+ 30 (car p)) (+ 45 (cadr p)))))
        (skia-close! path)
        (skia-close! shaper)
        (skia-close! font)
        (check-equal? (text-run-info-utf8 (vector-ref (text-blob-runs blob) 0)) #"AB")
        (with-skia ([surface (make-surface 400 120)] [paint (make-paint)])
          (check-not-exn (lambda () (draw-text-blob (surface-canvas surface) blob 0 0 paint)))))))
  (test-case "contour selection and normal orientation use the selected tangent"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [shaper (make-shaper font)]
                [path (make-path '((move 0 0) (line 100 0) (move 100 100) (line 100 400)))])
      (define run (shape-ab shaper))
      (with-skia ([blob (shaped-run->text-blob/on-path shaper run path
                                                     #:contour 1 #:normal-offset 5)])
        (define info (vector-ref (text-blob-runs blob) 0))
        (for ([transform (in-vector (text-run-info-transforms info))]
              [p (in-list (shaped-run-positions run))])
          (coordinates-near transform (list 0 1 (- 95 (cadr p)) (+ 100 (car p))))))))
  (test-case "path placement rejects excessive origins instead of clamping or wrapping"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [shaper (make-shaper font)]
                [path (make-path '((move 0 0) (line 100 0)))])
      (define run (shape-ab shaper))
      (for ([closed? '(#f #t)])
        (check-exn exn:fail?
                   (lambda () (shaped-run->text-blob/on-path shaper run path
                                                             #:start-offset 100000
                                                             #:force-closed? closed?))))
      (check-exn exn:fail?
                 (lambda () (shaped-run->text-blob/on-path shaper run path #:contour 2)))
      (check-exn exn:fail?
                 (lambda () (shaped-run->text-blob/on-path shaper run path #:start-offset -1000)))
      (check-false (skia-closed? path))
      (check-false (skia-closed? shaper))))
  (test-case "empty path placement validates resources and draws nothing"
    (with-skia ([face (test-face)] [font (make-font face)] [shaper (make-shaper font)]
                [path (make-path)] [surface (make-surface 4 4 #:background 'white)]
                [paint (make-paint)])
      (define run (shape-text shaper ""))
      (check-false (shaped-run->text-blob/on-path shaper run path))
      (check-exn exn:fail?
                 (lambda () (shaped-run->text-blob/on-path shaper run path #:text "A")))
      (check-exn exn:fail? (lambda () (draw-shaped-run/on-path #f shaper run path paint)))
      (define before (surface->rgba-bytes surface))
      (check-true (void? (draw-shaped-run/on-path (surface-canvas surface) shaper run path paint)))
      (check-equal? (surface->rgba-bytes surface) before)
      (skia-close! path)
      (check-exn exn:fail? (lambda () (shaped-run->text-blob/on-path shaper run path)))))
  (test-case "direct text-on-path drawing matches drawing the retained placement"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [shaper (make-shaper font)]
                [path (make-path '((move 10 40) (line 310 40)))]
                [first (make-surface 400 120 #:background 'white)]
                [second (make-surface 400 120 #:background 'white)]
                [paint (make-paint #:color 'blue)])
      (define run (shape-ab shaper))
      (define c1 (surface-canvas first))
      (define c2 (surface-canvas second))
      (canvas-translate! c1 5 7)
      (canvas-translate! c2 5 7)
      (with-skia ([blob (shaped-run->text-blob/on-path shaper run path
                                                     #:start-offset 20 #:normal-offset 5)])
        (draw-text-blob c1 blob 0 0 paint))
      (draw-shaped-run/on-path c2 shaper run path paint #:start-offset 20 #:normal-offset 5)
      (check-equal? (surface->rgba-bytes first) (surface->rgba-bytes second))
      (check-false (skia-closed? path))
      (check-false (skia-closed? shaper))
      (check-false (skia-closed? paint)))))
