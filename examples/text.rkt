#lang racket/base
(require racket/cmdline
         "../main.rkt")

(define output
  (command-line
   #:program "text.rkt"
   #:args ([filename "text.png"])
   filename))

(with-skia ([surface (make-surface 900 430 #:background "#F7F8FB")]
            [face (make-typeface)]
            [title-font (make-font face #:size 64 #:hinting 'normal)]
            [body-font (make-font face #:size 30)]
            [fill (make-paint #:color "#24324A")]
            [accent (make-paint #:color "#2878E5")]
            [rule (make-paint #:color "#CBD4E3" #:style 'stroke #:stroke-width 1)]
            [outline (make-paint #:color "#18A999" #:style 'stroke #:stroke-width 2)])
  (define canvas (surface-canvas surface))
  (define title "Skia from Racket")

  ;; draw-simple-text positions text by its baseline.
  (draw-simple-text canvas title 56 112 title-font accent)
  (draw-line canvas 56 122 844 122 rule)

  (define metrics (font-get-metrics body-font))
  (draw-simple-text canvas
                    (format "Family: ~a" (typeface-family-name face))
                    56 188 body-font fill)
  (draw-simple-text canvas
                    (format "Ascent ~a   Descent ~a   Line spacing ~a"
                            (font-metrics-ascent metrics)
                            (font-metrics-descent metrics)
                            (font-metrics-spacing metrics))
                    56 236 body-font fill)

  ;; Text outlines are ordinary Skia paths and can be stroked like any path.
  (with-skia ([letters (simple-text-path title-font "Outlined glyph paths" 56 338)])
    (draw-path canvas letters outline))

  (save-png surface output)
  (printf "Wrote ~a\n" output))
