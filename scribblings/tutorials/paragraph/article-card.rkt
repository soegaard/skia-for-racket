#lang racket

(require skia)

(provide card-width
         card-height
         draw-article-card)

(define card-width 920)
(define card-height 740)

(define paper-color "#EDF2F7")
(define card-color "#FFFFFF")
(define ink-color "#20304C")
(define blue-color "#326DE6")
(define muted-color "#697A90")
(define callout-color "#F0F5FC")

(define (draw-article-card canvas)
  (define face (make-typeface))
  (define font-manager (default-font-manager))
  (define body-font (make-font face #:size 26))
  (define body-shaper (make-shaper body-font))
  (define title-font (make-font face #:size 50))
  (define label-font (make-font face #:size 15))
  (define footer-font (make-font face #:size 13))
  (define ink (make-paint #:color ink-color))
  (define blue (make-paint #:color blue-color))
  (define muted (make-paint #:color muted-color))
  (define card-paint (make-paint #:color card-color))
  (define callout-paint (make-paint #:color callout-color))

  (define introduction
    (layout-text
     body-shaper
     "A page gives words a width. Paragraph layout chooses the lines and their baselines."
     #:width 744))

  (define multilingual-text
    (layout-mixed-text
     body-shaper font-manager
     "Skia places English beside العربية and עברית, even when a sentence includes 2026."
     #:width 744
     #:direction 'ltr))

  (define right-to-left-text
    (layout-mixed-text
     body-shaper font-manager
     "שלום 2026, Skia! مرحبا بالعالم and English."
     #:width 690
     #:direction 'auto
     #:align 'start))

  (draw-rounded-rect canvas 44 38 832 664 20 20 card-paint)
  (draw-simple-text canvas "SKIA / TEXT STUDIES" 88 100 label-font blue)
  (draw-simple-text canvas "A world of writing" 84 164 title-font ink)
  (draw-rect canvas 88 195 744 2 blue)

  (draw-text-layout canvas introduction 88 222 ink)

  (draw-simple-text canvas "THREE SCRIPTS, ONE PARAGRAPH" 88 352 label-font blue)
  (draw-mixed-text-layout canvas multilingual-text 88 376 ink)

  (draw-rounded-rect canvas 84 518 752 130 14 14 callout-paint)
  (draw-simple-text canvas "A RIGHT-TO-LEFT START" 108 551 label-font blue)
  (draw-mixed-text-layout canvas right-to-left-text 108 562 ink)

  (draw-simple-text canvas "WRAPPING  /  FONT FALLBACK  /  BIDI" 88 680 footer-font muted)
  (draw-simple-text canvas "SKIA  /  08" 741 680 footer-font muted))

(module+ main
  (define surface
    (make-surface card-width card-height
                  #:background paper-color))
  (draw-article-card (surface-canvas surface))
  (save-png surface "article-card.png" #:exists 'replace))
