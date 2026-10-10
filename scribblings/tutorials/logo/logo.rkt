#lang racket

(require skia)

(define size 500)

(define background-color "#F4F0E7")
(define fill-color "#246B5A")
(define outline-color "#173B35")

(define logo-commands
  '((move 250 50)
    (cubic 405 85 440 280 250 440)
    (cubic 60 280 95 85 250 50)
    (close)
    (move 165 310)
    (cubic 210 250 280 195 350 145)
    (cubic 315 220 270 305 205 355)
    (cubic 190 340 177 325 165 310)
    (close)))

(define (make-logo-path)
  (make-path logo-commands #:fill-rule 'even-odd))

(define (draw-logo canvas)
  (with-skia ([path (make-logo-path)]
              [fill (make-paint #:color fill-color)]
              [outline (make-paint #:color outline-color
                                   #:style 'stroke
                                   #:stroke-width 5
                                   #:join 'round)])
    (draw-path canvas path fill)
    (draw-path canvas path outline)))

(define (save-raster filename)
  (with-skia ([surface (make-surface size size
                                    #:background background-color)])
    (draw-logo (surface-canvas surface))
    (save-png surface filename #:exists 'replace)))

(define (save-vector filename)
  (define page
    (make-output-page size size draw-logo
                      #:unit 'px
                      #:background background-color))
  (save-output page filename 'svg #:exists 'replace))

(module+ main
  (save-raster "logo.png")
  (save-vector "logo.svg"))
