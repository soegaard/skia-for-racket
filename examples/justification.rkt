#lang racket/base

;;;
;;; Justification Example
;;;

;; Compares text alignment and justification using visible layout guides.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;;;
;;; Imports and Exports
;;;

(require racket/list racket/match "../main.rkt")

;;;
;;; Drawing Data and Helpers
;;;

; bg : string?
;   Specifies the bg color used by this drawing.
(define bg "#F4F6F9")

; panel-fill : string?
;   Specifies the panel fill color used by this drawing.
(define panel-fill "#FFFFFF")

; frame-color : string?
;   Specifies the frame color color used by this drawing.
(define frame-color "#CBD5E1")

; guide-color : string?
;   Specifies the guide color color used by this drawing.
(define guide-color "#DDE4EE")

; ink : string?
;   Specifies the ink color used by this drawing.
(define ink "#20304C")

; panel : canvas? real? real? real? real? string? -> void?
;   Draws one labeled comparison panel using the example's shared layout.
(define (panel c x y w h title)
  (with-skia ([fill (make-paint #:color panel-fill)]
              [stroke (make-paint #:color frame-color #:style 'stroke #:stroke-width 2)]
              [font (make-font #:size 12)]
              [text (make-paint #:color ink)])
    (draw-rounded-rect c x y w h 16 16 fill)
    (draw-rounded-rect c x y w h 16 16 stroke)
    (draw-simple-text c title (+ x 18) (+ y 30) font text)))

; guides : canvas? real? real? real? real? -> void?
;   Draws layout guides so the text placement can be compared visually.
(define (guides c x y h width)
  (with-skia ([p (make-paint #:color guide-color #:style 'stroke #:stroke-width 1)])
    (draw-line c x y x (+ y h) p)
    (draw-line c (+ x width) y (+ x width) (+ y h) p)))

; small-label : canvas? string? real? real? -> void?
;   Draws a compact explanatory label at the supplied baseline.
(define (small-label c text x y)
  (with-skia ([f (make-font #:size 12)] [p (make-paint #:color ink)])
    (draw-simple-text c text x y f p)))

; main : any/c -> void?
;   Renders the example gallery and writes it to the requested output file.
(define (main out)
  (with-skia ([surface (make-surface 1000 700 #:background bg)]
              [fm (default-font-manager)]
              [tf (make-typeface)]
              [font (make-font tf #:size 25)]
              [sh (make-shaper font)]
              [blue (make-paint #:color "#326DE6")]
              [teal (make-paint #:color "#18A999")]
              [orange (make-paint #:color "#F38C42")])
    (define c (surface-canvas surface))
    (for ([spec '((30 30 "justify: wrapped lines")
                  (355 30 "justify-all: final line")
                  (680 30 "start / center / end")
                  (30 365 "RTL inter-word justify")
                  (355 365 "mixed bidi justify")
                  (680 365 "spacing policy"))])
      (match-define (list x y title) spec)
      (panel c x y 290 305 title))

    (define width 230)

    (guides c 50 78 145 width)
    (define j1
      (layout-text sh
                   "Racket makes positioned text useful for compact mathematical graphics."
                   #:width width #:align 'justify))
    (draw-text-layout c j1 50 90 blue)
    (small-label c "final line remains start-aligned" 50 250)

    (guides c 375 78 145 width)
    (define j2
      (layout-text sh "alpha beta gamma" #:width width #:align 'justify-all))
    (draw-text-layout c j2 375 90 orange)
    (small-label c "single/final line fills the measure" 375 250)

    (guides c 700 78 155 width)
    (for ([align '(start center end)] [dy '(95 140 185)])
      (define l (layout-text sh "alpha beta" #:width width #:align align))
      (draw-text-layout c l 700 dy teal)
      (small-label c (symbol->string align) 700 (+ dy 30)))

    (guides c 50 413 145 width)
    (define j4
      (layout-mixed-text sh fm "שלום עולם טקסט ארוך יותר לבדיקה"
                         #:width width #:align 'justify #:direction 'rtl))
    (draw-mixed-text-layout c j4 50 425 blue)
    (small-label c "spaces expand in RTL visual flow" 50 585)

    (guides c 375 413 145 width)
    (define j5
      (layout-mixed-text sh fm
                         "Racket שלום world مرحبا 123 mixed paragraph text"
                         #:width width #:align 'justify))
    (draw-mixed-text-layout c j5 375 425 orange)
    (small-label c "bidi runs keep shaping; spaces absorb slack" 375 585)

    (guides c 700 413 145 width)
    (define nbsp (string #\u00A0))
    (define j6a
      (layout-text sh (string-append "ordinary space stretches")
                   #:width width #:align 'justify-all))
    (define j6b
      (layout-text sh (string-append "no" nbsp "break")
                   #:width width #:align 'justify-all))
    (draw-text-layout c j6a 700 425 teal)
    (draw-text-layout c j6b 700 480 teal)
    (small-label c "only U+0020 expands; NBSP stays fixed" 700 585)

    (save-png surface out #:exists 'replace)))

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; out : path-string?
  ;   Names the destination image selected by the command line.
  (define out
    (if (zero? (vector-length (current-command-line-arguments)))
        "justification.png"
        (vector-ref (current-command-line-arguments) 0)))
  (main out)
  (printf "Wrote ~a\n" out))
