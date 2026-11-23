#lang racket/base

;; Stage A execution probe. Explicit overrides deliberately test a managed pair
;; before the production managed loader exists. This is NOT catalog discovery.
(require json racket/cmdline racket/file racket/path
         (only-in file/sha1 bytes->hex-string)
         "../skia-lib/main.rkt" "../skia-lib/tests/typeface-fixtures.rkt")

(module+ main
  (define-values (skia-path harfbuzz-path)
    (command-line #:args (skia harfbuzz)
                  (values (path->complete-path skia) (path->complete-path harfbuzz))))
  (void (putenv "RACKET_SKIA_LIBRARY" (path->string skia-path)))
  (void (putenv "RACKET_HARFBUZZ_LIBRARY" (path->string harfbuzz-path)))
  (define (check ok message)
    (unless ok (error 'probe-managed-pair "~a" message)))
  (skia-check!)
  (harfbuzz-check!)
  (check (equal? (simplify-path (skia-native-library-path)) (simplify-path skia-path))
         "Skia did not use the explicit managed filename")
  (check (equal? (simplify-path (harfbuzz-native-library-path)) (simplify-path harfbuzz-path))
         "HarfBuzz did not use the explicit managed filename")
  (with-skia ([surface (make-surface 7 5 #:background (rgb 7 11 17))]
              [paint (make-paint #:color (rgb 231 53 79))])
    (draw-rect (surface-canvas surface) 1 1 3 2 paint)
    (check (equal? (surface-pixel surface 2 1) (rgb 231 53 79)) "asymmetric interior pixel")
    (check (equal? (surface-pixel surface 0 4) (rgb 7 11 17)) "asymmetric background pixel")
    (with-skia ([image (image-from-bytes (surface->png-bytes surface))])
      (check (and (= (image-width image) 7) (= (image-height image) 5)) "PNG dimensions")
      (check (equal? (image->rgba-bytes image) (surface->rgba-bytes surface)) "PNG exact pixel round trip")))
  (with-skia ([face (typeface-from-bytes (fixture-font-bytes))]
              [font (make-font face #:size 20)]
              [shaper (make-shaper font)])
    (define run (shape-text shaper "AV"))
    (check (equal? (shaped-run-glyphs run) '#(2 3)) "fixture glyph IDs")
    (check (equal? (shaped-run-glyphs (shape-text shaper "AV")) (shaped-run-glyphs run))
           "repeatable fixture shaping")
    (check (> (abs (shaped-run-advance-x run)) 0) "positive fixture advance"))
  (define (identity path)
    (hasheq 'path (path->string path)
            'sha256 (call-with-input-file path (lambda (in) (bytes->hex-string (sha256-bytes in))))))
  (write-json
   (hasheq 'status "passed" 'racket_version (version)
           'mode "source-with-explicit-managed-path-overrides"
           'skia (identity skia-path) 'harfbuzz (identity harfbuzz-path)
           'skia_version (skia-native-version) 'harfbuzz_version (harfbuzz-native-version)
           'asymmetric_pixels #t 'png_round_trip #t 'fixture_shaping #t
           'automatic_managed_discovery_qualified #f 'catalog_candidate_validated #f))
  (newline))
