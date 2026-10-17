#lang racket/base

;;;
;;; Reference Text Test
;;;

;; Checks font/shaper retention, glyph metrics, UTF-8 offsets, blob copying, wrapping, and
;; mixed-layout lifetime.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Opt-in native CPU/HarfBuzz acceptance. No font binary is bundled.
;; Set SKIA_REFERENCE_TEST_FONT to a local font file to select the semantic-test face.
;; Displayed examples, executed by reference-native-test.rkt, use the default face.
(require rackunit racket/file racket/list skia)


;;;
;;; Diagnostic Operations
;;;

; test-face : -> typeface?
;   Creates the configured Reference test face or the default face when no override is supplied.
(define (test-face)
  (define filename (getenv "SKIA_REFERENCE_TEST_FONT"))
  (if filename (typeface-from-file filename) (make-typeface)))


; same-run : shaped-run? shaped-run? -> void?
;   Checks equal glyphs, clusters, positions, and horizontal advance between shaped runs.
(define (same-run a b)
  (check-equal? (shaped-run-glyphs a) (shaped-run-glyphs b))
  (check-equal? (shaped-run-clusters a) (shaped-run-clusters b))
  (check-equal? (shaped-run-positions a) (shaped-run-positions b))
  (check-equal? (shaped-run-advance-x a) (shaped-run-advance-x b)))

