#lang racket/base

;;;
;;; Text Blob Scenes
;;;

;; Provides shared inputs and drawing fixtures for retained text runs, glyph positions, clusters,
;; and serialization.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
(require "../main.rkt" "typeface-fixtures.rkt")
(provide text-blob-scene-names text-blob-scene-width text-blob-scene-height
         make-text-blob-scene draw-text-blob-scene)

;;;
;;; Fixtures and Assertions
;;;

; text-blob-scene-names : (listof symbol?)
;   Lists the retained-run fixtures used for native, outline, CPU, and GPU comparisons.
(define text-blob-scene-names '(multi transformed curve))

; text-blob-scene-width : exact-positive-integer?
;   Sets the fixture width in pixels for drawing and storage-layout checks.
(define text-blob-scene-width 192)

; text-blob-scene-height : exact-positive-integer?
;   Sets the fixture height in pixels for drawing and storage-layout checks.
(define text-blob-scene-height 128)

; make-text-blob-scene : symbol? -> text-blob?
;   Creates the requested owned blob using deterministic generated font data.
(define (make-text-blob-scene name)
  (unless (memq name text-blob-scene-names)
    (raise-argument-error 'make-text-blob-scene "known scene" name))
  (with-skia ([face (typeface-from-bytes (fixture-font-bytes))]
              [bold-face (typeface-from-bytes (fixture-font-bytes #:bold? #t))]
              [font (make-font face #:size 40 #:hinting 'none #:edging 'alias
                                    #:linear-metrics? #t #:subpixel? #t #:baseline-snap? #f)]
              [bold (make-font bold-face #:size 40 #:hinting 'none #:edging 'alias
                                         #:linear-metrics? #t #:subpixel? #t #:baseline-snap? #f)])
    (case name
      [(multi)
       (with-skia ([b (make-text-blob-builder)])
         (text-blob-builder-add-run! b font '(2) #:origin '(20 70) #:text "A" #:clusters '(0))
         (text-blob-builder-add-horizontal-run! b bold '(3) '(60) #:y 70 #:text "V" #:clusters '(0))
         (text-blob-builder-add-positioned-run! b font '(2) '((100 70)) #:text "A" #:clusters '(0))
         (text-blob-builder-finish! b))]
      [(transformed)
       (with-skia ([b (make-text-blob-builder)])
         (text-blob-builder-add-transformed-run!
          b font '(2 3 2) '((0 1 24 36) (1 0 75 75) (0.5 0 120 65))
          #:text "AVA" #:clusters '(0 1 2))
         (text-blob-builder-finish! b))]
      [(curve)
       (with-skia ([sh (make-shaper font)]
                   [p (make-path '((move 55 105) (cubic 75 35 140 35 165 105)))])
         (shaped-run->text-blob/on-path (shape-text sh "AAA") p #:start-offset 10 ))])))

; draw-text-blob-scene : canvas? text-blob? -> any
;   Draws the retained blob at the common scene origin for capture comparisons.
(define (draw-text-blob-scene canvas blob)
  (with-skia ([ink (make-paint #:color (rgb 24 64 192) #:antialias? #f)]
              [marker (make-paint #:color (rgb 0 255 0) #:antialias? #f)])
    (draw-rect canvas 2 2 4 4 marker)
    (draw-text-blob canvas blob 0 0 ink)))
