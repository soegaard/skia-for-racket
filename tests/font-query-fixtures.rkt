#lang racket/base

;;;
;;; Font Query Fixtures
;;;

;; Provides shared inputs and drawing fixtures for font mutation, glyph metrics, and detached
;; outline queries.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
;; Shared procedural scenes for raster, GPU and independently rendered documents.
(require racket/list "../main.rkt" "typeface-fixtures.rkt")
(provide font-query-scenes font-query-width font-query-height
         draw-font-query-scene check-font-query-pixels)

;;;
;;; Fixtures and Assertions
;;;

; font-query-scenes : (listof symbol?)
;;   Lists the snapshot, mutated-font, and batch-outline comparison scenes.
(define font-query-scenes '(snapshot mutated batch))

; font-query-width : exact-positive-integer?
;;   Sets the fixture width in pixels for drawing and storage-layout checks.
(define font-query-width 160)

; font-query-height : exact-positive-integer?
;;   Sets the fixture height in pixels for drawing and storage-layout checks.
(define font-query-height 100)

; draw-font-query-scene : symbol? canvas? -> any
;;   Draws deterministic glyphs using generated fixture fonts and the requested font-query scenario.
(define (draw-font-query-scene scene canvas)
  (unless (memq scene font-query-scenes)
    (raise-argument-error 'draw-font-query-scene "snapshot, mutated, or batch" scene))
  (with-skia ([regular (typeface-from-bytes (fixture-font-bytes))]
              [bold (typeface-from-bytes (fixture-font-bytes #:bold? #t))]
              [font (make-font regular #:size 40 #:hinting 'none #:edging 'alias
                               #:linear-metrics? #t #:subpixel? #t
                               #:embedded-bitmaps? #t #:baseline-snap? #f)]
              [blob (make-positioned-text-blob font '#(2 3) (font-glyph-positions font '#(2 3)))]
              [paint (make-paint #:color 'black #:antialias? #f)])
    (font-set-typeface! font bold)
    (font-set-size! font 80)
    (font-set-embedded-bitmaps! font #f)
    (font-set-force-auto-hinting! font #t)
    (font-set-baseline-snap! font #t)
    (case scene
      [(snapshot)
       ;; The drawing must use the old regular 40px face/flags after all caller
       ;; wrappers close, not reconstruct its font from the mutated SkFont.
       (skia-close! font) (skia-close! regular) (skia-close! bold)
       (draw-text-blob canvas blob 20 60 paint)]
      [(mutated)
       (font-set-size! font 40)
       (skia-close! regular) (skia-close! bold)
       (draw-simple-text canvas "AV" 20 60 font paint)]
      [(batch)
       (font-set-typeface! font regular)
       (font-set-size! font 40) (font-set-scale-x! font 1.5) (font-set-skew-x! font 0.25)
       (font-set-force-auto-hinting! font #f) (font-set-baseline-snap! font #f)
       (define positions (font-glyph-positions font '#(2 3)))
       (define paths (font-glyph-paths font '#(2 3)))
       (dynamic-wind void
         (lambda ()
           (skia-close! font) (skia-close! regular) (skia-close! bold)
           (for ([p (in-vector paths)] [xy (in-vector positions)])
             (unless p (error 'font-query-scene "fixture unexpectedly has no outline"))
             (with-canvas-state canvas
               (canvas-translate! canvas (+ 20 (car xy)) (+ 60 (cadr xy)))
               (draw-path canvas p paint))))
         (lambda () (for ([p (in-vector paths)] #:when p) (skia-close! p))))])))

; probes : hash?
;;   Maps each scene to x, y, expected-color triples in logical pixel coordinates.
(define probes
  (hasheq
   'snapshot '((25 40 black) (50 36 black) (41 40 white) (70 40 white) (5 5 white))
   'mutated  '((25 40 black) (41 40 black) (61 36 black) (85 40 white) (5 5 white))
   'batch    '((25 40 black) (36 40 black) (60 36 black) (44 40 white) (85 40 white) (5 5 white))))

; check-font-query-pixels : symbol? bytes? -> void?
;;   Checks capture dimensions and scene-specific black/white landmark pixels.
(define (check-font-query-pixels scene data)
  (unless (and (bytes? data) (= (bytes-length data) (* font-query-width font-query-height 4)))
    (error 'font-query-pixels "wrong RGBA byte length"))
  (for ([probe (in-list (hash-ref probes scene))])
    (define offset (* 4 (+ (car probe) (* font-query-width (cadr probe)))))
    (define actual (bytes->list (subbytes data offset (+ offset 4))))
    (define expected (if (eq? (caddr probe) 'black) '(0 0 0 255) '(255 255 255 255)))
    (unless (equal? actual expected)
      (error 'font-query-pixels "~a: ~a expected ~a, got ~a" scene probe expected actual))))