(module+ test
  (skia-check!)
  (harfbuzz-check!)
  (test-case "font and shaper retain independent typeface and font state"
    (with-skia ([face (test-face)]
                [font (make-font face #:size 24)]
                [shaper (make-shaper font)])
      (check-not-equal? (font-char->glyph font #\A) 0
                        "The test typeface must contain the Latin letter A")
      (define before (shape-text shaper "AB" #:direction 'ltr #:script 'latn))
      (define metrics (font-get-metrics font))
      (define saved-ascent (font-metrics-ascent metrics))
      (skia-close! face)
      (font-set-size! font 48)
      (check-equal? (font-size font) 48.0)
      (same-run before (shape-text shaper "AB" #:direction 'ltr #:script 'latn))
      (skia-close! font)
      (same-run before (shape-text shaper "AB" #:direction 'ltr #:script 'latn))
      (check-equal? (font-metrics-ascent metrics) saved-ascent)
      (check-false (skia-resource? metrics))
      (with-skia ([blob (shaped-run->text-blob shaper before)])
        (skia-close! shaper)
        (check-true (text-blob? blob))
        (check-equal? (length (call-with-values (lambda () (text-blob-bounds blob)) list)) 4)
        (check-equal? (shaped-run-glyph-count before) (length (shaped-run-glyphs before))))))
  (test-case "typeface getter is owned, not a borrow"
    (with-skia ([source-face (test-face)]
                [font (make-font source-face #:size 24)]
                [face (font-typeface font)])
      (skia-close! font)
      (check-true (string? (typeface-family-name face)))
      (check-false (skia-closed? face))))
  (test-case "copied font bytes are independent of subsequent input mutation"
    (with-skia ([face (test-face)])
      (define-values (data index) (typeface->font-bytes face))
      (check-true (immutable? data))
      (define mutable (bytes-copy data))
      (with-skia ([copy (typeface-from-bytes mutable #:index index)])
        (define count (typeface-glyph-count copy))
        (bytes-fill! mutable 0)
        (check-equal? (typeface-glyph-count copy) count)
        (check-equal? count (typeface-glyph-count face))
        (skia-close! face)
        (check-true (font-style? (typeface-style copy))))))
  (test-case "empty style set and absent table differ from a failed native operation"
    (with-skia ([styles (make-empty-font-style-set)]
                [face (test-face)])
      (check-equal? (font-style-set-count styles) 0)
      (check-false (font-style-set-match styles))
      (check-equal? (font-style-set-styles styles) #())
      (check-exn exn:fail? (lambda () (font-style-set-ref styles 0)))
      (define tags (typeface-table-tags face))
      (check-true (immutable? tags))
      (define absent
        (for/first ([tag (in-range 0 65536)]
                    #:unless (for/or ([present (in-vector tags)]) (= tag present))) tag))
      (unless absent (error 'reference-text-test "could not select an absent test table tag"))
      (check-false (typeface-table-size face absent))
      (check-false (typeface-table-bytes face absent))
      (check-exn exn:fail? (lambda () (typeface-table-bytes face absent #:start -1)))
      (check-exn exn:fail? (lambda () (typeface-table-bytes face absent #:start 2 #:end 1)))))
  (test-case "glyph measurements are detached and use the current font"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)])
      (define glyphs (font-text->glyphs font "AB"))
      (define-values (widths bounds) (font-glyph-widths+bounds font glyphs))
      (check-equal? widths (font-glyph-widths font glyphs))
      (check-equal? bounds (font-glyph-bounds font glyphs))
      (check-true (immutable? widths))
      (check-true (immutable? bounds))
      (check-equal? (vector-length widths) (vector-length glyphs))
      (define positions (font-glyph-positions font glyphs #:origin '(7 11)))
      (check-equal? (vector-ref positions 0) '(7.0 11.0))
      (check-equal? (font-glyph-widths font '()) #())
      (check-equal? (font-glyph-paths font '()) #())
      (check-exn exn:fail?
                 (lambda () (font-glyph-widths font (list (typeface-glyph-count face)))))
      (skia-close! font)
      (check-equal? (vector-length widths) (vector-length glyphs))))
  (test-case "font-break-text reports characters, not UTF-8 bytes"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)])
      (define text "éA")
      (define-values (count width) (font-break-text font text 1000000))
      (check-equal? count 2)
      (check-equal? (bytes-length (string->bytes/utf-8 text)) 3)
      (check-equal? (substring text 0 count) text)
      (check-true (>= width 0))
      (define-values (empty-count empty-width) (font-break-text font "" 0))
      (check-equal? empty-count 0)
      (check-equal? empty-width 0.0)))
  (test-case "shaping clusters are UTF-8 byte offsets"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [shaper (make-shaper font)])
      (define run (shape-text shaper "éA" #:direction 'ltr #:script 'latn
                              #:features '("liga=0" "kern=0")))
      (define clusters (shaped-run-clusters run))
      (check-not-false (member 2 clusters))
      (check-true (andmap (lambda (index) (and (memv index '(0 2)) #t)) clusters))
      (check-equal? (length clusters) (length (shaped-run-positions run)))
      (check-equal? (shaped-run-glyph-count run) (length (shaped-run-glyphs run)))
      (define empty (shape-text shaper ""))
      (check-equal? (shaped-run-glyphs empty) '())
      (check-equal? (shaped-run-advance-x empty) 0.0)
      (check-exn exn:fail? (lambda () (shaped-run->text-blob shaper empty)))
      (check-exn exn:fail? (lambda () (shape-text shaper "A" #:features '("not a feature"))))))
  (test-case "positioned blobs copy input positions and font settings"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)])
      (define glyphs (font-text->glyphs font "AB"))
      (define positions (vector (vector 0 0) (vector 40 0)))
      (with-skia ([blob (make-positioned-text-blob font glyphs positions)])
        (define before (call-with-values (lambda () (text-blob-bounds blob)) list))
        (vector-set! (vector-ref positions 1) 0 400)
        (vector-set! glyphs 0 0)
        (font-set-size! font 48)
        (skia-close! font)
        (check-equal? (call-with-values (lambda () (text-blob-bounds blob)) list) before))))
  (test-case "wrapping retains over-wide words and empty trailing lines"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [shaper (make-shaper font)])
      (define text "unbreakable")
      (define natural (abs (shaped-run-advance-x (shape-text shaper text))))
      (define requested (max 1 (/ natural 2)))
      (define layout (layout-text shaper text #:width requested))
      (check-equal? (text-layout-line-count layout) 1)
      (check-true (>= (text-layout-width layout) requested))
      (check-= (text-layout-width layout) (max natural requested) 0.0001)
      (define lines (text-layout-lines (layout-text shaper "A\n" #:line-height 30)))
      (check-equal? (length lines) 2)
      (check-equal? (text-layout-line-text (cadr lines)) "")
      (check-= (- (text-layout-line-baseline (cadr lines))
                  (text-layout-line-baseline (car lines))) 30 0.0001)
      (check-exn exn:fail? (lambda () (layout-text shaper text #:align 'justify)))))
  (test-case "provider indices use paragraph character and grapheme boundaries"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [shaper (make-shaper font)])
      (check-not-exn
       (lambda ()
         (layout-text shaper "AB" #:break-provider
                       (lambda (paragraph language) (error 'unused-provider "must not run")))))
      (for ([invalid '(0 2)])
        (check-exn exn:fail?
                   (lambda ()
                     (layout-text shaper "AB" #:width 200 #:break-provider
                                   (lambda (paragraph language) (list invalid))))))
      (check-exn exn:fail?
                 (lambda ()
                   (layout-text shaper "e\u0301x" #:width 200 #:break-provider
                                 (lambda (paragraph language) '(1)))))
      (check-not-exn
       (lambda () (layout-text shaper "AB" #:width 200 #:break-provider
                                (lambda (paragraph language) '(1 1)))))
      (check-exn exn:fail?
                 (lambda ()
                   (layout-text shaper "AB" #:width 200 #:break-provider
                                 (lambda (paragraph language)
                                   (list (make-layout-break-opportunity 1 "-") 1)))))))
  (test-case "layout metadata survives closure but drawing requires the retained shaper"
    (with-skia ([face (test-face)] [font (make-font face #:size 24)]
                [shaper (make-shaper font)]
                [surface (make-surface 40 40)] [paint (make-paint)])
      (define layout (layout-text shaper ""))
      (check-false (skia-resource? layout))
      (define width (text-layout-width layout))
      (skia-close! shaper)
      (check-equal? (text-layout-width layout) width)
      (check-exn exn:fail?
                 (lambda () (draw-text-layout (surface-canvas surface) layout 0 0 paint)))))
  (test-case "mixed layout records bidi runs and requires its manager at drawing time"
    (with-skia ([face (test-face)] [font (make-font face #:size 20)]
                [shaper (make-shaper font)] [manager (make-font-manager)]
                [surface (make-surface 300 100)] [paint (make-paint)])
      (define layout (layout-mixed-text shaper manager "ABC אבג 123" #:width 260))
      (define runs (append-map mixed-text-line-runs (mixed-text-layout-lines layout)))
      (check-true (ormap (lambda (run) (eq? (mixed-text-run-direction run) 'rtl)) runs))
      (for ([run (in-list runs)])
        (check-equal? (mixed-text-run-direction run)
                      (if (odd? (mixed-text-run-level run)) 'rtl 'ltr)))
      (skia-close! manager)
      (check-exn exn:fail?
                 (lambda () (draw-mixed-text-layout (surface-canvas surface) layout 0 0 paint))))))
