#lang racket

(require skia)

(provide sheet-width
         sheet-height
         paper-color
         draw-study)

(define sheet-width 900)
(define sheet-height 610)
(define paper-color "#F3F7FB")
(define ink-color "#243852")
(define muted-color "#62768C")
(define blue-color "#326BC4")
(define teal-color "#159F99")

(define (draw-vector-art canvas)
  (define gradient
    (make-linear-gradient-shader 0 0 200 0
                                 (list blue-color teal-color)))
  (define fill (make-paint #:shader gradient))
  (define ring
    (make-paint #:color "#EAF6FA"
                #:style 'stroke
                #:stroke-width 3))
  (define dot (make-paint #:color "#F6B86C"))
  (draw-rounded-rect canvas 2 4 196 170 22 22 fill)
  (for ([radius '(62 43 24)])
    (draw-circle canvas 100 89 radius ring))
  (draw-line canvas 27 142 173 142 ring)
  (draw-circle canvas 100 89 10 dot))

(define (make-pixel-tile)
  (define surface
    (make-surface 32 32 #:background "#234D74"))
  (define canvas (surface-canvas surface))
  (define teal (make-paint #:color "#54B9B5"))
  (define amber (make-paint #:color "#F6B86C"))
  (for* ([row (in-range 4)]
         [column (in-range 4)]
         #:when (even? (+ row column)))
    (draw-rect canvas (* column 8) (* row 8) 8 8 teal))
  (draw-rect canvas 9 9 14 14 amber)
  (surface-snapshot surface))

(define (draw-pixel-art canvas)
  (define tile (make-pixel-tile))
  (draw-image-rect canvas tile 4 0 192 192
                   #:sampling 'nearest))

(define (draw-filtered-badge canvas)
  (define shadow
    (make-drop-shadow-image-filter
     0 9 7 7 (rgba 22 52 87 130)))
  (define fill
    (make-paint #:color "#24A7A0"
                #:image-filter shadow))
  (draw-rounded-rect canvas 26 18 146 116 24 24 fill))

(define (draw-fallback-art canvas)
  (define border
    (make-paint #:color ink-color
                #:style 'stroke
                #:stroke-width 2.5))
  (define center (make-paint #:color "#FFF3DA"))
  (with-output-label "bounded raster"
    (draw-rasterized canvas 0 0 206 180 draw-filtered-badge
                     #:scale 2))
  (with-output-label "vector details"
    (draw-rounded-rect canvas 26 18 146 116 24 24 border)
    (draw-circle canvas 99 76 15 center)))

(define (draw-study canvas)
  (define title-font (make-font #:size 39))
  (define subtitle-font (make-font #:size 18))
  (define label-font (make-font #:size 16))
  (define caption-font (make-font #:size 15))
  (define small-font (make-font #:size 14))
  (define ink (make-paint #:color ink-color))
  (define muted (make-paint #:color muted-color))
  (define blue (make-paint #:color blue-color))
  (define panel-fill (make-paint #:color 'white))
  (define rule
    (make-paint #:color "#D2E0EA"
                #:style 'stroke
                #:stroke-width 1.5))

  (draw-simple-text canvas "What stays vector?" 48 84 title-font ink)
  (draw-simple-text canvas "One page can contain shapes and pixels." 50 119
                    subtitle-font muted)
  (for ([x '(44 328 612)])
    (draw-rounded-rect canvas x 159 244 354 18 18 panel-fill)
    (draw-rounded-rect canvas x 159 244 354 18 18 rule))

  (draw-simple-text canvas "01   PATHS + GRADIENT" 62 201 label-font blue)
  (draw-simple-text canvas "02   RASTER IMAGE" 346 201 label-font blue)
  (draw-simple-text canvas "03   LOCAL FALLBACK" 630 201 label-font blue)

  (with-output-label "vector motif"
    (with-canvas-state canvas
      (canvas-translate! canvas 66 244)
      (draw-vector-art canvas)))
  (with-output-label "source pixels"
    (with-canvas-state canvas
      (canvas-translate! canvas 348 230)
      (draw-pixel-art canvas)))
  (with-canvas-state canvas
    (canvas-translate! canvas 630 238)
    (draw-fallback-art canvas))

  (draw-simple-text canvas "Resizable geometry" 63 471 caption-font ink)
  (draw-simple-text canvas "32 x 32 source pixels" 347 471 caption-font ink)
  (draw-simple-text canvas "Pixels only in this group" 631 471
                    caption-font ink)

  (draw-line canvas 48 546 850 546 rule)
  (draw-simple-text canvas "SVG and PDF can keep the frame, paths and labels as vectors."
                    50 573 small-font muted)
  (draw-simple-text canvas "Embedded images and the bounded effect remain pixels."
                    50 593 small-font muted))

(module+ main
  (define page
    (make-output-page sheet-width sheet-height draw-study
                      #:unit 'px
                      #:background paper-color))
  (define preview
    (output-page->image page #:dpi 96 #:text-mode 'outline))
  (save-output/audit page "what-stays-vector.pdf" 'pdf
                     #:text-mode 'outline
                     #:policy 'error
                     #:exists 'replace)
  (save-output/audit page "what-stays-vector.svg" 'svg
                     #:text-mode 'outline
                     #:policy 'error
                     #:exists 'replace)
  (save-image preview "what-stays-vector.png" 'png
              #:exists 'replace))
