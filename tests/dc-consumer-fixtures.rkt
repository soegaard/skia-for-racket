#lang racket/base
;; Real public clients, deliberately limited to the existing 0.55 DC subset.
;; This is test/example code, not a replacement pict or plot implementation.
(require racket/class racket/list
         (prefix-in rd: racket/draw)
         (prefix-in p: pict)
         (prefix-in plot: plot/no-gui))
(provide consumer-width consumer-height make-consumer-pict draw-consumer-pict
         draw-consumer-plot record-consumer consumer-state plot-probe-position)

(define consumer-width 320)
(define consumer-height 240)

(define (make-consumer-pict metric-dc)
  (define bm (rd:make-bitmap 12 10 #t))
  (define argb (make-bytes (* 12 10 4)))
  (for ([i (in-range 0 (bytes-length argb) 4)])
    (bytes-copy! argb i (bytes 255 20 180 60)))
  (send bm set-argb-pixels 0 0 12 10 argb)
  ;; The text's layout uses the same public metric protocol as ordinary pict.
  ;; Pixel equality with Cairo/Pango text is not an acceptance requirement.
  (parameterize ([p:dc-for-text-size metric-dc])
    (define red (p:colorize (p:filled-rectangle 44 28) "red"))
    (define blue (p:colorize (p:filled-rectangle 36 24) "blue"))
    (define overlap
      (p:cellophane
       (p:pin-over (p:colorize (p:filled-rectangle 36 24) "red") 12 0 blue)
       0.5 #:composite? #t))
    ;; 0.64: the exact same family/style, expressed with comma-description
    ;; syntax. Existing raster, GPU, replay and document consumer gates now
    ;; exercise the new parser without changing the scene or its pixel probes.
    (define ordinary-font (rd:make-font #:family 'swiss #:size 16))
    (define mapped-name
      (send rd:the-font-name-directory get-screen-name
            (send ordinary-font get-font-id) 'normal 'normal))
    (define described-font
      (rd:make-font #:face (string-append mapped-name ",") #:family 'swiss #:size 16))
    (define label
      (p:colorize (p:text "Skia / pict" described-font) "navy"))
    (for/fold ([scene (p:blank consumer-width consumer-height)])
              ([entry (in-list
                       (list (list 12 12 red)
                             (list 12 64 overlap)
                             (list 160 12 (p:bitmap bm))
                             (list 180 62 (p:rotate (p:rectangle 58 26) 0.2))
                             (list 180 110 (p:scale (p:ellipse 48 24) 1.25))
                             (list 12 126 (p:hc-append 8 label (p:disk 16)))))])
      (p:pin-over scene (car entry) (cadr entry) (caddr entry)))))

(define (draw-consumer-pict dc picture)
  (p:draw-pict picture dc 0 0)
  (void))

(define (draw-consumer-plot dc)
  ;; No plot/gui dependency, plot window, bitmap renderer, or plot-pict detour.
  ;; The returned metrics describe the layout selected by THIS target DC.
  (parameterize ([plot:plot-font-size 11]
                 [plot:plot-font-family 'swiss]
                 [plot:plot-background "white"]
                 [plot:plot-foreground "black"])
    (define metrics
      (plot:plot/dc
       (list (plot:function (lambda (x) (* 0.5 x)) -2 2
                            #:color "blue" #:width 3 #:style 'solid #:label "y = x / 2")
             (plot:points (list (vector -1 1) (vector 1 -1))
                          #:color "red" #:fill-color "red" #:sym 'fullcircle #:size 8))
       dc 0 0 consumer-width consumer-height
       #:x-min -2 #:x-max 2 #:y-min -1.5 #:y-max 1.5
       ;; Keep the real legend, but place it outside the data rectangle.
       ;; An inside top-right legend can cover the x=1.5/y=.75 curve probe
       ;; when platform font metrics make the legend slightly taller.
       #:title "Skia / plot" #:x-label "x" #:y-label "y"
       #:legend-anchor 'outside-top-right))
    ;; Retain only ordinary coordinates, not the plot area/DC object.
    (define lower (send metrics plot->dc (vector -2 -1.5)))
    (define upper (send metrics plot->dc (vector 2 1.5)))
    (hash 'lower_left (vector->list lower) 'upper_right (vector->list upper))))

(define (plot-probe-position layout x y)
  (define lo (hash-ref layout 'lower_left))
  (define hi (hash-ref layout 'upper_right))
  (values (+ (car lo) (* (/ (+ x 2) 4) (- (car hi) (car lo))))
          (+ (cadr lo) (* (/ (+ y 1.5) 3) (- (cadr hi) (cadr lo))))))

(define (record-consumer draw)
  (define recorder (new rd:record-dc% [width consumer-width] [height consumer-height]))
  (send recorder set-smoothing 'smoothed)
  (define layout (draw recorder))
  (values (send recorder get-recorded-procedure)
          (rd:recorded-datum->procedure (send recorder get-recorded-datum))
          layout))

(define (consumer-state dc)
  (define (rgba c) (list (send c red) (send c green) (send c blue) (send c alpha)))
  (list (send dc get-pen) (send dc get-brush) (send dc get-font)
        (send dc get-alpha) (send dc get-transformation) (send dc get-clipping-region)
        (send dc get-smoothing) (send dc get-text-mode)
        (rgba (send dc get-background)) (rgba (send dc get-text-foreground))
        (rgba (send dc get-text-background))))
